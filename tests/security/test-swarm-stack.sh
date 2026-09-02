#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
stack="$root/deploy/swarm/stack.yml"

grep -Eq '^    entrypoint:$' "$stack"
grep -Eq '^      - /run/configs/entrypoint.sh$' "$stack"
grep -Fq '        source: ${SMTP2GRAPH_STORAGE_HOST_PATH:' "$stack"
grep -Eq '^        target: /data$' "$stack"
grep -Eq '^      restart_policy:$' "$stack"
grep -Eq '^      update_config:$' "$stack"
grep -Eq '^      rollback_config:$' "$stack"
grep -Eq '^    healthcheck:$' "$stack"
grep -Fq '127.0.0.1:9464/readyz' "$stack"
grep -Eq '^    logging:$' "$stack"
grep -Eq '^      driver: local$' "$stack"
grep -Eq '^        max-size: "10m"$' "$stack"
grep -Eq '^        max-file: "30"$' "$stack"
grep -Eq '^    configs:$' "$stack"
grep -Eq '^  gateway_entrypoint:$' "$stack"
grep -Eq '^    external: true$' "$stack"
grep -Eq '^        mode: host$' "$stack"
grep -Eq '^      SMTP_BIND_ADDRESS: 0.0.0.0$' "$stack"
grep -Eq '^      QUEUE_MAX_BYTES: "1073741824"$' "$stack"
grep -Eq '^      QUEUE_REJECT_THRESHOLD_PERCENT: "80"$' "$stack"
if grep -Eq 'target: 9464|published: 9464' "$stack"; then
  printf 'ERROR: observability endpoint must not be host-published.\n' >&2
  exit 1
fi
if grep -Eq '^    build:|^    restart:|privileged:[[:space:]]*true|/var/run/docker.sock|network_mode:[[:space:]]*host|pid:[[:space:]]*host' "$stack"; then
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
    SMTP_TLS_FQDN=smtp-int.example.invalid \
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
