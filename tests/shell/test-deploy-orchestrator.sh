#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/deploy-orchestrator-swarm.sh"
tmp=$(mktemp -d)
trap 'chmod 700 -- "$tmp/mapping" 2>/dev/null || true; rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
calls="$tmp/docker.calls"
env_file="$tmp/development.env"
mapping_file="$tmp/mapping/secret-mapping.env"
server_env_file="$tmp/server.environment"
mkdir -p "$fake_bin" "$tmp/docker-secrets" "$tmp/mapping"

valid_digest='example.invalid/smtp2graph@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
rollback_digest='example.invalid/smtp2graph@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
printf '%s\n' \
  'DEPLOY_ENVIRONMENT="development"' \
  "SMTP2GRAPH_IMAGE_DIGEST=${valid_digest}" \
  'SWARM_STACK_NAME=smtp2graph' \
  'SWARM_OVERLAY_NETWORK=smtp2graph_internal' \
  "SMTP2GRAPH_STORAGE_HOST_PATH=${tmp}/data" \
  'SMTP2GRAPH_MODE=full' \
  'GRAPH_AUTH_MODE=certificate' \
  'SMTP_MAX_MESSAGE_BYTES=26214400' \
  'SMTP_MAX_SESSIONS_PER_IP=5' \
  'SMTP_MESSAGES_PER_MINUTE=30' \
  'SMTP_ALLOWED_SOURCE_CIDRS=10.42.0.0/24' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' \
  'GRAPH_SENDER_MAILBOX=noreply@example.invalid' \
  'SEND_RETRY_LIMIT=1' \
  'SEND_RETRY_INTERVAL_MINUTES=1' \
  "TLS_SECRET_MAPPING_FILE=${mapping_file}" \
  'GRAPH_TENANT_ID="00000000-0000-0000-0000-000000000000"' \
  'GRAPH_CLIENT_ID="11111111-1111-1111-1111-111111111111"' \
  'GRAPH_CERTIFICATE_THUMBPRINT="synthetic-thumbprint"' \
  'GRAPH_CERT_PRIVATE_KEY_PEM="synthetic-private-key"' \
  'SMTP_USERS_TSV="gateway\tsynthetic-password\tnoreply@example.invalid"' \
  'TLS_CERTIFICATE_PEM="synthetic-certificate"' \
  'TLS_PRIVATE_KEY_PEM="synthetic-tls-key"' \
  'GRAPH_TENANT_ID_SECRET_NAME=stale_tenant_reference' \
  'GRAPH_CLIENT_ID_SECRET_NAME=stale_client_reference' \
  'GRAPH_CREDENTIAL_SECRET_NAME=stale_credential_reference' \
  'GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=stale_thumbprint_reference' \
  'SMTP_CREDENTIALS_SECRET_NAME=stale_smtp_reference' \
  'TLS_CERTIFICATE_SECRET_NAME=stale_certificate_reference' \
  'TLS_PRIVATE_KEY_SECRET_NAME=stale_key_reference' >"$env_file"
chmod 600 "$env_file"
printf '%s\n' \
  'GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_vmapped' \
  'GRAPH_CLIENT_ID_SECRET_NAME=smtp2graph_graph_client_id_vmapped' \
  'GRAPH_CREDENTIAL_SECRET_NAME=smtp2graph_graph_credential_vmapped' \
  'GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_vmapped' \
  'SMTP_CREDENTIALS_SECRET_NAME=smtp2graph_smtp_users_vmapped' \
  'TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_vmapped' \
  'TLS_PRIVATE_KEY_SECRET_NAME=smtp2graph_tls_private_key_vmapped' >"$mapping_file"
chmod 600 "$mapping_file"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env_file"
cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_DOCKER_CALLS}"
if [[ "${1:-} ${2:-}" == 'stack deploy' ]]; then
  printf 'digest=%s\n' "${SMTP2GRAPH_IMAGE_DIGEST}" >>"${FAKE_DOCKER_CALLS}"
fi
case "${1:-} ${2:-}" in
  'secret inspect') test -f "${FAKE_DOCKER_SECRET_DIR}/${3}" ;;
  'secret create') cp "$4" "${FAKE_DOCKER_SECRET_DIR}/${3}" ;;
  'stack config')
    printf 'mapped-secret=%s\n' "${SMTP_CREDENTIALS_SECRET_NAME}" >>"${FAKE_DOCKER_CALLS}"
    printf 'derived-sender=%s\n' "${SMTP_ALLOWED_SENDER_ADDRESSES}" >>"${FAKE_DOCKER_CALLS}"
    printf 'config-version=%s\n' "${SMTP2GRAPH_CONFIG_VERSION}" >>"${FAKE_DOCKER_CALLS}"
    exit 0
    ;;
  'stack deploy') exit 0 ;;
  'info --format') printf '%s\n' true ;;
  info\ *) exit 0 ;;
  'service inspect' | 'service ps') exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$fake_bin/docker"
cat >"$fake_bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
input='' extract=''
while (($#)); do
  case "$1" in
    --extract)
      extract=${2:-}
      shift 2
      ;;
    *)
      input=$1
      shift
      ;;
  esac
done
if [[ -z "$extract" ]]; then
  cat "$input"
  exit 0
fi
key=${extract#*\"}
key=${key%%\"*}
awk -v key="$key" '$0 ~ ("^" key "=") { print substr($0, length(key) + 2); exit }' "$input"
EOF
chmod 700 "$fake_bin/sops"
cat >"$fake_bin/init-storage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'init-storage %s\n' "$*" >>"${FAKE_DOCKER_CALLS}"
EOF
chmod 700 "$fake_bin/init-storage"
export SMTP_INIT_STORAGE_SCRIPT="$fake_bin/init-storage"

PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --check >/dev/null
grep -Eq '^stack config ' "$calls"
grep -Eq '^mapped-secret=smtp2graph_smtp_users_vmapped$' "$calls"
grep -Eq '^derived-sender=noreply@example.invalid$' "$calls"
expected_config_version=$(sha256sum \
  "$root/scripts/entrypoint.sh" \
  "$root/scripts/lib/render-config.sh" \
  "$root/deploy/config/gateway-config.yml.template" \
  "$root/scripts/init-storage.sh" |
  sha256sum | awk '{print substr($1, 1, 16)}')
grep -Eq "^config-version=${expected_config_version}$" "$calls"
if grep -Eq '^stack deploy ' "$calls"; then
  printf 'ERROR: check unexpectedly submitted a stack deploy.\n' >&2
  exit 1
fi

chmod 500 "$tmp/mapping"

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" FAKE_DOCKER_SECRET_DIR="$tmp/docker-secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --deploy --apply >/dev/null
first_smtp_secret=$(awk -F= '/^mapped-secret=/ { value=$2 } END { print value }' "$calls")
[[ "$first_smtp_secret" != smtp2graph_smtp_users_vmapped ]]
sed -i 's/synthetic-password/synthetic-password-rotated/' "$env_file"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" FAKE_DOCKER_SECRET_DIR="$tmp/docker-secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --deploy --apply >/dev/null
second_smtp_secret=$(awk -F= '/^mapped-secret=/ { value=$2 } END { print value }' "$calls")
[[ "$second_smtp_secret" != "$first_smtp_secret" ]]
test "$(grep -c '^stack deploy ' "$calls")" -eq 2
test "$(grep -c '^init-storage ' "$calls")" -eq 2
if grep -Fq -- '--prune' "$calls"; then
  printf 'ERROR: deploy unexpectedly used --prune.\n' >&2
  exit 1
fi

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --status >/dev/null
grep -Eq '^service inspect smtp2graph_gateway$' "$calls"
grep -Eq '^service ps smtp2graph_gateway --no-trunc$' "$calls"

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --rollback --image-digest "$rollback_digest" --queue-compatibility-confirmed --apply >/dev/null
grep -Eq '^stack deploy ' "$calls"
grep -Eq "^digest=${rollback_digest}$" "$calls"

if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --rollback --image-digest "$rollback_digest" --apply >/dev/null 2>&1; then
  printf 'ERROR: rollback unexpectedly skipped queue compatibility confirmation.\n' >&2
  exit 1
fi

unknown_digest='example.invalid/smtp2graph@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --rollback --image-digest "$unknown_digest" --queue-compatibility-confirmed --apply >/dev/null
grep -Eq "^digest=${unknown_digest}$" "$calls"

production_env="$tmp/production.env"
sed 's/^DEPLOY_ENVIRONMENT="development"$/DEPLOY_ENVIRONMENT="production"/' "$env_file" >"$production_env"
chmod 600 "$production_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$production_env" --deploy --apply >/dev/null 2>&1; then
  printf 'ERROR: production deploy was unexpectedly accepted.\n' >&2
  exit 1
fi

printf '%s\n' 'SERVER_ENV=prod' >"$server_env_file"
control_plane_sha=$(git -C "$root" rev-parse HEAD)
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" FAKE_DOCKER_SECRET_DIR="$tmp/docker-secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$production_env" --deploy --apply --release-tag v1.1.6 --approval-context release-approval-20260801 --declared-deploy-ref "$control_plane_sha" >/dev/null
grep -Eq '^stack deploy ' "$calls"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$production_env" --deploy --apply --secret-mapping-already-reconciled --release-tag v1.1.6 --approval-context release-approval-20260801 --declared-deploy-ref "$control_plane_sha" >/dev/null 2>&1; then
  printf 'ERROR: production deploy unexpectedly skipped SOPS Secret reconciliation.\n' >&2
  exit 1
fi
printf '%s\n' 'SERVER_ENV=dev' >"$server_env_file"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$production_env" --deploy --apply --release-tag v1.1.6 --approval-context release-approval-20260801 --declared-deploy-ref "$control_plane_sha" >/dev/null 2>&1; then
  printf 'ERROR: production deploy unexpectedly accepted SERVER_ENV mismatch.\n' >&2
  exit 1
fi

placeholder_env="$tmp/placeholder.env"
sed 's#^SMTP2GRAPH_IMAGE_DIGEST=.*#SMTP2GRAPH_IMAGE_DIGEST=example.invalid/smtp2graph:latest#' "$env_file" >"$placeholder_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$placeholder_env" --check >/dev/null 2>&1; then
  printf 'ERROR: mutable image tag was unexpectedly accepted.\n' >&2
  exit 1
fi

missing_mapping_env="$tmp/missing-mapping.env"
sed '/^TLS_SECRET_MAPPING_FILE=/d' "$env_file" >"$missing_mapping_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$missing_mapping_env" --check >/dev/null 2>&1; then
  printf 'ERROR: deploy loader unexpectedly accepted a missing Secret mapping reference.\n' >&2
  exit 1
fi

incomplete_mapping="$tmp/incomplete-secret-mapping.env"
sed '$d' "$mapping_file" >"$incomplete_mapping"
chmod 600 "$incomplete_mapping"
incomplete_mapping_env="$tmp/incomplete-mapping.env"
sed "s#^TLS_SECRET_MAPPING_FILE=.*#TLS_SECRET_MAPPING_FILE=${incomplete_mapping}#" "$env_file" >"$incomplete_mapping_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$incomplete_mapping_env" --check >/dev/null 2>&1; then
  printf 'ERROR: deploy loader unexpectedly accepted an incomplete Secret mapping.\n' >&2
  exit 1
fi

chmod 644 "$mapping_file"
if ! PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --check >/dev/null 2>&1; then
  printf 'ERROR: deploy loader unexpectedly rejected a 0644 Secret mapping.\n' >&2
  exit 1
fi

chmod 666 "$mapping_file"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --env-file "$env_file" --check >/dev/null 2>&1; then
  printf 'ERROR: deploy loader unexpectedly accepted a world-writable Secret mapping.\n' >&2
  exit 1
fi
chmod 600 "$mapping_file"

fallback_root="$tmp/fallback-root"
mkdir -p "$fallback_root"
cp "$env_file" "$fallback_root/.env"
resolved_fallback=$(bash -c '. "$1"; resolve_deploy_env_file "$2" ""' _ "$root/scripts/lib/read-deploy-env.sh" "$fallback_root")
test "$resolved_fallback" = "$fallback_root/.env"

printf 'PASS: Swarm orchestrator validates inputs and performs only explicit development operations.\n'
