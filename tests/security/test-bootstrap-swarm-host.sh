#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/bootstrap-swarm-host.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
state="$tmp/state"
storage_parent="$tmp/storage-parent"
env_file="$tmp/deploy.env"
mkdir -p "$fake_bin" "$state" "$storage_parent"

printf '%s\n' \
  'DEPLOY_ENVIRONMENT=non-production' \
  'SWARM_OVERLAY_NETWORK=smtp2graph_internal' \
  "SMTP2GRAPH_STORAGE_HOST_PATH=${storage_parent}/data" \
  'SMTP_ALLOWED_SOURCE_CIDRS=10.42.0.0/24' >"$env_file"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'info --format') printf '%s\n' true ;;
  'node inspect')
    if [[ "$5" == '{{.ID}}' ]]; then printf '%s\n' fake-node; else cat "${FAKE_STATE}/label" 2>/dev/null || true; fi
    ;;
  'node update') printf '%s\n' true >"${FAKE_STATE}/label" ;;
  'network inspect')
    test -f "${FAKE_STATE}/network" || exit 1
    printf '%s\n' 'overlay swarm {"encrypted":""}'
    ;;
  'network create') : >"${FAKE_STATE}/network" ;;
  *) exit 0 ;;
esac
EOF
cat >"$fake_bin/nft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_STATE}/nft.calls"
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
chmod 700 "$fake_bin/docker" "$fake_bin/nft" "$fake_bin/id" "$fake_bin/install"

if PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$env_file" --check >/dev/null 2>&1; then
  printf 'ERROR: check unexpectedly accepted missing prerequisites.\n' >&2
  exit 1
fi

PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$env_file" --apply >/dev/null
PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$env_file" --apply >/dev/null
test -f "$state/network"
test "$(cat "$state/label")" = true
rg -q -- '--check --file' "$state/nft.calls"
rg -q -- '--file' "$state/nft.calls"

sed -i 's/"encrypted":""/"encrypted":"false"/' "$fake_bin/docker"
if PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$env_file" --check >/dev/null 2>&1; then
  printf 'ERROR: check unexpectedly accepted an unencrypted overlay.\n' >&2
  exit 1
fi

printf '%s\n' 'SMTP_ALLOWED_SOURCE_CIDRS=8.8.8.8/32' >>"$env_file"
if PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$env_file" --check >/dev/null 2>&1; then
  printf 'ERROR: check unexpectedly accepted a public CIDR.\n' >&2
  exit 1
fi

unsafe_env="$tmp/unsafe.env"
printf '%s\n' \
  'DEPLOY_ENVIRONMENT=non-production' \
  'SWARM_OVERLAY_NETWORK=smtp2graph_internal' \
  'SMTP2GRAPH_STORAGE_HOST_PATH=/' \
  'SMTP_ALLOWED_SOURCE_CIDRS=10.42.0.0/24' >"$unsafe_env"
if PATH="$fake_bin:$PATH" FAKE_STATE="$state" "$script" --env-file "$unsafe_env" --check >/dev/null 2>&1; then
  printf 'ERROR: check unexpectedly accepted the storage root.\n' >&2
  exit 1
fi

printf 'PASS: Swarm bootstrap checks and applies only reviewed non-production prerequisites.\n'
