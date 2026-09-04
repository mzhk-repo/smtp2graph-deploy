#!/usr/bin/env bash
# Category 1b: prepare only Graph client certificate material for SOPS handoff.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
log() { printf '[certificate-prepare] %s\n' "$*" >&2; }
usage() { printf '%s\n' 'Usage: scripts/prepare-certificate-env.sh --env-file FILE [--staging-file FILE] [--check|--apply] [--rotate-graph]' >&2; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "$root/scripts/lib/read-deploy-env.sh"
env_file='' staging_file="$root/.env.certificates" apply=false rotate_graph=false
while (($#)); do
  case "$1" in
    --env-file) env_file=${2:-}; shift 2 ;;
    --staging-file) staging_file=${2:-}; shift 2 ;;
    --check) apply=false; shift ;;
    --apply) apply=true; shift ;;
    --rotate-graph) rotate_graph=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unsupported argument: $1" ;;
  esac
done
[[ -n "$env_file" ]] || die '--env-file is required.'
[[ "$staging_file" = /* && ! -L "$staging_file" ]] || die '--staging-file must be an absolute non-symlink path.'
prepare_sops_deploy_env "$root" "$env_file" || die 'could not prepare encrypted deployment environment.'
trap cleanup_sops_deploy_env EXIT
load_deploy_env_file "$root" "$SOPS_DEPLOY_ENV_FILE" DEPLOY_ENVIRONMENT TLS_OUTPUT_DIR GRAPH_CERT_PRIVATE_KEY_PEM GRAPH_CERTIFICATE_THUMBPRINT
environment=${DEPLOY_ENVIRONMENT:-}
[[ "$environment" == development || "$environment" == production ]] || die 'DEPLOY_ENVIRONMENT must be development or production.'
is_missing() { [[ -z "$1" || "$1" == REPLACE_WITH_* ]]; }
missing=false
if is_missing "${GRAPH_CERT_PRIVATE_KEY_PEM:-}" || is_missing "${GRAPH_CERTIFICATE_THUMBPRINT:-}"; then
  if ! is_missing "${GRAPH_CERT_PRIVATE_KEY_PEM:-}" || ! is_missing "${GRAPH_CERTIFICATE_THUMBPRINT:-}"; then die 'Graph certificate key and thumbprint must be both present or both missing.'; fi
  missing=true
fi
[[ "$rotate_graph" == false ]] || missing=true
[[ "$missing" == true ]] || { log 'PASS: encrypted contract already has Graph certificate values.'; exit 0; }
[[ "$apply" == true ]] || die 'Graph certificate values are missing; rerun with --apply to prepare staging material.'
[[ "$TLS_OUTPUT_DIR" = /* && "$TLS_OUTPUT_DIR" != / ]] || die 'TLS_OUTPUT_DIR must be absolute and not /.'
for tool in openssl install mktemp awk; do command -v "$tool" >/dev/null || die "$tool is required."; done
parent=$(dirname "$TLS_OUTPUT_DIR")
[[ -d "$parent" && ! -L "$parent" ]] || die 'Graph certificate output parent must be an existing non-symlink directory.'
install -d -m 700 -- "$TLS_OUTPUT_DIR"
[[ -d "$TLS_OUTPUT_DIR" && ! -L "$TLS_OUTPUT_DIR" ]] || die 'Graph certificate output directory is unsafe.'
if [[ -e "$staging_file" ]]; then
  [[ -f "$staging_file" && ! -L "$staging_file" ]] || die 'existing staging file must be a regular non-symlink file.'
  [[ "$rotate_graph" == false ]] || die 'remove the prior .env.certificates after SOPS handoff before an explicit rotation.'
  log "Graph certificate staging is ready: $staging_file"
  exit 75
fi
stage_dir=$(mktemp -d /dev/shm/smtp2graph-graph-certificate.XXXXXX)
chmod 700 "$stage_dir"
# shellcheck disable=SC2317 # invoked by EXIT trap
cleanup() { rm -rf -- "$stage_dir"; cleanup_sops_deploy_env; }
trap cleanup EXIT
graph_key="$stage_dir/graph-key.pem" graph_cert="$TLS_OUTPUT_DIR/graph-client-certificate.pem"
openssl req -x509 -newkey rsa:3072 -nodes -days 730 -subj "/CN=smtp2graph-graph-client-${environment}" -keyout "$graph_key" -out "$stage_dir/graph-cert.pem" >/dev/null 2>&1
install -m 400 "$stage_dir/graph-cert.pem" "$graph_cert"
chmod 400 "$graph_key"
thumb=$(openssl x509 -in "$graph_cert" -noout -fingerprint -sha1 | awk -F= '{gsub(/:/, "", $2); print tolower($2)}')
[[ "$thumb" =~ ^[a-f0-9]{40}$ ]] || die 'could not calculate Graph certificate thumbprint.'
printf 'GRAPH_CERT_PRIVATE_KEY_PEM="' >"$staging_file"
awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\\n", $0 }' "$graph_key" >>"$staging_file"
printf '"\nGRAPH_CERTIFICATE_THUMBPRINT=%s\n' "$thumb" >>"$staging_file"
chmod 600 "$staging_file"
log "Graph certificate staging created: $staging_file"
exit 75
