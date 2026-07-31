#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stack="$root/deploy/swarm/stack.yml"
storage_init="$root/scripts/init-storage.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

require_stack_control() {
  local file=$1
  rg -q '^    user: "65532:65532"$' "$file" || return 1
  rg -q '^    read_only: true$' "$file" || return 1
  rg -q '^    cap_drop:$' "$file" || return 1
  rg -q '^      - ALL$' "$file" || return 1
  rg -q '^    security_opt:$' "$file" || return 1
  rg -q '^      - no-new-privileges:true$' "$file" || return 1
  rg -q '^          pids: 64$' "$file" || return 1
  rg -q '^      - /runtime:rw,nosuid,nodev,noexec,size=16m,uid=65532,gid=65532,mode=0700$' "$file" || return 1
  rg -q '^      - /tmp:rw,nosuid,nodev,noexec,size=16m,uid=65532,gid=65532,mode=0700$' "$file" || return 1
  rg -q '^          cpus: "1.00"$' "$file" || return 1
  rg -q '^          memory: 512M$' "$file" || return 1
  if rg -q 'privileged:[[:space:]]*true|/var/run/docker.sock|network_mode:[[:space:]]*host|pid:[[:space:]]*host' "$file"; then
    return 1
  fi
}

require_stack_control "$stack"
cp "$stack" "$tmp/weakened.yml"
sed -i '/^    read_only: true$/d' "$tmp/weakened.yml"
if require_stack_control "$tmp/weakened.yml"; then
  printf 'ERROR: hardening policy unexpectedly accepted a weakened manifest.\n' >&2
  exit 1
fi

mkdir -p "$tmp/storage"
"$storage_init" --storage-root "$tmp/storage" | rg -q '^READY: queue will be initialized as 65532:65532 mode 0700\.$'
if "$storage_init" --storage-root / >/dev/null 2>&1; then
  printf 'ERROR: storage initializer unexpectedly accepted /.\n' >&2
  exit 1
fi
mkdir -p "$tmp/storage/queue"
touch "$tmp/storage/queue/existing-message.eml"
if "$storage_init" --storage-root "$tmp/storage" >/dev/null 2>&1; then
  printf 'ERROR: storage initializer unexpectedly accepted a non-empty incompatible queue.\n' >&2
  exit 1
fi
rg -q 'never recursively changes ownership' "$storage_init"
if rg -q 'chown -R' "$storage_init"; then
  printf 'ERROR: storage initializer must not perform a recursive ownership change.\n' >&2
  exit 1
fi
printf 'PASS: container hardening and storage initialization policies fail closed.\n'
