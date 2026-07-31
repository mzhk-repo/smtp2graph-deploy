#!/usr/bin/env bash
# Category 1b: reconcile versioned Docker Secrets from an encrypted SOPS environment file.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[sops-secrets] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/reconcile-sops-secrets.sh --env-file FILE --mapping-file FILE [--environment non-production] [--apply]

Validates an encrypted SOPS YAML environment file. With --apply, plaintext is
decrypted only under /dev/shm and materialized as deterministic versioned Docker
Secrets. The mapping file contains names only and is updated atomically.
USAGE
}

env_file='' mapping_file='' environment='' apply=false
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
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die '--env-file must be an absolute regular non-symlink file.'
[[ "$mapping_file" = /* && -f "$mapping_file" && ! -L "$mapping_file" ]] || die '--mapping-file must be an existing regular non-symlink file.'
for tool in sops sha256sum mktemp stat awk install; do command -v "$tool" >/dev/null || die "$tool is required."; done

stage_dir=''
cleanup() { [[ -z "$stage_dir" ]] || rm -rf -- "$stage_dir"; }
trap cleanup EXIT
stage_dir=$(mktemp -d /dev/shm/smtp2graph-sops.XXXXXX)
chmod 700 "$stage_dir"
plain_env="$stage_dir/environment.env"
sops --decrypt --input-type yaml --output-type dotenv "$env_file" >"$plain_env" || die 'could not decrypt the SOPS environment file.'
chmod 600 "$plain_env"

declare -A values=()
declare -A seen=()
allowed_keys=(
  DEPLOY_ENVIRONMENT GRAPH_AUTH_MODE GRAPH_TENANT_ID GRAPH_CLIENT_ID
  GRAPH_CERTIFICATE_THUMBPRINT GRAPH_CLIENT_SECRET SMTP_USERS_TSV
  TLS_CERTIFICATE_PEM TLS_PRIVATE_KEY_PEM
)
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || die 'decrypted environment has invalid syntax.'
  key=${BASH_REMATCH[1]}
  value=${BASH_REMATCH[2]}
  known=false
  for item in "${allowed_keys[@]}"; do [[ "$key" == "$item" ]] && {
    known=true
    break
  }; done
  "$known" || continue
  [[ -z "${seen[$key]:-}" ]] || die "decrypted environment has duplicate key: $key."
  seen[$key]=1
  values[$key]=$value
done <"$plain_env"

require_value() {
  local key=$1
  [[ -n "${values[$key]:-}" ]] || die "required encrypted value is missing: $key."
  [[ "${values[$key]}" != REPLACE_WITH_* ]] || die "required encrypted value is still a placeholder: $key."
}
for key in DEPLOY_ENVIRONMENT GRAPH_AUTH_MODE GRAPH_TENANT_ID GRAPH_CLIENT_ID SMTP_USERS_TSV TLS_CERTIFICATE_PEM TLS_PRIVATE_KEY_PEM; do require_value "$key"; done
environment=${environment:-${values[DEPLOY_ENVIRONMENT]}}
[[ "$environment" == non-production || "$environment" == production ]] || die 'environment must be non-production or production.'
[[ "$environment" == "${values[DEPLOY_ENVIRONMENT]}" ]] || die '--environment does not match DEPLOY_ENVIRONMENT.'
[[ "$apply" == false || "$environment" == non-production ]] || die '--apply is limited to non-production; production requires separately approved orchestration.'
case "${values[GRAPH_AUTH_MODE]}" in
  certificate)
    credential_key=GRAPH_CERT_PRIVATE_KEY_PEM
    require_value GRAPH_CERTIFICATE_THUMBPRINT
    ;;
  client-secret)
    credential_key=GRAPH_CLIENT_SECRET
    require_value GRAPH_CLIENT_SECRET
    ;;
  *) die 'GRAPH_AUTH_MODE must be certificate or client-secret.' ;;
esac

extract_secret() {
  local key=$1 target=$2
  sops --decrypt --input-type yaml --extract "[\"$key\"]" --output-type binary "$env_file" >"$target" || die "could not extract encrypted value: $key."
  chmod 400 "$target"
  [[ -s "$target" ]] || die "encrypted value is empty: $key."
}
extract_secret GRAPH_TENANT_ID "$stage_dir/graph-tenant-id"
extract_secret GRAPH_CLIENT_ID "$stage_dir/graph-client-id"
extract_secret "$credential_key" "$stage_dir/graph-credential"
extract_secret SMTP_USERS_TSV "$stage_dir/smtp-users"
extract_secret TLS_CERTIFICATE_PEM "$stage_dir/smtp-tls-cert"
extract_secret TLS_PRIVATE_KEY_PEM "$stage_dir/smtp-tls-key"
if [[ "${values[GRAPH_AUTH_MODE]}" == certificate ]]; then
  extract_secret GRAPH_CERTIFICATE_THUMBPRINT "$stage_dir/graph-certificate-thumbprint"
fi

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
secret_names[TLS_CERTIFICATE_SECRET_NAME]=$(secret_for tls_certificate "$stage_dir/smtp-tls-cert")
secret_names[TLS_PRIVATE_KEY_SECRET_NAME]=$(secret_for tls_private_key "$stage_dir/smtp-tls-key")
if [[ "${values[GRAPH_AUTH_MODE]}" == certificate ]]; then
  secret_names[GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME]=$(secret_for graph_certificate_thumbprint "$stage_dir/graph-certificate-thumbprint")
fi

for key in GRAPH_TENANT_ID_SECRET_NAME GRAPH_CLIENT_ID_SECRET_NAME GRAPH_CREDENTIAL_SECRET_NAME SMTP_CREDENTIALS_SECRET_NAME TLS_CERTIFICATE_SECRET_NAME TLS_PRIVATE_KEY_SECRET_NAME GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME; do
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
    TLS_CERTIFICATE_SECRET_NAME) file=$stage_dir/smtp-tls-cert ;;
    TLS_PRIVATE_KEY_SECRET_NAME) file=$stage_dir/smtp-tls-key ;;
  esac
  docker secret inspect "${secret_names[$key]}" >/dev/null 2>&1 || docker secret create "${secret_names[$key]}" "$file" >/dev/null
done
mapping_tmp=$(mktemp "$(dirname "$mapping_file")/.sops-secret-map.XXXXXX")
chmod 600 "$mapping_tmp"
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
chmod 600 "$mapping_file"
log 'versioned Docker Secret mapping updated; deploy separately after policy verification.'
