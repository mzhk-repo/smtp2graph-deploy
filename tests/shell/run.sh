#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tests=(
  tests/shell/test-ci-deploy-swarm.sh
  tests/shell/test-deploy-orchestrator.sh
  tests/shell/test-deployment-smoke.sh
  tests/shell/test-entrypoint.sh
  tests/shell/test-integration-format-matrix.sh
  tests/shell/test-moodle-starttls-contract.sh
  tests/shell/test-e2e-send-mail.sh
  tests/shell/test-monitoring-contract.sh
  tests/shell/test-purge-failed.sh
  tests/shell/test-render-config.sh
  tests/shell/test-rehearse-deployment.sh
  tests/shell/test-verify-env.sh
  tests/recovery/cold-restore.sh
)

for test_script in "${tests[@]}"; do
  "${root}/${test_script}"
done

printf 'PASS: shell test suite completed.\n'
