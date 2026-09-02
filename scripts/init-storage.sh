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
Usage: scripts/init-storage.sh --storage-root ABSOLUTE_PATH [--backup-local-dir PATH \
  --backup-rclone-remote NAME --backup-rclone-path PATH] [--environment development|production] [--apply]

The default is validation-only. --apply requires a matching host SERVER_ENV and creates
or corrects only the validated storage root and its direct queue and failed children
with owner 65532:65532 and mode 0700. It never recursively changes ownership or
traverses message payloads. Optional backup paths create only an owner-only local
directory and an empty rclone destination during explicit apply.
USAGE
}

storage_root=''
backup_local_dir='' backup_rclone_remote='' backup_rclone_path=''
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
    --backup-local-dir)
      backup_local_dir=${2:-}
      shift 2
      ;;
    --backup-rclone-remote)
      backup_rclone_remote=${2:-}
      shift 2
      ;;
    --backup-rclone-path)
      backup_rclone_path=${2:-}
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
if [[ -n "$backup_local_dir$backup_rclone_remote$backup_rclone_path" ]]; then
  [[ -n "$backup_local_dir" && -n "$backup_rclone_remote" && -n "$backup_rclone_path" ]] || die 'backup local dir, rclone remote and rclone path must be supplied together.'
  [[ "$backup_local_dir" = /* && "$backup_local_dir" != / ]] || die '--backup-local-dir must be an absolute path other than /.'
  [[ "$backup_rclone_remote" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die '--backup-rclone-remote is unsafe.'
  [[ "$backup_rclone_path" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]{0,255}$ && "$backup_rclone_path" != *..* ]] || die '--backup-rclone-path is unsafe.'
fi
for tool in dirname basename find grep install realpath stat chown chmod; do command -v "$tool" >/dev/null || die "$tool is required."; done
if [[ "$apply" == true ]]; then
  [[ "$environment" == development || "$environment" == production ]] || die '--apply requires --environment development or production.'
  require_server_env_match "$environment" || die 'host SERVER_ENV must match --environment.'
fi

needs_mutation=false

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
    mkdir -p -- "$storage_root"
    needs_mutation=true
  fi
  [[ -d "$storage_root" && ! -L "$storage_root" ]] || die '--storage-root must be an existing non-symlink directory.'
  resolved_storage_root=$(realpath -e -- "$storage_root") || die 'could not resolve --storage-root.'
  [[ "$resolved_storage_root" == "$storage_root" ]] || die '--storage-root must not contain symlink components.'
}

prepare_storage_root

prepare_backup_local_dir() {
  [[ -z "$backup_local_dir" ]] && return
  if [[ ! -e "$backup_local_dir" ]]; then
    [[ "$apply" == true ]] || {
      printf 'READY: backup local directory will be initialized mode 0700.\n'
      return
    }
    mkdir -p -- "$backup_local_dir"
    chmod 0700 -- "$backup_local_dir"
    needs_mutation=true
  fi
  [[ -d "$backup_local_dir" && ! -L "$backup_local_dir" ]] || die '--backup-local-dir must be a non-symlink directory.'
  [[ "$(stat -c '%a' "$backup_local_dir")" =~ ^[67]00$ ]] || die '--backup-local-dir must not be group/world accessible.'
}

validate_storage_root_owner() {
  local owner mode
  owner=$(stat -c '%u:%g' "$storage_root") || die 'could not inspect storage root ownership.'
  mode=$(stat -c '%a' "$storage_root") || die 'could not inspect storage root permissions.'
  if [[ "$owner" != "$runtime_uid:$runtime_gid" || "$mode" != 700 ]]; then
    needs_mutation=true
    printf 'READY: storage root will be corrected to %s:%s mode 0700.\n' "$runtime_uid" "$runtime_gid"
    return
  fi
  printf 'PASS: storage root has reviewed owner and mode.\n'
}

validate_existing_child() {
  local child=$1 path owner mode
  path="$storage_root/$child"
  if [[ ! -e "$path" ]]; then
    needs_mutation=true
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
    needs_mutation=true
    printf 'READY: empty %s will be corrected to %s:%s mode 0700.\n' "$child" "$runtime_uid" "$runtime_gid"
    return
  fi
  printf 'PASS: %s has reviewed owner and mode.\n' "$child"
}

validate_storage_root_owner
for child in queue failed; do validate_existing_child "$child"; done
prepare_backup_local_dir
if [[ -n "$backup_rclone_remote" ]]; then
  needs_mutation=true
  [[ "$apply" == true ]] || printf 'READY: rclone backup destination will be initialized on apply.\n'
fi
[[ "$apply" == true ]] || exit 0
if [[ "$needs_mutation" == false ]]; then
  printf 'PASS: storage root and children are initialized; deploy separately through approved orchestration.\n'
  exit 0
fi
chown "$runtime_uid:$runtime_gid" -- "$storage_root" 2>/dev/null || true
chmod 0700 -- "$storage_root" 2>/dev/null || true
for child in queue failed; do
  if [[ ! -e "$storage_root/$child" ]]; then
    mkdir -p -- "$storage_root/$child" 2>/dev/null || true
  fi
  chown "$runtime_uid:$runtime_gid" -- "$storage_root/$child" 2>/dev/null || true
  chmod 0700 -- "$storage_root/$child" 2>/dev/null || true
done
if [[ -n "$backup_rclone_remote" ]]; then
  command -v rclone >/dev/null || die 'rclone is required to initialize backup destination.'
  rclone mkdir "$backup_rclone_remote:${backup_rclone_path%/}"
fi
printf 'PASS: storage root and children are initialized; deploy separately through approved orchestration.\n'
