#!/usr/bin/env bash
# Category 1a: validates declared and live non-production SMTP network policy.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
. "${project_root}/scripts/lib/read-deploy-env.sh"
env_file=''
if [[ "${1:-}" == --env-file ]]; then
  env_file=${2:-}
  shift 2
fi
load_deploy_env_file "$project_root" "$env_file" DEPLOY_ENVIRONMENT SWARM_OVERLAY_NETWORK SWARM_STACK_NAME
stack_file=${SMTP_STACK_FILE:-"${project_root}/deploy/swarm/smtp2graph.nonproduction.yml"}
nft_file=${SMTP_NFT_FILE:-"${project_root}/deploy/network/smtp2graph.nft"}
network=${SWARM_OVERLAY_NETWORK:-}
stack_name=${SWARM_STACK_NAME:-smtp2graph}
[[ -n "$network" ]] || die 'SWARM_OVERLAY_NETWORK is required.'
for tool in docker nft ss; do command -v "$tool" >/dev/null || die "$tool is required."; done
docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
[[ -f "$stack_file" && -f "$nft_file" ]] || die 'policy files are unavailable.'
rg -q 'mode: host' "$stack_file" || die 'SMTP publish mode must be host.'
! rg -q 'mode: ingress' "$stack_file" || die 'SMTP routing mesh publish is forbidden.'
rg -q 'tcp dport 2525 ip saddr @smtp2graph_smtp_clients accept' "$nft_file" || die 'nftables allowlist rule is missing.'
rg -q 'tcp dport 2525 drop' "$nft_file" || die 'nftables deny rule is missing.'
docker network inspect "$network" --format '{{json .Options}}' | rg -q '"encrypted":"true"' || die 'Swarm overlay encryption is not enabled.'
nft list ruleset | rg -q 'smtp2graph_smtp_clients' || die 'smtp2graph nftables policy is not loaded.'
secret_spec=$(docker service inspect "${stack_name}_gateway" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.File.Name}} {{.File.UID}} {{.File.GID}} {{.File.Mode}}{{"\\n"}}{{end}}') || die 'could not inspect gateway Secret mounts.'
printf '%s\n' "$secret_spec" | rg -q '^smtp-tls-key 65532 65532 256$' || die 'TLS private key mount must use uid/gid 65532 and mode 0400.'
printf '%s\n' "$secret_spec" | rg -q '^smtp-tls-cert 65532 65532 292$' || die 'TLS certificate mount must use uid/gid 65532 and mode 0444.'
ss -ltnH | rg -q '[:.]2525[[:space:]]' || die 'SMTP listener on port 2525 is unavailable.'
printf 'PASS: declared and live SMTP network policy is present.\n'
