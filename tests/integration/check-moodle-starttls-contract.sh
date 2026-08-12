#!/usr/bin/env bash
# Category 1a: Task 6.1 Moodle SMTP STARTTLS and authentication contract check.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
client="${script_dir}/moodle-starttls-contract.js"
env_file=''
smtp_host='127.0.0.1'
smtp_port=''
smtp_user='moodle'
password_file=''

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' 'Usage: check-moodle-starttls-contract.sh --env-file FILE [--smtp-host HOST] [--smtp-port PORT] [--smtp-user USER --password-file FILE]'
}

while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
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
    --smtp-user)
      smtp_user=${2:-}
      shift 2
      ;;
    --password-file)
      password_file=${2:-}
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
[[ "$smtp_host" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,253}$ ]] || die 'SMTP host is unsafe.'
[[ "$smtp_user" =~ ^[A-Za-z0-9._@-]+$ ]] || die 'SMTP user is unsafe.'
[[ -z "$password_file" || "$password_file" = /* && -f "$password_file" && ! -L "$password_file" ]] || die 'password file must be an absolute regular non-symlink file.'
[[ -x "$client" ]] || die 'Moodle STARTTLS client is unavailable.'
for tool in awk stat node mktemp; do command -v "$tool" >/dev/null || die "$tool is required."; done

env_mode=$(stat -c '%a' "$env_file") || die 'could not read env file mode.'
[[ "$env_mode" =~ ^[0-7]{3,4}$ && $((8#$env_mode & 077)) -eq 0 ]] || die 'env file must be readable only by its owner.'

read_value() {
  local expected_key=$1 line key value found=''
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die 'env file contains invalid syntax.'
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    [[ "$value" =~ ^\"(.*)\"$ ]] && value=${BASH_REMATCH[1]}
    [[ "$key" == "$expected_key" ]] || continue
    [[ -z "$found" ]] || die "env file contains duplicate ${expected_key}."
    found=$value
  done <"$env_file"
  [[ -n "$found" ]] || die "env file is missing ${expected_key}."
  printf '%s\n' "$found"
}

tls_name=$(read_value SMTP_TLS_FQDN)
configured_port=$(read_value SMTP_LISTEN_PORT)
[[ "$tls_name" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,253}$ ]] || die 'SMTP TLS hostname is invalid.'
if [[ -z "$smtp_port" ]]; then smtp_port=$configured_port; fi
[[ "$smtp_port" =~ ^[0-9]{1,5}$ ]] && ((smtp_port >= 1 && smtp_port <= 65535)) || die 'SMTP port is invalid.'

if [[ -n "$password_file" ]]; then
  password_mode=$(stat -c '%a' "$password_file") || die 'could not read password file mode.'
  [[ "$password_mode" =~ ^[0-7]{3,4}$ && $((8#$password_mode & 077)) -eq 0 ]] || die 'password file must be readable only by its owner.'
else
  users_escaped=$(read_value SMTP_USERS_TSV)
  stage_dir=$(mktemp -d /dev/shm/smtp2graph-moodle-contract.XXXXXX)
  chmod 700 "$stage_dir"
  password_file="$stage_dir/password"
  cleanup() { rm -rf -- "$stage_dir"; }
  trap cleanup EXIT

  users=$(printf '%b' "$users_escaped")
  moodle_password=''
  while IFS=$'\t' read -r username password sender_scope; do
    [[ -n "$username" && -n "$password" && -n "$sender_scope" ]] || die 'SMTP_USERS_TSV contains an invalid record.'
    [[ "$username" == "$smtp_user" ]] || continue
    [[ -z "$moodle_password" ]] || die "SMTP_USERS_TSV contains duplicate ${smtp_user} user."
    moodle_password=$password
  done <<<"$users"
  [[ -n "$moodle_password" ]] || die "SMTP_USERS_TSV does not contain ${smtp_user} user."
  umask 077
  printf '%s\n' "$moodle_password" >"$password_file"
  chmod 600 "$password_file"
  unset users users_escaped moodle_password password
fi

node "$client" "$smtp_host" "$smtp_port" "$tls_name" "$smtp_user" "$password_file"
