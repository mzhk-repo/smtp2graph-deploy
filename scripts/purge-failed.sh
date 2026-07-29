#!/usr/bin/env bash
# Category 2: purge expired failed SMTP payloads from a fixed validated storage subdirectory.
set -euo pipefail

STORAGE_ROOT="${SMTP2GRAPH_STORAGE_ROOT:-/data}"
RETENTION_DAYS=7
MODE=dry-run
MODE_EXPLICIT=false

usage() {
  printf 'Usage: %s [--dry-run|--apply]\n' "${0##*/}" >&2
}

die() {
  printf 'ERROR: %s\n' "$1" >&2
  exit "${2:-64}"
}

while (($#)); do
  case "$1" in
    --dry-run | --apply)
      [[ "${MODE_EXPLICIT}" = false ]] || die 'choose only one of --dry-run or --apply.'
      MODE=${1#--}
      MODE_EXPLICIT=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unsupported argument: $1"
      ;;
  esac
  shift
done

[[ "${STORAGE_ROOT}" = /* && "${STORAGE_ROOT}" != / ]] || die 'SMTP2GRAPH_STORAGE_ROOT must be an absolute path other than /.'
[[ -d "${STORAGE_ROOT}" && ! -L "${STORAGE_ROOT}" ]] || die 'SMTP2GRAPH_STORAGE_ROOT must be an existing non-symlink directory.' 66

storage_root_real="$(realpath -e -- "${STORAGE_ROOT}")" || die 'could not resolve SMTP2GRAPH_STORAGE_ROOT.' 66
failed_root="${storage_root_real}/failed"
[[ -d "${failed_root}" && ! -L "${failed_root}" ]] || die 'failed payload root must be an existing non-symlink directory.' 66
failed_root_real="$(realpath -e -- "${failed_root}")" || die 'could not resolve failed payload root.' 66
[[ "${failed_root_real}" = "${storage_root_real}/failed" ]] || die 'failed payload root must be the fixed failed child of SMTP2GRAPH_STORAGE_ROOT.' 66

mapfile -d '' -t expired_payloads < <(
  find "${failed_root_real}" -xdev -type f -mtime "+$((RETENTION_DAYS - 1))" -print0
)

if [[ "${MODE}" = dry-run ]]; then
  printf 'DRY-RUN: %s failed payload(s) are eligible for purge after %s days; no files were removed.\n' "${#expired_payloads[@]}" "${RETENTION_DAYS}"
  exit 0
fi

if ((${#expired_payloads[@]} > 0)); then
  rm -- "${expired_payloads[@]}"
fi
printf 'APPLY: purged %s failed payload(s) older than %s days from the validated failed root.\n' "${#expired_payloads[@]}" "${RETENTION_DAYS}"
