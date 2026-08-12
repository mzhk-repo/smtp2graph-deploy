#!/usr/bin/env bash
# Category 1a: Task 6.1 non-production gateway format delivery submission.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "${script_dir}/../.." && pwd)
client="${script_dir}/smtp-format-matrix.js"
env_file=''
smtp_user=''
password_file=''
smtp_host='127.0.0.1'
smtp_port='2525'
selected_case=''

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: run-gateway-format-matrix.sh --env-file FILE --smtp-user USER --password-file FILE [--smtp-host HOST] [--smtp-port PORT] [--case NAME]'
}

while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --smtp-user)
      smtp_user=${2:-}
      shift 2
      ;;
    --password-file)
      password_file=${2:-}
      shift 2
      ;;
    --smtp-host)
      smtp_host=${2:-}
      shift 2
      ;;
    --smtp-port)
      smtp_port=${2:-}
      shift 2
      ;;
    --case)
      selected_case=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unsupported argument: $1"
      ;;
  esac
done

[[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die 'env file must be an absolute regular non-symlink file.'
[[ "$smtp_user" =~ ^[A-Za-z0-9._@-]+$ ]] || die 'SMTP user is unsafe.'
[[ "$password_file" = /* && -f "$password_file" && ! -L "$password_file" ]] || die 'password file must be an absolute regular non-symlink file.'
[[ "$smtp_host" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,253}$ ]] || die 'SMTP host is unsafe.'
[[ "$smtp_port" =~ ^[0-9]{1,5}$ ]] && ((smtp_port >= 1 && smtp_port <= 65535)) || die 'SMTP port is invalid.'
[[ -z "$selected_case" || "$selected_case" =~ ^[a-z0-9-]+$ ]] || die 'test case is unsafe.'
[[ -x "$client" ]] || die 'SMTP format client is unavailable.'
for tool in awk stat node; do command -v "$tool" >/dev/null || die "$tool is required."; done

env_mode=$(stat -c '%a' "$env_file") || die 'could not read env file mode.'
password_mode=$(stat -c '%a' "$password_file") || die 'could not read password file mode.'
[[ "$env_mode" =~ ^[0-7]{3,4}$ && $((8#$env_mode & 077)) -eq 0 ]] || die 'env file must be readable only by its owner.'
[[ "$password_mode" =~ ^[0-7]{3,4}$ && $((8#$password_mode & 077)) -eq 0 ]] || die 'password file must be readable only by its owner.'

read_value() {
  local expected_key=$1 line key value found=''
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die 'env file contains invalid syntax.'
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    [[ "$key" == "$expected_key" ]] || continue
    [[ -z "$found" ]] || die "env file contains duplicate ${expected_key}."
    [[ "$value" =~ ^\"(.*)\"$ ]] && value=${BASH_REMATCH[1]}
    found=$value
  done <"$env_file"
  [[ -n "$found" ]] || die "env file is missing ${expected_key}."
  printf '%s\n' "$found"
}

sender=$(read_value GRAPH_SENDER_MAILBOX)
recipient=$(read_value NONPRODUCTION_RECIPIENT_ALLOWLIST)
tls_name=$(read_value SMTP_TLS_FQDN)
[[ "$sender" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || die 'canonical sender is invalid.'
[[ "$recipient" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || die 'non-production recipient is invalid.'
[[ "$tls_name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,253}$ ]] || die 'SMTP TLS hostname is invalid.'

node "$client" "$smtp_host" "$smtp_port" "$tls_name" "$smtp_user" "$password_file" "$sender" "$recipient" "$selected_case"
