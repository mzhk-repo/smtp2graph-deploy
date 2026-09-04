#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/renew-tls-certificate.sh"
tmp=$(mktemp -d /dev/shm/smtp2graph-renew-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
bin="$tmp/bin" mapping="$tmp/mapping.env" env_file="$tmp/env" server_env="$tmp/server.env"
mkdir -p "$bin" "$tmp/secrets" "$tmp/source"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=smtp-int.example.invalid' -addext 'subjectAltName=DNS:smtp-int.example.invalid' -keyout "$tmp/source/privkey.pem" -out "$tmp/source/fullchain.pem" >/dev/null 2>&1
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=development' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' \
  'TLS_ACME_EMAIL=operator@example.invalid' \
  "TLS_ACME_STATE_DIR=$tmp/acme" \
  "TLS_SECRET_MAPPING_FILE=$mapping" \
  'CLOUDFLARE_DNS_API_TOKEN=synthetic-token' \
  'SWARM_STACK_NAME=smtp2graph' >"$env_file"
chmod 600 "$env_file"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env"
: >"$mapping"
chmod 600 "$mapping"
cat >"$bin/sops" <<'EOF'
#!/usr/bin/env bash
cat "${!#}"
EOF
cat >"$bin/certbot" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config='' domain=''
while (($#)); do case "$1" in --config-dir) config=$2; shift 2;; -d) domain=$2; shift 2;; *) shift;; esac; done
mkdir -p "$config/archive/$domain" "$config/live/$domain"
cp "$FAKE_CERT_SOURCE/fullchain.pem" "$config/archive/$domain/fullchain1.pem"
cp "$FAKE_CERT_SOURCE/privkey.pem" "$config/archive/$domain/privkey1.pem"
ln -sfn "$config/archive/$domain/fullchain1.pem" "$config/live/$domain/fullchain.pem"
ln -sfn "$config/archive/$domain/privkey1.pem" "$config/live/$domain/privkey.pem"
EOF
cat >"$bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'secret inspect') test -f "$FAKE_SECRET_DIR/$3" ;;
  'secret create') cp "$4" "$FAKE_SECRET_DIR/$3" ;;
  *) exit 1 ;;
esac
EOF
chmod 700 "$bin"/*
PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_SECRET_DIR="$tmp/secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env" "$script" --env-file "$env_file" --check >/dev/null
PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_SECRET_DIR="$tmp/secrets" SMTP2GRAPH_SERVER_ENV_FILE="$server_env" "$script" --env-file "$env_file" --prepare-only --apply >/dev/null
grep -Eq '^TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_v' "$mapping"
grep -Eq '^TLS_PRIVATE_KEY_SECRET_NAME=smtp2graph_tls_private_key_v' "$mapping"
[[ $(find "$tmp/secrets" -type f | wc -l) -eq 2 ]]
printf 'PASS: TLS renewal prepares lineage-backed immutable Secrets without a service update.\n'
