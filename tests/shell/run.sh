#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tests=(
  tests/shell/test-deploy-orchestrator.sh
  tests/shell/test-entrypoint.sh
  tests/shell/test-purge-failed.sh
  tests/shell/test-render-config.sh
  tests/shell/test-verify-env.sh
)

for test_script in "${tests[@]}"; do
  "${root}/${test_script}"
done

printf 'PASS: shell test suite completed.\n'
