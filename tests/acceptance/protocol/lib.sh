#!/usr/bin/env bash
# Shared helpers for isolated SMTP2Graph protocol qualification tests.
set -euo pipefail

PROTOCOL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROTOCOL_PROJECT_ROOT="$(cd "${PROTOCOL_SCRIPT_DIR}/../../.." && pwd)"
PROTOCOL_IMAGE_REF="${PROTOCOL_IMAGE_REF:-docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d}"
PROTOCOL_ENTRYPOINT="${PROTOCOL_PROJECT_ROOT}/scripts/entrypoint.sh"
PROTOCOL_FIXTURE="${PROTOCOL_PROJECT_ROOT}/tests/fixtures/protocol-message.eml"
PROTOCOL_TEMP_DIR="$(mktemp -d)"
PROTOCOL_SECRETS_DIR="${PROTOCOL_TEMP_DIR}/secrets"
PROTOCOL_STATE_DIR="${PROTOCOL_TEMP_DIR}/state"
PROTOCOL_QUEUE_DIR="${PROTOCOL_TEMP_DIR}/queue"
PROTOCOL_NETWORK="smtp2graph-protocol-${$}"
PROTOCOL_MOCK="smtp2graph-protocol-mock-${$}"
PROTOCOL_GATEWAY="smtp2graph-protocol-gateway-${$}"

protocol_fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

protocol_cleanup() {
  docker rm -f "${PROTOCOL_GATEWAY}" "${PROTOCOL_MOCK}" >/dev/null 2>&1 || true
  docker network rm "${PROTOCOL_NETWORK}" >/dev/null 2>&1 || true
  protocol_purge_queue || true
  rm -rf "${PROTOCOL_TEMP_DIR}"
}

protocol_purge_queue() {
  if [[ -d "${PROTOCOL_QUEUE_DIR}" ]]; then
    docker run --rm --entrypoint /bin/sh \
      --mount "type=bind,src=${PROTOCOL_QUEUE_DIR},dst=/queue" \
      "${PROTOCOL_IMAGE_REF}" -c 'rm -rf /queue/* /queue/.[!.]* /queue/..?*' >/dev/null 2>&1 || true
  fi
}

protocol_wait_for() {
  local description="$1"
  local timeout_seconds="$2"
  shift 2
  local elapsed=0

  until "$@"; do
    ((elapsed += 1))
    if ((elapsed >= timeout_seconds)); then
      protocol_fail "timed out waiting for ${description}."
    fi
    sleep 1
  done
}

protocol_prepare() {
  [[ -x "${PROTOCOL_ENTRYPOINT}" ]] || protocol_fail 'runtime entrypoint is missing or not executable.'
  [[ -r "${PROTOCOL_FIXTURE}" ]] || protocol_fail 'protocol MIME fixture is missing.'
  docker info >/dev/null 2>&1 || protocol_fail 'Docker daemon is unavailable.'

  mkdir -p "${PROTOCOL_SECRETS_DIR}" "${PROTOCOL_STATE_DIR}" "${PROTOCOL_QUEUE_DIR}"
  chmod 0755 "${PROTOCOL_SECRETS_DIR}" "${PROTOCOL_STATE_DIR}"
  chmod 0777 "${PROTOCOL_QUEUE_DIR}"
  printf '%s\n' '00000000-0000-0000-0000-000000000000' >"${PROTOCOL_SECRETS_DIR}/graph-tenant-id"
  printf '%s\n' '11111111-1111-1111-1111-111111111111' >"${PROTOCOL_SECRETS_DIR}/graph-client-id"
  printf '%s\n' '0123456789ABCDEF0123456789ABCDEF01234567' >"${PROTOCOL_SECRETS_DIR}/graph-certificate-thumbprint"
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -subj '/CN=smtp2graph-protocol-test.invalid' \
    -addext 'subjectAltName=DNS:login.microsoftonline.com,DNS:graph.microsoft.com' \
    -keyout "${PROTOCOL_SECRETS_DIR}/graph-private-key" \
    -out "${PROTOCOL_SECRETS_DIR}/mock-ca.pem" >/dev/null 2>&1
  cp "${PROTOCOL_SECRETS_DIR}/graph-private-key" "${PROTOCOL_SECRETS_DIR}/smtp-tls-key"
  cp "${PROTOCOL_SECRETS_DIR}/mock-ca.pem" "${PROTOCOL_SECRETS_DIR}/smtp-tls-cert"
  chmod 0444 "${PROTOCOL_SECRETS_DIR}"/*
  printf '%s\n' success >"${PROTOCOL_STATE_DIR}/scenario"

  docker network create "${PROTOCOL_NETWORK}" >/dev/null
  docker run -d --name "${PROTOCOL_MOCK}" \
    --network "${PROTOCOL_NETWORK}" \
    --user "$(id -u):$(id -g)" \
    --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
    --mount "type=bind,src=${PROTOCOL_SCRIPT_DIR}/mock-graph.js,dst=/opt/mock/mock-graph.js,readonly" \
    --mount "type=bind,src=${PROTOCOL_SECRETS_DIR},dst=/tls,readonly" \
    --mount "type=bind,src=${PROTOCOL_STATE_DIR},dst=/state" \
    -e MOCK_GRAPH_TLS_KEY_PATH=/tls/graph-private-key \
    -e MOCK_GRAPH_TLS_CERT_PATH=/tls/mock-ca.pem \
    --entrypoint node \
    "${PROTOCOL_IMAGE_REF}" /opt/mock/mock-graph.js >/dev/null

  protocol_wait_for 'mock Graph readiness' 15 test -f "${PROTOCOL_STATE_DIR}/events.jsonl"
}

protocol_start_gateway() {
  local mode="$1"
  local scenario="$2"
  local retry_limit="${3:-1}"
  local mock_ip

  printf '%s\n' "${scenario}" >"${PROTOCOL_STATE_DIR}/scenario"
  rm -f "${PROTOCOL_STATE_DIR}/graph-attempts" "${PROTOCOL_STATE_DIR}/last-message.eml"
  mock_ip="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${PROTOCOL_MOCK}")"
  [[ -n "${mock_ip}" ]] || protocol_fail 'could not resolve mock Graph container IP.'

  docker run -d --name "${PROTOCOL_GATEWAY}" \
    --network "${PROTOCOL_NETWORK}" \
    --add-host "login.microsoftonline.com:${mock_ip}" \
    --add-host "graph.microsoft.com:${mock_ip}" \
    -p 127.0.0.1::587 \
    --user 65532:65532 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 64 \
    --memory 256m \
    --tmpfs /runtime:rw,nosuid,nodev,noexec,size=16m,uid=65532,gid=65532,mode=0700 \
    --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m,uid=65532,gid=65532,mode=0700 \
    --mount "type=bind,src=${PROTOCOL_QUEUE_DIR},dst=/runtime/mailroot" \
    --mount "type=bind,src=${PROTOCOL_SECRETS_DIR},dst=/run/secrets,readonly" \
    --mount "type=bind,src=${PROTOCOL_ENTRYPOINT},dst=/opt/smtp2graph/entrypoint.sh,readonly" \
    -e GRAPH_AUTH_MODE=certificate \
    -e "SMTP2GRAPH_MODE=${mode}" \
    -e "SEND_RETRY_LIMIT=${retry_limit}" \
    -e SEND_RETRY_INTERVAL_MINUTES=1 \
    -e SMTP_LISTEN_ADDRESS=0.0.0.0 \
    -e NODE_EXTRA_CA_CERTS=/run/secrets/mock-ca.pem \
    --entrypoint /bin/sh \
    "${PROTOCOL_IMAGE_REF}" /opt/smtp2graph/entrypoint.sh >/dev/null

  local attempt
  for attempt in $(seq 1 15); do
    if protocol_gateway_is_listening; then
      return 0
    fi
    sleep 1
  done
  docker logs "${PROTOCOL_GATEWAY}" 2>&1 >&2 || true
  protocol_fail 'gateway listener did not become ready.'
}

protocol_gateway_is_listening() {
  local port
  port="$(protocol_gateway_port)"
  node -e 'const tls=require("tls"); const socket=tls.connect({host:"127.0.0.1",port:Number(process.argv[1]),rejectUnauthorized:false}); socket.once("secureConnect",()=>socket.end()); socket.once("close",()=>process.exit(0)); socket.once("error",()=>process.exit(1));' "${port}" >/dev/null 2>&1
}

protocol_gateway_port() {
  docker inspect --format '{{(index (index .NetworkSettings.Ports "587/tcp") 0).HostPort}}' "${PROTOCOL_GATEWAY}"
}

protocol_submit_fixture() {
  local output_file="$1"
  node "${PROTOCOL_SCRIPT_DIR}/smtp-submit.js" \
    127.0.0.1 "$(protocol_gateway_port)" sender@example.invalid \
    'primary@example.invalid,copy@example.invalid,blind@example.invalid' \
    "${PROTOCOL_FIXTURE}" >"${output_file}"
}

protocol_graph_attempts() {
  if [[ -f "${PROTOCOL_STATE_DIR}/graph-attempts" ]]; then
    cat "${PROTOCOL_STATE_DIR}/graph-attempts"
  else
    printf '0\n'
  fi
}

protocol_wait_for_graph_attempts() {
  local attempts="$1"
  local timeout_seconds="${2:-20}"
  protocol_wait_for "${attempts} Graph attempt(s)" "${timeout_seconds}" bash -c "[[ \$(cat '${PROTOCOL_STATE_DIR}/graph-attempts' 2>/dev/null || printf 0) -ge ${attempts} ]]"
}

protocol_queue_has_eml() {
  docker exec "${PROTOCOL_GATEWAY}" /bin/sh -c 'find /runtime/mailroot/queue -maxdepth 1 -type f -name "*.eml" -print -quit | grep -q .'
}

protocol_queue_is_empty() {
  ! protocol_queue_has_eml
}

protocol_failed_has_eml() {
  docker exec "${PROTOCOL_GATEWAY}" /bin/sh -c 'find /runtime/mailroot/failed -maxdepth 1 -type f -name "*.eml" -print -quit | grep -q .'
}
