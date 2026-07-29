#!/usr/bin/env bash
# Category 1a: unit tests for policy and secret-backed SMTP user YAML rendering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=scripts/lib/render-config.sh
. "${PROJECT_ROOT}/scripts/lib/render-config.sh"
TEMP_DIR="$(mktemp -d)"
USERS_FILE="${TEMP_DIR}/smtp-users"

cleanup() { rm -rf -- "${TEMP_DIR}"; }
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  local expected="$1"
  shift
  local output
  local stderr_file="${TEMP_DIR}/stderr"
  if "$@" >/dev/null 2>"${stderr_file}"; then
    fail 'command unexpectedly succeeded.'
  fi
  output="$(<"${stderr_file}")"
  [[ "${output}" == *"${expected}"* ]] || fail "expected failure message was not returned: ${expected}"
  [[ "${output}" != *'secret-password'* ]] || fail 'secret password leaked to error output.'
}

global_senders="$(normalize_email_csv 'NoReply@Example.Invalid,alerts@example.invalid')" || fail 'global sender normalization failed.'
[[ "${global_senders}" == $'noreply@example.invalid\nalerts@example.invalid' ]] || fail 'email addresses were not normalized to lowercase.'

special_password="synthetic password #\$\"'\\"
printf '%s\t%s\t%s\n' 'grafana' "${special_password}" 'NoReply@Example.Invalid' >"${USERS_FILE}"
rendered="$(render_smtp_users "${USERS_FILE}" "${global_senders}")"
[[ "${rendered}" == *"username: 'grafana'"* ]] || fail 'SMTP username was not rendered.'
[[ "${rendered}" == *"allowedFrom:"*"'noreply@example.invalid'"* ]] || fail 'per-user sender policy was not normalized.'
[[ "${rendered}" == *"password: $(yaml_quote "${special_password}")"* ]] || fail 'special-character SMTP password was not safely rendered.'

printf 'grafana\tsecret-password\tNoReply@Example.Invalid\ngrafana\tanother-password\tNoReply@Example.Invalid\n' >"${USERS_FILE}"
expect_failure 'duplicate SMTP username' render_smtp_users "${USERS_FILE}" "${global_senders}"

printf 'grafana\tsecret-password\toutside@example.invalid\n' >"${USERS_FILE}"
expect_failure 'outside the global allowlist' render_smtp_users "${USERS_FILE}" "${global_senders}"

: >"${USERS_FILE}"
expect_failure 'SMTP users secret contains no records' render_smtp_users "${USERS_FILE}" "${global_senders}"

printf 'grafana\tsecret-password\n' >"${USERS_FILE}"
expect_failure 'malformed SMTP users record at line 1' render_smtp_users "${USERS_FILE}" "${global_senders}"

printf 'PASS: policy renderer normalizes emails and rejects unsafe SMTP user records without leaking passwords.\n'
