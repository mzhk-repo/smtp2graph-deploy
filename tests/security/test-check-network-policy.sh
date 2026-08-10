#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/scripts/check-network-policy.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  info\ *) exit 0 ;;
  'network inspect')
    [[ "${3:-}" == smtp2graph_internal_enc ]] || exit 1
    printf '%s\n' '{"encrypted":""}'
    ;;
  'service inspect')
    format=${!#}
    [[ "$format" == *'{{"\n"}}'* ]] || exit 1
    printf '%s\n' 'smtp-tls-key 65532 65532 0400' 'smtp-tls-cert 65532 65532 0444'
    ;;
  *) exit 1 ;;
esac
EOF
cat >"$fake_bin/nft" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == list && "${2:-}" == ruleset ]] || exit 1
printf '%s\n' 'table inet smtp2graph { set smtp2graph_smtp_clients {} }'
EOF
cat >"$fake_bin/ss" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'LISTEN 0 128 0.0.0.0:2525 0.0.0.0:*'
EOF
chmod 700 "$fake_bin/docker" "$fake_bin/nft" "$fake_bin/ss"

PATH="$fake_bin:$PATH" "$script" --network smtp2graph_internal_enc --stack-name smtp2graph >/dev/null
if PATH="$fake_bin:$PATH" "$script" --network 'unsafe network' >/dev/null 2>&1; then
  printf 'ERROR: network-policy check accepted an unsafe overlay name.\n' >&2
  exit 1
fi

printf 'PASS: live network-policy check requires an explicit safe deployment target.\n'
