#!/usr/bin/env bash
# Category 1b: validate or initialize the SMTP2Graph dev/prod Swarm host boundary.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[swarm-bootstrap] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/bootstrap-swarm-host.sh [--env-file FILE] [--check | --apply]

Validates the Docker Swarm manager, the encrypted external overlay,
the reviewed node label, persistent storage, and rendered nftables policy. --apply
is explicit and creates only missing reviewed prerequisites. Production additionally
requires SERVER_ENV=prod and an explicit approval context.
It never deploys a stack, creates Secrets, or removes Docker/nftables resources.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"

env_file=''
apply=false
approval_context=''
while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --check)
      apply=false
      shift
      ;;
    --apply)
      apply=true
      shift
      ;;
    --approval-context)
      approval_context=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

prepare_sops_deploy_env "$project_root" "$env_file" || die 'could not prepare encrypted deployment environment.'
trap cleanup_sops_deploy_env EXIT
load_deploy_env_file "$project_root" "$SOPS_DEPLOY_ENV_FILE" \
  DEPLOY_ENVIRONMENT SWARM_OVERLAY_NETWORK SMTP2GRAPH_STORAGE_HOST_PATH SMTP_ALLOWED_SOURCE_CIDRS

environment=${DEPLOY_ENVIRONMENT:-}
network=${SWARM_OVERLAY_NETWORK:-}
storage_root=${SMTP2GRAPH_STORAGE_HOST_PATH:-}
case "$environment" in
  development) node_label=smtp2graph_dev ;;
  production) node_label=smtp2graph_prod ;;
  *) die 'DEPLOY_ENVIRONMENT must be development or production.' ;;
esac
node_label_value='true'

require_server_env_match "$environment" || die 'host SERVER_ENV must match DEPLOY_ENVIRONMENT.'
if [[ "$environment" == production && "$apply" == true ]]; then
  [[ "$approval_context" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die 'production --apply requires a safe --approval-context identifier.'
fi
[[ "$environment" != production || -z "$approval_context" || "$approval_context" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die '--approval-context has an unsafe value.'
[[ "$network" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die 'SWARM_OVERLAY_NETWORK has an unsafe name.'
[[ "$storage_root" = /* && "$storage_root" != / ]] || die 'SMTP2GRAPH_STORAGE_HOST_PATH must be an absolute path other than /. '
[[ -n "${SMTP_ALLOWED_SOURCE_CIDRS:-}" ]] || die 'SMTP_ALLOWED_SOURCE_CIDRS is required.'
for tool in docker nft install realpath dirname basename mktemp; do
  command -v "$tool" >/dev/null || die "$tool is required."
done

storage_parent=$(dirname "$storage_root")
storage_leaf=$(basename "$storage_root")
[[ "$storage_leaf" != . && "$storage_leaf" != .. ]] || die 'SMTP2GRAPH_STORAGE_HOST_PATH has an unsafe final component.'

prepare_storage_root() {
  local resolved_parent resolved_root
  [[ -d "$storage_parent" && ! -L "$storage_parent" ]] || die 'storage parent must be an existing non-symlink directory.'
  resolved_parent=$(realpath -e -- "$storage_parent") || die 'could not resolve storage parent.'
  [[ "$storage_parent" == "$resolved_parent" ]] || die 'storage parent must not contain symlink components.'
  if [[ "$apply" == true && ! -e "$storage_root" ]]; then
    install -d -m 0750 -- "$resolved_parent/$storage_leaf"
  fi
  [[ -d "$storage_root" && ! -L "$storage_root" ]] || die 'storage root must be an existing non-symlink directory.'
  resolved_root=$(realpath -e -- "$storage_root") || die 'could not resolve storage root.'
  [[ "$resolved_root" == "$resolved_parent/$storage_leaf" ]] || die 'storage root must not contain symlink components.'
}

require_manager() {
  docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
  [[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == true ]] || die 'Docker Swarm manager access is required.'
}

ensure_node_label() {
  local node_id label_value
  node_id=$(docker node inspect self --format '{{.ID}}') || die 'could not inspect the current Swarm node.'
  label_value=$(docker node inspect self --format "{{index .Spec.Labels \"${node_label}\"}}") || die 'could not inspect current node labels.'
  if [[ "$label_value" == "$node_label_value" ]]; then
    return
  fi
  [[ "$apply" == true ]] || die "node label ${node_label}=${node_label_value} is required."
  docker node update --label-add "${node_label}=${node_label_value}" "$node_id" >/dev/null
}

ensure_overlay() {
  local network_state
  if network_state=$(docker network inspect "$network" --format '{{.Driver}} {{.Scope}} {{json .Options}}' 2>/dev/null); then
    [[ "$network_state" == overlay\ swarm* ]] || die 'existing network must be a Swarm overlay.'
    [[ "$network_state" == *'"encrypted":"true"'* || "$network_state" == *'"encrypted":""'* ]] || die 'existing overlay network is not encrypted.'
    return
  fi
  [[ "$apply" == true ]] || die 'encrypted external overlay network is required.'
  docker network create --driver overlay --opt encrypted "$network" >/dev/null
}

rendered_nft=''
cleanup() {
  [[ -z "$rendered_nft" ]] || rm -f -- "$rendered_nft"
  cleanup_sops_deploy_env
}
trap cleanup EXIT

if [[ "$apply" == true ]]; then
  [[ $(id -u) -eq 0 ]] || die '--apply requires a privileged operator for nftables and storage initialization.'
fi
require_manager
ensure_node_label
ensure_overlay

storage_args=(--storage-root "$storage_root")
if [[ "$apply" == true ]]; then
  storage_args+=(--environment "$environment" --apply)
fi
"${project_root}/scripts/init-storage.sh" "${storage_args[@]}"

rendered_nft=$(mktemp /dev/shm/smtp2graph-nft.XXXXXX)
"${project_root}/scripts/render-network-policy.sh" --env-file "$SOPS_DEPLOY_ENV_FILE" "$rendered_nft"
nft --check --file "$rendered_nft" >/dev/null
if [[ "$apply" == true ]]; then
  nft --file "$rendered_nft"
fi

if [[ "$apply" == true ]]; then
  log "PASS: ${environment} Swarm host prerequisites are applied."
else
  log "PASS: ${environment} Swarm host prerequisites are validated."
fi
