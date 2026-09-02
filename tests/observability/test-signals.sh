#!/usr/bin/env bash
# Category 1a: read-only verification of the deployed observability contract.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

stack_name='smtp2graph'
environment='development'

while (($#)); do
  case "$1" in
    --stack-name)
      stack_name=${2:-}
      shift 2
      ;;
    --environment)
      environment=${2:-}
      shift 2
      ;;
    -h | --help)
      printf '%s\n' 'Usage: test-signals.sh [--stack-name NAME] --environment development|production'
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$stack_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die 'stack name is unsafe.'
[[ "$environment" == development || "$environment" == production ]] || die 'environment must be development or production.'
command -v docker >/dev/null || die 'docker is required.'

service="${stack_name}_gateway"
healthcheck=$(docker service inspect "$service" --format '{{range .Spec.TaskTemplate.ContainerSpec.Healthcheck.Test}}{{printf "%s " .}}{{end}}') || die 'gateway service is unavailable.'
[[ "$healthcheck" == *'127.0.0.1:9464/readyz'* ]] || die 'gateway healthcheck does not use readiness endpoint.'

log_driver=$(docker service inspect "$service" --format '{{if .Spec.TaskTemplate.LogDriver}}{{.Spec.TaskTemplate.LogDriver.Name}} {{range $key, $value := .Spec.TaskTemplate.LogDriver.Options}}{{printf "%s=%s " $key $value}}{{end}}{{end}}') || die 'could not inspect logging policy.'
[[ "$log_driver" == local* && "$log_driver" == *'max-size=10m'* && "$log_driver" == *'max-file=30'* ]] || die 'gateway logging policy is not bounded.'

container=$(docker ps -q --filter "label=com.docker.swarm.service.name=${service}")
[[ "$container" =~ ^[a-f0-9]{12,64}$ ]] || die 'exactly one running gateway container is required.'

docker exec "$container" node -e '
const http = require("http");
const get = path => new Promise((resolve, reject) => {
  const request = http.get({host: "127.0.0.1", port: 9464, path, timeout: 3000}, response => {
    let body = "";
    response.on("data", chunk => body += chunk);
    response.on("end", () => resolve({status: response.statusCode, body}));
  });
  request.on("timeout", () => request.destroy(new Error("timeout")));
  request.on("error", reject);
});
(async () => {
  const [live, ready, metrics] = await Promise.all([get("/livez"), get("/readyz"), get("/metrics")]);
  if (live.status !== 200 || live.body !== "ok\n") throw new Error("liveness endpoint is unhealthy");
  if (ready.status !== 200 || ready.body !== "ready\n") throw new Error("readiness endpoint is unhealthy");
  for (const metric of [
    "smtp2graph_process_start_time_seconds",
    "smtp2graph_smtp_sessions_active",
    "smtp2graph_smtp_submissions_total",
    "smtp2graph_smtp_auth_total",
    "smtp2graph_delivery_attempts_total",
    "smtp2graph_delivery_duration_seconds",
    "smtp2graph_queue_messages",
    "smtp2graph_queue_bytes",
    "smtp2graph_storage_bytes",
    "smtp2graph_storage_reject_threshold_bytes",
    "smtp2graph_tls_certificate_not_after_seconds",
  ]) {
    if (!metrics.body.includes(metric)) throw new Error(`missing metric: ${metric}`);
  }
  if (/(recipient|client_ip|mailbox|password|token|attachment|body|reset)/i.test(metrics.body)) {
    throw new Error("metrics contain a sensitive or high-cardinality field");
  }
})().catch(error => { console.error(`ERROR: ${error.message}`); process.exit(1); });
'

docker logs --since 1h "$container" 2>&1 | node -e '
let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", chunk => raw += chunk);
process.stdin.on("end", () => {
  const lines = raw.split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) process.exit(0);
  for (const line of lines) {
    let event;
    try { event = JSON.parse(line); } catch { console.error("ERROR: current gateway log is not JSON"); process.exit(1); }
    if (/(body|attachment|password|token|reset)/i.test(Object.keys(event).join(" "))) {
      console.error("ERROR: current gateway log has a sensitive field name");
      process.exit(1);
    }
  }
});
'

printf 'PASS: %s observability endpoints, bounded metrics and structured logging are available.\n' "$environment"
