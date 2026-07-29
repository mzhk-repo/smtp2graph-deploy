#!/usr/bin/env bash
# Category 1a: Task 2.3 isolated SMTP2Graph runtime compatibility qualification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMAGE_REF="docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d"
ENTRYPOINT_SCRIPT="${PROJECT_ROOT}/scripts/entrypoint.sh"
RUNTIME_TEMPLATE_FILE="${PROJECT_ROOT}/deploy/config/gateway-config.yml.template"
RENDER_HELPER_FILE="${PROJECT_ROOT}/scripts/lib/render-config.sh"
TEMP_DIR="$(mktemp -d)"
SECRETS_DIR="${TEMP_DIR}/secrets"
CERTIFICATE_CONTAINER="smtp2graph-runtime-cert-${$}"
RESTART_CONTAINER="smtp2graph-runtime-restart-${$}"
FALLBACK_CONTAINER="smtp2graph-runtime-fallback-${$}"
SYNTHETIC_CLIENT_SECRET="runtime-fallback-material-for-task-2-3"
SYNTHETIC_SMTP_PASSWORD="runtime-smtp-password-for-task-3-2"

cleanup() {
  docker rm -f "${CERTIFICATE_CONTAINER}" "${RESTART_CONTAINER}" "${FALLBACK_CONTAINER}" >/dev/null 2>&1 || true
  rm -rf "${TEMP_DIR}"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

run_gateway() {
  local name="$1"
  local auth_mode="$2"
  shift 2

  docker run -d --name "${name}" \
    --network none \
    --user 65532:65532 \
    --read-only \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --pids-limit 64 \
    --memory 256m \
    --tmpfs /runtime:rw,nosuid,nodev,noexec,size=16m,uid=65532,gid=65532,mode=0700 \
    --tmpfs /tmp:rw,nosuid,nodev,noexec,size=16m \
    --mount "type=bind,src=${SECRETS_DIR},dst=/run/secrets,readonly" \
    --mount "type=bind,src=${ENTRYPOINT_SCRIPT},dst=/opt/smtp2graph/entrypoint.sh,readonly" \
    --mount "type=bind,src=${RUNTIME_TEMPLATE_FILE},dst=/opt/smtp2graph/gateway-config.yml.template,readonly" \
    --mount "type=bind,src=${RENDER_HELPER_FILE},dst=/opt/smtp2graph/render-config.sh,readonly" \
    -e "GRAPH_AUTH_MODE=${auth_mode}" \
    -e 'GRAPH_SENDER_MAILBOX=noreply@example.invalid' \
    -e 'SMTP_ALLOWED_SOURCE_CIDRS=127.0.0.1/32' \
    -e 'SMTP_ALLOWED_SENDER_ADDRESSES=noreply@example.invalid' \
    -e "DOCKER_SECRET_ALLOWED_UIDS=0:65532:$(id -u)" \
    -e 'RUNTIME_TEMPLATE_FILE=/opt/smtp2graph/gateway-config.yml.template' \
    -e 'RUNTIME_RENDER_HELPER_FILE=/opt/smtp2graph/render-config.sh' \
    "$@" \
    --entrypoint /bin/sh \
    "${IMAGE_REF}" \
    /opt/smtp2graph/entrypoint.sh >/dev/null
}

assert_running_listener() {
  local name="$1"
  local running
  local _attempt

  running="$(docker inspect --format '{{.State.Running}}' "${name}")"
  [[ "${running}" == 'true' ]] || fail "${name} did not remain running."
  for _attempt in $(seq 1 15); do
    if docker exec "${name}" node -e 'require("net").connect(587, "127.0.0.1").once("connect", function () { process.exit(0); }).once("error", function () { process.exit(1); });'; then
      return 0
    fi
    sleep 1
  done
  docker logs "${name}" 2>&1 >&2 || true
  fail "${name} did not listen on TCP/587 within 15 seconds."
}

assert_secret_absent() {
  local name="$1"
  local inspect_output
  local log_output

  inspect_output="$(docker inspect "${name}")"
  log_output="$(docker logs "${name}" 2>&1 || true)"
  [[ "${inspect_output}" != *"${SYNTHETIC_CLIENT_SECRET}"* ]] || fail 'synthetic client secret is present in docker inspect output.'
  [[ "${log_output}" != *"${SYNTHETIC_CLIENT_SECRET}"* ]] || fail 'synthetic client secret is present in container logs.'
  [[ "${inspect_output}" != *"${SYNTHETIC_SMTP_PASSWORD}"* ]] || fail 'synthetic SMTP password is present in docker inspect output.'
  [[ "${log_output}" != *"${SYNTHETIC_SMTP_PASSWORD}"* ]] || fail 'synthetic SMTP password is present in container logs.'
}

assert_hardening() {
  local name="$1"
  local hardening_summary
  local cap_drop
  local security_options

  hardening_summary="$(docker inspect --format '{{.Config.User}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.PidsLimit}}' "${name}")"
  [[ "${hardening_summary}" == '65532:65532 true 64' ]] || fail "${name} hardening settings differ from the qualification contract."
  cap_drop="$(docker inspect --format '{{json .HostConfig.CapDrop}}' "${name}")"
  security_options="$(docker inspect --format '{{json .HostConfig.SecurityOpt}}' "${name}")"
  [[ "${cap_drop}" == *'ALL'* ]] || fail "${name} does not drop all Linux capabilities."
  [[ "${security_options}" == *'no-new-privileges:true'* ]] || fail "${name} does not enforce no-new-privileges."
}

trap cleanup EXIT

[[ -x "${ENTRYPOINT_SCRIPT}" ]] || fail 'runtime entrypoint is missing or not executable.'
[[ -r "${RUNTIME_TEMPLATE_FILE}" ]] || fail 'runtime configuration template is missing or unreadable.'
[[ -r "${RENDER_HELPER_FILE}" ]] || fail 'runtime renderer helper is missing or unreadable.'
docker info >/dev/null 2>&1 || fail 'Docker daemon is unavailable.'

mkdir -p "${SECRETS_DIR}"
chmod 0755 "${SECRETS_DIR}"
printf '%s\n' '00000000-0000-0000-0000-000000000000' >"${SECRETS_DIR}/graph-tenant-id"
printf '%s\n' '11111111-1111-1111-1111-111111111111' >"${SECRETS_DIR}/graph-client-id"
printf '%s\n' '0123456789ABCDEF0123456789ABCDEF01234567' >"${SECRETS_DIR}/graph-certificate-thumbprint"
printf '%s\n' "${SYNTHETIC_CLIENT_SECRET}" >"${SECRETS_DIR}/graph-client-secret"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=smtp2graph-runtime-test.invalid' \
  -keyout "${SECRETS_DIR}/graph-private-key" \
  -out "${SECRETS_DIR}/smtp-tls-cert" >/dev/null 2>&1
cp "${SECRETS_DIR}/graph-private-key" "${SECRETS_DIR}/smtp-tls-key"
printf 'runtime-client\t%s\tnoreply@example.invalid\n' "${SYNTHETIC_SMTP_PASSWORD}" >"${SECRETS_DIR}/smtp-users"
chmod 0444 "${SECRETS_DIR}"/*

run_gateway "${FALLBACK_CONTAINER}" client-secret -e RUNTIME_ENTRYPOINT_MODE=render-only
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${FALLBACK_CONTAINER}")" == '0' ]] || fail 'client-secret render-only container did not exit successfully.'
assert_secret_absent "${FALLBACK_CONTAINER}"

run_gateway "${CERTIFICATE_CONTAINER}" certificate
assert_hardening "${CERTIFICATE_CONTAINER}"
assert_running_listener "${CERTIFICATE_CONTAINER}"
assert_secret_absent "${CERTIFICATE_CONTAINER}"
docker stop --time 10 "${CERTIFICATE_CONTAINER}" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${CERTIFICATE_CONTAINER}")" == '0' ]] || fail 'certificate-mode container did not stop gracefully.'

run_gateway "${RESTART_CONTAINER}" certificate
assert_hardening "${RESTART_CONTAINER}"
assert_running_listener "${RESTART_CONTAINER}"
assert_secret_absent "${RESTART_CONTAINER}"
docker stop --time 10 "${RESTART_CONTAINER}" >/dev/null
[[ "$(docker inspect --format '{{.State.ExitCode}}' "${RESTART_CONTAINER}")" == '0' ]] || fail 'restart container did not stop gracefully.'

printf 'PASS: runtime secret rendering, non-root/read-only startup, listener, stop and restart checks passed.\n'
