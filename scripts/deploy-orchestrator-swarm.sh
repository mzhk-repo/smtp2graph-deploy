#!/usr/bin/env bash
# Category 1b: validate, deploy, inspect, or explicitly roll back the SMTP2Graph dev/prod Swarm stack.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}

log() {
  printf '[smtp2graph-orchestrator] %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  scripts/deploy-orchestrator-swarm.sh --env-file FILE --check
  scripts/deploy-orchestrator-swarm.sh --env-file FILE --deploy --apply
  scripts/deploy-orchestrator-swarm.sh --env-file FILE --status
  scripts/deploy-orchestrator-swarm.sh --env-file FILE --rollback \
    --image-digest IMAGE@sha256:DIGEST --queue-compatibility-confirmed --apply

The script accepts only a strict allowlist of non-secret deployment settings and
Docker Secret names. It requires matching SERVER_ENV from /etc/environment and
never deletes stacks, services, networks, configs, Secrets, or queue data.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
init_storage_script=${SMTP_INIT_STORAGE_SCRIPT:-"${project_root}/scripts/init-storage.sh"}
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"

env_file=''
operation=''
apply=false
rollback_image=''
queue_compatibility_confirmed=false
approval_context=''
release_tag=''
declared_deploy_ref=''

while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --check | --deploy | --status | --rollback)
      [[ -z "$operation" ]] || die 'choose exactly one operation.'
      operation=${1#--}
      shift
      ;;
    --apply)
      apply=true
      shift
      ;;
    --image-digest)
      rollback_image=${2:-}
      shift 2
      ;;
    --queue-compatibility-confirmed)
      queue_compatibility_confirmed=true
      shift
      ;;
    --approval-context)
      approval_context=${2:-}
      shift 2
      ;;
    --release-tag)
      release_tag=${2:-}
      shift 2
      ;;
    --declared-deploy-ref)
      declared_deploy_ref=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ -n "$operation" ]] || die 'choose one operation.'
prepare_sops_deploy_env "$project_root" "$env_file" || die 'could not prepare encrypted deployment environment.'
trap cleanup_sops_deploy_env EXIT
allowed_keys=(
  DEPLOY_ENVIRONMENT
  SMTP2GRAPH_IMAGE_DIGEST
  SWARM_STACK_NAME
  SWARM_OVERLAY_NETWORK
  SMTP2GRAPH_STORAGE_HOST_PATH
  SMTP2GRAPH_MODE
  GRAPH_AUTH_MODE
  SMTP_MAX_MESSAGE_BYTES
  SMTP_MAX_SESSIONS_PER_IP
  SMTP_MESSAGES_PER_MINUTE
  SMTP_ALLOWED_SOURCE_CIDRS
  SMTP_TLS_FQDN
  GRAPH_SENDER_MAILBOX
  SEND_RETRY_LIMIT
  SEND_RETRY_INTERVAL_MINUTES
  TLS_SECRET_MAPPING_FILE
)
secret_mapping_keys=(
  GRAPH_TENANT_ID_SECRET_NAME
  GRAPH_CLIENT_ID_SECRET_NAME
  GRAPH_CREDENTIAL_SECRET_NAME
  GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME
  SMTP_CREDENTIALS_SECRET_NAME
  TLS_CERTIFICATE_SECRET_NAME
  TLS_PRIVATE_KEY_SECRET_NAME
)
allowed_keys+=("${secret_mapping_keys[@]}")
load_deploy_env_file "$project_root" "$SOPS_DEPLOY_ENV_FILE" "${allowed_keys[@]}"

[[ -n "${TLS_SECRET_MAPPING_FILE:-}" ]] || die 'required deployment key is missing: TLS_SECRET_MAPPING_FILE.'
load_deploy_secret_mapping "$TLS_SECRET_MAPPING_FILE" "${secret_mapping_keys[@]}" || die 'could not load complete Secret mapping.'
SMTP_ALLOWED_SENDER_ADDRESSES=$GRAPH_SENDER_MAILBOX

for key in "${allowed_keys[@]}"; do
  [[ -n "${!key:-}" ]] || die "required deployment key is missing: ${key}."
done

environment=$DEPLOY_ENVIRONMENT
case "$environment" in
  development | production) ;;
  *) die 'DEPLOY_ENVIRONMENT must be development or production.' ;;
esac
case "$environment" in
  development) SMTP2GRAPH_NODE_LABEL=smtp2graph_dev ;;
  production) SMTP2GRAPH_NODE_LABEL=smtp2graph_prod ;;
esac
require_server_env_match "$environment" || die 'host SERVER_ENV must match DEPLOY_ENVIRONMENT.'

is_digest() {
  [[ "$1" =~ ^[^[:space:]@]+@sha256:[a-f0-9]{64}$ ]]
}

is_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]
}

for key in SWARM_STACK_NAME SWARM_OVERLAY_NETWORK "${secret_mapping_keys[@]}"; do
  is_name "${!key}" || die "${key} has an unsafe name."
done
is_digest "$SMTP2GRAPH_IMAGE_DIGEST" || die 'SMTP2GRAPH_IMAGE_DIGEST must be an immutable sha256 digest.'
[[ "$SMTP2GRAPH_STORAGE_HOST_PATH" = /* && "$SMTP2GRAPH_STORAGE_HOST_PATH" != / ]] || die 'SMTP2GRAPH_STORAGE_HOST_PATH must be an absolute path other than /.'

stack_file=${SMTP_STACK_FILE:-"${project_root}/deploy/swarm/stack.yml"}
[[ "$stack_file" = /* && -f "$stack_file" && ! -L "$stack_file" ]] || die 'stack file must be an absolute regular non-symlink file.'
queue_compatibility_file=${SMTP_QUEUE_COMPATIBILITY_FILE:-"${project_root}/deploy/config/queue-compatibility.yml"}
[[ "$queue_compatibility_file" = /* && -f "$queue_compatibility_file" && ! -L "$queue_compatibility_file" ]] || die 'queue compatibility file must be an absolute regular non-symlink file.'

stack_env=()
for key in "${allowed_keys[@]}"; do
  [[ "$key" == DEPLOY_ENVIRONMENT || "$key" == SWARM_STACK_NAME || "$key" == TLS_SECRET_MAPPING_FILE ]] && continue
  stack_env+=("${key}=${!key:-}")
done
stack_env+=("SMTP_ALLOWED_SENDER_ADDRESSES=${SMTP_ALLOWED_SENDER_ADDRESSES}")
stack_env+=("SMTP2GRAPH_NODE_LABEL=${SMTP2GRAPH_NODE_LABEL}")
# Keep storage-policy changes in the declarative task revision.  The initializer
# runs before submission, but its contract also controls the bind-mounted data
# directory consumed by the gateway task.
config_version=$(sha256sum "$project_root/scripts/entrypoint.sh" "$project_root/scripts/lib/render-config.sh" "$project_root/deploy/config/gateway-config.yml.template" "$project_root/scripts/init-storage.sh" | sha256sum | awk '{print substr($1, 1, 16)}')
stack_env+=("SMTP2GRAPH_CONFIG_VERSION=${config_version}")

run_stack_config() {
  command -v docker >/dev/null || die 'docker is required.'
  env "${stack_env[@]}" docker stack config -c "$stack_file" >/dev/null
}

deploy_stack() {
  env "${stack_env[@]}" docker stack deploy --compose-file "$stack_file" "$SWARM_STACK_NAME"
}

initialize_storage() {
  [[ "$init_storage_script" = /* && -x "$init_storage_script" && ! -L "$init_storage_script" ]] || die 'storage initializer must be an absolute executable non-symlink file.'
  "$init_storage_script" --storage-root "$SMTP2GRAPH_STORAGE_HOST_PATH" --environment "$environment" --apply
}

queue_pair_is_approved() {
  local first=$1 second=$2
  awk -v first="$first" -v second="$second" '
    function value(line) { sub(/^[^:]+:[[:space:]]*/, "", line); gsub(/^"|"$/, "", line); return line }
    /^[[:space:]]*-[[:space:]]*current:/ { current=value($0); candidate=""; next }
    /^[[:space:]]*candidate:/ {
      candidate=value($0)
      if ((current == first && candidate == second) || (current == second && candidate == first)) found=1
    }
    END { exit(found ? 0 : 1) }
  ' "$queue_compatibility_file"
}

require_apply_authorization() {
  [[ "$apply" == true ]] || die "--${operation} requires --apply."
  if [[ "$environment" == production ]]; then
    [[ "$approval_context" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die 'production requires a safe --approval-context identifier.'
    [[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'production requires --release-tag vX.Y.Z.'
    [[ "$declared_deploy_ref" =~ ^[a-f0-9]{40}$ ]] || die 'production requires --declared-deploy-ref as a 40-character SHA.'
    [[ "$(git -C "$project_root" rev-parse HEAD)" == "$declared_deploy_ref" ]] || die 'declared deploy ref does not match checked-out control-plane SHA.'
  else
    [[ -z "$approval_context" && -z "$release_tag" && -z "$declared_deploy_ref" ]] || die 'development deploy does not accept production release options.'
  fi
  docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
  [[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == true ]] || die 'Docker Swarm manager access is required.'
}

case "$operation" in
  check)
    [[ "$apply" == false && -z "$rollback_image" && "$queue_compatibility_confirmed" == false ]] || die '--check accepts no mutation or rollback options.'
    run_stack_config
    log 'PASS: stack input and rendered Swarm configuration are valid.'
    ;;
  deploy)
    [[ -z "$rollback_image" && "$queue_compatibility_confirmed" == false ]] || die '--deploy accepts no rollback options.'
    run_stack_config
    require_apply_authorization
    initialize_storage
    deploy_stack
    log "PASS: ${environment} stack deploy submitted; run check-network-policy.sh after service convergence."
    ;;
  status)
    [[ "$apply" == false && -z "$rollback_image" && "$queue_compatibility_confirmed" == false ]] || die '--status accepts no mutation or rollback options.'
    command -v docker >/dev/null || die 'docker is required.'
    docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
    docker service inspect "${SWARM_STACK_NAME}_gateway" >/dev/null
    docker service ps "${SWARM_STACK_NAME}_gateway" --no-trunc
    ;;
  rollback)
    [[ -n "$rollback_image" ]] || die '--rollback requires --image-digest.'
    is_digest "$rollback_image" || die '--image-digest must be an immutable sha256 digest.'
    [[ "$queue_compatibility_confirmed" == true ]] || die '--rollback requires --queue-compatibility-confirmed.'
    queue_pair_is_approved "$SMTP2GRAPH_IMAGE_DIGEST" "$rollback_image" || die 'rollback digest pair is absent from approved queue compatibility metadata.'
    run_stack_config
    require_apply_authorization
    initialize_storage
    rollback_env=("${stack_env[@]}" "SMTP2GRAPH_IMAGE_DIGEST=${rollback_image}")
    env "${rollback_env[@]}" docker stack deploy --compose-file "$stack_file" "$SWARM_STACK_NAME"
    log "PASS: explicit ${environment} rollback deploy submitted; verify queue and SMTP delivery before closing the change."
    ;;
esac
