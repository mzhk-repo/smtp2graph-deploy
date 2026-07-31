#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stack="${root}/deploy/swarm/stack.yml"
nft="${root}/deploy/network/smtp2graph.nft"
renderer="${root}/scripts/render-network-policy.sh"
rg -q 'mode: host' "$stack"
if rg -q 'mode: ingress' "$stack"; then
  printf 'ERROR: routing mesh publish is forbidden.\n' >&2
  exit 1
fi
rg -q 'target: 2525' "$stack"
rg -q 'mode: 0400' "$stack"
rg -q 'tcp dport 2525 ip saddr @smtp2graph_smtp_clients accept' "$nft"
rg -q 'tcp dport 2525 drop' "$nft"
if rg -q '0\.0\.0\.0/0|::/0' "$nft"; then
  printf 'ERROR: public CIDR is forbidden.\n' >&2
  exit 1
fi
rendered=$(mktemp /dev/shm/smtp2graph-nft-test.XXXXXX)
env_file=$(mktemp /dev/shm/smtp2graph-nft-env.XXXXXX)
trap 'rm -f -- "$rendered" "$env_file"' EXIT
printf '%s\n' 'SMTP_ALLOWED_SOURCE_CIDRS=10.42.0.0/24,192.168.20.4/32' >"$env_file"
"$renderer" --env-file "$env_file" "$rendered"
rg -q '10.42.0.0/24,192.168.20.4/32' "$rendered"
printf '%s\n' 'SMTP_ALLOWED_SOURCE_CIDRS=100.64.0.4/32' >"$env_file"
"$renderer" --env-file "$env_file" "$rendered"
rg -q '100.64.0.4/32' "$rendered"
printf '%s\n' 'SMTP_ALLOWED_SOURCE_CIDRS=8.8.8.8/32' >"$env_file"
if "$renderer" --env-file "$env_file" "$rendered" >/dev/null 2>&1; then
  printf 'ERROR: public CIDR unexpectedly rendered.\n' >&2
  exit 1
fi
printf 'PASS: development Swarm and nftables policy are deny-by-default.\n'
