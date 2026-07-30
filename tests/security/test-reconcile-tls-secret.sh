#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="${root}/scripts/reconcile-tls-secret.sh"
tmp=$(mktemp -d /dev/shm/smtp2graph-tls-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
key="$tmp/key.pem"; cert="$tmp/cert.pem"; mapping="$tmp/nonproduction.env"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$key" -out "$cert" -days 2 -subj '/CN=smtp-int.ldubgd.edu.ua' -addext 'subjectAltName=DNS:smtp-int.ldubgd.edu.ua' >/dev/null 2>&1
chmod 600 "$key" "$cert"; : > "$mapping"; chmod 600 "$mapping"
"$script" --environment non-production --certificate-file "$cert" --key-file "$key" --mapping-file "$mapping" | rg -q '^TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_v'
chmod 644 "$key"
if "$script" --environment non-production --certificate-file "$cert" --key-file "$key" --mapping-file "$mapping" >/dev/null 2>&1; then
  printf 'ERROR: writable/private-key mode validation unexpectedly succeeded.\n' >&2; exit 1
fi
printf 'PASS: TLS reconciler validates certificate identity, key match and private-key mode.\n'
