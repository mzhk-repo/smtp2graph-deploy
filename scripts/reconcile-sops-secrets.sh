#!/usr/bin/env bash
# Category 1b: reconcile versioned Docker Secrets from a SOPS or owner-only CI environment file.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[sops-secrets] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/reconcile-sops-secrets.sh --env-file FILE --mapping-file FILE [--environment development|production] [--approval-context ID] [--apply]

Validates a SOPS-encrypted Dotenv environment file or an owner-only plaintext
Dotenv file prepared by the CI deployer. With --apply, values are materialized
as deterministic versioned Docker Secrets. The mapping file contains names only
and is updated atomically.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"
# shellcheck source=scripts/lib/render-config.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/render-config.sh"

env_file='' mapping_file='' environment='' apply=false approval_context=''
while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --mapping-file)
      mapping_file=${2:-}
      shift 2
      ;;
    --environment)
      environment=${2:-}
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    --approval-context)
      approval_context=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die '--env-file must be an absolute regular non-symlink file.'
[[ "$mapping_file" = /* && ! -L "$mapping_file" ]] || die '--mapping-file must be an absolute non-symlink path.'
if [[ -e "$mapping_file" ]]; then
  [[ -f "$mapping_file" ]] || die '--mapping-file must be a regular non-symlink file.'
else
  touch "$mapping_file" || die 'could not create secret mapping file.'
  chmod 600 "$mapping_file" || die 'could not set permissions on secret mapping file.'
fi
for tool in dd grep sha256sum mktemp stat tail awk install openssl; do command -v "$tool" >/dev/null || die "$tool is required."; done

source_is_sops=false
if grep -q '^sops_version=' "$env_file" || grep -q 'ENC\[AES256_GCM' "$env_file"; then
  source_is_sops=true
  command -v sops >/dev/null || die 'sops is required for encrypted environment input.'
else
  env_mode=$(stat -c '%a' "$env_file") || die 'could not inspect plaintext environment file permissions.'
  [[ "$env_mode" =~ ^[0-7]{3,4}$ && $((8#$env_mode & 077)) -eq 0 ]] || die 'plaintext environment file must be owner-only.'
fi

stage_dir=''
cleanup() { [[ -z "$stage_dir" ]] || rm -rf -- "$stage_dir"; }
trap cleanup EXIT
stage_dir=$(mktemp -d /dev/shm/smtp2graph-sops.XXXXXX)
chmod 700 "$stage_dir"
plain_env="$stage_dir/environment.env"
[[ ! -e "$plain_env" ]] || die 'internal plaintext staging path already exists.'

extract_source_value() {
  local key=$1
  if [[ "$source_is_sops" == true ]]; then
    sops --decrypt --input-type dotenv --extract "[\"$key\"]" --output-type binary "$env_file"
    return
  fi
  awk -v key="$key" '
    $0 ~ ("^" key "=") {
      if (found++) exit 64
      printf "%s", substr($0, length(key) + 2)
    }
    END { if (!found) exit 65 }
  ' "$env_file"
}

extract_secret() {
  local key=$1 target=$2 raw_target raw_size first_byte last_byte decoded_target value
  raw_target="$target.raw"
  extract_source_value "$key" >"$raw_target" || die "could not extract environment value: $key."
  raw_size=$(stat -c '%s' "$raw_target") || die "could not inspect environment value: $key."
  [[ "$raw_size" -gt 0 ]] || die "environment value is empty: $key."
  first_byte=$(dd if="$raw_target" bs=1 count=1 status=none)
  last_byte=$(tail -c 1 "$raw_target")
  if [[ "$raw_size" -ge 2 && "$first_byte" == '"' && "$last_byte" == '"' ]]; then
    dd if="$raw_target" of="$target" bs=1 skip=1 count=$((raw_size - 2)) status=none
    rm -f -- "$raw_target"
  else
    mv "$raw_target" "$target"
  fi
  case "$key" in
    SMTP_USERS_TSV | GRAPH_CERT_PRIVATE_KEY_PEM)
      decoded_target="$target.decoded"
      value=$(cat "$target")
      printf '%b' "$value" >"$decoded_target"
      mv "$decoded_target" "$target"
      ;;
  esac
  case "$key" in
    GRAPH_CERT_PRIVATE_KEY_PEM)
      if grep -Fq '\n' "$target"; then
        decoded_target="$target.decoded"
        value=$(cat "$target")
        printf '%b' "$value" >"$decoded_target"
        mv "$decoded_target" "$target"
      fi
      if grep -q '\\$' "$target"; then
        decoded_target="$target.decoded"
        sed 's/\\$//' "$target" >"$decoded_target"
        mv "$decoded_target" "$target"
      fi
      ;;
  esac
  chmod 400 "$target"
  [[ -s "$target" ]] || die "environment value is empty: $key."
  ! grep -q '^REPLACE_WITH_' "$target" || die "required environment value is still a placeholder: $key."
}
extract_metadata() {
  local key=$1 value
  value=$(extract_source_value "$key") || die "could not extract environment value: $key."
  if [[ ${value:0:1} == '"' && ${value: -1} == '"' ]]; then
    value=${value:1:${#value}-2}
  fi
  [[ -n "$value" ]] || die "environment value is empty: $key."
  [[ "$value" != REPLACE_WITH_* ]] || die "required environment value is still a placeholder: $key."
  printf '%s\n' "$value"
}
declared_environment=$(extract_metadata DEPLOY_ENVIRONMENT)
graph_auth_mode=$(extract_metadata GRAPH_AUTH_MODE)
environment=${environment:-$declared_environment}
[[ "$environment" == development || "$environment" == production ]] || die 'environment must be development or production.'
[[ "$environment" == "$declared_environment" ]] || die '--environment does not match DEPLOY_ENVIRONMENT.'
require_server_env_match "$environment" || die 'host SERVER_ENV must match DEPLOY_ENVIRONMENT.'
if [[ "$apply" == true && "$environment" == production && -n "$approval_context" ]]; then
  [[ "$approval_context" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die 'production --apply requires a safe --approval-context identifier.'
fi

extract_secret GRAPH_TENANT_ID "$stage_dir/graph-tenant-id"
extract_secret GRAPH_CLIENT_ID "$stage_dir/graph-client-id"
extract_secret SMTP_USERS_TSV "$stage_dir/smtp-users"
graph_sender_mailbox=$(extract_metadata GRAPH_SENDER_MAILBOX)
global_sender=$(normalize_email "$graph_sender_mailbox") || die 'GRAPH_SENDER_MAILBOX is invalid.'
render_smtp_users "$stage_dir/smtp-users" "$global_sender" >/dev/null || die 'SMTP_USERS_TSV does not satisfy the runtime SMTP policy.'
case "$graph_auth_mode" in
  certificate)
    extract_secret GRAPH_CERT_PRIVATE_KEY_PEM "$stage_dir/graph-credential"
    extract_secret GRAPH_CERTIFICATE_THUMBPRINT "$stage_dir/graph-certificate-thumbprint"
    ;;
  client-secret) extract_secret GRAPH_CLIENT_SECRET "$stage_dir/graph-credential" ;;
  *) die 'GRAPH_AUTH_MODE must be certificate or client-secret.' ;;
esac

declare -A secret_names=()
secret_for() {
  local logical=$1 file=$2 hash
  hash=$(sha256sum "$file" | awk '{print substr($1, 1, 16)}')
  printf 'smtp2graph_%s_v%s\n' "$logical" "$hash"
}
secret_names[GRAPH_TENANT_ID_SECRET_NAME]=$(secret_for graph_tenant_id "$stage_dir/graph-tenant-id")
secret_names[GRAPH_CLIENT_ID_SECRET_NAME]=$(secret_for graph_client_id "$stage_dir/graph-client-id")
secret_names[GRAPH_CREDENTIAL_SECRET_NAME]=$(secret_for graph_credential "$stage_dir/graph-credential")
secret_names[SMTP_CREDENTIALS_SECRET_NAME]=$(secret_for smtp_users "$stage_dir/smtp-users")
if [[ "$graph_auth_mode" == certificate ]]; then
  secret_names[GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME]=$(secret_for graph_certificate_thumbprint "$stage_dir/graph-certificate-thumbprint")
fi

for key in GRAPH_TENANT_ID_SECRET_NAME GRAPH_CLIENT_ID_SECRET_NAME GRAPH_CREDENTIAL_SECRET_NAME SMTP_CREDENTIALS_SECRET_NAME GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME; do
  [[ -z "${secret_names[$key]:-}" ]] || printf '%s=%s\n' "$key" "${secret_names[$key]}"
done
[[ "$apply" == true ]] || exit 0
command -v docker >/dev/null || die 'docker is required with --apply.'
for key in "${!secret_names[@]}"; do
  case "$key" in
    GRAPH_TENANT_ID_SECRET_NAME) file=$stage_dir/graph-tenant-id ;;
    GRAPH_CLIENT_ID_SECRET_NAME) file=$stage_dir/graph-client-id ;;
    GRAPH_CREDENTIAL_SECRET_NAME) file=$stage_dir/graph-credential ;;
    GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME) file=$stage_dir/graph-certificate-thumbprint ;;
    SMTP_CREDENTIALS_SECRET_NAME) file=$stage_dir/smtp-users ;;
  esac
  docker secret inspect "${secret_names[$key]}" >/dev/null 2>&1 || docker secret create "${secret_names[$key]}" "$file" >/dev/null
done
mapping_tmp=$(mktemp "$(dirname "$mapping_file")/.sops-secret-map.XXXXXX")
chmod 644 "$mapping_tmp"
names_file="$stage_dir/names"
for key in "${!secret_names[@]}"; do printf '%s=%s\n' "$key" "${secret_names[$key]}"; done >"$names_file"
chmod 400 "$names_file"
awk -F= -v names_file="$stage_dir/names" '
  BEGIN { while ((getline line < names_file) > 0) { split(line, pair, "="); names[pair[1]]=pair[2] } }
  $1 in names { print $1 "=" names[$1]; seen[$1]=1; next }
  { print }
  END { for (key in names) if (!seen[key]) print key "=" names[key] }
' "$mapping_file" >"$mapping_tmp"
mv "$mapping_tmp" "$mapping_file"
chmod 644 "$mapping_file"
if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
  chown "${SUDO_UID}:${SUDO_GID}" "$mapping_file" 2>/dev/null || true
fi
log 'versioned Docker Secret mapping updated; deploy separately after policy verification.'
