#!/usr/bin/env bash
# Category 1a: verifies dry-run and apply semantics for failed payload retention.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PURGE_SCRIPT="${PROJECT_ROOT}/scripts/purge-failed.sh"
TEMP_DIR="$(mktemp -d)"
STORAGE_ROOT="${TEMP_DIR}/storage"
FAILED_ROOT="${STORAGE_ROOT}/failed"
QUEUE_ROOT="${STORAGE_ROOT}/queue"

cleanup() { rm -rf -- "${TEMP_DIR}"; }
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

mkdir -p "${FAILED_ROOT}/nested" "${QUEUE_ROOT}"
printf 'expired failed payload\n' >"${FAILED_ROOT}/expired.eml"
printf 'nested expired failed payload\n' >"${FAILED_ROOT}/nested/expired.eml"
printf 'recent failed payload\n' >"${FAILED_ROOT}/recent.eml"
printf 'queue payload must remain untouched\n' >"${QUEUE_ROOT}/expired.eml"
touch -d '8 days ago' "${FAILED_ROOT}/expired.eml" "${FAILED_ROOT}/nested/expired.eml" "${QUEUE_ROOT}/expired.eml"

dry_run_output="$(SMTP2GRAPH_STORAGE_ROOT="${STORAGE_ROOT}" "${PURGE_SCRIPT}")"
[[ "${dry_run_output}" == *'2 failed payload(s)'* ]] || fail 'dry-run did not report the expected eligible payload count.'
[[ -f "${FAILED_ROOT}/expired.eml" && -f "${FAILED_ROOT}/nested/expired.eml" ]] || fail 'dry-run removed a failed payload.'
[[ -f "${QUEUE_ROOT}/expired.eml" ]] || fail 'dry-run touched queue data.'

apply_output="$(SMTP2GRAPH_STORAGE_ROOT="${STORAGE_ROOT}" "${PURGE_SCRIPT}" --apply)"
[[ "${apply_output}" == *'purged 2 failed payload(s)'* ]] || fail 'apply did not report the expected purge count.'
[[ ! -e "${FAILED_ROOT}/expired.eml" && ! -e "${FAILED_ROOT}/nested/expired.eml" ]] || fail 'expired failed payload was not purged.'
[[ -f "${FAILED_ROOT}/recent.eml" ]] || fail 'recent failed payload was purged.'
[[ -f "${QUEUE_ROOT}/expired.eml" ]] || fail 'queue payload was touched.'

printf 'PASS: failed-payload purge defaults to dry-run and never touches queue data.\n'
