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

usage() { printf 'Usage: %s [--build-repo PATH] (--release vX.Y.Z | --latest) (--check | --apply) [--env-file PATH]\n' "$0" >&2; }
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
[[ -f "$manifest" && -d "$build_repo/.git" ]] || die 'bundle or build repository is unavailable'
[[ "$(git -C "$build_repo" remote get-url upstream)" == "https://github.com/SMTP2Graph/SMTP2Graph" ]] || die 'unexpected upstream fetch URL'
[[ "$(git -C "$build_repo" remote get-url --push upstream)" == "DISABLED" ]] || die 'upstream push URL must be DISABLED'
base_tag=$(awk -F= '$1=="BASE_TAG" {print $2}' "$manifest")
base_object=$(awk -F= '$1=="BASE_TAG_OBJECT" {print $2}' "$manifest")
base_commit=$(awk -F= '$1=="BASE_COMMIT" {print $2}' "$manifest")
[[ "$(git -C "$build_repo" rev-parse "$base_tag")" == "$base_object" ]] || die 'base annotated tag object differs from manifest'
[[ "$(git -C "$build_repo" rev-parse "${base_tag}^{commit}")" == "$base_commit" ]] || die 'base peeled commit differs from manifest'
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
  printf 'INFO: existing branch %s will be retested; patch-id review remains manual.\n' "$branch"
fi
worktree=$(mktemp -d "${TMPDIR:-/tmp}/smtp2graph-upgrade.XXXXXX")
cleanup() {
  status=$?
  if ((status == 0)); then git -C "$build_repo" worktree remove --force "$worktree"; else printf 'FAIL: preserved worktree for review: %s\n' "$worktree" >&2; fi
  exit "$status"
}
trap cleanup EXIT
if git -C "$build_repo" show-ref --verify --quiet "refs/heads/${branch}"; then git -C "$build_repo" worktree add "$worktree" "$branch"; else git -C "$build_repo" worktree add -b "$branch" "$worktree" "$release"; fi
if ! git -C "$worktree" log -1 --format=%B | grep -q 'Gate B: qualification regressions'; then
  for key in PATCH_001 PATCH_002 PATCH_003 PATCH_004; do
    line=$(awk -F= -v key="$key" '$1==key {print substr($0, length(key)+2)}' "$manifest")
    IFS='|' read -r asset expected_hash message <<<"$line"
    actual_hash=$(sha256sum "${bundle_dir}/${asset}" | awk '{print $1}')
    [[ "$actual_hash" == "$expected_hash" ]] || die "checksum mismatch: ${asset}"
    git -C "$worktree" apply --check "${bundle_dir}/${asset}"
    git -C "$worktree" apply --index "${bundle_dir}/${asset}"
    git -C "$worktree" -c user.name='smtp2graph patch automation' -c user.email='noreply@invalid' commit -m "$message"
  done
fi
(cd "$worktree" && npm ci && npm run build && npx mocha 'test/00unit/**/*.spec.ts' && npm run test:receive -- --logging error)
env_file=${env_file:-"${build_repo}/.env"}
if [[ -f "$env_file" ]] && rg -q '^(CLIENTID|CLIENTSECRET|CLIENTTENANT|MAILBOX|ADDITIONALRECIPIENT|DENIED_MAILBOX|AZURE_CERT_THUMBPRINT|AZURE_CERT_PRIVATE_KEY_PATH)=' "$env_file"; then
  (cd "$worktree" && DOTENV_CONFIG_PATH="$env_file" npm run test:send)
  printf 'PASS: %s passed local and Microsoft 365 regressions.\n' "$branch"
else
  printf 'PARTIAL: %s passed local regressions; Microsoft 365 inputs are incomplete.\n' "$branch"
fi
