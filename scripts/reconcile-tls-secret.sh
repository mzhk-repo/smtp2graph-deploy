#!/usr/bin/env bash
# Category 1b: reconcile dev/prod TLS Docker Secrets from protected PEM files.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[tls-secret] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/reconcile-tls-secret.sh [--env-file FILE] [--environment development|production] [--certificate-file FILE --key-file FILE --mapping-file FILE] [--approval-context ID] [--apply]

Checks a PEM certificate/key pair for smtp-int.ldubgd.edu.ua. Without --apply it
only validates and prints deterministic versioned Docker Secret names.
USAGE
}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
. "${root}/scripts/lib/read-deploy-env.sh"
env_file='' environment='' certificate_file='' key_file='' mapping_file='' apply=false approval_context=''
while (($#)); do
  case "$1" in
    --environment)
      environment=${2:-}
      shift 2
      ;;
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --certificate-file)
      certificate_file=${2:-}
      shift 2
      ;;
    --key-file)
      key_file=${2:-}
      shift 2
      ;;
    --mapping-file)
      mapping_file=${2:-}
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

load_deploy_env_file "$root" "$env_file" DEPLOY_ENVIRONMENT TLS_CERTIFICATE_FILE TLS_PRIVATE_KEY_FILE TLS_SECRET_MAPPING_FILE SMTP_TLS_FQDN
environment=${environment:-${DEPLOY_ENVIRONMENT:-}}
certificate_file=${certificate_file:-${TLS_CERTIFICATE_FILE:-}}
key_file=${key_file:-${TLS_PRIVATE_KEY_FILE:-}}
mapping_file=${mapping_file:-${TLS_SECRET_MAPPING_FILE:-}}
tls_fqdn=${SMTP_TLS_FQDN:-smtp-int.ldubgd.edu.ua}

[[ "$environment" == development || "$environment" == production ]] || die '--environment must be development or production.'
require_server_env_match "$environment" || die 'host SERVER_ENV must match DEPLOY_ENVIRONMENT.'
if [[ "$apply" == true && "$environment" == production ]]; then
  [[ "$approval_context" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die 'production --apply requires a safe --approval-context identifier.'
fi
for required in certificate_file key_file mapping_file; do [[ -n "${!required}" ]] || die "--${required//_/-} is required."; done
for tool in openssl sha256sum mktemp stat awk; do command -v "$tool" >/dev/null || die "$tool is required."; done

require_protected_file() {
  local path=$1 mode owner
  [[ "$path" = /* && -f "$path" && ! -L "$path" ]] || die 'TLS input must be an absolute regular non-symlink file.'
  mode=$(stat -c '%a' "$path") || die 'could not inspect TLS input permissions.'
  owner=$(stat -c '%u' "$path") || die 'could not inspect TLS input owner.'
  [[ "$mode" =~ ^[0-7]{3,4}$ ]] || die 'TLS input mode is invalid.'
  [[ "$mode" != *[2367] && "$owner" == "$(id -u)" ]] || die 'TLS input must be owned by the invoking operator and not writable by group or other users.'
}
require_protected_file "$certificate_file"
require_protected_file "$key_file"
key_mode=$(stat -c '%a' "$key_file")
[[ "$key_mode" == 400 || "$key_mode" == 600 ]] || die 'TLS private key mode must be 0400 or 0600.'
openssl x509 -in "$certificate_file" -noout >/dev/null 2>&1 || die 'TLS certificate is not valid PEM.'
openssl pkey -in "$key_file" -noout >/dev/null 2>&1 || die 'TLS private key is not valid PEM.'
openssl x509 -in "$certificate_file" -checkend 1 -noout >/dev/null 2>&1 || die 'TLS certificate is expired or expires within one second.'
openssl x509 -in "$certificate_file" -noout -checkhost "$tls_fqdn" >/dev/null 2>&1 || die 'TLS certificate does not match configured SMTP_TLS_FQDN.'
cert_pub=$(openssl x509 -in "$certificate_file" -pubkey -noout | openssl pkey -pubin -pubout -outform DER | sha256sum | awk '{print $1}')
key_pub=$(openssl pkey -in "$key_file" -pubout -outform DER | sha256sum | awk '{print $1}')
[[ "$cert_pub" == "$key_pub" ]] || die 'TLS certificate and private key do not match.'
[[ -f "$mapping_file" && ! -L "$mapping_file" ]] || die '--mapping-file must be an existing regular non-symlink file.'

cert_hash=$(sha256sum "$certificate_file" | awk '{print substr($1, 1, 16)}')
key_hash=$(sha256sum "$key_file" | awk '{print substr($1, 1, 16)}')
cert_secret="smtp2graph_tls_certificate_v${cert_hash}"
key_secret="smtp2graph_tls_private_key_v${key_hash}"
printf 'TLS_CERTIFICATE_SECRET_NAME=%s\nTLS_PRIVATE_KEY_SECRET_NAME=%s\n' "$cert_secret" "$key_secret"
[[ "$apply" == true ]] || exit 0
command -v docker >/dev/null || die 'docker is required with --apply.'
stage_dir=$(mktemp -d /dev/shm/smtp2graph-tls.XXXXXX)
chmod 700 "$stage_dir"
cleanup() { rm -rf -- "$stage_dir"; }
trap cleanup EXIT
install -m 0400 "$certificate_file" "$stage_dir/certificate.pem"
install -m 0400 "$key_file" "$stage_dir/private-key.pem"
for item in "$cert_secret:$stage_dir/certificate.pem" "$key_secret:$stage_dir/private-key.pem"; do
  name=${item%%:*}
  file=${item#*:}
  docker secret inspect "$name" >/dev/null 2>&1 || docker secret create "$name" "$file" >/dev/null
done
mapping_tmp=$(mktemp "$(dirname "$mapping_file")/.tls-secret-map.XXXXXX")
chmod 644 "$mapping_tmp"
awk -v cert="$cert_secret" -v key="$key_secret" '
  BEGIN { seen_cert=0; seen_key=0 }
  /^TLS_CERTIFICATE_SECRET_NAME=/ { print "TLS_CERTIFICATE_SECRET_NAME=" cert; seen_cert=1; next }
  /^TLS_PRIVATE_KEY_SECRET_NAME=/ { print "TLS_PRIVATE_KEY_SECRET_NAME=" key; seen_key=1; next }
  { print }
  END { if (!seen_cert) print "TLS_CERTIFICATE_SECRET_NAME=" cert; if (!seen_key) print "TLS_PRIVATE_KEY_SECRET_NAME=" key }
' "$mapping_file" >"$mapping_tmp"
mv "$mapping_tmp" "$mapping_file"
chmod 644 "$mapping_file"
if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
  chown "${SUDO_UID}:${SUDO_GID}" "$mapping_file" 2>/dev/null || true
fi
log 'TLS Docker Secret mapping updated; deploy separately after policy verification.'
