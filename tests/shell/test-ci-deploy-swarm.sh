#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
wrapper="$root/scripts/ci-deploy-swarm.sh"
workflow="$root/.github/workflows/deploy-image.yml"

bash -n "$wrapper"
rg -q -- '--env-file "\$env_file" --deploy --apply' "$wrapper"
rg -q -- '--release-tag "\$DEPLOYMENT_RELEASE_TAG"' "$wrapper"
rg -q -- '--approval-context "\$APPROVAL_CONTEXT"' "$wrapper"
rg -q -- '--declared-deploy-ref "\$DECLARED_DEPLOY_REF"' "$wrapper"
rg -q 'workflow_dispatch:' "$workflow"
rg -q 'resolved_image_digest: \$\{\{ inputs.image_digest \}\}' "$workflow"
rg -q 'build_and_push_docker: false' "$workflow"
rg -q 'release_evidence_verified' "$workflow"
if rg -q 'deploy: false' "$workflow"; then
  printf 'ERROR: control-plane dispatcher unexpectedly disables deploy.\n' >&2
  exit 1
fi

printf 'PASS: CI dispatcher uses an immutable digest and the reviewed Swarm CLI contract.\n'
