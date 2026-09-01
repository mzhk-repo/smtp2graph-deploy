#!/usr/bin/env bash
# Category 1a: isolated backup/restore regression with a fake rclone remote.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
backup="$root/scripts/backup.sh"
restore="$root/scripts/restore.sh"
tmp=$(mktemp -d /dev/shm/smtp2graph-recovery-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/local" "$tmp/cloud/smtp2graph/development" "$tmp/target"
chmod 700 "$tmp/local" "$tmp/cloud" "$tmp/target"
printf '%s\n' 'SERVER_ENV=dev' >"$tmp/server.env"
recipient=$(awk '/^[[:space:]]+age: age1/{print $2; exit}' "$root/.sops.yaml")
cat >"$tmp/plain.env" <<EOF
DEPLOY_ENVIRONMENT=development
SMTP2GRAPH_BACKUP_LOCAL_DIR=$tmp/local
SMTP2GRAPH_BACKUP_RCLONE_REMOTE=test-drive
SMTP2GRAPH_BACKUP_RCLONE_PATH=smtp2graph/development
SMTP2GRAPH_BACKUP_LOCAL_RETENTION_COUNT=7
SMTP2GRAPH_BACKUP_CLOUD_RETENTION_COUNT=30
EOF
printf 'creation_rules:\n  - path_regex: ".*"\n    age: %s\n' "$recipient" >"$tmp/.sops.yaml"
sops --config "$tmp/.sops.yaml" --encrypt --input-type dotenv --output-type dotenv "$tmp/plain.env" >"$tmp/env.dev.enc"
cat >"$tmp/bin/rclone" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cloud=${FAKE_RCLONE_CLOUD:?}
path_for() { printf '%s/%s\n' "$cloud" "${1#*:}"; }
case "$1" in
  copyto)
    source=$2; destination=$3
    if [[ "$source" == *:* && ! -f "$source" ]]; then cp "$(path_for "$source")" "$destination"; else destination=$(path_for "$destination"); mkdir -p "$(dirname "$destination")"; cp "$source" "$destination"; fi
    ;;
  lsf) find "$(path_for "$2")" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' ;;
  deletefile) rm -f -- "$(path_for "$2")" ;;
  *) exit 64 ;;
esac
EOF
chmod 700 "$tmp/bin/rclone"
for n in $(seq -w 1 8); do touch "$tmp/local/smtp2graph-development-20260101T0000${n}Z.tar.gz" "$tmp/local/smtp2graph-development-20260101T0000${n}Z.tar.gz.sha256"; done
for n in $(seq -w 1 31); do touch "$tmp/cloud/smtp2graph/development/smtp2graph-development-20260101T0000${n}Z.tar.gz" "$tmp/cloud/smtp2graph/development/smtp2graph-development-20260101T0000${n}Z.tar.gz.sha256"; done
env PATH="$tmp/bin:$PATH" FAKE_RCLONE_CLOUD="$tmp/cloud" SMTP2GRAPH_SERVER_ENV_FILE="$tmp/server.env" "$backup" --environment development --env-file "$tmp/env.dev.enc" --check
env PATH="$tmp/bin:$PATH" FAKE_RCLONE_CLOUD="$tmp/cloud" SMTP2GRAPH_SERVER_ENV_FILE="$tmp/server.env" "$backup" --environment development --env-file "$tmp/env.dev.enc" --apply
archive=$(find "$tmp/local" -maxdepth 1 -name 'smtp2graph-development-*.tar.gz' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)
[[ -n "$archive" && -f "$archive.sha256" ]] || {
  echo 'ERROR: backup archive is missing.' >&2
  exit 1
}
[[ $(find "$tmp/local" -maxdepth 1 -name '*.tar.gz' | wc -l) -eq 7 ]] || {
  echo 'ERROR: local retention failed.' >&2
  exit 1
}
[[ $(find "$tmp/cloud/smtp2graph/development" -maxdepth 1 -name '*.tar.gz' | wc -l) -eq 30 ]] || {
  echo 'ERROR: cloud retention failed.' >&2
  exit 1
}
tar -tzf "$archive" | grep -Eq '(^|/)data/(queue|failed|logs)' && {
  echo 'ERROR: forbidden storage was archived.' >&2
  exit 1
}
env SMTP2GRAPH_SERVER_ENV_FILE="$tmp/server.env" "$restore" --environment development --env-file "$tmp/env.dev.enc" --backup "$archive" --target "$tmp/target" --confirm-target "$tmp/target" --check
env SMTP2GRAPH_SERVER_ENV_FILE="$tmp/server.env" "$restore" --environment development --env-file "$tmp/env.dev.enc" --backup "$archive" --target "$tmp/target" --confirm-target "$tmp/target" --apply
test -f "$tmp/target/env.dev.enc"
test -f "$tmp/target/recovery-manifest.txt"
test -f "$tmp/target/scripts/deploy-orchestrator-swarm.sh"
echo 'PASS: control-plane backup, dual retention and cold restore are isolated and queue-free.'
