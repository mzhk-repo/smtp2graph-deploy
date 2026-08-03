#!/usr/bin/env bash
# Category 1b: translate the reviewed CI deployment contract into the Swarm orchestrator CLI.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
orchestrator="${project_root}/scripts/deploy-orchestrator-swarm.sh"
env_file=${ORCHESTRATOR_ENV_FILE:-}
environment=${ENVIRONMENT_NAME:-}

[[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die 'ORCHESTRATOR_ENV_FILE must be an absolute regular non-symlink file.'
[[ -x "$orchestrator" ]] || die 'deploy orchestrator is missing or not executable.'

case "$environment" in
  development)
    [[ -z "${DEPLOYMENT_RELEASE_TAG:-}" && -z "${APPROVAL_CONTEXT:-}" ]] || die 'development deploy does not accept production release context.'
    exec "$orchestrator" --env-file "$env_file" --deploy --apply
    ;;
  production)
    [[ "${DEPLOYMENT_RELEASE_TAG:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die 'production requires DEPLOYMENT_RELEASE_TAG vX.Y.Z.'
    [[ "${DECLARED_DEPLOY_REF:-}" =~ ^[a-f0-9]{40}$ ]] || die 'production requires DECLARED_DEPLOY_REF as a 40-character SHA.'
    [[ "${APPROVAL_CONTEXT:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die 'production requires a safe APPROVAL_CONTEXT identifier.'
    exec "$orchestrator" --env-file "$env_file" --deploy --apply \
      --release-tag "$DEPLOYMENT_RELEASE_TAG" \
      --approval-context "$APPROVAL_CONTEXT" \
      --declared-deploy-ref "$DECLARED_DEPLOY_REF"
    ;;
  *) die 'ENVIRONMENT_NAME must be development or production.' ;;
esac
