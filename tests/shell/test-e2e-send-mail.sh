#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner="$root/tests/integration/test-e2e-send-mail.sh"
helper="$root/tests/integration/smtp-send-mail.py"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

env_file="$tmp/test.env"
password_file="$tmp/password"

printf '%s\n' \
  'GRAPH_SENDER_MAILBOX=noreply@example.invalid' \
  'NONPRODUCTION_RECIPIENT_ALLOWLIST=recipient@example.invalid' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' \
  'SMTP_LISTEN_PORT=2525' \
  'SMTP_USERS_TSV="gateway\ttestpass\tnoreply@example.invalid"' >"$env_file"
chmod 0600 "$env_file"

printf '%s\n' 'testpass' >"$password_file"
chmod 0600 "$password_file"

bash -n "$runner"
python3 -m py_compile "$helper"

# Test invalid port
if "$runner" --env-file "$env_file" --smtp-port invalid >/dev/null 2>&1; then
  printf 'ERROR: test runner accepted an invalid SMTP port.\n' >&2
  exit 1
fi

# Test missing password
if "$runner" --smtp-user gateway --sender a@b.c --recipient d@e.f >/dev/null 2>&1; then
  printf 'ERROR: test runner accepted missing password.\n' >&2
  exit 1
fi

# Test unsafe env file permissions
chmod 0644 "$env_file"
if "$runner" --env-file "$env_file" >/dev/null 2>&1; then
  printf 'ERROR: test runner accepted an env file readable by others.\n' >&2
  exit 1
fi

printf 'PASS: E2E send mail runner validates its safe input boundary.\n'
