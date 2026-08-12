#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner="$root/tests/integration/check-moodle-starttls-contract.sh"
client="$root/tests/integration/moodle-starttls-contract.js"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
env_file="$tmp/moodle.env"

printf '%s\n' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' \
  'SMTP_LISTEN_PORT=2525' \
  'SMTP_USERS_TSV="moodle\\tsynthetic-password-not-for-output\\tnoreply@example.invalid"' >"$env_file"
chmod 0600 "$env_file"

bash -n "$runner"
node --check "$client"
if "$runner" --env-file "$env_file" --smtp-port invalid >/dev/null 2>&1; then
  printf 'ERROR: Moodle contract runner accepted an invalid SMTP port.\n' >&2
  exit 1
fi
chmod 0644 "$env_file"
if "$runner" --env-file "$env_file" >/dev/null 2>&1; then
  printf 'ERROR: Moodle contract runner accepted an env file readable by group or other.\n' >&2
  exit 1
fi

printf 'PASS: Moodle STARTTLS contract runner validates its safe input boundary.\n'
