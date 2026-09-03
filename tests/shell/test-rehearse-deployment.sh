#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/rehearse-deployment.sh"
tmp=$(mktemp -d)
password_file=$(mktemp /dev/shm/smtp2graph-rehearsal-password.XXXXXX)
trap 'rm -rf -- "$tmp"; rm -f -- "$password_file"' EXIT
fake_bin="$tmp/bin"
storage="$tmp/data"
env_file="$tmp/development.env"
mapping_file="$tmp/secret-mapping.env"
server_env="$tmp/server.environment"
evidence="$tmp/evidence"
secret_state="$tmp/secret-state"
mkdir -p "$fake_bin" "$storage/queue" "$evidence"
chmod 700 "$evidence"
tls_cert="$tmp/tls-cert.pem"
tls_key="$tmp/tls-key.pem"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -subj '/CN=smtp-int.example.invalid' -addext 'subjectAltName=DNS:smtp-int.example.invalid' \
  -keyout "$tls_key" -out "$tls_cert" >/dev/null 2>&1
tls_certificate_escaped=$(awk '{ printf "%s\\n", $0 }' "$tls_cert")
tls_private_key_escaped=$(awk '{ printf "%s\\n", $0 }' "$tls_key")
printf '%s\n' 'synthetic-test-password' >"$password_file"
chmod 600 "$password_file"

current='example.invalid/smtp2graph@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
candidate='example.invalid/smtp2graph@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=development' \
  "SMTP2GRAPH_IMAGE_DIGEST=${current}" \
  'SWARM_STACK_NAME=smtp2graph' \
  'SWARM_OVERLAY_NETWORK=smtp2graph_internal' \
  "SMTP2GRAPH_STORAGE_HOST_PATH=${storage}" \
  "SMTP2GRAPH_BACKUP_LOCAL_DIR=${storage}/backups" \
  'SMTP2GRAPH_BACKUP_RCLONE_REMOTE=gdrive-backup' \
  'SMTP2GRAPH_BACKUP_RCLONE_PATH=smtp2graph/dev' \
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
  "TLS_CERTIFICATE_PEM=\"${tls_certificate_escaped}\"" \
  "TLS_PRIVATE_KEY_PEM=\"${tls_private_key_escaped}\"" \
  'NONPRODUCTION_RECIPIENT_ALLOWLIST=recipient@example.invalid' >"$env_file"
chmod 600 "$env_file"
printf '%s\n' \
  'GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_vtest' \
  'GRAPH_CLIENT_ID_SECRET_NAME=smtp2graph_graph_client_id_vtest' \
  'GRAPH_CREDENTIAL_SECRET_NAME=smtp2graph_graph_credential_vtest' \
  'GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_vtest' \
  'SMTP_CREDENTIALS_SECRET_NAME=smtp2graph_smtp_users_vtest' \
  'TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_vtest' \
  'TLS_PRIVATE_KEY_SECRET_NAME=smtp2graph_tls_private_key_vtest' >"$mapping_file"
chmod 600 "$mapping_file"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env"
cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'info --format') printf '%s\n' true ;;
  info\ *) exit 0 ;;
  'stack config') exit 0 ;;
  'stack deploy')
    if [[ "${GRAPH_CREDENTIAL_SECRET_NAME:-}" != smtp2graph_rehearsal_graph_cred_* ]]; then rm -f -- "${FAKE_QUEUE_DIR}/rehearsal.eml"; fi
    exit 0
    ;;
  'service inspect')
    if [[ "$*" == *'.Spec.Mode.Replicated.Replicas'* ]]; then printf '%s\n' 1
    else printf '%s\n' \
      'graph-tenant-id 65532 65532 292' 'graph-client-id 65532 65532 292' \
      'graph-certificate-thumbprint 65532 65532 292' 'graph-credential 65532 65532 256' \
      'smtp-users 65532 65532 256' 'smtp-tls-cert 65532 65532 292' 'smtp-tls-key 65532 65532 256'; fi
    ;;
  'service ps')
    if [[ "$*" == *'{{.ID}}'* ]]; then printf '%s\n' task123
    else printf '%s\n' 'Running 1 second ago|'; fi
    ;;
  'network inspect')
    printf '%s\n' 'overlay swarm {"encrypted":"true"}'
    exit 0
    ;;
  'network create') exit 0 ;;
  'secret inspect') [[ -f "${FAKE_SECRET_STATE}" ]] ;;
  'secret create') touch "${FAKE_SECRET_STATE}" ;;
  'secret rm') rm -f -- "${FAKE_SECRET_STATE}" ;;
  *) exit 1 ;;
esac
EOF
cat >"$fake_bin/smoke" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'PASS: fake smoke\n'
EOF
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
cat >"$fake_bin/init-storage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
cat >"$fake_bin/bootstrap-host" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "${FAKE_QUEUE_DIR}/rehearsal.eml"
printf 'PASS: fake SMTP submit\n'
EOF
cat >"$fake_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == env ]]; then
  shift
  while [[ "${1:-}" == *=* ]]; do shift; done
fi
exec "$@"
EOF
chmod 700 "$fake_bin/docker" "$fake_bin/smoke" "$fake_bin/node" "$fake_bin/sops" "$fake_bin/init-storage" "$fake_bin/bootstrap-host" "$fake_bin/sudo"
export SMTP_BOOTSTRAP_HOST_SCRIPT="$fake_bin/bootstrap-host"

PATH="$fake_bin:$PATH" \
  FAKE_QUEUE_DIR="$storage/queue" FAKE_SECRET_STATE="$secret_state" \
  SMTP2GRAPH_SERVER_ENV_FILE="$server_env" \
  SMTP_INIT_STORAGE_SCRIPT="$fake_bin/init-storage" \
  SMTP2GRAPH_SMOKE_SCRIPT="$fake_bin/smoke" SMTP2GRAPH_SMTP_SUBMIT_HELPER="$root/tests/acceptance/deployment/smtp-submit.js" \
  "$script" --env-file "$env_file" --current-digest "$current" --candidate-digest "$candidate" \
  --recipient recipient@example.invalid --smtp-user rehearsal-client --password-file "$password_file" \
  --backup-reference backup-20260803 --evidence-dir "$evidence" --apply >/dev/null

test ! -e "$secret_state"
test ! -e "$storage/queue/rehearsal.eml"
test "$(find "$evidence" -type f | wc -l)" -eq 1
grep -Eq '^rollback-and-queue-drain=passed$' "$evidence"/*

if PATH="$fake_bin:$PATH" SMTP2GRAPH_SERVER_ENV_FILE="$server_env" \
  "$script" --env-file "$env_file" --current-digest "$current" --candidate-digest "$candidate" \
  --recipient outsider@example.invalid --smtp-user rehearsal-client --password-file "$password_file" \
  --backup-reference backup-20260803 --evidence-dir "$evidence" --apply >/dev/null 2>&1; then
  printf 'ERROR: rehearsal unexpectedly accepted a non-allowlisted recipient.\n' >&2
  exit 1
fi

chmod 644 "$password_file"
if PATH="$fake_bin:$PATH" SMTP2GRAPH_SERVER_ENV_FILE="$server_env" \
  "$script" --env-file "$env_file" --current-digest "$current" --candidate-digest "$candidate" \
  --recipient recipient@example.invalid --smtp-user rehearsal-client --password-file "$password_file" \
  --backup-reference backup-20260803 --evidence-dir "$evidence" --apply >/dev/null 2>&1; then
  printf 'ERROR: rehearsal unexpectedly accepted weak password-file permissions.\n' >&2
  exit 1
fi
printf 'PASS: deployment rehearsal validates safety inputs and restores temporary state.\n'
