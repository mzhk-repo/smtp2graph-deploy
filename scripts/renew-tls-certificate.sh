#!/usr/bin/env bash
# Category 2: renew one ACME TLS lineage and converge its two Docker Secret mounts.
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
log() { printf '[tls-renewal] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/renew-tls-certificate.sh --env-file FILE [--check|--dry-run|--apply] [--prepare-only] [--force-renewal]

Renews the configured DNS-01 certificate and reconciles only the two gateway TLS
Docker Secrets. --prepare-only creates/mapping-reconciles secrets without a service update.
USAGE
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "$root/scripts/lib/read-deploy-env.sh"

env_file='' mode=check prepare_only=false force=false
while (($#)); do
  case "$1" in
    --env-file) env_file=${2:-}; shift 2 ;;
    --check) mode=check; shift ;;
    --dry-run) mode=dry-run; shift ;;
    --apply) mode=apply; shift ;;
    --prepare-only) prepare_only=true; shift ;;
    --force-renewal) force=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unsupported argument: $1" ;;
  esac
done
[[ -n "$env_file" ]] || die '--env-file is required.'
[[ "$mode" != check || "$prepare_only" == false ]] || die '--prepare-only requires --apply.'
[[ "$mode" != dry-run || "$prepare_only" == false ]] || die '--prepare-only requires --apply.'

prepare_sops_deploy_env "$root" "$env_file" || die 'could not prepare encrypted deployment environment.'
stage_dir=$(mktemp -d /dev/shm/smtp2graph-tls-renew.XXXXXX)
chmod 700 "$stage_dir"
cleanup() { rm -rf -- "$stage_dir"; cleanup_sops_deploy_env; }
trap cleanup EXIT
load_deploy_env_file "$root" "$SOPS_DEPLOY_ENV_FILE" \
  DEPLOY_ENVIRONMENT SMTP_TLS_FQDN TLS_ACME_EMAIL TLS_ACME_STATE_DIR \
  TLS_SECRET_MAPPING_FILE CLOUDFLARE_DNS_API_TOKEN SWARM_STACK_NAME

environment=${DEPLOY_ENVIRONMENT:-}
case "$environment" in development|production) ;; *) die 'DEPLOY_ENVIRONMENT must be development or production.' ;; esac
require_server_env_match "$environment" || die 'host SERVER_ENV must match DEPLOY_ENVIRONMENT.'
[[ "$force" == false || "$environment" == development ]] || die '--force-renewal is development-only.'
for key in SMTP_TLS_FQDN TLS_ACME_EMAIL TLS_ACME_STATE_DIR TLS_SECRET_MAPPING_FILE CLOUDFLARE_DNS_API_TOKEN SWARM_STACK_NAME; do
  [[ -n "${!key:-}" && "${!key}" != REPLACE_WITH_* ]] || die "required TLS renewal key is missing: $key."
done
[[ "$TLS_ACME_STATE_DIR" = /* && "$TLS_ACME_STATE_DIR" != / ]] || die 'TLS_ACME_STATE_DIR must be an absolute path other than /.'
[[ "$TLS_SECRET_MAPPING_FILE" = /* && "$TLS_SECRET_MAPPING_FILE" != / ]] || die 'TLS_SECRET_MAPPING_FILE must be an absolute path other than /.'
[[ "$SWARM_STACK_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die 'SWARM_STACK_NAME is unsafe.'
for tool in certbot docker flock install mktemp openssl realpath sha256sum timeout awk grep; do command -v "$tool" >/dev/null || die "$tool is required."; done
if [[ -n "${SOPS_AGE_KEY_FILE:-}" ]]; then
  [[ "$SOPS_AGE_KEY_FILE" = /* && -f "$SOPS_AGE_KEY_FILE" && ! -L "$SOPS_AGE_KEY_FILE" ]] || die 'SOPS_AGE_KEY_FILE must be an absolute regular non-symlink file.'
  age_mode=$(stat -c '%a' "$SOPS_AGE_KEY_FILE") || die 'could not inspect SOPS age identity.'
  [[ $((8#$age_mode & 077)) -eq 0 ]] || die 'SOPS age identity must be owner-only.'
fi

install -d -m 700 -- "$TLS_ACME_STATE_DIR"
mkdir -p -- "$(dirname "$TLS_SECRET_MAPPING_FILE")"
[[ -d "$TLS_ACME_STATE_DIR" && ! -L "$TLS_ACME_STATE_DIR" ]] || die 'TLS_ACME_STATE_DIR is unsafe.'
[[ -e "$TLS_SECRET_MAPPING_FILE" || ! -L "$TLS_SECRET_MAPPING_FILE" ]] || die 'TLS_SECRET_MAPPING_FILE is unsafe.'
[[ -e "$TLS_SECRET_MAPPING_FILE" ]] || { : >"$TLS_SECRET_MAPPING_FILE"; chmod 600 "$TLS_SECRET_MAPPING_FILE"; }

exec 9>"$stage_dir/renew.lock"
flock -n 9 || die 'another TLS renewal is already running.'
credentials="$stage_dir/cloudflare.ini"
printf 'dns_cloudflare_api_token = %s\n' "$CLOUDFLARE_DNS_API_TOKEN" >"$credentials"
chmod 600 "$credentials"
certbot_args=(certonly --non-interactive --agree-tos --email "$TLS_ACME_EMAIL" --cert-name "$SMTP_TLS_FQDN" -d "$SMTP_TLS_FQDN"
  --dns-cloudflare --dns-cloudflare-credentials "$credentials"
  --config-dir "$TLS_ACME_STATE_DIR" --work-dir "$TLS_ACME_STATE_DIR/work" --logs-dir "$TLS_ACME_STATE_DIR/logs")
[[ "$mode" != dry-run ]] || certbot_args+=(--dry-run)
[[ "$force" == false ]] || certbot_args+=(--force-renewal)
if [[ "$mode" == check ]]; then
  log 'PASS: TLS renewal inputs are valid.'
  exit 0
fi
certbot "${certbot_args[@]}" >/dev/null
[[ "$mode" != dry-run ]] || { log 'PASS: Certbot dry-run completed.'; exit 0; }

lineage="$TLS_ACME_STATE_DIR/live/$SMTP_TLS_FQDN"
cert_file=$(realpath -e -- "$lineage/fullchain.pem") || die 'Certbot certificate lineage is missing.'
key_file=$(realpath -e -- "$lineage/privkey.pem") || die 'Certbot private-key lineage is missing.'
archive_root=$(realpath -e -- "$TLS_ACME_STATE_DIR/archive/$SMTP_TLS_FQDN") || die 'Certbot archive lineage is missing.'
[[ "$cert_file" == "$archive_root/"* && "$key_file" == "$archive_root/"* ]] || die 'Certbot lineage resolves outside its archive.'

approval=( )
[[ "$environment" != production ]] || approval=(--approval-context systemd-tls-renewal)
temp_mapping="$stage_dir/mapping.env"
cp -- "$TLS_SECRET_MAPPING_FILE" "$temp_mapping"
chmod 600 "$temp_mapping"
names=$("$root/scripts/reconcile-tls-secret.sh" --environment "$environment" --certificate-file "$cert_file" --key-file "$key_file" --mapping-file "$temp_mapping" --apply "${approval[@]}")
desired_cert=$(awk -F= '$1 == "TLS_CERTIFICATE_SECRET_NAME" { print $2 }' <<<"$names")
desired_key=$(awk -F= '$1 == "TLS_PRIVATE_KEY_SECRET_NAME" { print $2 }' <<<"$names")
[[ -n "$desired_cert" && -n "$desired_key" ]] || die 'could not determine TLS Secret names.'
if [[ "$prepare_only" == true ]]; then
  "$root/scripts/reconcile-tls-secret.sh" --environment "$environment" --certificate-file "$cert_file" --key-file "$key_file" --mapping-file "$TLS_SECRET_MAPPING_FILE" --apply "${approval[@]}" >/dev/null
  log 'PASS: TLS Secrets and mapping are prepared.'
  exit 0
fi

docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
[[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == true ]] || die 'Docker Swarm manager access is required.'
service="${SWARM_STACK_NAME}_gateway"
secret_lines=$(docker service inspect "$service" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{printf "%s=%s\\n" .File.Name .SecretName}}{{end}}') || die 'gateway service is unavailable.'
current_cert=$(awk -F= '$1 == "smtp-tls-cert" { print $2 }' <<<"$secret_lines")
current_key=$(awk -F= '$1 == "smtp-tls-key" { print $2 }' <<<"$secret_lines")
[[ -n "$current_cert" && -n "$current_key" ]] || die 'gateway TLS Secret targets are incomplete.'
if [[ "$current_cert" != "$desired_cert" || "$current_key" != "$desired_key" ]]; then
  if ! docker service update --detach=false \
    --secret-rm "$current_cert" --secret-rm "$current_key" \
    --secret-add "source=$desired_cert,target=smtp-tls-cert,uid=65532,gid=65532,mode=0444" \
    --secret-add "source=$desired_key,target=smtp-tls-key,uid=65532,gid=65532,mode=0400" "$service"; then
    docker service rollback "$service" >/dev/null 2>&1 || true
    die 'TLS Secret service update failed; rollback requested.'
  fi
fi
expected_fp=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 | tr -d ':')
actual_fp=$(printf 'QUIT\r\n' | timeout 20 openssl s_client -starttls smtp -connect 127.0.0.1:2525 -servername "$SMTP_TLS_FQDN" 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | tr -d ':') || {
  docker service rollback "$service" >/dev/null 2>&1 || true
  die 'STARTTLS probe failed; rollback requested.'
}
[[ "$actual_fp" == "$expected_fp" ]] || { docker service rollback "$service" >/dev/null 2>&1 || true; die 'STARTTLS probe certificate does not match the Certbot lineage; rollback requested.'; }
"$root/scripts/reconcile-tls-secret.sh" --environment "$environment" --certificate-file "$cert_file" --key-file "$key_file" --mapping-file "$TLS_SECRET_MAPPING_FILE" --apply "${approval[@]}" >/dev/null
log 'PASS: TLS certificate, Docker Secrets, mapping and STARTTLS endpoint are converged.'
