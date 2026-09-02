#!/usr/bin/env bash
# Category 2: restore a verified control-plane backup into an empty target only.
set -euo pipefail
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "$root/scripts/lib/read-deploy-env.sh"
environment='' env_file='' backup='' cloud_backup='' target='' confirm='' apply=false
while (($#)); do case "$1" in
  --environment)
    environment=${2:-}
    shift 2
    ;;
  --env-file)
    env_file=${2:-}
    shift 2
    ;;
  --backup)
    backup=${2:-}
    shift 2
    ;;
  --cloud-backup)
    cloud_backup=${2:-}
    shift 2
    ;;
  --target)
    target=${2:-}
    shift 2
    ;;
  --confirm-target)
    confirm=${2:-}
    shift 2
    ;;
  --check)
    apply=false
    shift
    ;;
  --apply)
    apply=true
    shift
    ;;
  *) die "unsupported argument: $1" ;; esac done
[[ "$environment" == development || "$environment" == production ]] || die '--environment must be development or production.'
[[ -n "$env_file" ]] || env_file="$root/env.$([[ "$environment" == development ]] && printf dev || printf prod).enc"
[[ "$env_file" = /* ]] || die '--env-file must be absolute.'
[[ -n "$backup" && -z "$cloud_backup" || -z "$backup" && -n "$cloud_backup" ]] || die 'choose exactly one of --backup or --cloud-backup.'
[[ "$target" = /* && "$target" != / && "$confirm" == "$target" ]] || die '--target and exact --confirm-target are required.'
prepare_sops_deploy_env "$root" "$env_file"
trap 'cleanup_sops_deploy_env' EXIT
load_deploy_env_file "$root" "$SOPS_DEPLOY_ENV_FILE" DEPLOY_ENVIRONMENT SMTP2GRAPH_BACKUP_RCLONE_REMOTE SMTP2GRAPH_BACKUP_RCLONE_PATH
[[ "$DEPLOY_ENVIRONMENT" == "$environment" ]] || die 'DEPLOY_ENVIRONMENT does not match --environment.'
require_server_env_match "$environment"
for tool in tar sha256sum; do command -v "$tool" >/dev/null || die "$tool is required."; done
stage=$(mktemp -d /dev/shm/smtp2graph-restore.XXXXXX)
chmod 700 "$stage"
cleanup() {
  rm -rf -- "$stage"
  cleanup_sops_deploy_env
}
trap cleanup EXIT
if [[ -n "$cloud_backup" ]]; then
  [[ "$cloud_backup" =~ ^smtp2graph-${environment}-[0-9]{8}T[0-9]{6}Z\.tar\.gz$ ]] || die '--cloud-backup is unsafe.'
  command -v rclone >/dev/null || die 'rclone is required for --cloud-backup.'
  cloud="$SMTP2GRAPH_BACKUP_RCLONE_REMOTE:${SMTP2GRAPH_BACKUP_RCLONE_PATH%/}"
  backup="$stage/$cloud_backup"
  rclone copyto "$cloud/$cloud_backup" "$backup"
  rclone copyto "$cloud/$cloud_backup.sha256" "$backup.sha256"
fi
[[ "$backup" = /* && -f "$backup" && ! -L "$backup" && -f "$backup.sha256" ]] || die 'backup and checksum must be regular files.'
(cd "$(dirname "$backup")" && sha256sum -c "$(basename "$backup").sha256")
tar -tzf "$backup" | awk '($0 ~ /(^|\/)(\.\.?)(\/|$)/ || $0 !~ /^(\.sops\.yaml|env\.(dev|prod)\.enc|deploy\/|scripts\/|docs\/adr\/|docs\/RUNBOOK\.md|docs\/scripts_runbook\.md|recovery-manifest\.txt)/) { exit 1 }' || die 'backup contains an unexpected path.'
[[ "$apply" == true ]] || {
  printf 'PASS: backup is valid; no files were restored.\n'
  exit 0
}
[[ ! -e "$target" ]] || { [[ -d "$target" && ! -L "$target" && -z "$(find "$target" -mindepth 1 -print -quit)" ]]; } || die '--target must be a new or empty non-symlink directory.'
mkdir -p "$target"
tar -C "$target" -xzf "$backup"
printf 'PASS: control-plane bundle restored to %s; reconcile secrets and deploy separately.\n' "$target"
