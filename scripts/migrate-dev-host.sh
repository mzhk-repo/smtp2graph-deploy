#!/usr/bin/env bash
# Category 1b: explicitly migrate the legacy non-production host boundary to dev.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}
log() { printf '[dev-host-migration] %s\n' "$*" >&2; }
usage() {
  cat <<'USAGE'
Usage: scripts/migrate-dev-host.sh --env-file FILE [--check | --apply]

Migrates only the legacy /srv/smtp2graph/non-production tree and
smtp2graph_nonproduction node label to the reviewed dev equivalents. It refuses
to run while the gateway service has running tasks, follows no symlinks and never
copies, deletes or inspects queue payloads. --apply requires SERVER_ENV=dev.
USAGE
}

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=scripts/lib/read-deploy-env.sh
# shellcheck disable=SC1091
. "${project_root}/scripts/lib/read-deploy-env.sh"

env_file=''
apply=false
test_root=''
while (($#)); do
  case "$1" in
    --env-file)
      env_file=${2:-}
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
    --test-root)
      test_root=${2:-}
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ -n "$env_file" ]] || die '--env-file is required.'
load_deploy_env_file "$project_root" "$env_file" DEPLOY_ENVIRONMENT SMTP2GRAPH_STORAGE_HOST_PATH SWARM_STACK_NAME
[[ "${DEPLOY_ENVIRONMENT:-}" == development ]] || die 'legacy migration is available only for DEPLOY_ENVIRONMENT=development.'
SMTP2GRAPH_NODE_LABEL=smtp2graph_dev
require_server_env_match development || die 'legacy migration requires host SERVER_ENV=dev.'

base_root='/srv/smtp2graph'
if [[ -n "$test_root" ]]; then
  [[ "${SMTP2GRAPH_TEST_MODE:-}" == 1 ]] || die '--test-root is available only with SMTP2GRAPH_TEST_MODE=1.'
  [[ "$test_root" = /tmp/* && -d "$test_root" && ! -L "$test_root" ]] || die '--test-root must be an existing non-symlink directory under /tmp.'
  base_root="$test_root/srv/smtp2graph"
fi
legacy_root="$base_root/non-production"
target_root="$base_root/dev"
[[ "$SMTP2GRAPH_STORAGE_HOST_PATH" == "$target_root/data" ]] || die "development storage path must be ${target_root}/data."
for path in "$base_root" "$legacy_root" "$target_root"; do
  [[ ! -e "$path" || ! -L "$path" ]] || die "migration path must not be a symlink: $path"
done
[[ -d "$base_root" && ! -L "$base_root" ]] || die 'SMTP2Graph storage parent must be an existing non-symlink directory.'

command -v docker >/dev/null || die 'docker is required.'
docker info >/dev/null 2>&1 || die 'Docker API is unavailable or access is denied.'
[[ "$(docker info --format '{{.Swarm.ControlAvailable}}')" == true ]] || die 'Docker Swarm manager access is required.'
if docker service ps "${SWARM_STACK_NAME:-smtp2graph}_gateway" --filter desired-state=running --format '{{.ID}}' 2>/dev/null | grep -q .; then
  die 'gateway service has running tasks; stop it and assess queue compatibility before migration.'
fi

if [[ -d "$legacy_root" ]]; then
  "${project_root}/scripts/init-storage.sh" --storage-root "$legacy_root/data"
fi
if [[ -d "$target_root" ]]; then
  "${project_root}/scripts/init-storage.sh" --storage-root "$target_root/data"
fi

node_id=$(docker node inspect self --format '{{.ID}}') || die 'could not inspect current Swarm node.'
old_label=$(docker node inspect self --format '{{index .Spec.Labels "smtp2graph_nonproduction"}}') || die 'could not inspect legacy node label.'
new_label=$(docker node inspect self --format '{{index .Spec.Labels "smtp2graph_dev"}}') || die 'could not inspect dev node label.'

if [[ "$apply" == false ]]; then
  log "PASS: migration preflight complete (legacy=${legacy_root}, target=${target_root}, old-label=${old_label:-absent}, dev-label=${new_label:-absent})."
  exit 0
fi
[[ $(id -u) -eq 0 ]] || die '--apply requires a privileged operator.'
if [[ -d "$legacy_root" && ! -e "$target_root" ]]; then
  mv -- "$legacy_root" "$target_root"
elif [[ -d "$legacy_root" && -d "$target_root" ]]; then
  die 'both legacy and dev storage roots exist; manual queue compatibility review is required.'
fi
[[ "$new_label" == true ]] || docker node update --label-add smtp2graph_dev=true "$node_id" >/dev/null
[[ -z "$old_label" ]] || docker node update --label-rm smtp2graph_nonproduction "$node_id" >/dev/null
"${project_root}/scripts/init-storage.sh" --storage-root "$SMTP2GRAPH_STORAGE_HOST_PATH" --environment development --apply
log 'PASS: legacy non-production host boundary migrated to dev.'
