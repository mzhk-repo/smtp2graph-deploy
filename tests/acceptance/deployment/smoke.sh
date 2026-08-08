#!/usr/bin/env bash
# Category 1a: read-only live Swarm and SMTP readiness verification for Task 5.4.
set -euo pipefail

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

stack_name='smtp2graph'
smtp_host='127.0.0.1'
smtp_port='2525'

while (($#)); do
  case "$1" in
    --stack-name)
      stack_name=${2:-}
      shift 2
      ;;
    --smtp-host)
      smtp_host=${2:-}
      shift 2
      ;;
    --smtp-port)
      smtp_port=${2:-}
      shift 2
      ;;
    -h | --help)
      printf '%s\n' 'Usage: smoke.sh [--stack-name NAME] [--smtp-host HOST] [--smtp-port PORT]'
      exit 0
      ;;
    *) die "unsupported argument: $1" ;;
  esac
done

[[ "$stack_name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$ ]] || die 'stack name is unsafe.'
[[ "$smtp_host" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,253}$ ]] || die 'SMTP host is unsafe.'
if ! [[ "$smtp_port" =~ ^[0-9]{1,5}$ ]] || ((smtp_port < 1 || smtp_port > 65535)); then die 'SMTP port is invalid.'; fi
for tool in docker timeout bash; do command -v "$tool" >/dev/null || die "$tool is required."; done

service="${stack_name}_gateway"
replicas=$(docker service inspect "$service" --format '{{.Spec.Mode.Replicated.Replicas}}') || die 'gateway service is unavailable.'
[[ "$replicas" == 1 ]] || die 'gateway service must declare exactly one replica.'

mapfile -t tasks < <(docker service ps "$service" --filter desired-state=running --format '{{.CurrentState}}|{{.Error}}')
[[ ${#tasks[@]} -eq 1 ]] || die 'gateway must have exactly one desired running task.'
[[ "${tasks[0]}" == Running*'|' ]] || die 'gateway desired task is not Running or reports an error.'

secret_spec=$(docker service inspect "$service" --format '{{range .Spec.TaskTemplate.ContainerSpec.Secrets}}{{.File.Name}} {{.File.UID}} {{.File.GID}} {{printf "%#o" .File.Mode}}{{"\n"}}{{end}}') || die 'could not inspect gateway Secret mount metadata.'
require_secret_mode() {
  local name=$1 mode=$2
  printf '%s\n' "$secret_spec" | rg -q "^${name} 65532 65532 ${mode}$" || die "required Secret mount mode is invalid: ${name}."
}
require_secret_mode graph-tenant-id 0444
require_secret_mode graph-client-id 0444
require_secret_mode graph-certificate-thumbprint 0444
require_secret_mode graph-credential 0400
require_secret_mode smtp-users 0400
require_secret_mode smtp-tls-cert 0444
require_secret_mode smtp-tls-key 0400

# shellcheck disable=SC2016 # $1/$2 and $line expand inside the isolated Bash process.
greeting=$(timeout 10 bash -c 'exec 3<>"/dev/tcp/$1/$2"; IFS= read -r line <&3; printf "%s" "$line"; exec 3>&- 3<&-' _ "$smtp_host" "$smtp_port") || die 'SMTP connection failed.'
[[ "$greeting" == 220* ]] || die 'SMTP listener did not return a 220 greeting.'
printf 'PASS: gateway task, SMTP greeting and Secret mount metadata are valid.\n'
