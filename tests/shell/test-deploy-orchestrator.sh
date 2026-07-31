#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/deploy-orchestrator-swarm.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
calls="$tmp/docker.calls"
env_file="$tmp/non-production.env"
mkdir -p "$fake_bin"

valid_digest='example.invalid/smtp2graph@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
rollback_digest='example.invalid/smtp2graph@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=non-production' \
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
  'SMTP_ALLOWED_SENDER_ADDRESSES=noreply@example.invalid' \
  'GRAPH_SENDER_MAILBOX=noreply@example.invalid' \
  'SEND_RETRY_LIMIT=1' \
  'SEND_RETRY_INTERVAL_MINUTES=1' \
  'GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_vtest' \
  'GRAPH_CLIENT_ID_SECRET_NAME=smtp2graph_graph_client_id_vtest' \
  'GRAPH_CREDENTIAL_SECRET_NAME=smtp2graph_graph_credential_vtest' \
  'GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_vtest' \
  'SMTP_CREDENTIALS_SECRET_NAME=smtp2graph_smtp_users_vtest' \
  'TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_vtest' \
  'TLS_PRIVATE_KEY_SECRET_NAME=smtp2graph_tls_private_key_vtest' >"$env_file"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_DOCKER_CALLS}"
if [[ "${1:-} ${2:-}" == 'stack deploy' ]]; then
  printf 'digest=%s\n' "${SMTP2GRAPH_IMAGE_DIGEST}" >>"${FAKE_DOCKER_CALLS}"
fi
case "${1:-} ${2:-}" in
  'stack config') exit 0 ;;
  'stack deploy') exit 0 ;;
  'info --format') printf '%s\n' true ;;
  info\ *) exit 0 ;;
  'service inspect' | 'service ps') exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$fake_bin/docker"

PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --check >/dev/null
rg -q '^stack config ' "$calls"
if rg -q '^stack deploy ' "$calls"; then
  printf 'ERROR: check unexpectedly submitted a stack deploy.\n' >&2
  exit 1
fi

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --deploy --apply >/dev/null
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --deploy --apply >/dev/null
test "$(rg -c '^stack deploy ' "$calls")" -eq 2
if rg -q -- '--prune' "$calls"; then
  printf 'ERROR: deploy unexpectedly used --prune.\n' >&2
  exit 1
fi

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --status >/dev/null
rg -q '^service inspect smtp2graph_gateway$' "$calls"
rg -q '^service ps smtp2graph_gateway --no-trunc$' "$calls"

: >"$calls"
PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --rollback --image-digest "$rollback_digest" --queue-compatibility-confirmed --apply >/dev/null
rg -q '^stack deploy ' "$calls"
rg -q "^digest=${rollback_digest}$" "$calls"

if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$env_file" --rollback --image-digest "$rollback_digest" --apply >/dev/null 2>&1; then
  printf 'ERROR: rollback unexpectedly skipped queue compatibility confirmation.\n' >&2
  exit 1
fi

production_env="$tmp/production.env"
sed 's/^DEPLOY_ENVIRONMENT=non-production$/DEPLOY_ENVIRONMENT=production/' "$env_file" >"$production_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$production_env" --deploy --apply >/dev/null 2>&1; then
  printf 'ERROR: production deploy was unexpectedly accepted.\n' >&2
  exit 1
fi

placeholder_env="$tmp/placeholder.env"
sed 's#^SMTP2GRAPH_IMAGE_DIGEST=.*#SMTP2GRAPH_IMAGE_DIGEST=example.invalid/smtp2graph:latest#' "$env_file" >"$placeholder_env"
if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --env-file "$placeholder_env" --check >/dev/null 2>&1; then
  printf 'ERROR: mutable image tag was unexpectedly accepted.\n' >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" FAKE_DOCKER_CALLS="$calls" "$script" --check >/dev/null 2>&1; then
  printf 'ERROR: implicit local env fallback was unexpectedly accepted.\n' >&2
  exit 1
fi

printf 'PASS: Swarm orchestrator validates inputs and performs only explicit non-production operations.\n'
