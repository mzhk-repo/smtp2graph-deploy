#!/bin/sh
# POSIX helper for rendering SMTP policy YAML from non-secret inputs and a Docker Secret TSV.

yaml_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/''/g"
  printf "'"
}

normalize_email() {
  value=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case "${value}" in
    '' | *@ | @*) return 1 ;;
  esac
  local_part=${value%@*}
  domain_part=${value#*@}
  [ -n "${local_part}" ] && [ -n "${domain_part}" ] || return 1
  case "${domain_part}" in
    *@*) return 1 ;;
  esac
  printf '%s\n' "${value}" | grep -Eq '^[^[:space:]@]+@[^[:space:]@]+$' || return 1
  case "${domain_part}" in
    .* | *..* | *.) return 1 ;;
  esac
  printf '%s\n' "${value}"
}

normalize_email_csv() {
  remaining=$1
  normalized=''
  [ -n "${remaining}" ] || return 1

  while :; do
    value=${remaining%%,*}
    if [ "${remaining}" = "${value}" ]; then
      remaining=''
    else
      remaining=${remaining#*,}
    fi
    email=$(normalize_email "${value}") || return 1
    if [ -n "${normalized}" ] && printf '%s\n' "${normalized}" | grep -F -x -- "${email}" >/dev/null; then
      return 1
    fi
    if [ -n "${normalized}" ]; then
      normalized="${normalized}
${email}"
    else
      normalized=${email}
    fi
    [ -n "${remaining}" ] || break
  done
  printf '%s\n' "${normalized}"
}

normalize_cidr_csv() {
  remaining=$1
  normalized=''
  [ -n "${remaining}" ] || return 1

  while :; do
    value=${remaining%%,*}
    if [ "${remaining}" = "${value}" ]; then
      remaining=''
    else
      remaining=${remaining#*,}
    fi
    case "${value}" in
      '' | *[!0-9A-Fa-f:./]*) return 1 ;;
    esac
    if [ -n "${normalized}" ] && printf '%s\n' "${normalized}" | grep -F -x -- "${value}" >/dev/null; then
      return 1
    fi
    if [ -n "${normalized}" ]; then
      normalized="${normalized}
${value}"
    else
      normalized=${value}
    fi
    [ -n "${remaining}" ] || break
  done
  printf '%s\n' "${normalized}"
}

render_yaml_list() {
  indent=$1
  values=$2
  printf '%s\n' "${values}" | while IFS= read -r value; do
    [ -n "${value}" ] || return 1
    printf '%s- %s\n' "${indent}" "$(yaml_quote "${value}")"
  done
}

render_smtp_users() {
  users_file=$1
  global_senders=$2
  line_number=0
  user_count=0
  usernames=''

  while IFS= read -r line || [ -n "${line}" ]; do
    line_number=$((line_number + 1))
    line=$(printf '%s' "${line}" | tr -d '\r')
    [ -n "${line}" ] || {
      printf 'ERROR: malformed SMTP users record at line %s (credentials redacted).\n' "${line_number}" >&2
      return 1
    }
    tab_count=$(printf '%s' "${line}" | tr -cd '\t' | wc -c | tr -d ' ')
    if [ "${tab_count}" -ne 2 ]; then
      printf 'ERROR: malformed SMTP users record at line %s (credentials redacted).\n' "${line_number}" >&2
      return 1
    fi
    tab=$(printf '\t')
    IFS="${tab}" read -r username password sender_csv <<EOF
${line}
EOF
    case "${username}" in
      '' | *[!A-Za-z0-9._@-]*)
        printf 'ERROR: malformed SMTP users record at line %s (credentials redacted).\n' "${line_number}" >&2
        return 1
        ;;
    esac
    [ -n "${password}" ] || {
      printf 'ERROR: malformed SMTP users record at line %s (credentials redacted).\n' "${line_number}" >&2
      return 1
    }
    if [ -n "${usernames}" ] && printf '%s\n' "${usernames}" | grep -F -x -- "${username}" >/dev/null; then
      printf 'ERROR: duplicate SMTP username at line %s (credentials redacted).\n' "${line_number}" >&2
      return 1
    fi
    user_senders=$(normalize_email_csv "${sender_csv}") || {
      printf 'ERROR: malformed SMTP users sender policy at line %s (credentials redacted).\n' "${line_number}" >&2
      return 1
    }
    while IFS= read -r sender; do
      if ! printf '%s\n' "${global_senders}" | grep -F -x -- "${sender}" >/dev/null; then
        printf 'ERROR: SMTP user sender is outside the global allowlist at line %s (credentials redacted).\n' "${line_number}" >&2
        return 1
      fi
    done <<EOF
${user_senders}
EOF
    printf '  - username: %s\n' "$(yaml_quote "${username}")"
    printf '    password: %s\n' "$(yaml_quote "${password}")"
    printf '    allowedFrom:\n'
    render_yaml_list '      ' "${user_senders}" || return 1
    if [ -n "${usernames}" ]; then
      usernames="${usernames}
${username}"
    else
      usernames=${username}
    fi
    user_count=$((user_count + 1))
  done <"${users_file}"

  [ "${user_count}" -gt 0 ] || {
    printf 'ERROR: SMTP users secret contains no records (credentials redacted).\n' >&2
    return 1
  }
}
