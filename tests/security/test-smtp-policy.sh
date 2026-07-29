#!/usr/bin/env bash
# Category 1a: verifies fail-closed SMTP deny-by-default policy rendering.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENTRYPOINT="${PROJECT_ROOT}/scripts/entrypoint.sh"
TEMPLATE="${PROJECT_ROOT}/deploy/config/gateway-config.yml.template"
TEMP_DIR="$(mktemp -d)"
RUNTIME_DIR="$(mktemp -d /dev/shm/smtp2graph-policy.XXXXXX)"
SECRETS_DIR="${TEMP_DIR}/secrets"
SYNTHETIC_SMTP_PASSWORD='synthetic-password-not-for-output'

cleanup() {
  rm -rf -- "${TEMP_DIR}" "${RUNTIME_DIR}"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail 'command unexpectedly succeeded.'
  fi
  [[ "${output}" == *"${expected}"* ]] || fail "expected failure message was not returned: ${expected}"
  [[ "${output}" != *"${SYNTHETIC_SMTP_PASSWORD}"* ]] || fail 'SMTP password leaked to error output.'
}

run_render() {
  env \
    RUNTIME_CONFIG_DIR="${RUNTIME_DIR}" \
    DOCKER_SECRETS_DIR="${SECRETS_DIR}" \
    RUNTIME_TEMPLATE_FILE="${TEMPLATE}" \
    RUNTIME_ENTRYPOINT_MODE=render-only \
    GRAPH_SENDER_MAILBOX=noreply@example.invalid \
    SMTP_ALLOWED_SOURCE_CIDRS="${SMTP_ALLOWED_SOURCE_CIDRS-127.0.0.1/32}" \
    SMTP_ALLOWED_SENDER_ADDRESSES="${SMTP_ALLOWED_SENDER_ADDRESSES-noreply@example.invalid}" \
    "${ENTRYPOINT}"
}

mkdir -p "${SECRETS_DIR}"
printf '%s\n' '00000000-0000-0000-0000-000000000000' >"${SECRETS_DIR}/graph-tenant-id"
printf '%s\n' '11111111-1111-1111-1111-111111111111' >"${SECRETS_DIR}/graph-client-id"
printf '%s\n' '0123456789ABCDEF0123456789ABCDEF01234567' >"${SECRETS_DIR}/graph-certificate-thumbprint"
printf '%s\n' 'synthetic-private-key' >"${SECRETS_DIR}/graph-private-key"
printf '%s\n' 'synthetic-tls-key' >"${SECRETS_DIR}/smtp-tls-key"
printf '%s\n' 'synthetic-tls-cert' >"${SECRETS_DIR}/smtp-tls-cert"
printf 'grafana\t%s\tNoReply@Example.Invalid\n' "${SYNTHETIC_SMTP_PASSWORD}" >"${SECRETS_DIR}/smtp-users"
chmod 0444 "${SECRETS_DIR}"/*

run_render >/dev/null
grep -F 'requireAuth: true' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'rendered configuration does not require SMTP authentication.'
grep -F -- "- '127.0.0.1/32'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'source CIDR allowlist is missing from rendered configuration.'
grep -F -- "- 'noreply@example.invalid'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'sender allowlist is missing from rendered configuration.'
grep -F "username: 'grafana'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'SMTP user is missing from rendered configuration.'

SMTP_ALLOWED_SOURCE_CIDRS='' expect_failure 'required non-secret runtime value is empty.' run_render
SMTP_ALLOWED_SENDER_ADDRESSES='' expect_failure 'required non-secret runtime value is empty.' run_render

rm -f -- "${SECRETS_DIR}/smtp-users"
expect_failure 'required Docker Secret file is unavailable.' run_render
printf 'grafana\t%s\toutside@example.invalid\n' "${SYNTHETIC_SMTP_PASSWORD}" >"${SECRETS_DIR}/smtp-users"
chmod 0444 "${SECRETS_DIR}/smtp-users"
expect_failure 'outside the global allowlist' run_render

printf 'PASS: SMTP policy fails closed without required allowlists or a valid per-user sender policy.\n'
