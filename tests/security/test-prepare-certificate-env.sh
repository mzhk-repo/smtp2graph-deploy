#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/prepare-certificate-env.sh"
tmp=$(mktemp -d /dev/shm/smtp2graph-cert-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
bin="$tmp/bin" env_file="$tmp/env" staging="$tmp/.env.certificates"
mkdir -p "$bin" "$tmp/source"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -subj '/CN=smtp-int.example.invalid' -addext 'subjectAltName=DNS:smtp-int.example.invalid' \
  -keyout "$tmp/source/privkey.pem" -out "$tmp/source/fullchain.pem" >/dev/null 2>&1
cat >"$bin/certbot" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
config='' domain=''
while (($#)); do
  case "$1" in
    --config-dir) config=$2; shift 2 ;;
    -d) domain=$2; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "$config/live/$domain"
cp "$FAKE_CERT_SOURCE/fullchain.pem" "$config/live/$domain/fullchain.pem"
cp "$FAKE_CERT_SOURCE/privkey.pem" "$config/live/$domain/privkey.pem"
printf 'certbot\n' >>"$FAKE_CERT_CALLS"
EOF
chmod 700 "$bin/certbot"

printf '%s\n' \
  'DEPLOY_ENVIRONMENT=development' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' \
  'TLS_ACME_EMAIL=operator@example.invalid' \
  "TLS_ACME_STATE_DIR=$tmp/acme" \
  "TLS_OUTPUT_DIR=$tmp/output" \
  'CLOUDFLARE_DNS_API_TOKEN=synthetic-token' \
  'GRAPH_CERT_PRIVATE_KEY_PEM=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' \
  'GRAPH_CERTIFICATE_THUMBPRINT=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' \
  'TLS_CERTIFICATE_PEM=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' \
  'TLS_PRIVATE_KEY_PEM=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' >"$env_file"
chmod 600 "$env_file"

if PATH="$bin:$PATH" "$script" --env-file "$env_file" --staging-file "$staging" --check >/dev/null 2>&1; then
  printf 'ERROR: missing certificate values unexpectedly passed check.\n' >&2
  exit 1
fi
if PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_CERT_CALLS="$tmp/calls" "$script" --env-file "$env_file" --staging-file "$staging" --apply >/dev/null 2>&1; then
  printf 'ERROR: generation unexpectedly continued without SOPS handoff.\n' >&2
  exit 1
fi
[[ $(stat -c '%a' "$staging") == 600 ]]
grep -q '^GRAPH_CERT_PRIVATE_KEY_PEM=".*\\n' "$staging"
grep -Eq '^GRAPH_CERTIFICATE_THUMBPRINT=[a-f0-9]{40}$' "$staging"
grep -q '^TLS_CERTIFICATE_PEM=".*\\n' "$staging"
grep -q '^TLS_PRIVATE_KEY_PEM=".*\\n' "$staging"
openssl x509 -in "$tmp/output/graph-client-certificate.pem" -noout >/dev/null
[[ $(wc -l <"$tmp/calls") -eq 1 ]]
if PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_CERT_CALLS="$tmp/calls" "$script" --env-file "$env_file" --staging-file "$staging" --apply >/dev/null 2>&1; then
  printf 'ERROR: pending staging unexpectedly continued without SOPS handoff.\n' >&2
  exit 1
fi
[[ $(wc -l <"$tmp/calls") -eq 1 ]]

sed 's/^TLS_PRIVATE_KEY_PEM=.*/TLS_PRIVATE_KEY_PEM=existing/' "$env_file" >"$tmp/partial.env"
if PATH="$bin:$PATH" "$script" --env-file "$tmp/partial.env" --staging-file "$tmp/partial.stage" --apply >/dev/null 2>&1; then
  printf 'ERROR: partial TLS input was accepted.\n' >&2
  exit 1
fi
printf 'PASS: certificate preparation stages escaped PEM values and fails closed for incomplete input.\n'
