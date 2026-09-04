#!/usr/bin/env bash
set -euo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
for key in SMTP2GRAPH_PROJECT_ROOT SMTP2GRAPH_ENV_FILE SOPS_AGE_KEY_FILE; do
  [[ -n "${!key:-}" ]] || die "missing systemd renewal setting: $key."
done
[[ "$SMTP2GRAPH_PROJECT_ROOT" = /* && -d "$SMTP2GRAPH_PROJECT_ROOT" && ! -L "$SMTP2GRAPH_PROJECT_ROOT" ]] || die 'SMTP2GRAPH_PROJECT_ROOT is unsafe.'
[[ "$SMTP2GRAPH_ENV_FILE" = /* && -f "$SMTP2GRAPH_ENV_FILE" && ! -L "$SMTP2GRAPH_ENV_FILE" ]] || die 'SMTP2GRAPH_ENV_FILE is unsafe.'
[[ "$SOPS_AGE_KEY_FILE" = /* && -f "$SOPS_AGE_KEY_FILE" && ! -L "$SOPS_AGE_KEY_FILE" ]] || die 'SOPS_AGE_KEY_FILE is unsafe.'
script="$SMTP2GRAPH_PROJECT_ROOT/scripts/renew-tls-certificate.sh"
[[ -x "$script" && ! -L "$script" ]] || die 'TLS renewal script is unavailable.'
exec "$script" --env-file "$SMTP2GRAPH_ENV_FILE" --apply
