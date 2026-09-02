#!/usr/bin/env bash
# Category 2: create an allowlisted control-plane backup locally and through rclone.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "$root/scripts/lib/read-deploy-env.sh"

environment='' env_file='' apply=false
while (($#)); do
  case "$1" in
    --environment)
      environment=${2:-}
      shift 2
      ;;
    --env-file)
      env_file=${2:-}
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
    *) die "unsupported argument: $1" ;;
  esac
done
[[ "$environment" == development || "$environment" == production ]] || die '--environment must be development or production.'
[[ -n "$env_file" ]] || env_file="$root/env.$([[ "$environment" == development ]] && printf dev || printf prod).enc"
[[ "$env_file" = /* ]] || die '--env-file must be absolute.'
prepare_sops_deploy_env "$root" "$env_file"
trap 'cleanup_sops_deploy_env' EXIT
grep -q '^sops_version=' "$SOPS_DEPLOY_SOURCE_FILE" || grep -q 'ENC\[AES256_GCM' "$SOPS_DEPLOY_SOURCE_FILE" || die 'backup source environment must be SOPS-encrypted.'
load_deploy_env_file "$root" "$SOPS_DEPLOY_ENV_FILE" DEPLOY_ENVIRONMENT SMTP2GRAPH_BACKUP_LOCAL_DIR SMTP2GRAPH_BACKUP_RCLONE_REMOTE SMTP2GRAPH_BACKUP_RCLONE_PATH SMTP2GRAPH_BACKUP_LOCAL_RETENTION_COUNT SMTP2GRAPH_BACKUP_CLOUD_RETENTION_COUNT
[[ "$DEPLOY_ENVIRONMENT" == "$environment" ]] || die 'DEPLOY_ENVIRONMENT does not match --environment.'
require_server_env_match "$environment"
for tool in tar sha256sum rclone git find sort; do command -v "$tool" >/dev/null || die "$tool is required."; done
[[ "$SMTP2GRAPH_BACKUP_LOCAL_DIR" = /* && "$SMTP2GRAPH_BACKUP_LOCAL_DIR" != / && -d "$SMTP2GRAPH_BACKUP_LOCAL_DIR" && ! -L "$SMTP2GRAPH_BACKUP_LOCAL_DIR" ]] || die 'SMTP2GRAPH_BACKUP_LOCAL_DIR must be an existing absolute non-symlink directory.'
[[ "$(stat -c '%a' "$SMTP2GRAPH_BACKUP_LOCAL_DIR")" =~ ^[67]00$ ]] || die 'SMTP2GRAPH_BACKUP_LOCAL_DIR must not be group/world accessible.'
[[ "$SMTP2GRAPH_BACKUP_RCLONE_REMOTE" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die 'SMTP2GRAPH_BACKUP_RCLONE_REMOTE is unsafe.'
[[ "$SMTP2GRAPH_BACKUP_RCLONE_PATH" =~ ^[A-Za-z0-9][A-Za-z0-9_./-]{0,255}$ && "$SMTP2GRAPH_BACKUP_RCLONE_PATH" != *..* ]] || die 'SMTP2GRAPH_BACKUP_RCLONE_PATH is unsafe.'
for key in SMTP2GRAPH_BACKUP_LOCAL_RETENTION_COUNT SMTP2GRAPH_BACKUP_CLOUD_RETENTION_COUNT; do [[ "${!key}" =~ ^[1-9][0-9]*$ ]] || die "$key must be a positive integer."; done
[[ "$apply" == true ]] || {
  printf 'PASS: backup contract is valid; no archive was created.\n'
  exit 0
}

stamp=$(date -u +%Y%m%dT%H%M%SZ)
name="smtp2graph-${environment}-${stamp}.tar.gz"
archive="$SMTP2GRAPH_BACKUP_LOCAL_DIR/$name"
checksum="$archive.sha256"
stage=$(mktemp -d /dev/shm/smtp2graph-backup.XXXXXX)
chmod 700 "$stage"
cleanup() {
  rm -rf -- "$stage"
  cleanup_sops_deploy_env
}
trap cleanup EXIT
printf 'environment=%s\ngit_revision=%s\narchive=%s\n' "$environment" "$(git -C "$root" rev-parse HEAD)" "$name" >"$stage/recovery-manifest.txt"
env_name="env.$([[ "$environment" == development ]] && printf dev || printf prod).enc"
cp -- "$SOPS_DEPLOY_SOURCE_FILE" "$stage/$env_name"
tar -C "$root" -czf "$archive" .sops.yaml deploy scripts docs/adr docs/RUNBOOK.md docs/scripts_runbook.md -C "$stage" "$env_name" recovery-manifest.txt
(cd "$SMTP2GRAPH_BACKUP_LOCAL_DIR" && sha256sum "$name" >"$(basename "$checksum")")
cloud="$SMTP2GRAPH_BACKUP_RCLONE_REMOTE:${SMTP2GRAPH_BACKUP_RCLONE_PATH%/}"
rclone copyto "$archive" "$cloud/$name"
rclone copyto "$checksum" "$cloud/$(basename "$checksum")"
rotate_local() { find "$SMTP2GRAPH_BACKUP_LOCAL_DIR" -maxdepth 1 -type f -name "smtp2graph-${environment}-*.tar.gz" -printf '%f\n' | sort -r | tail -n "+$((SMTP2GRAPH_BACKUP_LOCAL_RETENTION_COUNT + 1))" | while IFS= read -r old; do [[ -z "$old" ]] || rm -f -- "$SMTP2GRAPH_BACKUP_LOCAL_DIR/$old" "$SMTP2GRAPH_BACKUP_LOCAL_DIR/$old.sha256"; done; }
rotate_cloud() { rclone lsf "$cloud" --files-only --include "smtp2graph-${environment}-*.tar.gz" | sort -r | tail -n "+$((SMTP2GRAPH_BACKUP_CLOUD_RETENTION_COUNT + 1))" | while IFS= read -r old; do [[ -z "$old" ]] || {
  rclone deletefile "$cloud/$old"
  rclone deletefile "$cloud/$old.sha256" || true
}; done; }
rotate_local
rotate_cloud
printf 'PASS: backup created: %s\n' "$archive"
