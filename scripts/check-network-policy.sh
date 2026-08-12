#!/usr/bin/env bash
# Category 1a: validates declared and live development SMTP network policy.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
usage() {
  printf '%s\n' 'Usage: scripts/check-network-policy.sh --network OVERLAY_NAME [--stack-name NAME]'
}

network=''
stack_name='smtp2graph'
while (($#)); do
  case "$1" in
    --network)
      network=${2:-}
      shift 2
      ;;
    --stack-name)
      stack_name=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$network" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die '--network must be a safe Swarm overlay name.'
[[ "$stack_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die '--stack-name must be safe.'
stack_file=${SMTP_STACK_FILE:-"${project_root}/deploy/swarm/stack.yml"}
nft_file=${SMTP_NFT_FILE:-"${project_root}/deploy/network/smtp2graph.nft"}
for tool in docker nft ss grep; do command -v "$tool" >/dev/null || die "$tool is required."; done
docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
[[ -f "$stack_file" && -f "$nft_file" ]] || die 'policy files are unavailable.'
grep -Fq 'mode: host' "$stack_file" || die 'SMTP publish mode must be host.'
! grep -Fq 'mode: ingress' "$stack_file" || die 'SMTP routing mesh publish is forbidden.'
grep -Fq 'iifname "lo" tcp dport 2525 accept' "$nft_file" || die 'development loopback smoke rule is missing.'
grep -Fq 'tcp dport 2525 ip saddr @smtp2graph_smtp_clients accept' "$nft_file" || die 'nftables allowlist rule is missing.'
grep -Fq 'tcp dport 2525 drop' "$nft_file" || die 'nftables deny rule is missing.'
docker network inspect "$network" --format '{{json .Options}}' | grep -Eq '"encrypted":"(true)?"' || die 'Swarm overlay encryption is not enabled.'
nft list ruleset | grep -Fq 'smtp2graph_smtp_clients' || die 'smtp2graph nftables policy is not loaded.'
secret_spec=$(docker service inspect "${stack_name}_gateway" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.File.Name}} {{.File.UID}} {{.File.GID}} {{printf "%#o" .File.Mode}}{{"\n"}}{{end}}') || die 'could not inspect gateway Secret mounts.'
printf '%s\n' "$secret_spec" | grep -Fqx -- 'smtp-tls-key 65532 65532 0400' || die 'TLS private key mount must use uid/gid 65532 and mode 0400.'
printf '%s\n' "$secret_spec" | grep -Fqx -- 'smtp-tls-cert 65532 65532 0444' || die 'TLS certificate mount must use uid/gid 65532 and mode 0444.'
ss -ltnH | grep -Eq '[:.]2525[[:space:]]' || die 'SMTP listener on port 2525 is unavailable.'
printf 'PASS: declared and live SMTP network policy is present.\n'
