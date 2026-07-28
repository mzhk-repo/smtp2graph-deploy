#!/usr/bin/env bash
# Category 1a: Task 2.4 retry, timeout and permanent-error qualification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

blockers=()

record_blocker() {
  blockers+=("$1")
  printf 'BLOCKER: %s\n' "$1" >&2
}

restart_gateway() {
  docker rm -f "${PROTOCOL_GATEWAY}" >/dev/null 2>&1 || true
  protocol_purge_queue
  protocol_start_gateway "$@"
}

trap protocol_cleanup EXIT
protocol_prepare

protocol_start_gateway full retry-after
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/retry-after-ack.json"
protocol_wait_for_graph_attempts 2 20
retry_gap_ms="$(jq -s 'map(select(.kind == "graph") | .timestamp) | .[1] - .[0]' "${PROTOCOL_STATE_DIR}/events.jsonl")"
if [[ "${retry_gap_ms}" -lt 1800 ]]; then
  record_blocker "HTTP 429 Retry-After=2 was not honoured; observed Graph retry gap: ${retry_gap_ms} ms."
else
  printf 'PASS: HTTP 429 retry gap was %s ms.\n' "${retry_gap_ms}"
fi

restart_gateway full timeout
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/timeout-ack.json"
protocol_wait_for_graph_attempts 1
protocol_wait_for 'queued HTTP 408 message' 10 protocol_queue_has_eml
printf 'PASS: HTTP 408 leaves the message in the durable queue for retry.\n'

restart_gateway full access-denied
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/access-denied-ack.json"
protocol_wait_for_graph_attempts 1
protocol_wait_for 'access-denied failed result' 10 protocol_failed_has_eml
printf 'PASS: permanent access-denied message moved atomically to failed state.\n'

restart_gateway full server-error 1
protocol_submit_fixture "${PROTOCOL_TEMP_DIR}/server-error-ack.json"
protocol_wait_for_graph_attempts 1
protocol_wait_for 'failed message after bounded 500 retry' 160 protocol_failed_has_eml
printf 'PASS: HTTP 500 retried with bounded queue lifecycle and moved to failed state.\n'

if ((${#blockers[@]})); then
  printf 'FAIL: %s Gate B blocker(s) detected.\n' "${#blockers[@]}" >&2
  exit 1
fi

printf 'PASS: failure injection checks passed without Gate B blockers.\n'
