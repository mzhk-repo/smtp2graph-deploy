#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/migrate-dev-host.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
state="$tmp/state"
server_env_file="$tmp/server.environment"
env_file="$tmp/development.env"
base_root="$tmp/srv/smtp2graph"
legacy_root="$base_root/non-production"
target_root="$base_root/dev"
mkdir -p "$fake_bin" "$state" "$legacy_root/data/queue" "$legacy_root/data/failed"
printf '%s\n' 'SERVER_ENV=dev' >"$server_env_file"
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=development' \
  "SMTP2GRAPH_STORAGE_HOST_PATH=${target_root}/data" \
  'SWARM_STACK_NAME=smtp2graph' >"$env_file"
printf '%s\n' true >"$state/old-label"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'info --format') printf '%s\n' true ;;
  'info ') exit 0 ;;
  'service ps') [[ "${FAKE_RUNNING:-0}" == 1 ]] && printf '%s\n' running-task ;;
  'node inspect')
    if [[ "${5:-}" == '{{.ID}}' ]]; then
      printf '%s\n' fake-node
    elif [[ "${5:-}" == *smtp2graph_nonproduction* ]]; then
      cat "${FAKE_STATE}/old-label" 2>/dev/null || true
    else
      cat "${FAKE_STATE}/dev-label" 2>/dev/null || true
    fi
    ;;
  'node update')
    case "$*" in
      *'--label-add smtp2graph_dev=true'*) printf '%s\n' true >"${FAKE_STATE}/dev-label" ;;
      *'--label-rm smtp2graph_nonproduction'*) : >"${FAKE_STATE}/old-label" ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
cat >"$fake_bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -u ]] && { printf '%s\n' 0; exit 0; }
exec /usr/bin/id "$@"
EOF
cat >"$fake_bin/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target=${!#}
mkdir -p -- "$target"
chmod 0700 -- "$target"
EOF
chmod 700 "$fake_bin/docker" "$fake_bin/id" "$fake_bin/install"

test_env=(PATH="$fake_bin:$PATH" FAKE_STATE="$state" SMTP2GRAPH_SERVER_ENV_FILE="$server_env_file" SMTP2GRAPH_TEST_MODE=1)
if env "${test_env[@]}" FAKE_RUNNING=1 "$script" --env-file "$env_file" --test-root "$tmp" --check >/dev/null 2>&1; then
  printf 'ERROR: migration unexpectedly accepted a running gateway.\n' >&2
  exit 1
fi
env "${test_env[@]}" "$script" --env-file "$env_file" --test-root "$tmp" --apply >/dev/null
test -d "$target_root/data/queue"
test ! -e "$legacy_root"
test "$(cat "$state/dev-label")" = true
test ! -s "$state/old-label"
env "${test_env[@]}" "$script" --env-file "$env_file" --test-root "$tmp" --apply >/dev/null

ln -s "$target_root" "$base_root/unsafe"
unsafe_env="$tmp/unsafe.env"
sed "s#${target_root}/data#${base_root}/unsafe/data#" "$env_file" >"$unsafe_env"
if env "${test_env[@]}" "$script" --env-file "$unsafe_env" --test-root "$tmp" --check >/dev/null 2>&1; then
  printf 'ERROR: migration unexpectedly accepted a symlinked target.\n' >&2
  exit 1
fi

printf 'PASS: dev host migration rejects unsafe state and is idempotent.\n'
