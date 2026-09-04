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
staged_tls_certificate=$(sed -n 's/^TLS_CERTIFICATE_PEM="\(.*\)"$/\1/p' "$staging")
staged_tls_private_key=$(sed -n 's/^TLS_PRIVATE_KEY_PEM="\(.*\)"$/\1/p' "$staging")
printf '%b' "$staged_tls_certificate" >"$tmp/staged-tls-cert.pem"
printf '%b' "$staged_tls_private_key" >"$tmp/staged-tls-key.pem"
openssl x509 -in "$tmp/staged-tls-cert.pem" -noout >/dev/null
openssl pkey -in "$tmp/staged-tls-key.pem" -noout >/dev/null
[[ $(wc -l <"$tmp/calls") -eq 1 ]]
if PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_CERT_CALLS="$tmp/calls" "$script" --env-file "$env_file" --staging-file "$staging" --apply >/dev/null 2>&1; then
  printf 'ERROR: pending staging unexpectedly continued without SOPS handoff.\n' >&2
  exit 1
fi
[[ $(wc -l <"$tmp/calls") -eq 1 ]]

mkdir -p "$tmp/restricted"
cat >"$bin/install" <<'EOF'
#!/usr/bin/env bash
target=${!#}
if [[ "$target" == "$FAKE_DENIED_DIR" && "${FAKE_SUDO_USED:-}" != true ]]; then
  exit 1
fi
exec /usr/bin/install "$@"
EOF
chmod 700 "$bin/install"
cat >"$bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo\n' >>"$FAKE_CERT_CALLS"
FAKE_SUDO_USED=true "$@"
EOF
chmod 700 "$bin/sudo"
cat >"$bin/id" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -u | -g) printf '1001\n' ;;
  *) exec /usr/bin/id "$@" ;;
esac
EOF
chmod 700 "$bin/id"
sed "s|^TLS_OUTPUT_DIR=.*|TLS_OUTPUT_DIR=$tmp/restricted/output|" "$env_file" >"$tmp/escalated.env"
PATH="$bin:$PATH" FAKE_CERT_SOURCE="$tmp/source" FAKE_CERT_CALLS="$tmp/calls" FAKE_DENIED_DIR="$tmp/restricted/output" "$script" --env-file "$tmp/escalated.env" --staging-file "$tmp/escalated.stage" --apply >/dev/null 2>&1 || test $? -eq 75
grep -q '^sudo$' "$tmp/calls"
[[ $(stat -c '%u:%g:%a' "$tmp/restricted/output") == 1001:1001:700 ]]

sed 's/^TLS_PRIVATE_KEY_PEM=.*/TLS_PRIVATE_KEY_PEM=existing/' "$env_file" >"$tmp/partial.env"
if PATH="$bin:$PATH" "$script" --env-file "$tmp/partial.env" --staging-file "$tmp/partial.stage" --apply >/dev/null 2>&1; then
  printf 'ERROR: partial TLS input was accepted.\n' >&2
  exit 1
fi
printf 'PASS: certificate preparation stages escaped PEM values and fails closed for incomplete input.\n'
