#!/usr/bin/env bash
# Category 1b: validate or initialize the SMTP2Graph persistent storage root and fixed children.
set -euo pipefail

runtime_uid=65532
runtime_gid=65532

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
usage() {
  cat <<'USAGE'
Usage: scripts/init-storage.sh --storage-root ABSOLUTE_PATH [--environment development|production] [--apply]

The default is validation-only. --apply requires a matching host SERVER_ENV and creates
or corrects only the validated storage root and its direct queue and failed children
with owner 65532:65532 and mode 0700. It never recursively changes ownership or
traverses message payloads.
USAGE
}

storage_root=''
environment=''
apply=false
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"
while (($#)); do
  case "$1" in
    --storage-root)
      storage_root=${2:-}
      shift 2
      ;;
    --environment)
      environment=${2:-}
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$storage_root" = /* && "$storage_root" != / ]] || die '--storage-root must be an absolute path other than /.'
for tool in dirname basename find grep install realpath stat chown chmod; do command -v "$tool" >/dev/null || die "$tool is required."; done
if [[ "$apply" == true ]]; then
  [[ "$environment" == development || "$environment" == production ]] || die '--apply requires --environment development or production.'
  require_server_env_match "$environment" || die 'host SERVER_ENV must match --environment.'
  [[ $(id -u) -eq 0 ]] || die '--apply requires a privileged operator to set the reviewed runtime owner.'
fi

prepare_storage_root() {
  local parent leaf ancestor resolved_ancestor resolved_storage_root
  parent=$(dirname "$storage_root")
  leaf=$(basename "$storage_root")
  [[ "$leaf" != . && "$leaf" != .. ]] || die '--storage-root has an unsafe final component.'
  if [[ ! -e "$storage_root" ]]; then
    [[ "$apply" == true ]] || die '--storage-root must be an existing non-symlink directory.'
    ancestor=$parent
    while [[ ! -e "$ancestor" ]]; do ancestor=$(dirname "$ancestor"); done
    [[ -d "$ancestor" && ! -L "$ancestor" && "$ancestor" != / ]] || die '--storage-root requires an existing non-symlink ancestor below /. '
    resolved_ancestor=$(realpath -e -- "$ancestor") || die 'could not resolve --storage-root ancestor.'
    [[ "$resolved_ancestor" == "$ancestor" ]] || die '--storage-root ancestor must not contain symlink components.'
    install -d -m 0750 -- "$storage_root"
  fi
  [[ -d "$storage_root" && ! -L "$storage_root" ]] || die '--storage-root must be an existing non-symlink directory.'
  resolved_storage_root=$(realpath -e -- "$storage_root") || die 'could not resolve --storage-root.'
  [[ "$resolved_storage_root" == "$storage_root" ]] || die '--storage-root must not contain symlink components.'
}

prepare_storage_root

validate_storage_root_owner() {
  local owner mode
  owner=$(stat -c '%u:%g' "$storage_root") || die 'could not inspect storage root ownership.'
  mode=$(stat -c '%a' "$storage_root") || die 'could not inspect storage root permissions.'
  if [[ "$owner" != "$runtime_uid:$runtime_gid" || "$mode" != 700 ]]; then
    printf 'READY: storage root will be corrected to %s:%s mode 0700.\n' "$runtime_uid" "$runtime_gid"
    return
  fi
  printf 'PASS: storage root has reviewed owner and mode.\n'
}

validate_existing_child() {
  local child=$1 path owner mode
  path="$storage_root/$child"
  if [[ ! -e "$path" ]]; then
    printf 'READY: %s will be initialized as %s:%s mode 0700.\n' "$child" "$runtime_uid" "$runtime_gid"
    return
  fi
  [[ -d "$path" && ! -L "$path" ]] || die "$child must be a direct non-symlink directory."
  owner=$(stat -c '%u:%g' "$path") || die "could not inspect $child ownership."
  mode=$(stat -c '%a' "$path") || die "could not inspect $child permissions."
  if [[ "$owner" != "$runtime_uid:$runtime_gid" || "$mode" != 700 ]]; then
    if find "$path" -mindepth 1 -print -quit | grep -q .; then
      die "$child is non-empty with incompatible ownership or mode; migration requires separate review."
    fi
    printf 'READY: empty %s will be corrected to %s:%s mode 0700.\n' "$child" "$runtime_uid" "$runtime_gid"
    return
  fi
  printf 'PASS: %s has reviewed owner and mode.\n' "$child"
}

validate_storage_root_owner
for child in queue failed; do validate_existing_child "$child"; done
[[ "$apply" == true ]] || exit 0
chown "$runtime_uid:$runtime_gid" -- "$storage_root"
chmod 0700 -- "$storage_root"
for child in queue failed; do
  install -d -o "$runtime_uid" -g "$runtime_gid" -m 0700 -- "$storage_root/$child"
done
printf 'PASS: storage root and children are initialized; deploy separately through approved orchestration.\n'
