#!/usr/bin/env bash
# Category 1b: validate, deploy, inspect, or explicitly roll back the non-production SMTP2Graph Swarm stack.
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
Docker Secret names. --deploy and --rollback are limited to non-production and
never delete stacks, services, networks, configs, Secrets, or queue data.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"

env_file=''
operation=''
apply=false
rollback_image=''
queue_compatibility_confirmed=false

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
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ -n "$operation" ]] || die 'choose one operation.'
[[ -n "$env_file" || -n "${ORCHESTRATOR_ENV_FILE:-}" ]] || die '--env-file or ORCHESTRATOR_ENV_FILE is required; local .env fallback is not allowed here.'

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
  SMTP_ALLOWED_SENDER_ADDRESSES
  GRAPH_SENDER_MAILBOX
  SEND_RETRY_LIMIT
  SEND_RETRY_INTERVAL_MINUTES
  GRAPH_TENANT_ID_SECRET_NAME
  GRAPH_CLIENT_ID_SECRET_NAME
  GRAPH_CREDENTIAL_SECRET_NAME
  GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME
  SMTP_CREDENTIALS_SECRET_NAME
  TLS_CERTIFICATE_SECRET_NAME
  TLS_PRIVATE_KEY_SECRET_NAME
)
load_deploy_env_file "$project_root" "$env_file" "${allowed_keys[@]}"

for key in "${allowed_keys[@]}"; do
  [[ -n "${!key:-}" ]] || die "required deployment key is missing: ${key}."
done

environment=$DEPLOY_ENVIRONMENT
case "$environment" in
  development | non-production | production) ;;
  *) die 'DEPLOY_ENVIRONMENT must be development, non-production, or production.' ;;
esac

is_digest() {
  [[ "$1" =~ ^[^[:space:]@]+@sha256:[a-f0-9]{64}$ ]]
}

is_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]]
}

is_digest "$SMTP2GRAPH_IMAGE_DIGEST" || die 'SMTP2GRAPH_IMAGE_DIGEST must be an immutable sha256 digest.'
for key in SWARM_STACK_NAME SWARM_OVERLAY_NETWORK \
  GRAPH_TENANT_ID_SECRET_NAME GRAPH_CLIENT_ID_SECRET_NAME GRAPH_CREDENTIAL_SECRET_NAME \
  GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME SMTP_CREDENTIALS_SECRET_NAME \
  TLS_CERTIFICATE_SECRET_NAME TLS_PRIVATE_KEY_SECRET_NAME; do
  is_name "${!key}" || die "${key} has an unsafe name."
done
[[ "$SMTP2GRAPH_STORAGE_HOST_PATH" = /* && "$SMTP2GRAPH_STORAGE_HOST_PATH" != / ]] || die 'SMTP2GRAPH_STORAGE_HOST_PATH must be an absolute path other than /.'

stack_file=${SMTP_STACK_FILE:-"${project_root}/deploy/swarm/stack.yml"}
[[ "$stack_file" = /* && -f "$stack_file" && ! -L "$stack_file" ]] || die 'stack file must be an absolute regular non-symlink file.'

stack_env=()
for key in "${allowed_keys[@]}"; do
  [[ "$key" == DEPLOY_ENVIRONMENT || "$key" == SWARM_STACK_NAME ]] && continue
  stack_env+=("${key}=${!key}")
done

run_stack_config() {
  command -v docker >/dev/null || die 'docker is required.'
  env "${stack_env[@]}" docker stack config -c "$stack_file" >/dev/null
}

require_nonproduction_apply() {
  [[ "$apply" == true ]] || die "--${operation} requires --apply."
  [[ "$environment" == non-production ]] || die "--${operation} is limited to non-production; production requires separately approved orchestration."
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
    require_nonproduction_apply
    env "${stack_env[@]}" docker stack deploy --compose-file "$stack_file" "$SWARM_STACK_NAME"
    log 'PASS: non-production stack deploy submitted; run check-network-policy.sh after service convergence.'
    ;;
  status)
    [[ "$apply" == false && -z "$rollback_image" && "$queue_compatibility_confirmed" == false ]] || die '--status accepts no mutation or rollback options.'
    [[ "$environment" == non-production ]] || die '--status is available only for the reviewed non-production stack.'
    command -v docker >/dev/null || die 'docker is required.'
    docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
    docker service inspect "${SWARM_STACK_NAME}_gateway" >/dev/null
    docker service ps "${SWARM_STACK_NAME}_gateway" --no-trunc
    ;;
  rollback)
    [[ -n "$rollback_image" ]] || die '--rollback requires --image-digest.'
    is_digest "$rollback_image" || die '--image-digest must be an immutable sha256 digest.'
    [[ "$queue_compatibility_confirmed" == true ]] || die '--rollback requires --queue-compatibility-confirmed.'
    run_stack_config
    require_nonproduction_apply
    rollback_env=("${stack_env[@]}" "SMTP2GRAPH_IMAGE_DIGEST=${rollback_image}")
    env "${rollback_env[@]}" docker stack deploy --compose-file "$stack_file" "$SWARM_STACK_NAME"
    log 'PASS: explicit non-production rollback deploy submitted; verify queue and SMTP delivery before closing the change.'
    ;;
esac
