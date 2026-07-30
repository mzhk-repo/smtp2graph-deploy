#!/usr/bin/env bash
# Category 1b: render a non-production nftables policy from explicit private IPv4 CIDRs.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
template=${SMTP_NFT_TEMPLATE:-"${root}/deploy/network/smtp2graph.nft"}
output=${1:-}
cidrs=${SMTP_ALLOWED_SOURCE_CIDRS:-}
[[ -n "$output" && "$output" = /* && -n "$cidrs" ]] || die 'absolute output path and SMTP_ALLOWED_SOURCE_CIDRS are required.'
[[ -f "$template" && ! -L "$template" ]] || die 'nftables template is unavailable.'
IFS=',' read -r -a values <<< "$cidrs"
rendered=()
for cidr in "${values[@]}"; do
  [[ "$cidr" =~ ^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)[0-9.]+/[0-9]{1,2}$ ]] || die 'only private IPv4 CIDRs are permitted.'
  rendered+=("$cidr")
done
replacement=$(IFS=,; printf '%s' "${rendered[*]}")
tmp=$(mktemp "$(dirname "$output")/.smtp2graph-nft.XXXXXX"); chmod 600 "$tmp"
sed "s|__SMTP_ALLOWED_SOURCE_CIDRS__|${replacement}|" "$template" > "$tmp"
mv "$tmp" "$output"; chmod 600 "$output"
