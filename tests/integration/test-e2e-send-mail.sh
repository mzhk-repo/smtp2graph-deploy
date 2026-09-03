#!/usr/bin/env bash
# Category 1a: Live end-to-end SMTP delivery test using Python standard library smtplib.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
python_helper="${script_dir}/smtp-send-mail.py"

env_file=''
smtp_host='127.0.0.1'
smtp_port=''
smtp_user='gateway'
smtp_user=''
password_file=''
sender=''
recipient=''
subject=''
tls_name=''
insecure=false

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE_EOF'
Usage: test-e2e-send-mail.sh [OPTIONS]

Options:
  --env-file FILE          Decrypted or plaintext environment file to read defaults from
  --smtp-host HOST         SMTP gateway host (default: 127.0.0.1)
  --smtp-port PORT         SMTP gateway port (default: 2525 or from env)
  --smtp-user USER         SMTP user for authentication (default: gateway)
  --password-file FILE     Path to file containing password (mode 0600)
  --sender SENDER          MAIL FROM address (default: GRAPH_SENDER_MAILBOX from env)
  --recipient RECIPIENT    RCPT TO address (default: NONPRODUCTION_RECIPIENT_ALLOWLIST from env)
  --subject TEXT           Subject of the test email
  --tls-name FQDN          TLS hostname for SNI (default: SMTP_TLS_FQDN from env)
  --insecure               Skip TLS certificate validation (e.g. for localhost test)
  -h, --help               Show this help message

Examples:
  # Using an env file (auto-extracts user password, sender, recipient, and TLS name):
  ./tests/integration/test-e2e-send-mail.sh --env-file /dev/shm/decrypted.env --insecure

  # Supplying arguments manually:
  ./tests/integration/test-e2e-send-mail.sh \
    --smtp-host 127.0.0.1 --smtp-port 2525 \
    --smtp-user gateway --password-file /path/to/password \
    --sender noreply@ldubgd.edu.ua --recipient user@example.com --insecure
USAGE_EOF
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
    --sender)
      sender=${2:-}
      shift 2
      ;;
    --recipient)
      recipient=${2:-}
      shift 2
      ;;
    --subject)
      subject=${2:-}
      shift 2
      ;;
    --tls-name)
      tls_name=${2:-}
      shift 2
      ;;
    --insecure)
      insecure=true
      shift
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

command -v python3 >/dev/null || die 'python3 is required.'
[[ -f "$python_helper" && -x "$python_helper" ]] || die 'Python helper smtp-send-mail.py is unavailable.'

read_env_value() {
  local expected_key=$1 line key value found=''
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    [[ "$key" == "$expected_key" ]] || continue
    [[ "$value" =~ ^\"(.*)\"$ ]] && value=${BASH_REMATCH[1]}
    [[ "$value" =~ ^\'(.*)\'$ ]] && value=${BASH_REMATCH[1]}
    found=$value
  done <"$env_file"
  printf '%s\n' "$found"
}

stage_dir=''
cleanup() {
  if [[ -n "$stage_dir" && -d "$stage_dir" ]]; then
    rm -rf -- "$stage_dir"
  fi
}
trap cleanup EXIT

if [[ -n "$env_file" ]]; then
  [[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die 'env file must be an absolute regular non-symlink file.'
  env_mode=$(stat -c '%a' "$env_file") || die 'could not read env file mode.'
  [[ "$env_mode" =~ ^[0-7]{3,4}$ && $((8#$env_mode & 077)) -eq 0 ]] || die 'env file must be readable only by its owner.'

  [[ -n "$sender" ]] || sender=$(read_env_value GRAPH_SENDER_MAILBOX)
  [[ -n "$recipient" ]] || recipient=$(read_env_value NONPRODUCTION_RECIPIENT_ALLOWLIST)
  [[ -n "$tls_name" ]] || tls_name=$(read_env_value SMTP_TLS_FQDN)
  [[ -n "$smtp_port" ]] || smtp_port=$(read_env_value SMTP_LISTEN_PORT)

  if [[ -z "$password_file" ]]; then
    users_escaped=$(read_env_value SMTP_USERS_TSV)
    if [[ -n "$users_escaped" ]]; then
      stage_dir=$(mktemp -d /dev/shm/smtp2graph-e2e.XXXXXX)
      chmod 700 "$stage_dir"
      password_file="$stage_dir/password"

      users=$(printf '%b' "$users_escaped")
      matched_user=''
      matched_password=''
      while IFS=$'\t' read -r u p _; do
        [[ -n "$u" && -n "$p" ]] || continue
        if [[ -z "$smtp_user" || "$u" == "$smtp_user" ]]; then
          matched_user=$u
          matched_password=$p
          break
        fi
      done <<<"$users"

      if [[ -n "$matched_password" ]]; then
        smtp_user=$matched_user
        umask 077
        printf '%s\n' "$matched_password" >"$password_file"
        chmod 600 "$password_file"
      else
        die "user '${smtp_user}' not found in SMTP_USERS_TSV."
        die "user '${smtp_user:-<any>}' not found in SMTP_USERS_TSV."
      fi
      unset users users_escaped matched_password
      unset users users_escaped matched_user matched_password
    fi
  fi
fi

# Fallback defaults
[[ -n "$smtp_user" ]] || smtp_user='gateway'
[[ -n "$smtp_port" ]] || smtp_port='2525'
[[ -n "$tls_name" ]] || tls_name='smtp-int.ldubgd.edu.ua'

# Validations
[[ "$smtp_host" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,253}$ ]] || die 'SMTP host is unsafe.'
if ! [[ "$smtp_port" =~ ^[0-9]{1,5}$ ]] || ((smtp_port < 1 || smtp_port > 65535)); then die 'SMTP port is invalid.'; fi
[[ "$smtp_user" =~ ^[A-Za-z0-9._@-]+$ ]] || die 'SMTP user is unsafe.'
[[ -n "$password_file" ]] || die 'password file or env file with SMTP_USERS_TSV is required.'
[[ -f "$password_file" && ! -L "$password_file" ]] || die 'password file must be a regular non-symlink file.'
[[ -n "$sender" ]] || die 'sender address is required (use --sender or --env-file).'
[[ -n "$recipient" ]] || die 'recipient address is required (use --recipient or --env-file).'

args=(
  --host "$smtp_host"
  --port "$smtp_port"
  --tls-name "$tls_name"
  --user "$smtp_user"
  --password-file "$password_file"
  --sender "$sender"
  --recipient "$recipient"
)

[[ -z "$subject" ]] || args+=(--subject "$subject")
[[ "$insecure" == false ]] || args+=(--insecure)

python3 "$python_helper" "${args[@]}"
