#!/usr/bin/env bash
# Category 1a: verifies purge root validation and refusal of unsafe path layouts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PURGE_SCRIPT="${PROJECT_ROOT}/scripts/purge-failed.sh"
TEMP_DIR="$(mktemp -d)"

cleanup() { rm -rf -- "${TEMP_DIR}"; }
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
  [[ "${output}" == *"${expected}"* ]] || fail "expected failure was not returned: ${expected}"
}

expect_failure 'absolute path other than /' env SMTP2GRAPH_STORAGE_ROOT=/ "${PURGE_SCRIPT}" --dry-run
expect_failure 'existing non-symlink directory' env SMTP2GRAPH_STORAGE_ROOT="${TEMP_DIR}/missing" "${PURGE_SCRIPT}" --dry-run
expect_failure 'choose only one' env SMTP2GRAPH_STORAGE_ROOT="${TEMP_DIR}" "${PURGE_SCRIPT}" --dry-run --apply

mkdir -p "${TEMP_DIR}/storage"
ln -s / "${TEMP_DIR}/storage/failed"
expect_failure 'existing non-symlink directory' env SMTP2GRAPH_STORAGE_ROOT="${TEMP_DIR}/storage" "${PURGE_SCRIPT}" --apply

printf 'PASS: failed-payload purge rejects unsafe roots and symlinked failed directories.\n'
