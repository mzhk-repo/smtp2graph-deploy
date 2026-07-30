#!/usr/bin/env bash
# Strict parser for deploy-adjacent environment files; never source this file.

resolve_deploy_env_file() {
  local root=$1 requested=$2
  if [[ -n "$requested" ]]; then
    printf '%s\n' "$requested"
    return
  fi
  if [[ -n "${ORCHESTRATOR_ENV_FILE:-}" ]]; then
    printf '%s\n' "$ORCHESTRATOR_ENV_FILE"
    return
  fi
  if [[ -f "$root/.env" ]]; then
    printf 'WARNING: using local .env only for non-production.\n' >&2
    printf '%s\n' "$root/.env"
    return
  fi
  return 1
}

load_deploy_env_file() {
  local root=$1 requested=$2 file line key value allowed item
  declare -A seen=()
  shift 2
  file=$(resolve_deploy_env_file "$root" "$requested") || return 0
  [[ "$file" = /* && -f "$file" && ! -L "$file" ]] || {
    printf 'ERROR: env file must be an absolute regular non-symlink file.\n' >&2
    return 64
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || {
      printf 'ERROR: invalid env syntax.\n' >&2
      return 64
    }
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    allowed=false
    for item in "$@"; do [[ "$key" == "$item" ]] && {
      allowed=true
      break
    }; done
    "$allowed" || continue
    [[ -v "seen[$key]" ]] && {
      printf 'ERROR: duplicate env key: %s.\n' "$key" >&2
      return 64
    }
    seen["$key"]=1
    printf -v "$key" '%s' "$value"
  done <"$file"
}
