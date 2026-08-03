#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$root/tests/acceptance/deployment/smoke.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-} ${2:-}" in
  'service inspect')
    if [[ "$*" == *'.Spec.Mode.Replicated.Replicas'* ]]; then printf '%s\n' 1
    else printf '%s\n' \
      'graph-tenant-id 65532 65532 292' 'graph-client-id 65532 65532 292' \
      'graph-certificate-thumbprint 65532 65532 292' 'graph-credential 65532 65532 256' \
      'smtp-users 65532 65532 256' 'smtp-tls-cert 65532 65532 292' 'smtp-tls-key 65532 65532 256'; fi
    ;;
  'service ps') printf '%s\n' 'Running 1 second ago|' ;;
  *) exit 1 ;;
esac
EOF
cat >"$fake_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
shift
printf '220 smtp2graph ESMTP\r\n'
EOF
chmod 700 "$fake_bin/docker" "$fake_bin/timeout"

PATH="$fake_bin:$PATH" "$script" --stack-name smtp2graph --smtp-host 127.0.0.1 --smtp-port 2525 >/dev/null
printf 'PASS: deployment smoke validates service, secret metadata and SMTP greeting.\n'
