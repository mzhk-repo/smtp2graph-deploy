#!/usr/bin/env bash
# Category 1b: perform the approved development deployment, upgrade and rollback rehearsal.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[smtp2graph-rehearsal] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage:
  scripts/rehearse-deployment.sh --env-file FILE --current-digest IMAGE@sha256:DIGEST \
    --candidate-digest IMAGE@sha256:DIGEST --recipient ADDRESS --smtp-user USER \
    --password-file /dev/shm/FILE --backup-reference ID --evidence-dir DIRECTORY --apply

The rehearsal is development-only. It creates one temporary invalid Graph
credential Secret, submits one synthetic SMTP message, upgrades and rolls back
only an approved exact-digest compatibility pair, then restores the original
Secret mapping. Mailbox delivery is verified manually from the emitted
X-Rehearsal-ID using a read-only non-production mailbox query.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
orchestrator="${project_root}/scripts/deploy-orchestrator-swarm.sh"
smoke_script=${SMTP2GRAPH_SMOKE_SCRIPT:-"${project_root}/tests/acceptance/deployment/smoke.sh"}
submit_helper=${SMTP2GRAPH_SMTP_SUBMIT_HELPER:-"${project_root}/tests/acceptance/deployment/smtp-submit.js"}
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"

env_file='' current_digest='' candidate_digest='' recipient='' smtp_user='' password_file=''
backup_reference='' evidence_dir='' apply=false
while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
      shift 2
      ;;
    --current-digest)
      current_digest=${2:-}
      shift 2
      ;;
    --candidate-digest)
      candidate_digest=${2:-}
      shift 2
      ;;
    --recipient)
      recipient=${2:-}
      shift 2
      ;;
    --smtp-user)
      smtp_user=${2:-}
      shift 2
      ;;
    --password-file)
      password_file=${2:-}
      shift 2
      ;;
    --backup-reference)
      backup_reference=${2:-}
      shift 2
      ;;
    --evidence-dir)
      evidence_dir=${2:-}
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

[[ "$apply" == true ]] || die 'rehearsal requires --apply.'
[[ "$env_file" = /* && -f "$env_file" && ! -L "$env_file" ]] || die '--env-file must be an absolute regular non-symlink file.'
[[ "$password_file" = /dev/shm/* && -f "$password_file" && ! -L "$password_file" ]] || die '--password-file must be an absolute regular non-symlink file below /dev/shm.'
[[ "$(stat -c '%a:%u' "$password_file")" == "600:$(id -u)" ]] || die '--password-file must be mode 0600 and owned by the invoking user.'
[[ "$backup_reference" =~ ^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$ ]] || die '--backup-reference must be a safe identifier.'
[[ "$evidence_dir" = /* && -d "$evidence_dir" && ! -L "$evidence_dir" ]] || die '--evidence-dir must be an existing absolute non-symlink directory.'
[[ "$(stat -c '%a' "$evidence_dir")" =~ ^[67]00$ ]] || die '--evidence-dir must not be group/world readable.'
[[ "$smtp_user" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]{0,127}$ ]] || die '--smtp-user is unsafe.'
[[ "$recipient" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || die '--recipient is invalid.'
for tool in docker node awk find stat mktemp date grep; do command -v "$tool" >/dev/null || die "$tool is required."; done
[[ -x "$orchestrator" && -x "$smoke_script" && -f "$submit_helper" ]] || die 'required rehearsal helper is unavailable.'

is_digest() { [[ "$1" =~ ^[^[:space:]@]+@sha256:[a-f0-9]{64}$ ]]; }
is_digest "$current_digest" || die '--current-digest must be immutable.'
is_digest "$candidate_digest" || die '--candidate-digest must be immutable.'
[[ "$current_digest" != "$candidate_digest" ]] || die 'current and candidate digests must differ.'

allowed_keys=(
  DEPLOY_ENVIRONMENT SMTP2GRAPH_IMAGE_DIGEST SWARM_STACK_NAME SWARM_OVERLAY_NETWORK
  SMTP2GRAPH_STORAGE_HOST_PATH SMTP2GRAPH_MODE GRAPH_AUTH_MODE
  SMTP_MAX_MESSAGE_BYTES SMTP_MAX_SESSIONS_PER_IP SMTP_MESSAGES_PER_MINUTE
  SMTP_ALLOWED_SOURCE_CIDRS SMTP_TLS_FQDN GRAPH_SENDER_MAILBOX
  SEND_RETRY_LIMIT SEND_RETRY_INTERVAL_MINUTES GRAPH_TENANT_ID_SECRET_NAME
  GRAPH_CLIENT_ID_SECRET_NAME GRAPH_CREDENTIAL_SECRET_NAME GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME
  SMTP_CREDENTIALS_SECRET_NAME TLS_CERTIFICATE_SECRET_NAME TLS_PRIVATE_KEY_SECRET_NAME
  NONPRODUCTION_RECIPIENT_ALLOWLIST TLS_SECRET_MAPPING_FILE
  SMTP2GRAPH_BACKUP_LOCAL_DIR SMTP2GRAPH_BACKUP_RCLONE_REMOTE SMTP2GRAPH_BACKUP_RCLONE_PATH
)
load_deploy_env_file "$project_root" "$env_file" "${allowed_keys[@]}"
secret_mapping_keys=(
  GRAPH_TENANT_ID_SECRET_NAME GRAPH_CLIENT_ID_SECRET_NAME GRAPH_CREDENTIAL_SECRET_NAME
  GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME SMTP_CREDENTIALS_SECRET_NAME
  TLS_CERTIFICATE_SECRET_NAME TLS_PRIVATE_KEY_SECRET_NAME
)
load_deploy_secret_mapping "$TLS_SECRET_MAPPING_FILE" "${secret_mapping_keys[@]}" || die 'could not load complete Secret mapping.'
[[ "${DEPLOY_ENVIRONMENT:-}" == development ]] || die 'Task 5.4 rehearsal is development-only.'
require_server_env_match development || die 'host SERVER_ENV must be dev.'
[[ "${SMTP2GRAPH_IMAGE_DIGEST:-}" == "$current_digest" ]] || die 'current digest must match SMTP2GRAPH_IMAGE_DIGEST in the env contract.'

recipient_lc=${recipient,,}
recipient_allowed=false
IFS=',' read -r -a recipient_list <<<"${NONPRODUCTION_RECIPIENT_ALLOWLIST:-}"
for allowed in "${recipient_list[@]}"; do [[ "${allowed,,}" == "$recipient_lc" ]] && recipient_allowed=true; done
[[ "$recipient_allowed" == true ]] || die 'recipient is absent from NONPRODUCTION_RECIPIENT_ALLOWLIST.'

storage_root=$SMTP2GRAPH_STORAGE_HOST_PATH
[[ "$storage_root" = /* && "$storage_root" != / && -d "$storage_root" && ! -L "$storage_root" ]] || die 'storage root is unsafe or unavailable.'
[[ -d "$storage_root/queue" && ! -L "$storage_root/queue" ]] || die 'queue directory is unsafe or unavailable.'
queue_count() { find "$storage_root/queue" -xdev -maxdepth 1 -type f -name '*.eml' -printf '.' | wc -c; }
wait_for() {
  local description=$1 timeout_seconds=$2 expected=$3 count elapsed=0
  while true; do
    count=$(queue_count)
    if [[ "$expected" == drain ]]; then ((count <= queue_before)) && return; else ((count >= expected)) && return; fi
    ((elapsed += 1))
    ((elapsed < timeout_seconds)) || die "timed out waiting for ${description}."
    sleep 1
  done
}

stage_dir=$(mktemp -d /dev/shm/smtp2graph-rehearsal.XXXXXX)
chmod 700 "$stage_dir"
rehearsal_id="task54-$(date -u +%Y%m%dT%H%M%SZ)-$$"
temporary_secret="smtp2graph_rehearsal_graph_cred_${rehearsal_id//[-:]/_}"
temporary_env="$stage_dir/deployment.env"
temporary_mapping="$stage_dir/secret-mapping.env"
active_temporary_mapping=false
evidence_file="$evidence_dir/${rehearsal_id}.txt"

restore_original() {
  [[ "$active_temporary_mapping" == true ]] || return 0
  "$orchestrator" --env-file "$env_file" --deploy --apply >/dev/null
  active_temporary_mapping=false
}
cleanup() {
  status=$?
  if [[ "$active_temporary_mapping" == true ]]; then
    log 'restoring original development Secret mapping after interrupted rehearsal.'
    restore_original || status=1
  fi
  if docker secret inspect "$temporary_secret" >/dev/null 2>&1; then docker secret rm "$temporary_secret" >/dev/null || status=1; fi
  rm -rf -- "$stage_dir"
  exit "$status"
}
trap cleanup EXIT

render_mapping() {
  local credential=$1
  awk -v credential="$credential" '
    /^GRAPH_CREDENTIAL_SECRET_NAME=/ { print "GRAPH_CREDENTIAL_SECRET_NAME=" credential; next }
    { print }
  ' "$TLS_SECRET_MAPPING_FILE" >"$temporary_mapping"
  chmod 600 "$temporary_mapping"
}
render_env() {
  local image=$1 mapping=$2 output=$3
  awk -v image="$image" -v mapping="$mapping" '
    /^SMTP2GRAPH_IMAGE_DIGEST=/ { print "SMTP2GRAPH_IMAGE_DIGEST=" image; next }
    /^TLS_SECRET_MAPPING_FILE=/ { print "TLS_SECRET_MAPPING_FILE=" mapping; next }
    { print }
  ' "$env_file" >"$output"
  chmod 600 "$output"
}
smoke() { "$smoke_script" --stack-name "$SWARM_STACK_NAME"; }
running_task_id() { docker service ps "${SWARM_STACK_NAME}_gateway" --filter desired-state=running --format '{{.ID}}'; }

printf 'Task 5.4 rehearsal\nbackup-reference=%s\ncurrent-digest=%s\ncandidate-digest=%s\n' "$backup_reference" "$current_digest" "$candidate_digest" >"$evidence_file"
chmod 600 "$evidence_file"

"$orchestrator" --env-file "$env_file" --deploy --apply
smoke
task_before=$(running_task_id)
[[ "$task_before" =~ ^[A-Za-z0-9]+$ ]] || die 'could not identify the running gateway task.'
"$orchestrator" --env-file "$env_file" --deploy --apply
[[ "$(running_task_id)" == "$task_before" ]] || die 'no-op redeploy replaced the running gateway task.'
printf 'fresh-deploy-and-noop=passed\n' >>"$evidence_file"

printf 'synthetic-invalid-credential-for-rehearsal\n' | docker secret create "$temporary_secret" - >/dev/null
render_mapping "$temporary_secret"
render_env "$current_digest" "$temporary_mapping" "$temporary_env"
"$orchestrator" --env-file "$temporary_env" --deploy --apply --secret-mapping-already-reconciled
active_temporary_mapping=true
smoke
queue_before=$(queue_count)
node "$submit_helper" 127.0.0.1 2525 "$smtp_user" "$password_file" "$GRAPH_SENDER_MAILBOX" "$recipient" "$rehearsal_id"
wait_for 'durable queued SMTP submission' 60 $((queue_before + 1))
printf 'queued-before-upgrade=%s\n' "$((queue_before + 1))" >>"$evidence_file"

render_env "$candidate_digest" "$temporary_mapping" "$temporary_env"
"$orchestrator" --env-file "$temporary_env" --deploy --apply --secret-mapping-already-reconciled
smoke
wait_for 'queue preservation after candidate upgrade' 30 $((queue_before + 1))
printf 'candidate-upgrade=passed\n' >>"$evidence_file"

render_env "$candidate_digest" "$TLS_SECRET_MAPPING_FILE" "$temporary_env"
"$orchestrator" --env-file "$temporary_env" --rollback --image-digest "$current_digest" --queue-compatibility-confirmed --apply
active_temporary_mapping=false
smoke
wait_for 'queue drain after rollback and credential restoration' 180 drain
printf 'rollback-and-queue-drain=passed\nrehearsal-id=%s\nmanual-mailbox-verification=required\n' "$rehearsal_id" >>"$evidence_file"
log "PASS: rehearsal completed. Verify X-Rehearsal-ID ${rehearsal_id} through a read-only non-production mailbox query."
