#!/usr/bin/env bash
# Category 1a: Task 3.3 isolated local SMTP-to-Graph MVP harness.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
compose_file="${project_root}/compose.test.yaml"
fixture="${project_root}/tests/fixtures/protocol-message.eml"
scenario_client="${script_dir}/smtp-scenario.js"
upgrade_script="${project_root}/scripts/upgrade-smtp2graph-fork.sh"
test_root="$(mktemp -d /dev/shm/smtp2graph-mvp.XXXXXX)"
project_name="smtp2graph-mvp-${$}"
test_image="smtp2graph-local-mvp-${$}:v1-1-5"
env_file="${test_root}/compose.env"
mock_ip="172.30.$((($$ % 200) + 20)).2"
test_subnet="${mock_ip%.*}.0/24"
smtp_user='mvp-client'
smtp_password='synthetic-mvp-password-not-for-output'
suite='mvp'
test_image_override=''
remove_test_image=1

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [--suite mvp|task62] [--image NAME@sha256:DIGEST]\n' "$0" >&2
}

while (($#)); do
  case "$1" in
    --suite)
      suite=${2:?}
      shift 2
      ;;
    --image)
      test_image_override=${2:?}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

case "${suite}" in
  mvp | task62) ;;
  *) die 'suite must be mvp or task62' ;;
esac
if [[ -n "${test_image_override}" ]]; then
  printf '%s\n' "${test_image_override}" | grep -Eq '^[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$' ||
    die 'image must be a lowercase digest-pinned OCI reference'
fi

compose() {
  docker compose --project-name "${project_name}" --env-file "${env_file}" --file "${compose_file}" "$@"
}

cleanup() {
  status=$?
  if ((status != 0)) && [[ -f "${env_file}" ]]; then
    compose logs --no-color >&2 || true
  fi
  if [[ -f "${env_file}" ]]; then
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  if ((remove_test_image)); then
    docker image rm --force "${test_image}" >/dev/null 2>&1 || true
  fi
  rm -rf -- "${test_root}"
  exit "${status}"
}
trap cleanup EXIT

wait_for() {
  local description="$1"
  local timeout_seconds="$2"
  shift 2
  local elapsed=0
  until "$@"; do
    ((elapsed += 1))
    if ((elapsed >= timeout_seconds)); then
      die "timed out waiting for ${description}"
    fi
    sleep 1
  done
}

queue_is_empty() {
  ! compose exec -T gateway /bin/sh -c 'find /data/queue -maxdepth 1 -type f -name "*.eml" -print -quit | grep -q .'
}

queue_has_payload() {
  compose exec -T gateway /bin/sh -c 'find /data/queue -maxdepth 1 -type f -name "*.eml" -print -quit | grep -q .'
}

graph_attempts_at_least() {
  local expected="$1"
  [[ -f "${test_root}/state/graph-attempts" ]] && [[ "$(cat "${test_root}/state/graph-attempts")" -ge "${expected}" ]]
}

run_scenario() {
  local name="$1"
  local attempt
  for attempt in $(seq 1 20); do
    if compose exec -T -e "SMTP_TEST_USER=${smtp_user}" -e "SMTP_TEST_PASSWORD=${smtp_password}" \
      mock-graph node /opt/smoke/smtp-scenario.js gateway 587 "${name}" /opt/smoke/protocol-message.eml >/dev/null; then
      return 0
    fi
    sleep 1
  done
  die "SMTP scenario did not complete: ${name}"
}

reset_graph_state() {
  rm -f "${test_root}/state/graph-attempts" "${test_root}/state/last-message.eml" "${test_root}/state/events.jsonl"
  : >"${test_root}/state/events.jsonl"
}

failed_has_payload() {
  compose exec -T gateway /bin/sh -c 'find /data/failed -maxdepth 1 -type f -name "*.eml" -print -quit | grep -q .'
}

clear_failed_payloads() {
  compose exec -T gateway /bin/sh -c 'find /data/failed -maxdepth 1 -type f -name "*.eml" -delete'
}

assert_retry_after() {
  node -e '
const fs = require("fs");
const events = fs.readFileSync(process.argv[1], "utf8").trim().split("\\n").filter(Boolean).map(JSON.parse).filter(event => event.kind === "graph");
if (events.length < 2 || events[1].timestamp - events[0].timestamp < 1800) process.exit(1);
' "${test_root}/state/events.jsonl"
}

[[ -r "${compose_file}" && -r "${fixture}" && -r "${scenario_client}" && -x "${upgrade_script}" ]] || die 'required Task 3.3 harness asset is unavailable'
command -v docker >/dev/null 2>&1 || die 'docker is required'
command -v node >/dev/null 2>&1 || die 'node is required'
command -v openssl >/dev/null 2>&1 || die 'openssl is required'
docker info >/dev/null 2>&1 || die 'Docker daemon is unavailable'
docker compose version >/dev/null 2>&1 || die 'Docker Compose v2 is required'

mkdir -p "${test_root}/secrets" "${test_root}/state" "${test_root}/storage"
chmod 0777 "${test_root}/state" "${test_root}/storage"
printf '%s\n' '00000000-0000-0000-0000-000000000000' >"${test_root}/secrets/graph-tenant-id"
printf '%s\n' '11111111-1111-1111-1111-111111111111' >"${test_root}/secrets/graph-client-id"
printf '%s\n' '0123456789ABCDEF0123456789ABCDEF01234567' >"${test_root}/secrets/graph-certificate-thumbprint"
printf '%s\n' "${smtp_user}"$'\t'"${smtp_password}"$'\t''noreply@example.invalid' >"${test_root}/secrets/smtp-users"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj '/CN=smtp2graph-local-mvp.invalid' \
  -addext 'subjectAltName=DNS:login.microsoftonline.com,DNS:graph.microsoft.com' \
  -keyout "${test_root}/secrets/graph-private-key" \
  -out "${test_root}/secrets/mock-ca.pem" >/dev/null 2>&1
cp "${test_root}/secrets/graph-private-key" "${test_root}/secrets/smtp-tls-key"
cp "${test_root}/secrets/mock-ca.pem" "${test_root}/secrets/smtp-tls-cert"
chmod 0444 "${test_root}/secrets"/*
printf '%s\n' success >"${test_root}/state/scenario"
chmod 0600 "${test_root}/state/scenario"

test_image="${test_image_override:-${test_image}}"
if [[ -n "${test_image_override}" ]]; then
  remove_test_image=0
fi
if [[ "${suite}" == task62 ]]; then
  queue_max_bytes=1048576
else
  queue_max_bytes=1073741824
fi

cat >"${env_file}" <<EOF
SMTP2GRAPH_TEST_IMAGE=${test_image}
SMTP2GRAPH_TEST_ROOT=${test_root}
SMTP2GRAPH_TEST_SUBNET=${test_subnet}
SMTP2GRAPH_MOCK_IP=${mock_ip}
SMTP2GRAPH_TEST_UID=$(id -u)
SMTP2GRAPH_QUEUE_MAX_BYTES=${queue_max_bytes}
SMTP2GRAPH_QUEUE_REJECT_THRESHOLD_PERCENT=80
SMTP2GRAPH_MESSAGES_PER_MINUTE=30
EOF
chmod 0600 "${env_file}"

if [[ -z "${test_image_override}" ]]; then
  "${upgrade_script}" --release v1.1.5 --apply --test-image "${test_image}"
fi
compose up --detach
wait_for 'mock Graph readiness' 20 test -f "${test_root}/state/events.jsonl"
run_scenario positive
wait_for 'positive Graph submission' 20 graph_attempts_at_least 1
wait_for 'positive queue drain' 20 queue_is_empty

run_scenario unauthenticated
run_scenario denied-sender
run_scenario oversize
queue_is_empty || die 'a rejected SMTP submission created a queue payload'

printf '%s\n' timeout >"${test_root}/state/scenario"
run_scenario positive
wait_for 'queued payload before restart' 20 queue_has_payload
printf '%s\n' success >"${test_root}/state/scenario"
compose restart gateway >/dev/null
wait_for 'Graph submission after restart' 20 graph_attempts_at_least 3
wait_for 'queue drain after restart' 20 queue_is_empty

if [[ "${suite}" == task62 ]]; then
  reset_graph_state
  printf '%s\n' retry-after >"${test_root}/state/scenario"
  run_scenario positive
  wait_for 'Retry-After Graph retry' 20 graph_attempts_at_least 2
  assert_retry_after || die 'Graph Retry-After was not honoured for at least 1.8 seconds'
  wait_for 'Retry-After queue drain' 20 queue_is_empty

  reset_graph_state
  printf '%s\n' access-denied >"${test_root}/state/scenario"
  run_scenario positive
  wait_for 'access-denied Graph attempt' 20 graph_attempts_at_least 1
  wait_for 'access-denied failed payload' 20 failed_has_payload
  queue_is_empty || die 'access-denied payload remained in the live queue'

  clear_failed_payloads
  reset_graph_state
  printf '%s\n' server-error >"${test_root}/state/scenario"
  run_scenario positive
  wait_for 'initial 5xx Graph attempt' 20 graph_attempts_at_least 1
  wait_for 'bounded 5xx failed payload' 160 failed_has_payload
  queue_is_empty || die 'bounded 5xx payload remained in the live queue'

  clear_failed_payloads
  reset_graph_state
  printf '%s\n' unauthorized >"${test_root}/state/scenario"
  run_scenario positive
  wait_for 'initial 401 Graph attempt' 20 graph_attempts_at_least 1
  wait_for 'bounded 401 failed payload' 160 failed_has_payload
  queue_is_empty || die 'bounded 401 payload remained in the live queue'

  clear_failed_payloads
  reset_graph_state
  printf '%s\n' success >"${test_root}/state/scenario"
  compose restart gateway >/dev/null
  for attempt in $(seq 1 30); do
    run_scenario positive
  done
  run_scenario rate-limited
  wait_for 'burst queue drain' 40 queue_is_empty

  compose restart gateway >/dev/null
  compose exec -T gateway /bin/sh -c 'dd if=/dev/zero of=/data/queue/.task62-capacity-fill bs=1024 count=820 status=none'
  run_scenario capacity-rejected
  compose exec -T gateway /bin/sh -c 'rm -f -- /data/queue/.task62-capacity-fill'
fi

printf 'PASS: %s suite passed without Microsoft 365 access or live gateway mutation.\n' "${suite}"
