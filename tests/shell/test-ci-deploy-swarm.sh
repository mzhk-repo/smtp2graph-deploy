#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
wrapper="$root/scripts/ci-deploy-swarm.sh"
workflow="$root/.github/workflows/deploy-image.yml"

bash -n "$wrapper"
grep -Fq -- '--env-file "$env_file" --deploy --apply' "$wrapper"
grep -Fq -- '--release-tag "$DEPLOYMENT_RELEASE_TAG"' "$wrapper"
grep -Fq -- '--approval-context "$APPROVAL_CONTEXT"' "$wrapper"
grep -Fq -- '--declared-deploy-ref "$DECLARED_DEPLOY_REF"' "$wrapper"
grep -Fq 'branches: [main, dev]' "$workflow"
grep -Eq "tags: \\['v\\*\\.\\*\\.\\*'\\]" "$workflow"
grep -Fq 'workflow_dispatch:' "$workflow"
grep -Fq 'name: CI checks (main)' "$workflow"
grep -Fq "github.ref == 'refs/heads/main'" "$workflow"
grep -Fq 'name: CI checks and development deploy' "$workflow"
grep -Fq "github.ref == 'refs/heads/dev'" "$workflow"
grep -Fq 'name: CI checks and production deploy' "$workflow"
grep -Eq "startsWith\\(github\\.ref, 'refs/tags/v'\\)" "$workflow"
grep -Fq 'deployment_release_tag: ${{ github.ref_name }}' "$workflow"
grep -Fq 'resolved_image_digest: ${{ inputs.image_digest }}' "$workflow"
grep -Fq 'build_and_push_docker: false' "$workflow"
grep -Fq 'release_evidence_verified' "$workflow"

printf 'PASS: CI/CD caller routes main, dev and release tags through the reviewed Swarm contract.\n'
