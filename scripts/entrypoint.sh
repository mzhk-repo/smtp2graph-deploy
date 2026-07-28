#!/usr/bin/env bash
# Category 1b: render SMTP2Graph runtime configuration from Docker Secret files.
# Inputs: explicit allowlisted runtime input file and non-secret environment values.
# Side effects: creates config.yml only inside an existing tmpfs runtime mount.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_TEMPLATE_FILE="${RUNTIME_TEMPLATE_FILE:-${PROJECT_ROOT}/deploy/config/gateway-config.yml.template}"
RUNTIME_CONFIG_DIR="${RUNTIME_CONFIG_DIR:-/runtime}"
DOCKER_SECRETS_DIR="${DOCKER_SECRETS_DIR:-/run/secrets}"
RUNTIME_CONFIG_FILE="${RUNTIME_CONFIG_FILE:-}"
RUNTIME_ENTRYPOINT_MODE="${RUNTIME_ENTRYPOINT_MODE:-run}"

SMTP2GRAPH_MODE="${SMTP2GRAPH_MODE:-full}"
GRAPH_AUTH_MODE="${GRAPH_AUTH_MODE:-certificate}"
SMTP_BIND_ADDRESS="${SMTP_BIND_ADDRESS:-127.0.0.1}"
SMTP_LISTEN_PORT="${SMTP_LISTEN_PORT:-587}"
SMTP_MAX_MESSAGE_BYTES="${SMTP_MAX_MESSAGE_BYTES:-26214400}"
GRAPH_SENDER_MAILBOX="${GRAPH_SENDER_MAILBOX:-}"
SEND_RETRY_LIMIT="${SEND_RETRY_LIMIT:-1}"
SEND_RETRY_INTERVAL_MINUTES="${SEND_RETRY_INTERVAL_MINUTES:-1}"
temp_config=''

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-64}"
}

cleanup() {
  [[ -z "${temp_config}" ]] || rm -f -- "${temp_config}"
}
trap cleanup EXIT HUP INT TERM

yaml_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/''/g"
  printf "'"
}

require_value() {
  [[ -n "$1" ]] || die 'required non-secret runtime value is empty.'
}

require_integer() {
  local name="$1"
  local value="$2"
  [[ "${value}" =~ ^[0-9]+$ ]] || die "${name} must be an unsigned integer."
}

parse_runtime_input_file() {
  local line key value
  [[ -z "${RUNTIME_CONFIG_FILE}" ]] && return 0
  [[ -r "${RUNTIME_CONFIG_FILE}" && -f "${RUNTIME_CONFIG_FILE}" && ! -L "${RUNTIME_CONFIG_FILE}" ]] || die 'runtime input file must be a readable regular file.' 66

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die 'runtime input file contains invalid syntax.'
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "${key}" in
      SMTP2GRAPH_MODE | GRAPH_AUTH_MODE | SMTP_BIND_ADDRESS | SMTP_LISTEN_PORT | SMTP_MAX_MESSAGE_BYTES | GRAPH_SENDER_MAILBOX | SEND_RETRY_LIMIT | SEND_RETRY_INTERVAL_MINUTES)
        printf -v "${key}" '%s' "${value}"
        ;;
      *)
        die "runtime input file contains unsupported key: ${key}."
        ;;
    esac
  done <"${RUNTIME_CONFIG_FILE}"
}

require_tmpfs_dir() {
  [[ -d "${RUNTIME_CONFIG_DIR}" && ! -L "${RUNTIME_CONFIG_DIR}" ]] || die 'runtime configuration directory must be an existing directory.' 66
  awk -v mount_path="${RUNTIME_CONFIG_DIR}" '$3 == "tmpfs" && ($2 == mount_path || index(mount_path, $2 "/") == 1) { found = 1 } END { exit !found }' /proc/mounts || die 'runtime configuration directory must be a dedicated tmpfs mount.' 66
}

require_secret_file() {
  local path="$1"
  local mode owner current_uid
  [[ -r "${path}" && -f "${path}" && ! -L "${path}" ]] || die 'required Docker Secret file is unavailable.' 66
  mode="$(stat -c '%a' "${path}")" || die 'could not inspect Docker Secret permissions.' 66
  owner="$(stat -c '%u' "${path}")" || die 'could not inspect Docker Secret owner.' 66
  current_uid="$(id -u)"
  (((8#${mode} & 8#022) == 0)) || die 'Docker Secret file must not be writable by group or other users.' 66
  [[ "${owner}" == '0' || "${owner}" == "${current_uid}" ]] || die 'Docker Secret file owner is not permitted.' 66
}

read_secret_line() {
  local value
  require_secret_file "$1"
  value="$(tr -d '\r\n' <"$1")"
  [[ -n "${value}" ]] || die 'required Docker Secret value is empty.' 66
  printf '%s' "${value}"
}

validate_inputs() {
  require_value "${SMTP2GRAPH_MODE}"
  [[ "${SMTP2GRAPH_MODE}" == 'full' ]] || die 'SMTP2GRAPH_MODE must be full.'
  [[ "${GRAPH_AUTH_MODE}" == 'certificate' || "${GRAPH_AUTH_MODE}" == 'client-secret' ]] || die 'GRAPH_AUTH_MODE must be certificate or client-secret.'
  require_value "${SMTP_BIND_ADDRESS}"
  require_value "${GRAPH_SENDER_MAILBOX}"
  require_integer 'SMTP_LISTEN_PORT' "${SMTP_LISTEN_PORT}"
  ((SMTP_LISTEN_PORT >= 1 && SMTP_LISTEN_PORT <= 65535)) || die 'SMTP_LISTEN_PORT must be between 1 and 65535.'
  require_integer 'SMTP_MAX_MESSAGE_BYTES' "${SMTP_MAX_MESSAGE_BYTES}"
  ((SMTP_MAX_MESSAGE_BYTES > 0 && SMTP_MAX_MESSAGE_BYTES % 1024 == 0)) || die 'SMTP_MAX_MESSAGE_BYTES must be a positive multiple of 1024.'
  require_integer 'SEND_RETRY_LIMIT' "${SEND_RETRY_LIMIT}"
  require_integer 'SEND_RETRY_INTERVAL_MINUTES' "${SEND_RETRY_INTERVAL_MINUTES}"
  ((SEND_RETRY_INTERVAL_MINUTES >= 1)) || die 'SEND_RETRY_INTERVAL_MINUTES must be at least 1.'
}

render_credential_block() {
  case "${GRAPH_AUTH_MODE}" in
    certificate)
      local thumbprint private_key_path
      thumbprint="$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-certificate-thumbprint")"
      private_key_path="${GRAPH_PRIVATE_KEY_PATH:-${DOCKER_SECRETS_DIR}/graph-private-key}"
      require_secret_file "${private_key_path}"
      printf '%s\n' '    certificate:'
      printf '      thumbprint: %s\n' "$(yaml_quote "${thumbprint}")"
      printf '      privateKeyPath: %s\n' "$(yaml_quote "${private_key_path}")"
      ;;
    client-secret)
      local client_secret
      client_secret="$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-client-secret")"
      printf '    secret: %s\n' "$(yaml_quote "${client_secret}")"
      unset client_secret
      ;;
  esac
}

render_template() {
  local line tenant_id client_id tls_key_path tls_cert_path max_size_kib
  tenant_id="$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-tenant-id")"
  client_id="$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-client-id")"
  tls_key_path="${SMTP_TLS_KEY_PATH:-${DOCKER_SECRETS_DIR}/smtp-tls-key}"
  tls_cert_path="${SMTP_TLS_CERT_PATH:-${DOCKER_SECRETS_DIR}/smtp-tls-cert}"
  require_secret_file "${tls_key_path}"
  require_secret_file "${tls_cert_path}"
  max_size_kib=$((SMTP_MAX_MESSAGE_BYTES / 1024))

  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      'mode: __SMTP2GRAPH_MODE__') printf 'mode: %s\n' "$(yaml_quote "${SMTP2GRAPH_MODE}")" ;;
      '    tenant: __GRAPH_TENANT_ID__') printf '    tenant: %s\n' "$(yaml_quote "${tenant_id}")" ;;
      '    id: __GRAPH_CLIENT_ID__') printf '    id: %s\n' "$(yaml_quote "${client_id}")" ;;
      '__GRAPH_CREDENTIAL_BLOCK__') render_credential_block ;;
      '  retryLimit: __SEND_RETRY_LIMIT__') printf '  retryLimit: %s\n' "${SEND_RETRY_LIMIT}" ;;
      '  retryInterval: __SEND_RETRY_INTERVAL_MINUTES__') printf '  retryInterval: %s\n' "${SEND_RETRY_INTERVAL_MINUTES}" ;;
      '  forceMailbox: __GRAPH_SENDER_MAILBOX__') printf '  forceMailbox: %s\n' "$(yaml_quote "${GRAPH_SENDER_MAILBOX}")" ;;
      '  port: __SMTP_LISTEN_PORT__') printf '  port: %s\n' "${SMTP_LISTEN_PORT}" ;;
      '  listenAddress: __SMTP_BIND_ADDRESS__') printf '  listenAddress: %s\n' "$(yaml_quote "${SMTP_BIND_ADDRESS}")" ;;
      '  tlsKeyPath: __SMTP_TLS_KEY_PATH__') printf '  tlsKeyPath: %s\n' "$(yaml_quote "${tls_key_path}")" ;;
      '  tlsCertPath: __SMTP_TLS_CERT_PATH__') printf '  tlsCertPath: %s\n' "$(yaml_quote "${tls_cert_path}")" ;;
      '  maxSize: __SMTP_MAX_SIZE_KIB__') printf "  maxSize: '%sk'\n" "${max_size_kib}" ;;
      *'__'*) die 'runtime template contains an unsupported placeholder.' 65 ;;
      *) printf '%s\n' "${line}" ;;
    esac
  done <"${RUNTIME_TEMPLATE_FILE}"
}

main() {
  [[ -r "${RUNTIME_TEMPLATE_FILE}" && -f "${RUNTIME_TEMPLATE_FILE}" && ! -L "${RUNTIME_TEMPLATE_FILE}" ]] || die 'runtime template is unavailable.' 66
  [[ "${RUNTIME_ENTRYPOINT_MODE}" == 'run' || "${RUNTIME_ENTRYPOINT_MODE}" == 'render-only' ]] || die 'unsupported RUNTIME_ENTRYPOINT_MODE.'
  parse_runtime_input_file
  validate_inputs
  require_tmpfs_dir

  umask 077
  temp_config="$(mktemp "${RUNTIME_CONFIG_DIR}/config.yml.XXXXXX")"
  render_template >"${temp_config}"
  chmod 0600 "${temp_config}"
  mv -f -- "${temp_config}" "${RUNTIME_CONFIG_DIR}/config.yml"
  temp_config=''

  if [[ "${RUNTIME_ENTRYPOINT_MODE}" == 'render-only' ]]; then
    printf 'PASS: runtime configuration rendered in the configured tmpfs directory.\n'
    return 0
  fi

  cd "${RUNTIME_CONFIG_DIR}"
  exec /bin/sh /bin/startup.sh
}

main "$@"
