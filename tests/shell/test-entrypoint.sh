#!/usr/bin/env bash
# Category 1a: negative and rendering tests for the Task 3.1 runtime wrapper.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENTRYPOINT="${PROJECT_ROOT}/scripts/entrypoint.sh"
TEMPLATE="${PROJECT_ROOT}/deploy/config/gateway-config.yml.template"
TEMP_DIR="$(mktemp -d)"
RUNTIME_DIR="$(mktemp -d /dev/shm/smtp2graph-entrypoint.XXXXXX)"
SECRETS_DIR="${TEMP_DIR}/secrets"

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
}

run_render() {
  env \
    RUNTIME_CONFIG_DIR="${RUNTIME_DIR}" \
    DOCKER_SECRETS_DIR="${SECRETS_DIR}" \
    RUNTIME_TEMPLATE_FILE="${TEMPLATE}" \
    RUNTIME_ENTRYPOINT_MODE=render-only \
    GRAPH_AUTH_MODE="${GRAPH_AUTH_MODE:-certificate}" \
    GRAPH_SENDER_MAILBOX=noreply@example.invalid \
    SMTP_MAX_SESSIONS_PER_IP="${SMTP_MAX_SESSIONS_PER_IP-5}" \
    SMTP_MESSAGES_PER_MINUTE="${SMTP_MESSAGES_PER_MINUTE-30}" \
    SMTP2GRAPH_STORAGE_ROOT="${SMTP2GRAPH_STORAGE_ROOT-/data}" \
    QUEUE_MAX_BYTES="${QUEUE_MAX_BYTES-1073741824}" \
    QUEUE_REJECT_THRESHOLD_PERCENT="${QUEUE_REJECT_THRESHOLD_PERCENT-80}" \
    SMTP_ALLOWED_SOURCE_CIDRS=127.0.0.1/32 \
    SMTP_ALLOWED_SENDER_ADDRESSES=NOREPLY@example.invalid \
    "${ENTRYPOINT}"
}

mkdir -p "${SECRETS_DIR}"
printf '%s\n' '00000000-0000-0000-0000-000000000000' >"${SECRETS_DIR}/graph-tenant-id"
printf '%s\n' '11111111-1111-1111-1111-111111111111' >"${SECRETS_DIR}/graph-client-id"
printf '%s\n' '0123456789ABCDEF0123456789ABCDEF01234567' >"${SECRETS_DIR}/graph-certificate-thumbprint"
printf '%s\n' 'synthetic-client-secret-for-test-only' >"${SECRETS_DIR}/graph-client-secret"
printf '%s\n' 'synthetic-private-key' >"${SECRETS_DIR}/graph-private-key"
printf '%s\n' 'synthetic-tls-key' >"${SECRETS_DIR}/smtp-tls-key"
printf '%s\n' 'synthetic-tls-cert' >"${SECRETS_DIR}/smtp-tls-cert"
printf 'grafana\tsynthetic-password\tNoreply@Example.Invalid\n' >"${SECRETS_DIR}/smtp-users"
chmod 0444 "${SECRETS_DIR}"/*

run_render >/dev/null
[[ -f "${RUNTIME_DIR}/config.yml" ]] || fail 'rendered configuration is missing.'
[[ "$(stat -c '%a' "${RUNTIME_DIR}/config.yml")" == '600' ]] || fail 'rendered configuration mode is not 0600.'
grep -F "'noreply@example.invalid'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'expected sender mailbox is missing from rendered configuration.'
grep -F "'noreply@example.invalid'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'normalized sender policy is missing from rendered configuration.'
grep -F "requireAuth: true" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'SMTP authentication is not required in rendered configuration.'
grep -F 'secure: false' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'STARTTLS mode is not enabled in rendered configuration.'
grep -F 'allowInsecureAuth: false' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'SMTP AUTH is permitted before STARTTLS.'
grep -F 'maxSessionsPerIp: 5' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'per-IP session limit is missing from rendered configuration.'
grep -A 2 '^  rateLimit:$' "${RUNTIME_DIR}/config.yml" | grep -F 'duration: 60' >/dev/null || fail 'rate-limit duration is missing from rendered configuration.'
grep -A 2 '^  rateLimit:$' "${RUNTIME_DIR}/config.yml" | grep -F 'limit: 30' >/dev/null || fail 'per-client message limit is missing from rendered configuration.'
grep -F "rootPath: '/data'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'persistent storage root is missing from rendered configuration.'
grep -F 'maxBytes: 1073741824' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'queue capacity is missing from rendered configuration.'
grep -F 'rejectThresholdPercent: 80' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'queue rejection threshold is missing from rendered configuration.'
grep -A 3 '^observability:$' "${RUNTIME_DIR}/config.yml" | grep -F "listenAddress: '0.0.0.0'" >/dev/null || fail 'observability listener is not internal-overlay ready.'
grep -A 3 '^observability:$' "${RUNTIME_DIR}/config.yml" | grep -F 'port: 9464' >/dev/null || fail 'observability port is missing from rendered configuration.'
grep -F 'synthetic-client-secret-for-test-only' "${RUNTIME_DIR}/config.yml" >/dev/null && fail 'certificate render unexpectedly contains client secret.'

GRAPH_AUTH_MODE=client-secret run_render >/dev/null
grep -F 'synthetic-client-secret-for-test-only' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'client-secret fallback did not render the Docker Secret value.'

rm -f -- "${SECRETS_DIR}/smtp-tls-key"
expect_failure 'required Docker Secret file is unavailable.' run_render
printf '%s\n' 'synthetic-tls-key' >"${SECRETS_DIR}/smtp-tls-key"
chmod 0666 "${SECRETS_DIR}/smtp-tls-key"
expect_failure 'must not be writable by group or other users.' run_render
chmod 0444 "${SECRETS_DIR}/smtp-tls-key"

QUEUE_MAX_BYTES=0 expect_failure 'QUEUE_MAX_BYTES must be at least 1.' run_render
QUEUE_REJECT_THRESHOLD_PERCENT=101 expect_failure 'QUEUE_REJECT_THRESHOLD_PERCENT must be between 1 and 100.' run_render
SMTP2GRAPH_STORAGE_ROOT=relative-path expect_failure 'SMTP2GRAPH_STORAGE_ROOT must be an absolute path other than /.' run_render
SMTP_MAX_SESSIONS_PER_IP=0 expect_failure 'SMTP_MAX_SESSIONS_PER_IP must be at least 1.' run_render
SMTP_MESSAGES_PER_MINUTE=0 expect_failure 'SMTP_MESSAGES_PER_MINUTE must be at least 1.' run_render

STORAGE_INPUT="${TEMP_DIR}/storage.env"
printf '%s\n' 'SMTP2GRAPH_STORAGE_ROOT=/runtime-data' 'QUEUE_MAX_BYTES=2048' 'QUEUE_REJECT_THRESHOLD_PERCENT=75' >"${STORAGE_INPUT}"
RUNTIME_CONFIG_FILE="${STORAGE_INPUT}" run_render >/dev/null
grep -F "rootPath: '/runtime-data'" "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'storage root from the strict runtime input was not rendered.'
grep -F 'maxBytes: 2048' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'queue capacity from the strict runtime input was not rendered.'
grep -F 'rejectThresholdPercent: 75' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'queue threshold from the strict runtime input was not rendered.'

POLICY_LIMITS_INPUT="${TEMP_DIR}/policy-limits.env"
printf '%s\n' 'SMTP_MAX_SESSIONS_PER_IP=3' 'SMTP_MESSAGES_PER_MINUTE=12' >"${POLICY_LIMITS_INPUT}"
RUNTIME_CONFIG_FILE="${POLICY_LIMITS_INPUT}" run_render >/dev/null
grep -F 'maxSessionsPerIp: 3' "${RUNTIME_DIR}/config.yml" >/dev/null || fail 'per-IP session limit from the strict runtime input was not rendered.'
grep -A 2 '^  rateLimit:$' "${RUNTIME_DIR}/config.yml" | grep -F 'limit: 12' >/dev/null || fail 'per-client message limit from the strict runtime input was not rendered.'

MALICIOUS_INPUT="${TEMP_DIR}/malicious.env"
MARKER="${TEMP_DIR}/must-not-exist"
printf '%s\n' "UNEXPECTED=\$(touch ${MARKER})" >"${MALICIOUS_INPUT}"
expect_failure 'unsupported key: UNEXPECTED.' env RUNTIME_CONFIG_FILE="${MALICIOUS_INPUT}" RUNTIME_CONFIG_DIR="${RUNTIME_DIR}" DOCKER_SECRETS_DIR="${SECRETS_DIR}" RUNTIME_TEMPLATE_FILE="${TEMPLATE}" RUNTIME_ENTRYPOINT_MODE=render-only GRAPH_SENDER_MAILBOX=noreply@example.invalid "${ENTRYPOINT}"
[[ ! -e "${MARKER}" ]] || fail 'runtime input file was executed.'

INJECTION_INPUT="${TEMP_DIR}/injection.env"
printf '%s\n' 'SMTP_BIND_ADDRESS=127.0.0.1' 'mode: send' >"${INJECTION_INPUT}"
expect_failure 'runtime input file contains invalid syntax.' env RUNTIME_CONFIG_FILE="${INJECTION_INPUT}" RUNTIME_CONFIG_DIR="${RUNTIME_DIR}" DOCKER_SECRETS_DIR="${SECRETS_DIR}" RUNTIME_TEMPLATE_FILE="${TEMPLATE}" RUNTIME_ENTRYPOINT_MODE=render-only GRAPH_SENDER_MAILBOX=noreply@example.invalid "${ENTRYPOINT}"

printf 'PASS: entrypoint renders only in tmpfs and rejects unsafe secret or input-file conditions.\n'
