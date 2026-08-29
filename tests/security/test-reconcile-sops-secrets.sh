#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/reconcile-sops-secrets.sh"
recipient=$(awk '/^[[:space:]]+age: age1/{print $2; exit}' "$root/.sops.yaml")
tmp=$(mktemp -d /dev/shm/smtp2graph-sops-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
plain="$tmp/env.dev.enc"
encrypted="$tmp/environment.enc"
mapping="$tmp/mapping.env"
fake_bin="$tmp/bin"
server_env_file="$tmp/server.environment"
mkdir -p "$fake_bin" "$tmp/docker-secrets"
cat >"$plain" <<'EOF'
DEPLOY_ENVIRONMENT="development"
GRAPH_AUTH_MODE="certificate"
GRAPH_TENANT_ID="00000000-0000-0000-0000-000000000000"
GRAPH_CLIENT_ID="11111111-1111-1111-1111-111111111111"
GRAPH_CERTIFICATE_THUMBPRINT="synthetic-thumbprint"
GRAPH_CERT_PRIVATE_KEY_PEM="synthetic-private-key-line-one\nsynthetic-private-key-line-two"
SMTP_USERS_TSV="gateway\tsynthetic-password!\tnoreply@example.invalid"
TLS_CERTIFICATE_PEM="synthetic-certificate-line-one\nsynthetic-certificate-line-two"
TLS_PRIVATE_KEY_PEM="synthetic-tls-key-line-one\nsynthetic-tls-key-line-two"
GRAPH_SENDER_MAILBOX="noreply@example.invalid"
EOF
chmod 600 "$plain"
sops --encrypt --input-type dotenv --output-type dotenv --age "$recipient" "$plain" >"$encrypted"
: >"$mapping"
chmod 600 "$mapping"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env_file"
SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --environment development --env-file "$encrypted" --mapping-file "$mapping" | grep -Eq '^GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_v'
SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --environment development --env-file "$plain" --mapping-file "$mapping" | grep -Eq '^GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_v'
cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  secret)
    case "$2" in
      inspect) test -f "${FAKE_DOCKER_SECRET_DIR}/$3" ;;
      create) cp "$4" "${FAKE_DOCKER_SECRET_DIR}/$3" ;;
    esac
    ;;
esac
EOF
chmod 700 "$fake_bin/docker"
PATH="$fake_bin:$PATH" FAKE_DOCKER_SECRET_DIR="$tmp/docker-secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --environment development --env-file "$encrypted" --mapping-file "$mapping" --apply >/dev/null
grep -Eq '^GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_v' "$mapping"
[[ $(find "$tmp/docker-secrets" -type f | wc -l) -eq 7 ]]
grep -Eq '^synthetic-private-key-line-two$' "$tmp/docker-secrets"/*
grep -Eq 'synthetic-password!' "$tmp/docker-secrets"/*
grep -Fq $'gateway\tsynthetic-password!\tnoreply@example.invalid' "$tmp/docker-secrets"/*
if SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "${script}" --environment production --env-file "$encrypted" --mapping-file "$mapping" --apply >/dev/null 2>&1; then
  printf 'ERROR: production apply unexpectedly succeeded.\n' >&2
  exit 1
fi
chmod 640 "$plain"
if SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --environment development --env-file "$plain" --mapping-file "$mapping" >/dev/null 2>&1; then
  printf 'ERROR: reconciler unexpectedly accepted group-readable plaintext input.\n' >&2
  exit 1
fi
invalid_plain="$tmp/invalid-smtp-users.env"
awk '
  /^SMTP_USERS_TSV=/ { print "SMTP_USERS_TSV=\"gateway synthetic-password noreply@example.invalid\""; next }
  { print }
' "$plain" >"$invalid_plain"
chmod 600 "$invalid_plain"
if SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$script" --environment development --env-file "$invalid_plain" --mapping-file "$mapping" >/dev/null 2>&1; then
  printf 'ERROR: reconciler unexpectedly accepted malformed SMTP user input.\n' >&2
  exit 1
fi
printf 'PASS: SOPS secret reconciler handles encrypted and owner-only CI plaintext inputs with deterministic names and dev/prod guards.\n'
