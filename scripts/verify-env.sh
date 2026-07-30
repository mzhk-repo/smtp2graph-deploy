#!/usr/bin/env bash
# Category 1a: validate the committed example contract without loading env files.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONTRACT_FILE="${PROJECT_ROOT}/deploy/config/env-contract.keys"
EXAMPLE_FILE="${VERIFY_ENV_EXAMPLE_FILE:-${PROJECT_ROOT}/.env.example}"

usage() {
  printf 'Usage: %s --example-only\n' "${0##*/}" >&2
}

if [[ "${#}" -ne 1 || "${1:-}" != "--example-only" ]]; then
  usage
  exit 64
fi

if [[ ! -r "${CONTRACT_FILE}" || ! -r "${EXAMPLE_FILE}" ]]; then
  printf 'ERROR: configuration contract or example file is missing.\n' >&2
  exit 66
fi

declare -A required_keys=()
declare -A expected_values=()
declare -A actual_values=()

while IFS='|' read -r key requirement classification expected_value extra || [[ -n "${key:-}" ]]; do
  key="${key%$'\r'}"
  [[ -z "${key}" || "${key}" == \#* ]] && continue

  if [[ -n "${extra:-}" || ! "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]] ||
    [[ "${requirement}" != "required" ]] ||
    [[ "${classification}" != "public" && "${classification}" != "secret-reference" && "${classification}" != "secret-value" ]] ||
    [[ -z "${expected_value}" ]]; then
    printf 'ERROR: invalid contract entry for key %s.\n' "${key}" >&2
    exit 65
  fi

  required_keys["${key}"]="${classification}"
  expected_values["${key}"]="${expected_value}"
done <"${CONTRACT_FILE}"

while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%$'\r'}"
  [[ -z "${line}" || "${line}" == \#* ]] && continue

  if [[ ! "${line}" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]]; then
    printf 'ERROR: invalid .env.example syntax.\n' >&2
    exit 65
  fi

  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"

  if [[ -v "actual_values[${key}]" ]]; then
    printf 'ERROR: duplicate key in .env.example: %s.\n' "${key}" >&2
    exit 65
  fi
  if [[ ! -v "required_keys[${key}]" ]]; then
    printf 'ERROR: unknown key in .env.example: %s.\n' "${key}" >&2
    exit 65
  fi

  actual_values["${key}"]="${value}"
done <"${EXAMPLE_FILE}"

for key in "${!required_keys[@]}"; do
  if [[ ! -v "actual_values[${key}]" ]]; then
    printf 'ERROR: required key is missing from .env.example: %s.\n' "${key}" >&2
    exit 65
  fi
  if [[ "${actual_values[${key}]}" != "${expected_values[${key}]}" ]]; then
    printf 'ERROR: unsupported example value for key: %s.\n' "${key}" >&2
    exit 65
  fi
done

printf 'PASS: .env.example matches the experimental configuration contract; values were not printed.\n'
