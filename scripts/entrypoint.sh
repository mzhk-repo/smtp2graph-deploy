#!/bin/sh
# Category 1b: render SMTP2Graph runtime configuration from Docker Secret files.
# Inputs: explicit allowlisted runtime input file and non-secret environment values.
# Side effects: creates config.yml only inside an existing tmpfs runtime mount.
set -eu

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(CDPATH='' cd "${SCRIPT_DIR}/.." && pwd)
RUNTIME_RENDER_HELPER_FILE=${RUNTIME_RENDER_HELPER_FILE:-"${SCRIPT_DIR}/lib/render-config.sh"}
if [ ! -r "${RUNTIME_RENDER_HELPER_FILE}" ] || [ ! -f "${RUNTIME_RENDER_HELPER_FILE}" ] || [ -L "${RUNTIME_RENDER_HELPER_FILE}" ]; then
  printf 'ERROR: runtime renderer helper is unavailable.\n' >&2
  exit 66
fi
# shellcheck source=scripts/lib/render-config.sh
. "${RUNTIME_RENDER_HELPER_FILE}"
RUNTIME_TEMPLATE_FILE=${RUNTIME_TEMPLATE_FILE:-"${PROJECT_ROOT}/deploy/config/gateway-config.yml.template"}
RUNTIME_CONFIG_DIR=${RUNTIME_CONFIG_DIR:-/runtime}
DOCKER_SECRETS_DIR=${DOCKER_SECRETS_DIR:-/run/secrets}
RUNTIME_CONFIG_FILE=${RUNTIME_CONFIG_FILE:-}
RUNTIME_ENTRYPOINT_MODE=${RUNTIME_ENTRYPOINT_MODE:-run}

SMTP2GRAPH_MODE=${SMTP2GRAPH_MODE:-full}
GRAPH_AUTH_MODE=${GRAPH_AUTH_MODE:-certificate}
SMTP_BIND_ADDRESS=${SMTP_BIND_ADDRESS:-127.0.0.1}
SMTP_LISTEN_PORT=${SMTP_LISTEN_PORT:-587}
SMTP_MAX_MESSAGE_BYTES=${SMTP_MAX_MESSAGE_BYTES:-26214400}
SMTP_MAX_SESSIONS_PER_IP=${SMTP_MAX_SESSIONS_PER_IP:-5}
SMTP_MESSAGES_PER_MINUTE=${SMTP_MESSAGES_PER_MINUTE:-30}
SMTP2GRAPH_STORAGE_ROOT=${SMTP2GRAPH_STORAGE_ROOT:-/data}
QUEUE_MAX_BYTES=${QUEUE_MAX_BYTES:-1073741824}
QUEUE_REJECT_THRESHOLD_PERCENT=${QUEUE_REJECT_THRESHOLD_PERCENT:-80}
SMTP_ALLOWED_SOURCE_CIDRS=${SMTP_ALLOWED_SOURCE_CIDRS:-}
SMTP_ALLOWED_SENDER_ADDRESSES=${SMTP_ALLOWED_SENDER_ADDRESSES:-}
GRAPH_SENDER_MAILBOX=${GRAPH_SENDER_MAILBOX:-}
SEND_RETRY_LIMIT=${SEND_RETRY_LIMIT:-1}
SEND_RETRY_INTERVAL_MINUTES=${SEND_RETRY_INTERVAL_MINUTES:-1}
DOCKER_SECRET_ALLOWED_UIDS=${DOCKER_SECRET_ALLOWED_UIDS:-"0:$(id -u)"}
temp_config=''

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-64}"
}

cleanup() {
  [ -z "${temp_config}" ] || rm -f "${temp_config}"
}
trap cleanup 0 1 2 15

require_value() {
  [ -n "$1" ] || die 'required non-secret runtime value is empty.'
}

require_integer() {
  case "$2" in
    '' | *[!0-9]*) die "$1 must be an unsigned integer." ;;
  esac
}

parse_runtime_input_file() {
  [ -z "${RUNTIME_CONFIG_FILE}" ] && return 0
  if [ ! -r "${RUNTIME_CONFIG_FILE}" ] || [ ! -f "${RUNTIME_CONFIG_FILE}" ] || [ -L "${RUNTIME_CONFIG_FILE}" ]; then
    die 'runtime input file must be a readable regular file.' 66
  fi

  while IFS= read -r line || [ -n "${line}" ]; do
    line=$(printf '%s' "${line}" | tr -d '\r')
    case "${line}" in
      '' | \#*) continue ;;
      *=*) ;;
      *) die 'runtime input file contains invalid syntax.' ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    printf '%s\n' "${key}" | grep -Eq '^[A-Z][A-Z0-9_]*$' || die 'runtime input file contains invalid syntax.'
    case "${key}" in
      SMTP2GRAPH_MODE) SMTP2GRAPH_MODE=${value} ;;
      GRAPH_AUTH_MODE) GRAPH_AUTH_MODE=${value} ;;
      SMTP_BIND_ADDRESS) SMTP_BIND_ADDRESS=${value} ;;
      SMTP_LISTEN_PORT) SMTP_LISTEN_PORT=${value} ;;
      SMTP_MAX_MESSAGE_BYTES) SMTP_MAX_MESSAGE_BYTES=${value} ;;
      SMTP_MAX_SESSIONS_PER_IP) SMTP_MAX_SESSIONS_PER_IP=${value} ;;
      SMTP_MESSAGES_PER_MINUTE) SMTP_MESSAGES_PER_MINUTE=${value} ;;
      SMTP2GRAPH_STORAGE_ROOT) SMTP2GRAPH_STORAGE_ROOT=${value} ;;
      QUEUE_MAX_BYTES) QUEUE_MAX_BYTES=${value} ;;
      QUEUE_REJECT_THRESHOLD_PERCENT) QUEUE_REJECT_THRESHOLD_PERCENT=${value} ;;
      SMTP_ALLOWED_SOURCE_CIDRS) SMTP_ALLOWED_SOURCE_CIDRS=${value} ;;
      SMTP_ALLOWED_SENDER_ADDRESSES) SMTP_ALLOWED_SENDER_ADDRESSES=${value} ;;
      GRAPH_SENDER_MAILBOX) GRAPH_SENDER_MAILBOX=${value} ;;
      SEND_RETRY_LIMIT) SEND_RETRY_LIMIT=${value} ;;
      SEND_RETRY_INTERVAL_MINUTES) SEND_RETRY_INTERVAL_MINUTES=${value} ;;
      *) die "runtime input file contains unsupported key: ${key}." ;;
    esac
  done <"${RUNTIME_CONFIG_FILE}"
}

require_tmpfs_dir() {
  if [ ! -d "${RUNTIME_CONFIG_DIR}" ] || [ -L "${RUNTIME_CONFIG_DIR}" ]; then
    die 'runtime configuration directory must be an existing directory.' 66
  fi
  awk -v mount_path="${RUNTIME_CONFIG_DIR}" '$3 == "tmpfs" && ($2 == mount_path || index(mount_path, $2 "/") == 1) { found = 1 } END { exit !found }' /proc/mounts || die 'runtime configuration directory must be a dedicated tmpfs mount.' 66
}

require_secret_file() {
  if [ ! -r "$1" ] || [ ! -f "$1" ] || [ -L "$1" ]; then
    die 'required Docker Secret file is unavailable.' 66
  fi
  mode=$(stat -c '%a' "$1") || die 'could not inspect Docker Secret permissions.' 66
  owner=$(stat -c '%u' "$1") || die 'could not inspect Docker Secret owner.' 66
  case "${mode}" in
    '' | *[!0-7]*) die 'Docker Secret file mode is invalid.' 66 ;;
  esac
  last_two_digits=$(printf '%s' "${mode}" | sed 's/.*\(..\)$/\1/')
  case "${last_two_digits}" in
    *[2367]*) die 'Docker Secret file must not be writable by group or other users.' 66 ;;
  esac
  case "${DOCKER_SECRET_ALLOWED_UIDS}" in
    '' | :* | *: | *::* | *[!0-9:]*) die 'DOCKER_SECRET_ALLOWED_UIDS is invalid.' 64 ;;
  esac
  case ":${DOCKER_SECRET_ALLOWED_UIDS}:" in
    *":${owner}:"*) ;;
    *) die 'Docker Secret file owner is not permitted.' 66 ;;
  esac
}

read_secret_line() {
  require_secret_file "$1"
  secret_value=$(tr -d '\r\n' <"$1")
  [ -n "${secret_value}" ] || die 'required Docker Secret value is empty.' 66
  printf '%s' "${secret_value}"
}

validate_inputs() {
  require_value "${SMTP2GRAPH_MODE}"
  [ "${SMTP2GRAPH_MODE}" = full ] || die 'SMTP2GRAPH_MODE must be full.'
  case "${GRAPH_AUTH_MODE}" in
    certificate | client-secret) ;;
    *) die 'GRAPH_AUTH_MODE must be certificate or client-secret.' ;;
  esac
  require_value "${SMTP_BIND_ADDRESS}"
  require_value "${SMTP_ALLOWED_SOURCE_CIDRS}"
  require_value "${SMTP_ALLOWED_SENDER_ADDRESSES}"
  require_value "${GRAPH_SENDER_MAILBOX}"
  case "${SMTP2GRAPH_STORAGE_ROOT}" in
    /*) ;;
    *) die 'SMTP2GRAPH_STORAGE_ROOT must be an absolute path other than /.' ;;
  esac
  [ "${SMTP2GRAPH_STORAGE_ROOT}" != / ] || die 'SMTP2GRAPH_STORAGE_ROOT must be an absolute path other than /.'
  require_integer SMTP_LISTEN_PORT "${SMTP_LISTEN_PORT}"
  if [ "${SMTP_LISTEN_PORT}" -lt 1 ] || [ "${SMTP_LISTEN_PORT}" -gt 65535 ]; then
    die 'SMTP_LISTEN_PORT must be between 1 and 65535.'
  fi
  require_integer SMTP_MAX_MESSAGE_BYTES "${SMTP_MAX_MESSAGE_BYTES}"
  if [ "${SMTP_MAX_MESSAGE_BYTES}" -le 0 ] || [ $((SMTP_MAX_MESSAGE_BYTES % 1024)) -ne 0 ]; then
    die 'SMTP_MAX_MESSAGE_BYTES must be a positive multiple of 1024.'
  fi
  require_integer SMTP_MAX_SESSIONS_PER_IP "${SMTP_MAX_SESSIONS_PER_IP}"
  [ "${SMTP_MAX_SESSIONS_PER_IP}" -ge 1 ] || die 'SMTP_MAX_SESSIONS_PER_IP must be at least 1.'
  require_integer SMTP_MESSAGES_PER_MINUTE "${SMTP_MESSAGES_PER_MINUTE}"
  [ "${SMTP_MESSAGES_PER_MINUTE}" -ge 1 ] || die 'SMTP_MESSAGES_PER_MINUTE must be at least 1.'
  require_integer QUEUE_MAX_BYTES "${QUEUE_MAX_BYTES}"
  [ "${QUEUE_MAX_BYTES}" -ge 1 ] || die 'QUEUE_MAX_BYTES must be at least 1.'
  require_integer QUEUE_REJECT_THRESHOLD_PERCENT "${QUEUE_REJECT_THRESHOLD_PERCENT}"
  if [ "${QUEUE_REJECT_THRESHOLD_PERCENT}" -lt 1 ] || [ "${QUEUE_REJECT_THRESHOLD_PERCENT}" -gt 100 ]; then
    die 'QUEUE_REJECT_THRESHOLD_PERCENT must be between 1 and 100.'
  fi
  require_integer SEND_RETRY_LIMIT "${SEND_RETRY_LIMIT}"
  require_integer SEND_RETRY_INTERVAL_MINUTES "${SEND_RETRY_INTERVAL_MINUTES}"
  [ "${SEND_RETRY_INTERVAL_MINUTES}" -ge 1 ] || die 'SEND_RETRY_INTERVAL_MINUTES must be at least 1.'
}

render_credential_block() {
  case "${GRAPH_AUTH_MODE}" in
    certificate)
      certificate_thumbprint=$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-certificate-thumbprint")
      graph_private_key_path=${GRAPH_PRIVATE_KEY_PATH:-"${DOCKER_SECRETS_DIR}/graph-private-key"}
      require_secret_file "${graph_private_key_path}"
      printf '%s\n' '    certificate:'
      printf '      thumbprint: %s\n' "$(yaml_quote "${certificate_thumbprint}")"
      printf '      privateKeyPath: %s\n' "$(yaml_quote "${graph_private_key_path}")"
      ;;
    client-secret)
      graph_client_secret=$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-client-secret")
      printf '    secret: %s\n' "$(yaml_quote "${graph_client_secret}")"
      unset graph_client_secret
      ;;
  esac
}

render_template() {
  tenant_id=$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-tenant-id")
  client_id=$(read_secret_line "${DOCKER_SECRETS_DIR}/graph-client-id")
  smtp_tls_key_path=${SMTP_TLS_KEY_PATH:-"${DOCKER_SECRETS_DIR}/smtp-tls-key"}
  smtp_tls_cert_path=${SMTP_TLS_CERT_PATH:-"${DOCKER_SECRETS_DIR}/smtp-tls-cert"}
  require_secret_file "${smtp_tls_key_path}"
  require_secret_file "${smtp_tls_cert_path}"
  smtp_users_path=${SMTP_USERS_SECRET_PATH:-"${DOCKER_SECRETS_DIR}/smtp-users"}
  require_secret_file "${smtp_users_path}"
  global_senders=$(normalize_email_csv "${SMTP_ALLOWED_SENDER_ADDRESSES}") || die 'SMTP_ALLOWED_SENDER_ADDRESSES must be a non-empty unique CSV email list.'
  source_cidrs=$(normalize_cidr_csv "${SMTP_ALLOWED_SOURCE_CIDRS}") || die 'SMTP_ALLOWED_SOURCE_CIDRS must be a non-empty unique CSV IP/CIDR list.'
  max_size_kib=$((SMTP_MAX_MESSAGE_BYTES / 1024))

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      'mode: __SMTP2GRAPH_MODE__') printf 'mode: %s\n' "$(yaml_quote "${SMTP2GRAPH_MODE}")" ;;
      '    tenant: __GRAPH_TENANT_ID__') printf '    tenant: %s\n' "$(yaml_quote "${tenant_id}")" ;;
      '    id: __GRAPH_CLIENT_ID__') printf '    id: %s\n' "$(yaml_quote "${client_id}")" ;;
      '__GRAPH_CREDENTIAL_BLOCK__') render_credential_block ;;
      '  retryLimit: __SEND_RETRY_LIMIT__') printf '  retryLimit: %s\n' "${SEND_RETRY_LIMIT}" ;;
      '  retryInterval: __SEND_RETRY_INTERVAL_MINUTES__') printf '  retryInterval: %s\n' "${SEND_RETRY_INTERVAL_MINUTES}" ;;
      '  forceMailbox: __GRAPH_SENDER_MAILBOX__') printf '  forceMailbox: %s\n' "$(yaml_quote "${GRAPH_SENDER_MAILBOX}")" ;;
      '  rootPath: __SMTP2GRAPH_STORAGE_ROOT__') printf '  rootPath: %s\n' "$(yaml_quote "${SMTP2GRAPH_STORAGE_ROOT}")" ;;
      '  maxBytes: __QUEUE_MAX_BYTES__') printf '  maxBytes: %s\n' "${QUEUE_MAX_BYTES}" ;;
      '  rejectThresholdPercent: __QUEUE_REJECT_THRESHOLD_PERCENT__') printf '  rejectThresholdPercent: %s\n' "${QUEUE_REJECT_THRESHOLD_PERCENT}" ;;
      '  port: __SMTP_LISTEN_PORT__') printf '  port: %s\n' "${SMTP_LISTEN_PORT}" ;;
      '  listenAddress: __SMTP_BIND_ADDRESS__') printf '  listenAddress: %s\n' "$(yaml_quote "${SMTP_BIND_ADDRESS}")" ;;
      '  tlsKeyPath: __SMTP_TLS_KEY_PATH__') printf '  tlsKeyPath: %s\n' "$(yaml_quote "${smtp_tls_key_path}")" ;;
      '  tlsCertPath: __SMTP_TLS_CERT_PATH__') printf '  tlsCertPath: %s\n' "$(yaml_quote "${smtp_tls_cert_path}")" ;;
      '  maxSize: __SMTP_MAX_SIZE_KIB__') printf "  maxSize: '%sk'\n" "${max_size_kib}" ;;
      '__SMTP_ALLOWED_SOURCE_CIDRS__') render_yaml_list '    ' "${source_cidrs}" ;;
      '__SMTP_ALLOWED_SENDER_ADDRESSES__') render_yaml_list '    ' "${global_senders}" ;;
      '  maxSessionsPerIp: __SMTP_MAX_SESSIONS_PER_IP__') printf '  maxSessionsPerIp: %s\n' "${SMTP_MAX_SESSIONS_PER_IP}" ;;
      '    limit: __SMTP_MESSAGES_PER_MINUTE__') printf '    limit: %s\n' "${SMTP_MESSAGES_PER_MINUTE}" ;;
      '__SMTP_USERS__') render_smtp_users "${smtp_users_path}" "${global_senders}" ;;
      *'__'*) die 'runtime template contains an unsupported placeholder.' 65 ;;
      *) printf '%s\n' "${line}" ;;
    esac
  done <"${RUNTIME_TEMPLATE_FILE}"
}

main() {
  if [ ! -r "${RUNTIME_TEMPLATE_FILE}" ] || [ ! -f "${RUNTIME_TEMPLATE_FILE}" ] || [ -L "${RUNTIME_TEMPLATE_FILE}" ]; then
    die 'runtime template is unavailable.' 66
  fi
  case "${RUNTIME_ENTRYPOINT_MODE}" in
    run | render-only) ;;
    *) die 'unsupported RUNTIME_ENTRYPOINT_MODE.' ;;
  esac
  parse_runtime_input_file
  validate_inputs
  require_tmpfs_dir

  umask 077
  temp_config=$(mktemp "${RUNTIME_CONFIG_DIR}/config.yml.XXXXXX")
  render_template >"${temp_config}"
  chmod 0600 "${temp_config}"
  mv -f "${temp_config}" "${RUNTIME_CONFIG_DIR}/config.yml"
  temp_config=''

  if [ "${RUNTIME_ENTRYPOINT_MODE}" = render-only ]; then
    printf 'PASS: runtime configuration rendered in the configured tmpfs directory.\n'
    return 0
  fi

  cd "${RUNTIME_CONFIG_DIR}"
  exec /bin/sh /bin/startup.sh
}

main "$@"
