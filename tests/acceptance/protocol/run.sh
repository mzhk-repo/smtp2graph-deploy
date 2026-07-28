#!/usr/bin/env bash
# Category 1a: Task 2.4 MIME, acknowledgement and queue-restart qualification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

trap protocol_cleanup EXIT
protocol_prepare

ack_file="${PROTOCOL_TEMP_DIR}/smtp-ack.json"
protocol_start_gateway full success
protocol_submit_fixture "${ack_file}"
protocol_wait_for_graph_attempts 1
ack_timestamp="$(jq -r '.timestamp' "${ack_file}")"
graph_timestamp="$(jq -r 'select(.kind == "graph") | .timestamp' "${PROTOCOL_STATE_DIR}/events.jsonl" | head -n 1)"
[[ "${ack_timestamp}" -le "${graph_timestamp}" ]] || protocol_fail 'SMTP acknowledgement occurred after Graph submission started.'

docker stop --time 10 "${PROTOCOL_GATEWAY}" >/dev/null
docker rm "${PROTOCOL_GATEWAY}" >/dev/null
protocol_purge_queue

protocol_start_gateway receive success
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/restart-ack.json"
protocol_wait_for 'queued EML before restart' 10 protocol_queue_has_eml

docker stop --time 10 "${PROTOCOL_GATEWAY}" >/dev/null
docker rm "${PROTOCOL_GATEWAY}" >/dev/null
protocol_start_gateway full success
protocol_wait_for_graph_attempts 1
protocol_wait_for 'captured MIME message' 10 test -f "${PROTOCOL_STATE_DIR}/last-message.eml"
protocol_wait_for 'queue drain after Graph acceptance' 10 protocol_queue_is_empty

restart_gateway() {
  docker rm -f "${PROTOCOL_GATEWAY}" >/dev/null 2>&1 || true
  protocol_start_gateway "$@"
}

restart_gateway receive success
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/crash-ack.json"
protocol_wait_for 'queued EML before crash' 10 protocol_queue_has_eml
docker kill --signal KILL "${PROTOCOL_GATEWAY}" >/dev/null
docker rm "${PROTOCOL_GATEWAY}" >/dev/null
protocol_start_gateway full success
protocol_wait_for_graph_attempts 1
[[ "$(protocol_graph_attempts)" == '1' ]] || protocol_fail 'crash recovery caused duplicate Graph delivery.'
protocol_wait_for 'queue drain after crash recovery' 10 protocol_queue_is_empty

rg -q '^From: .*SMTP2Graph QA.*sender@example\.invalid' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q '^To: primary@example.invalid' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q '^Cc: copy@example.invalid' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q '^Bcc: blind@example.invalid' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q '^Reply-To: replies@example.invalid' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q 'Тестове HTML-повідомлення' "${PROTOCOL_STATE_DIR}/last-message.eml"
rg -q 'U1lOVEhFVElDX0FUVEFDSE1FTlQ=' "${PROTOCOL_STATE_DIR}/last-message.eml"

printf 'PASS: MIME fields, BCC injection, UTF-8, attachment, durable queue restart, crash-after-250 recovery and SMTP acknowledgement boundary verified.\n'
