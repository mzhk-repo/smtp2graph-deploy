#!/usr/bin/env bash
# Category 1a: static validation of the VictoriaMetrics scrape integration contract.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
scrape_file="${root}/deploy/monitoring/smtp2graph-scrape.yml"
monitoring_readme="${root}/deploy/monitoring/README.md"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_fixed() {
  local value=$1
  local file=$2
  grep -Fq -- "$value" "$file" || fail "missing required contract value in ${file#"$root"/}: $value"
}

require_fixed 'job_name: smtp2graph-gateway' "$scrape_file"
require_fixed 'metrics_path: /metrics' "$scrape_file"
require_fixed 'smtp2graph_gateway:9464' "$scrape_file"
require_fixed 'env: prod' "$scrape_file"
require_fixed 'service: smtp2graph' "$scrape_file"
require_fixed 'component: gateway' "$scrape_file"
require_fixed 'external SMTP provider rather than SMTP2Graph' "$monitoring_readme"
require_fixed 'SMTP2GRAPH_METRICS_TARGET' "$monitoring_readme"
require_fixed 'test-synthetic-and-metrics.sh' "$monitoring_readme"

if grep -Eq 'published:[[:space:]]*9464|target:[[:space:]]*9464' "${root}/deploy/swarm/stack.yml"; then
  fail 'observability port 9464 must not be host-published.'
fi

printf 'PASS: VictoriaMetrics scrape and independent synthetic-alert contracts are documented.\n'
