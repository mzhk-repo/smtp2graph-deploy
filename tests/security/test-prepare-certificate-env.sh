#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/prepare-certificate-env.sh"
tmp=$(mktemp -d /dev/shm/smtp2graph-graph-cert-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
env_file="$tmp/env" staging="$tmp/.env.certificates"
mkdir -p "$tmp/parent"
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=development' \
  "TLS_OUTPUT_DIR=$tmp/parent/output" \
  'GRAPH_CERT_PRIVATE_KEY_PEM=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' \
  'GRAPH_CERTIFICATE_THUMBPRINT=REPLACE_WITH_SOPS_ENCRYPTED_SECRET' >"$env_file"
chmod 600 "$env_file"
if "$script" --env-file "$env_file" --staging-file "$staging" --check >/dev/null 2>&1; then
  printf 'ERROR: missing Graph certificate values unexpectedly passed.\n' >&2
  exit 1
fi
if "$script" --env-file "$env_file" --staging-file "$staging" --apply >/dev/null 2>&1; then
  printf 'ERROR: Graph certificate staging unexpectedly completed deployment.\n' >&2
  exit 1
fi
[[ $(stat -c '%a' "$staging") == 600 ]]
grep -q '^GRAPH_CERT_PRIVATE_KEY_PEM=".*\\n' "$staging"
grep -Eq '^GRAPH_CERTIFICATE_THUMBPRINT=[a-f0-9]{40}$' "$staging"
openssl x509 -in "$tmp/parent/output/graph-client-certificate.pem" -noout >/dev/null
printf 'PASS: Graph certificate preparation stages only Graph material for SOPS handoff.\n'
