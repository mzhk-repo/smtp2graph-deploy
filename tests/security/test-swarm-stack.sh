#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stack="$root/deploy/swarm/stack.yml"

rg -q '^    entrypoint:$' "$stack"
rg -q '^      - /run/configs/entrypoint.sh$' "$stack"
rg -Fq '        source: ${SMTP2GRAPH_STORAGE_HOST_PATH:' "$stack"
rg -q '^        target: /data$' "$stack"
rg -Fq 'node.labels.${SMTP2GRAPH_NODE_LABEL:' "$stack"
rg -q '^      restart_policy:$' "$stack"
rg -q '^      update_config:$' "$stack"
rg -q '^      rollback_config:$' "$stack"
rg -q '^    healthcheck:$' "$stack"
rg -q 'connect\(2525' "$stack"
rg -q '^    configs:$' "$stack"
rg -q '^  gateway_entrypoint:$' "$stack"
rg -q '^    external: true$' "$stack"
rg -q '^        mode: host$' "$stack"
rg -q '^      SMTP_BIND_ADDRESS: 0.0.0.0$' "$stack"
rg -q '^      QUEUE_MAX_BYTES: "1073741824"$' "$stack"
rg -q '^      QUEUE_REJECT_THRESHOLD_PERCENT: "80"$' "$stack"
if rg -q '^    build:|^    restart:|privileged:[[:space:]]*true|/var/run/docker.sock|network_mode:[[:space:]]*host|pid:[[:space:]]*host' "$stack"; then
  printf 'ERROR: stack contains a forbidden Compose or privilege field.\n' >&2
  exit 1
fi

if command -v docker >/dev/null; then
  env \
    SMTP2GRAPH_IMAGE_DIGEST='example.invalid/smtp2graph@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    SMTP2GRAPH_STORAGE_HOST_PATH=/srv/smtp2graph/dev/data \
    SMTP2GRAPH_NODE_LABEL=smtp2graph_dev \
    SMTP2GRAPH_CONFIG_VERSION=testconfig000001 \
    SMTP2GRAPH_MODE=full \
    GRAPH_AUTH_MODE=certificate \
    SMTP_MAX_MESSAGE_BYTES=26214400 \
    SMTP_MAX_SESSIONS_PER_IP=5 \
    SMTP_MESSAGES_PER_MINUTE=30 \
    SMTP_ALLOWED_SOURCE_CIDRS=10.42.0.0/24 \
    GRAPH_SENDER_MAILBOX=noreply@example.invalid \
    SEND_RETRY_LIMIT=1 \
    SEND_RETRY_INTERVAL_MINUTES=1 \
    SWARM_OVERLAY_NETWORK=smtp2graph_internal \
    GRAPH_TENANT_ID_SECRET_NAME=smtp2graph_graph_tenant_id_vtest \
    GRAPH_CLIENT_ID_SECRET_NAME=smtp2graph_graph_client_id_vtest \
    GRAPH_CERTIFICATE_THUMBPRINT_SECRET_NAME=smtp2graph_graph_certificate_thumbprint_vtest \
    GRAPH_CREDENTIAL_SECRET_NAME=smtp2graph_graph_credential_vtest \
    SMTP_CREDENTIALS_SECRET_NAME=smtp2graph_smtp_users_vtest \
    TLS_CERTIFICATE_SECRET_NAME=smtp2graph_tls_certificate_vtest \
    TLS_PRIVATE_KEY_SECRET_NAME=smtp2graph_tls_private_key_vtest \
    docker stack config -c "$stack" >/dev/null
fi

printf 'PASS: dev/prod Swarm stack has reviewed runtime, storage and security controls.\n'
