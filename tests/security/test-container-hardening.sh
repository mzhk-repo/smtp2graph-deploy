#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stack="$root/deploy/swarm/stack.yml"
storage_init="$root/scripts/init-storage.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

require_stack_control() {
  local file=$1
  grep -Eq '^    user: "65532:65532"$' "$file" || return 1
  grep -Eq '^    read_only: true$' "$file" || return 1
  grep -Eq '^    cap_drop:$' "$file" || return 1
  grep -Eq '^      - ALL$' "$file" || return 1
  grep -Eq '^    security_opt:$' "$file" || return 1
  grep -Eq '^      - no-new-privileges:true$' "$file" || return 1
  grep -Eq '^          pids: 64$' "$file" || return 1
  grep -Eq '^      - type: tmpfs$' "$file" || return 1
  grep -Eq '^        target: /runtime$' "$file" || return 1
  grep -Eq '^        target: /tmp$' "$file" || return 1
  grep -Eq '^          cpus: "1.00"$' "$file" || return 1
  grep -Eq '^          memory: 512M$' "$file" || return 1
  if grep -Eq 'privileged:[[:space:]]*true|/var/run/docker.sock|network_mode:[[:space:]]*host|pid:[[:space:]]*host' "$file"; then
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
storage_out=$("$storage_init" --storage-root "$tmp/storage")
printf '%s\n' "$storage_out" | grep -Eq '^READY: storage root will be corrected to 65532:65532 mode 0700\.$'
printf '%s\n' "$storage_out" | grep -Eq '^READY: queue will be initialized as 65532:65532 mode 0700\.$'
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
grep -Fq 'never recursively changes ownership' "$storage_init"
if grep -Fq 'chown -R' "$storage_init"; then
  printf 'ERROR: storage initializer must not perform a recursive ownership change.\n' >&2
  exit 1
fi
server_env_file="$tmp/server.environment"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env_file"
rm -f "$tmp/storage/queue/existing-message.eml"
SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" "$storage_init" --storage-root "$tmp/storage" --environment development --apply >/dev/null
test -d "$tmp/storage/queue"
test -d "$tmp/storage/failed"
printf 'PASS: container hardening and storage initialization policies fail closed.\n'
