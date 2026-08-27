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
rg -q 'branches: \[main, dev\]' "$workflow"
rg -q "tags: \['v\*\.\*\.\*'\]" "$workflow"
rg -q 'workflow_dispatch:' "$workflow"
rg -q 'name: CI checks \(main\)' "$workflow"
rg -q "github\.ref == 'refs/heads/main'" "$workflow"
rg -q 'name: CI checks and development deploy' "$workflow"
rg -q "github\.ref == 'refs/heads/dev'" "$workflow"
rg -q 'name: CI checks and production deploy' "$workflow"
rg -q "startsWith\(github\.ref, 'refs/tags/v'\)" "$workflow"
rg -q 'deployment_release_tag: \$\{\{ github\.ref_name \}\}' "$workflow"
rg -q 'resolved_image_digest: \$\{\{ inputs.image_digest \}\}' "$workflow"
rg -q 'build_and_push_docker: false' "$workflow"
rg -q 'release_evidence_verified' "$workflow"

printf 'PASS: CI/CD caller routes main, dev and release tags through the reviewed Swarm contract.\n'
