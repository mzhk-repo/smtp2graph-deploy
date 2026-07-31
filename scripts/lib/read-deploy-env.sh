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
    printf 'WARNING: using local .env only for development.\n' >&2
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

expected_server_env() {
  case "$1" in
    development) printf '%s\n' dev ;;
    production) printf '%s\n' prod ;;
    *)
      printf 'ERROR: DEPLOY_ENVIRONMENT must be development or production.\n' >&2
      return 64
      ;;
  esac
}

read_server_env() {
  local path=${SMTP2GRAPH_SERVER_ENV_FILE:-/etc/environment} line key value server_env=''
  [[ "$path" = /* && -f "$path" && ! -L "$path" ]] || {
    printf 'ERROR: server environment file must be an absolute regular non-symlink file.\n' >&2
    return 64
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || continue
    key=${BASH_REMATCH[1]}
    value=${BASH_REMATCH[2]}
    [[ "$key" == SERVER_ENV ]] || continue
    [[ -z "$server_env" ]] || {
      printf 'ERROR: duplicate SERVER_ENV in server environment file.\n' >&2
      return 64
    }
    server_env=$value
  done <"$path"
  [[ "$server_env" == dev || "$server_env" == prod ]] || {
    printf 'ERROR: SERVER_ENV must be dev or prod.\n' >&2
    return 64
  }
  printf '%s\n' "$server_env"
}

require_server_env_match() {
  local deployment_environment=$1 expected actual
  expected=$(expected_server_env "$deployment_environment") || return
  actual=$(read_server_env) || return
  [[ "$actual" == "$expected" ]] || {
    printf 'ERROR: host SERVER_ENV=%s does not match DEPLOY_ENVIRONMENT=%s.\n' "$actual" "$deployment_environment" >&2
    return 64
  }
}
