#!/usr/bin/env bash
# Category 1a: Task 6.2 disposable failure, durability and retention suite.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../../.." && pwd)"
default_image='ghcr.io/mzhk-repo/smtp2graph-build@sha256:3d5069229059411988884913b6afba2d198c43e2440c1037e44d6aa54f172f65'
image_ref="${GATEWAY_IMAGE_DIGEST:-${default_image}}"

usage() {
  printf 'Usage: %s --environment staging [--image NAME@sha256:DIGEST]\n' "$0" >&2
}

environment=''
while (($#)); do
  case "$1" in
    --environment)
      environment=${2:?}
      shift 2
      ;;
    --image)
      image_ref=${2:?}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 64
      ;;
  esac
done

[[ "${environment}" == staging ]] || {
  usage
  exit 64
}
printf '%s\n' "${image_ref}" | grep -Eq '^[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}$' ||
  {
    printf 'ERROR: image must be a lowercase digest-pinned OCI reference.\n' >&2
    exit 64
  }

"${project_root}/tests/shell/test-purge-failed.sh"
"${project_root}/tests/security/test-purge-failed.sh"
exec "${project_root}/tests/smoke/run.sh" --suite task62 --image "${image_ref}"
