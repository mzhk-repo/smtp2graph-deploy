#!/usr/bin/env bash
# Category 1b: render a development nftables policy from explicit non-public IPv4 CIDRs.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${root}/scripts/lib/read-deploy-env.sh"
template=${SMTP_NFT_TEMPLATE:-}
env_file=''
if [[ "${1:-}" == --env-file ]]; then
  env_file=${2:-}
  shift 2
fi
load_deploy_env_file "$root" "$env_file" DEPLOY_ENVIRONMENT SMTP_ALLOWED_SOURCE_CIDRS
output=${1:-}
cidrs=${SMTP_ALLOWED_SOURCE_CIDRS:-}
[[ -n "$output" && "$output" = /* && -n "$cidrs" ]] || die 'absolute output path and SMTP_ALLOWED_SOURCE_CIDRS are required.'
if [[ -z "$template" ]]; then
  case "${DEPLOY_ENVIRONMENT:-development}" in
    development) template="${root}/deploy/network/smtp2graph.nft" ;;
    production) template="${root}/deploy/network/smtp2graph-prod.nft" ;;
    *) die 'DEPLOY_ENVIRONMENT must be development or production.' ;;
  esac
fi
[[ -f "$template" && ! -L "$template" ]] || die 'nftables template is unavailable.'
IFS=',' read -r -a values <<<"$cidrs"
rendered=()
for cidr in "${values[@]}"; do
  [[ "$cidr" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.)[0-9.]+/[0-9]{1,2}$ ]] || die 'only RFC1918 or CGNAT IPv4 CIDRs are permitted.'
  rendered+=("$cidr")
done
replacement=$(
  IFS=,
  printf '%s' "${rendered[*]}"
  python3 -c '
import ipaddress, sys
cidrs = sys.argv[1:]
nets = [ipaddress.ip_network(c) for c in cidrs]
collapsed = list(ipaddress.collapse_addresses(nets))
print(",".join(str(n) for n in collapsed))
' "${rendered[@]}"
)
tmp=$(mktemp "$(dirname "$output")/.smtp2graph-nft.XXXXXX")
chmod 600 "$tmp"
sed "s|__SMTP_ALLOWED_SOURCE_CIDRS__|${replacement}|" "$template" >"$tmp"
mv "$tmp" "$output"
chmod 600 "$output"
