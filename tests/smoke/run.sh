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

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

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
  docker image rm --force "${test_image}" >/dev/null 2>&1 || true
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
  ! find "${test_root}/storage/queue" -maxdepth 1 -type f -name '*.eml' -print -quit | grep -q .
}

queue_has_payload() {
  find "${test_root}/storage/queue" -maxdepth 1 -type f -name '*.eml' -print -quit | grep -q .
}

graph_attempts_at_least() {
  local expected="$1"
  [[ -f "${test_root}/state/graph-attempts" ]] && [[ "$(cat "${test_root}/state/graph-attempts")" -ge "${expected}" ]]
}

run_scenario() {
  local name="$1"
  SMTP_TEST_USER="${smtp_user}" SMTP_TEST_PASSWORD="${smtp_password}" \
    node "${scenario_client}" 127.0.0.1 "${smtp_port}" "${name}" "${fixture}" >/dev/null
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

cat >"${env_file}" <<EOF
SMTP2GRAPH_TEST_IMAGE=${test_image}
SMTP2GRAPH_TEST_ROOT=${test_root}
SMTP2GRAPH_TEST_SUBNET=${test_subnet}
SMTP2GRAPH_MOCK_IP=${mock_ip}
SMTP2GRAPH_TEST_UID=$(id -u)
EOF
chmod 0600 "${env_file}"

"${upgrade_script}" --release v1.1.5 --apply --test-image "${test_image}"
compose up --detach
wait_for 'mock Graph readiness' 20 test -f "${test_root}/state/events.jsonl"
smtp_port="$(compose port gateway 587 | awk -F: 'NR == 1 {print $NF}')"
[[ "${smtp_port}" =~ ^[0-9]+$ ]] || die 'could not resolve the published SMTP port'

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

printf 'PASS: local MVP positive, negative and queue-restart flows passed without Microsoft 365 access.\n'
