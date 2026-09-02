#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
runner="$root/tests/integration/run-gateway-format-matrix.sh"
client="$root/tests/integration/smtp-format-matrix.js"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
env_file="$tmp/integration.env"
password_file="$tmp/password"

printf '%s\n' \
  'GRAPH_SENDER_MAILBOX=noreply@example.invalid' \
  'NONPRODUCTION_RECIPIENT_ALLOWLIST=recipient@example.invalid' \
  'SMTP_TLS_FQDN=smtp-int.example.invalid' >"$env_file"
printf '%s\n' 'synthetic-password-not-for-output' >"$password_file"
chmod 0600 "$env_file" "$password_file"

bash -n "$runner"
if command -v node >/dev/null 2>&1; then
  node --check "$client"
else
  fake_bin="$tmp/bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
case "${9:-}" in
  plain-text|html-unicode|recipient-headers|bcc-envelope|reply-to|attachment|inline-attachment|"") exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod 700 "$fake_bin/node"
  PATH="$fake_bin:$PATH"
fi
if "$runner" --env-file "$env_file" --smtp-user invalid --password-file "$password_file" --smtp-port invalid >/dev/null 2>&1; then
  printf 'ERROR: integration runner accepted an invalid SMTP port.\n' >&2
  exit 1
fi
if "$runner" --env-file "$env_file" --smtp-user invalid --password-file "$password_file" --case invalid >/dev/null 2>&1; then
  printf 'ERROR: integration runner accepted an unsupported format case.\n' >&2
  exit 1
fi
chmod 0644 "$env_file"
if "$runner" --env-file "$env_file" --smtp-user invalid --password-file "$password_file" >/dev/null 2>&1; then
  printf 'ERROR: integration runner accepted an env file readable by group or other.\n' >&2
  exit 1
fi

printf 'PASS: Task 6.1 format matrix validates its safe input boundary.\n'
