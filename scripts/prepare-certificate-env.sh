#!/usr/bin/env bash
# Category 1b: prepare missing TLS and Graph certificate values for SOPS handoff.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[certificate-prepare] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/prepare-certificate-env.sh --env-file FILE [--staging-file FILE] [--check|--apply] [--rotate-tls] [--rotate-graph]

Creates missing TLS and Graph certificate material only with --apply. Generated
Dotenv values are written to a protected staging file for manual SOPS handoff.
USAGE
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "$root/scripts/lib/read-deploy-env.sh"

env_file='' staging_file="$root/.env.certificates" apply=false rotate_tls=false rotate_graph=false
while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --staging-file)
      staging_file=${2:-}
      shift 2
      ;;
    --check)
      apply=false
      shift
      ;;
    --apply)
      apply=true
      shift
      ;;
    --rotate-tls)
      rotate_tls=true
      shift
      ;;
    --rotate-graph)
      rotate_graph=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ -n "$env_file" ]] || die '--env-file is required.'
[[ "$staging_file" = /* && ! -L "$staging_file" ]] || die '--staging-file must be an absolute non-symlink path.'
prepare_sops_deploy_env "$root" "$env_file" || die 'could not prepare encrypted deployment environment.'
trap cleanup_sops_deploy_env EXIT
load_deploy_env_file "$root" "$SOPS_DEPLOY_ENV_FILE" \
  DEPLOY_ENVIRONMENT SMTP_TLS_FQDN TLS_ACME_EMAIL TLS_ACME_STATE_DIR TLS_OUTPUT_DIR \
  CLOUDFLARE_DNS_API_TOKEN GRAPH_CERT_PRIVATE_KEY_PEM GRAPH_CERTIFICATE_THUMBPRINT \
  TLS_CERTIFICATE_PEM TLS_PRIVATE_KEY_PEM

for tool in awk certbot install mktemp openssl stat; do command -v "$tool" >/dev/null || die "$tool is required."; done
environment=${DEPLOY_ENVIRONMENT:-}
[[ "$environment" == development || "$environment" == production ]] || die 'DEPLOY_ENVIRONMENT must be development or production.'

is_missing() { [[ -z "$1" || "$1" == REPLACE_WITH_* ]]; }
graph_missing=false tls_missing=false
if is_missing "${GRAPH_CERT_PRIVATE_KEY_PEM:-}" || is_missing "${GRAPH_CERTIFICATE_THUMBPRINT:-}"; then
  if ! is_missing "${GRAPH_CERT_PRIVATE_KEY_PEM:-}" || ! is_missing "${GRAPH_CERTIFICATE_THUMBPRINT:-}"; then
    die 'Graph certificate key and thumbprint must be both present or both missing.'
  fi
  graph_missing=true
fi
if is_missing "${TLS_CERTIFICATE_PEM:-}" || is_missing "${TLS_PRIVATE_KEY_PEM:-}"; then
  if ! is_missing "${TLS_CERTIFICATE_PEM:-}" || ! is_missing "${TLS_PRIVATE_KEY_PEM:-}"; then
    die 'TLS certificate and private key must be both present or both missing.'
  fi
  tls_missing=true
fi

if [[ "$rotate_graph" == true ]]; then graph_missing=true; fi
if [[ "$rotate_tls" == true ]]; then tls_missing=true; fi
if [[ "$graph_missing" == false && "$tls_missing" == false ]]; then
  log 'PASS: encrypted contract already has certificate values.'
  exit 0
fi
[[ "$apply" == true ]] || die 'certificate values are missing; rerun with --apply to prepare staging material.'

[[ -n "${TLS_OUTPUT_DIR:-}" && "$TLS_OUTPUT_DIR" != REPLACE_WITH_* ]] || die 'required certificate input is missing: TLS_OUTPUT_DIR.'
[[ "$TLS_OUTPUT_DIR" = /* && "$TLS_OUTPUT_DIR" != / ]] || die 'TLS_OUTPUT_DIR must be absolute and not /.'

ensure_directory_for_caller() {
  local directory=$1 parent leaf resolved_parent uid gid mode
  parent=$(dirname "$directory") || die 'could not resolve certificate directory parent.'
  leaf=$(basename "$directory") || die 'could not resolve certificate directory name.'
  [[ -d "$parent" && ! -L "$parent" ]] || die "certificate directory parent must be an existing non-symlink directory: $parent."
  resolved_parent=$(realpath -e -- "$parent") || die 'could not resolve certificate directory parent.'
  [[ "$parent" == "$resolved_parent" && "$leaf" != . && "$leaf" != .. ]] || die 'certificate directory must not contain symlink components.'
  directory="$resolved_parent/$leaf"
  uid=$(id -u)
  gid=$(id -g)
  if ! install -d -m 700 -- "$directory" 2>/dev/null; then
    [[ "$uid" -ne 0 ]] || die "could not create certificate directory: $directory."
    command -v sudo >/dev/null || die "sudo is required to create certificate directory: $directory."
    sudo install -d -m 700 -o "$uid" -g "$gid" -- "$directory" || die "could not create certificate directory: $directory."
  fi
  [[ -d "$directory" && ! -L "$directory" ]] || die "certificate directory is unsafe: $directory."
  [[ $(stat -c '%u:%g' "$directory") == "$uid:$gid" ]] || die "certificate directory must be owned by the invoking user: $directory."
  mode=$(stat -c '%a' "$directory") || die "could not inspect certificate directory mode: $directory."
  [[ $((8#$mode & 077)) -eq 0 ]] || die "certificate directory must not be accessible by group or other: $directory."
}

# shellcheck disable=SC2317 # invoked through EXIT trap
cleanup() {
  rm -rf -- "$stage_dir"
  cleanup_sops_deploy_env
}
stage_dir=$(mktemp -d /dev/shm/smtp2graph-certificate.XXXXXX)
trap cleanup EXIT
chmod 700 "$stage_dir"
ensure_directory_for_caller "$TLS_OUTPUT_DIR"

graph_cert="$TLS_OUTPUT_DIR/graph-client-certificate.pem"
tls_cert="$stage_dir/tls-cert.pem" tls_key="$stage_dir/tls-key.pem"
graph_key="$stage_dir/graph-key.pem" graph_thumb=''

staging_value() {
  local key=$1 target=$2 value
  value=$(awk -v key="$key" '$0 ~ ("^" key "=") { print substr($0, length(key) + 2); exit }' "$staging_file")
  [[ "$value" =~ ^\".*\"$ ]] && value=${value:1:${#value}-2}
  printf '%b' "$value" >"$target"
  chmod 400 "$target"
}
validate_tls_pair() {
  openssl x509 -in "$1" -noout -checkhost "$SMTP_TLS_FQDN" >/dev/null 2>&1 || return 1
  openssl x509 -in "$1" -checkend 1 -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "$2" -noout >/dev/null 2>&1 || return 1
  local cert_pub key_pub
  cert_pub=$(openssl x509 -in "$1" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | sha256sum | awk '{print $1}')
  key_pub=$(openssl pkey -in "$2" -pubout -outform DER | sha256sum | awk '{print $1}')
  [[ "$cert_pub" == "$key_pub" ]]
}
validate_graph_pair() {
  local key=$1 cert=$2 expected_thumb=$3 actual_thumb cert_pub key_pub
  openssl x509 -in "$cert" -checkend 1 -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || return 1
  actual_thumb=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 | awk -F= '{gsub(/:/, "", $2); print tolower($2)}')
  [[ "$actual_thumb" == "$expected_thumb" ]] || return 1
  cert_pub=$(openssl x509 -in "$cert" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | sha256sum | awk '{print $1}')
  key_pub=$(openssl pkey -in "$key" -pubout -outform DER | sha256sum | awk '{print $1}')
  [[ "$cert_pub" == "$key_pub" ]]
}

if [[ -e "$staging_file" ]]; then
  [[ -f "$staging_file" && ! -L "$staging_file" ]] || die 'existing staging file must be a regular non-symlink file.'
  staging_mode=$(stat -c '%a' "$staging_file") || die 'could not inspect staging file mode.'
  [[ $((8#$staging_mode & 077)) -eq 0 ]] || die 'existing staging file must not be readable or writable by group/other.'
  if [[ "$rotate_graph" == true || "$rotate_tls" == true ]]; then
    die 'remove the prior .env.certificates after SOPS handoff before an explicit rotation.'
  fi
  if [[ "$graph_missing" == true ]] && grep -q '^GRAPH_CERT_PRIVATE_KEY_PEM=' "$staging_file" && grep -q '^GRAPH_CERTIFICATE_THUMBPRINT=' "$staging_file"; then
    staging_value GRAPH_CERT_PRIVATE_KEY_PEM "$graph_key"
    pending_thumb=$(awk -F= '/^GRAPH_CERTIFICATE_THUMBPRINT=/{print $2; exit}' "$staging_file")
    [[ -f "$graph_cert" && ! -L "$graph_cert" ]] || die 'pending Graph public certificate is missing or unsafe.'
    validate_graph_pair "$graph_key" "$graph_cert" "$pending_thumb" || die 'pending Graph staging material is invalid.'
    graph_missing=false
    log 'reusing pending Graph certificate staging material.'
  fi
  if [[ "$tls_missing" == true ]] && grep -q '^TLS_CERTIFICATE_PEM=' "$staging_file" && grep -q '^TLS_PRIVATE_KEY_PEM=' "$staging_file"; then
    staging_value TLS_CERTIFICATE_PEM "$tls_cert"
    staging_value TLS_PRIVATE_KEY_PEM "$tls_key"
    validate_tls_pair "$tls_cert" "$tls_key" || die 'pending TLS staging material is invalid.'
    tls_missing=false
    log 'reusing pending TLS certificate staging material.'
  fi
  [[ "$graph_missing" == true || "$tls_missing" == true ]] && die 'existing staging file is incomplete; finish handoff or remove it before generating new material.'
  log "certificate staging is ready: $staging_file"
  exit 75
fi

if [[ "$tls_missing" == true ]]; then
  for key in SMTP_TLS_FQDN TLS_ACME_EMAIL TLS_ACME_STATE_DIR CLOUDFLARE_DNS_API_TOKEN; do
    [[ -n "${!key:-}" && "${!key}" != REPLACE_WITH_* ]] || die "required TLS issuance input is missing: ${key}."
  done
  [[ "$SMTP_TLS_FQDN" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]] || die 'SMTP_TLS_FQDN is unsafe.'
  [[ "$TLS_ACME_STATE_DIR" = /* && "$TLS_ACME_STATE_DIR" != / ]] || die 'TLS_ACME_STATE_DIR must be absolute and not /.'
  ensure_directory_for_caller "$TLS_ACME_STATE_DIR"
  credentials="$stage_dir/cloudflare.ini"
  printf 'dns_cloudflare_api_token = %s\n' "$CLOUDFLARE_DNS_API_TOKEN" >"$credentials"
  chmod 600 "$credentials"
  certbot_args=(certonly --non-interactive --agree-tos --email "$TLS_ACME_EMAIL"
    --dns-cloudflare --dns-cloudflare-credentials "$credentials"
    --config-dir "$TLS_ACME_STATE_DIR" --work-dir "$TLS_ACME_STATE_DIR/work" --logs-dir "$TLS_ACME_STATE_DIR/logs")
  [[ "$rotate_tls" == false ]] || certbot_args+=(--force-renewal)
  certbot "${certbot_args[@]}" -d "$SMTP_TLS_FQDN" >/dev/null
  issued_dir="$TLS_ACME_STATE_DIR/live/$SMTP_TLS_FQDN"
  [[ -f "$issued_dir/fullchain.pem" && -f "$issued_dir/privkey.pem" ]] || die 'Certbot did not produce the expected certificate files.'
  install -m 400 "$issued_dir/fullchain.pem" "$tls_cert"
  install -m 400 "$issued_dir/privkey.pem" "$tls_key"
  validate_tls_pair "$tls_cert" "$tls_key" || die 'issued TLS certificate/key pair is invalid.'
fi

if [[ "$graph_missing" == true ]]; then
  [[ ! -L "$graph_cert" ]] || die 'Graph public certificate path must not be a symlink.'
  openssl req -x509 -newkey rsa:3072 -nodes -days 730 \
    -subj "/CN=smtp2graph-graph-client-${environment}" \
    -keyout "$graph_key" -out "$stage_dir/graph-cert.pem" >/dev/null 2>&1
  install -m 400 "$stage_dir/graph-cert.pem" "$graph_cert"
  chmod 400 "$graph_key"
  graph_thumb=$(openssl x509 -in "$graph_cert" -noout -fingerprint -sha1 | awk -F= '{gsub(/:/, "", $2); print tolower($2)}')
  [[ "$graph_thumb" =~ ^[a-f0-9]{40}$ ]] || die 'could not calculate Graph certificate thumbprint.'
  validate_graph_pair "$graph_key" "$graph_cert" "$graph_thumb" || die 'generated Graph certificate/key pair is invalid.'
fi

emit_pem() {
  local key=$1 file=$2
  printf '%s="' "$key"
  awk '{ gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); printf "%s\\n", $0 }' "$file"
  printf '"\n'
}
staging_tmp=$(mktemp "$(dirname "$staging_file")/.env.certificates.XXXXXX")
chmod 600 "$staging_tmp"
if [[ "$graph_missing" == true ]]; then
  emit_pem GRAPH_CERT_PRIVATE_KEY_PEM "$graph_key" >>"$staging_tmp"
  printf 'GRAPH_CERTIFICATE_THUMBPRINT=%s\n' "$graph_thumb" >>"$staging_tmp"
fi
if [[ "$tls_missing" == true ]]; then
  emit_pem TLS_CERTIFICATE_PEM "$tls_cert" >>"$staging_tmp"
  emit_pem TLS_PRIVATE_KEY_PEM "$tls_key" >>"$staging_tmp"
fi
mv "$staging_tmp" "$staging_file"
chmod 600 "$staging_file"
log "certificate staging created: $staging_file"
log 'copy its values into the selected env.*.enc with SOPS, delete staging, then rerun deploy.'
exit 75
