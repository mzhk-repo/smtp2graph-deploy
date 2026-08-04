#!/usr/bin/env bash
# Category 2: applies reviewed upstream patch assets in an isolated build-repo worktree.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/.." && pwd)"
bundle_dir="${project_root}/patches/smtp2graph/v1.1.5"
manifest="${bundle_dir}/manifest.env"
build_repo="$(cd "${project_root}/.." && pwd)/smtp2graph-build"
mode=""
release=""
env_file=""
test_image=""

target_branch=""
do_push=0

usage() { printf 'Usage: %s [--build-repo PATH] (--release vX.Y.Z | --latest) (--check | --apply) [--env-file PATH] [--test-image NAME:TAG] [--target-branch BRANCH] [--push]\n' "$0" >&2; }
die() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
while (($#)); do
  case "$1" in
    --build-repo)
      build_repo=${2:?}
      shift 2
      ;;
    --release)
      release=${2:?}
      shift 2
      ;;
    --latest)
      release=__latest__
      shift
      ;;
    --check | --apply)
      [[ -z "$mode" ]] || die 'choose one of --check or --apply'
      mode=${1#--}
      shift
      ;;
    --env-file)
      env_file=${2:?}
      shift 2
      ;;
    --test-image)
      [[ -z "$test_image" ]] || die 'test image may be specified only once'
      test_image=${2:?}
      shift 2
      ;;
    --target-branch)
      [[ -z "$target_branch" ]] || die 'target branch may be specified only once'
      target_branch=${2:?}
      shift 2
      ;;
    --push)
      do_push=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done
[[ -n "$mode" && -n "$release" ]] || {
  usage
  exit 64
}
if [[ -n "$test_image" ]]; then
  [[ "$mode" == apply ]] || die '--test-image requires --apply'
  printf '%s\n' "$test_image" | grep -Eq '^[a-z0-9][a-z0-9._/-]*:[a-z0-9][a-z0-9._-]*$' || die 'test image must use a safe local NAME:TAG reference'
fi
if [[ -n "$target_branch" ]]; then
  [[ "$mode" == apply ]] || die '--target-branch requires --apply'
  printf '%s\n' "$target_branch" | grep -Eq '^[a-zA-Z0-9._/-]+$' || die 'target branch must use a safe branch name reference'
fi
if ((do_push)); then
  [[ -n "$target_branch" ]] || die '--push requires --target-branch'
fi
[[ -f "$manifest" && -d "$build_repo/.git" ]] || die 'bundle or build repository is unavailable'
upstream_remote=$(awk -F= '$1=="UPSTREAM_REMOTE" {print $2}' "$manifest")
[[ "$(git -C "$build_repo" remote get-url upstream)" == "$upstream_remote" ]] || die 'unexpected upstream fetch URL'
[[ "$(git -C "$build_repo" remote get-url --push upstream)" == "DISABLED" ]] || die 'upstream push URL must be DISABLED'
base_tag=$(awk -F= '$1=="BASE_TAG" {print $2}' "$manifest")
git -C "$build_repo" rev-parse -q --verify "refs/tags/${base_tag}^{commit}" >/dev/null || die 'manifest base tag is unavailable'
if [[ "$release" == __latest__ ]]; then
  release=$(git -C "$build_repo" tag --list 'v*' | awk '/^v[0-9]+\.[0-9]+\.[0-9]+$/ {print}' | sort -V | tail -n1)
  [[ -n "$release" ]] || die 'no stable upstream tag found'
fi
git -C "$build_repo" rev-parse -q --verify "refs/tags/${release}^{commit}" >/dev/null || die "unknown release: ${release}"
branch="upgrade/${release}"
if [[ "$mode" == check ]]; then
  printf 'CHECK: release=%s branch=%s bundle=%s\n' "$release" "$branch" "$bundle_dir"
  exit 0
fi
git -C "$build_repo" fetch upstream --tags --prune
if git -C "$build_repo" show-ref --verify --quiet "refs/heads/${branch}"; then
  die "existing ${branch} requires explicit patch-id review; it was not modified"
fi
worktree=$(mktemp -d "${TMPDIR:-/tmp}/smtp2graph-upgrade.XXXXXX")
cleanup() {
  status=$?
  if ((status == 0)); then
    if [[ -n "${target_branch:-}" && -d "${worktree:-}" ]]; then
      target_commit=$(git -C "$worktree" rev-parse HEAD)
      if [[ "$(git -C "$build_repo" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "$target_branch" ]]; then
        git -C "$build_repo" reset --hard "$target_commit" >/dev/null
      else
        git -C "$build_repo" branch -f "$target_branch" "$target_commit" >/dev/null
      fi
      printf 'TARGET_BRANCH: updated %s to %s in build repository\n' "$target_branch" "$target_commit"
      if ((do_push)); then
        git -C "$build_repo" push --force-with-lease origin "$target_branch" >/dev/null
        printf 'PUSH: updated remote origin/%s in build repository\n' "$target_branch"
      fi
    fi
    git -C "$build_repo" worktree remove --force "$worktree"
    git -C "$build_repo" branch -D "$branch"
  else
    printf 'FAIL: preserved worktree for review: %s\n' "$worktree" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
git -C "$build_repo" worktree add -b "$branch" "$worktree" "$release"
mapfile -t patch_assets < <(awk '/^[[:space:]]*"[A-Za-z0-9._-]+\.patch"[[:space:]]*$/ {gsub(/[[:space:]"]/, ""); print}' "$manifest")
((${#patch_assets[@]} > 0)) || die 'manifest must contain at least one safe patch asset name'
[[ "$(printf '%s\n' "${patch_assets[@]}" | sort -u | wc -l)" -eq "${#patch_assets[@]}" ]] || die 'manifest contains duplicate patch asset names'
for asset in "${patch_assets[@]}"; do
  [[ -f "${bundle_dir}/${asset}" ]] || die "missing patch asset: ${asset}"
  git -C "$worktree" apply --check --ignore-space-change "${bundle_dir}/${asset}"
  git -C "$worktree" apply --index --ignore-space-change "${bundle_dir}/${asset}"
  git -C "$worktree" -c user.name='smtp2graph patch automation' -c user.email='noreply@invalid' commit -m "Gate B: apply ${asset%.patch}"
done
(cd "$worktree" && npm ci && npm run build && npx mocha 'test/00unit/**/*.spec.ts' && npm run test:receive -- --logging error)
if [[ -n "$env_file" && -f "$env_file" ]] && rg -q '^(CLIENTID|CLIENTSECRET|CLIENTTENANT|MAILBOX|ADDITIONALRECIPIENT|DENIED_MAILBOX|AZURE_CERT_THUMBPRINT|AZURE_CERT_PRIVATE_KEY_PATH)=' "$env_file"; then
  (cd "$worktree" && DOTENV_CONFIG_PATH="$env_file" npm run test:send)
  printf 'PASS: %s passed local and Microsoft 365 regressions.\n' "$branch"
else
  printf 'PARTIAL: %s passed local regressions; Microsoft 365 suite was not explicitly requested with a complete --env-file.\n' "$branch"
fi
if [[ -n "$test_image" ]]; then
  command -v docker >/dev/null 2>&1 || die 'docker is required to build a local test image'
  docker info >/dev/null 2>&1 || die 'Docker daemon is unavailable'
  (
    cd "$worktree"
    docker build --pull=false --build-arg "VERSION=${release}" --tag "$test_image" .
  )
  printf 'TEST_IMAGE: %s\n' "$test_image"
fi
