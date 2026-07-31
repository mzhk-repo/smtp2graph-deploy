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
mkdir -p "$fake_bin" "$tmp/docker-secrets"
cat >"$plain" <<'EOF'
DEPLOY_ENVIRONMENT: non-production
GRAPH_AUTH_MODE: certificate
GRAPH_TENANT_ID: 00000000-0000-0000-0000-000000000000
GRAPH_CLIENT_ID: 11111111-1111-1111-1111-111111111111
GRAPH_CERTIFICATE_THUMBPRINT: synthetic-thumbprint
GRAPH_CERT_PRIVATE_KEY_PEM: |
  -----BEGIN PRIVATE KEY-----
  synthetic-test-only
  -----END PRIVATE KEY-----
SMTP_USERS_TSV: "gateway\\tsynthetic-password\\tnoreply@example.invalid"
TLS_CERTIFICATE_PEM: |
  -----BEGIN CERTIFICATE-----
  synthetic-test-only
  -----END CERTIFICATE-----
TLS_PRIVATE_KEY_PEM: |
  -----BEGIN PRIVATE KEY-----
  synthetic-test-only
  -----END PRIVATE KEY-----
EOF
sops --encrypt --input-type yaml --age "$recipient" "$plain" >"$encrypted"
: >"$mapping"
chmod 600 "$mapping"
"$script" --environment non-production --env-file "$encrypted" --mapping-file "$mapping" | rg -q '^GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_v'
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
PATH="$fake_bin:$PATH" FAKE_DOCKER_SECRET_DIR="$tmp/docker-secrets" "$script" --environment non-production --env-file "$encrypted" --mapping-file "$mapping" --apply >/dev/null
rg -q '^GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_v' "$mapping"
[[ $(find "$tmp/docker-secrets" -type f | wc -l) -eq 7 ]]
if "${script}" --environment production --env-file "$encrypted" --mapping-file "$mapping" --apply >/dev/null 2>&1; then
  printf 'ERROR: production apply unexpectedly succeeded.\n' >&2
  exit 1
fi
printf 'PASS: SOPS secret reconciler uses encrypted inputs, deterministic names and non-production-only apply.\n'
