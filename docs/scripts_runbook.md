# Script runbook

## `reconcile-tls-secret.sh`

- Category: 1b (non-production deploy-adjacent TLS secret reconciliation).
- Inputs: explicit `--environment non-production`, PEM certificate/key files, and an existing mapping file. The certificate must cover `smtp-int.ldubgd.edu.ua`; the key must be owner-only `0400` or `0600`.
- Environment: `--env-file FILE` (or `ORCHESTRATOR_ENV_FILE`, then local `.env` only with warning) is strictly parsed without `source`; only the task's allowlisted keys are consumed.
- Local non-production `.env` uses `DEPLOY_ENVIRONMENT=non-production`, `SMTP_ALLOWED_SOURCE_CIDRS=<MOODLE_IPV4>/32,<OVERLAY_CIDR>`, the TLS paths, `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_DNS_API_TOKEN`. The token is a `secret-value`: it belongs only in ignored local `.env` now and `env.*.enc` after Task 4.3.
- Side effects: default mode is validation only. `--apply` stages files only in `/dev/shm`, creates deterministic immutable Docker Secrets when absent, and atomically updates the explicit mapping file. It never deploys a stack, changes DNS or firewall state.
- Safety: refuses production, symlinks, invalid/expired/mismatched PEM material and inaccessible Docker API; private material is never logged.
- Check: `./tests/security/test-reconcile-tls-secret.sh`.

## `check-network-policy.sh`

- Category: 1a (read-only non-production SMTP network-policy validation).
- Inputs: `SWARM_OVERLAY_NETWORK` and reviewed Swarm/nftables policy files.
- Safety: validates host publish mode, no routing mesh, encrypted overlay and loaded nftables allowlist/deny rule; it fails closed when Docker API access is unavailable. `0.0.0.0` listener output is not treated as public exposure by itself.

## `render-network-policy.sh`

- Category: 1b (non-production firewall policy rendering).
- Inputs: `SMTP_ALLOWED_SOURCE_CIDRS` as a comma-separated RFC1918 or explicitly approved CGNAT (`100.64.0.0/10`) IPv4 CIDR list and an explicit absolute output path.
- Safety: refuses public/IPv6 CIDR, renders from the reviewed template atomically and never applies nftables rules.

## `entrypoint.sh`

- Category: 1b (deploy-adjacent runtime configuration rendering).
- Inputs: an existing tmpfs `RUNTIME_CONFIG_DIR`, mounted Docker Secret files in `DOCKER_SECRETS_DIR`, the reviewed `deploy/config/gateway-config.yml.template`, the reviewed `scripts/lib/render-config.sh` helper, and optionally `RUNTIME_CONFIG_FILE` containing only the allowlisted non-secret keys. `RUNTIME_RENDER_HELPER_FILE` is only the explicit helper mount path when the wrapper is injected into an image. SMTP policy inputs are `SMTP_ALLOWED_SOURCE_CIDRS` and `SMTP_ALLOWED_SENDER_ADDRESSES` as non-empty unique CSV lists, positive `SMTP_MAX_SESSIONS_PER_IP`, and positive `SMTP_MESSAGES_PER_MINUTE`, rendered with a fixed 60-second window. The bounded persistent queue inputs are an absolute non-root `SMTP2GRAPH_STORAGE_ROOT`, positive `QUEUE_MAX_BYTES` and `QUEUE_REJECT_THRESHOLD_PERCENT` from 1 through 100. The required `smtp-users` Docker Secret uses one strict TSV record per line: `username<TAB>password<TAB>sender1@example.invalid,sender2@example.invalid`.
- Side effects: atomically writes `config.yml` with mode `0600` only inside `RUNTIME_CONFIG_DIR`; in `run` mode it starts the gateway through its image-provided `startup.sh`.
- Safety: POSIX `/bin/sh` compatible; does not source input files; requires SMTP AUTH, source-IP and sender allowlists, and rejects unknown keys, missing/non-regular secrets, group/other-writable secrets, owners outside `DOCKER_SECRET_ALLOWED_UIDS` (default: root and runtime UID), malformed/duplicate TSV users and user-specific senders outside the global allowlist. Emails are normalized to lowercase; diagnostics redact credentials.
- Check: `sh -n scripts/entrypoint.sh`, `shellcheck scripts/entrypoint.sh`, `./tests/shell/test-render-config.sh`, `./tests/shell/test-entrypoint.sh`, `./tests/acceptance/runtime/run.sh`.
- Rollback: restore the prior reviewed wrapper and template together; do not reuse rendered config outside its tmpfs mount.

## `upgrade-smtp2graph-fork.sh`

- Category: 2 (manual maintenance with Git ref/worktree side effects).
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file, optional safe local `--test-image NAME:TAG`. Без explicit `--env-file` script не читає build-plane `.env` і не запускає M365 suite.
- Side effects: fetches upstream tags, creates a temporary local `upgrade/vX.Y.Z` branch and worktree. With `--test-image`, after successful local regressions it builds a local Docker image from this worktree; the caller removes that image. On success automation removes the worktree and branch; on failure it preserves them for review. It never pushes, deploys, deletes an existing branch or resolves conflicts.
- Check: `--check` validates release selection without creating a branch.
- Rollback: on a failed run, remove only the explicitly reviewed local `upgrade/vX.Y.Z` branch after confirming it is not checked out; upstream v1.1.5 is not a production rollback target.

## `tests/smoke/run.sh`

- Category: 1a (isolated local functional verification).
- Inputs: reviewed `compose.test.yaml`, versioned patch bundle, local build-plane Git checkout, protocol MIME fixture and synthetic runtime files generated only in `/dev/shm`.
- Side effects: runs patch replay/regressions, builds a temporary local image, starts an internal Compose network with a mock Graph, publishes SMTP only on loopback and creates synthetic queue state. It validates positive, unauthenticated, denied-sender, oversize and queue-restart flows.
- Safety: does not read `.env` or M365 credentials; no production network, deployment, persistent queue or GHCR push. A trap removes Compose resources, local image and all temporary material after success or failure.
- Check: `make test-local`.
- Rollback: the harness is disposable; inspect failure logs, then rerun after fixing the reviewed test/configuration change.

## `purge-failed.sh`

- Category: 2 (autonomous failed-payload retention maintenance).
- Inputs: `SMTP2GRAPH_STORAGE_ROOT` (default `/data`) and explicit `--dry-run` or `--apply`. The retention is fixed at seven days; the script targets only the validated direct child `${SMTP2GRAPH_STORAGE_ROOT}/failed`.
- Side effects: `--dry-run` is the default and only reports the eligible count. `--apply` removes regular files at least seven full days old; it never follows symlinks, removes directories or accesses `${SMTP2GRAPH_STORAGE_ROOT}/queue`.
- Safety: rejects `/`, missing or symlinked storage/failed roots, cross-device traversal and unsupported arguments. File names are not emitted to logs.
- Check: `./tests/shell/test-purge-failed.sh`, `./tests/security/test-purge-failed.sh`, `shellcheck scripts/purge-failed.sh`.
- Rollback: no automated restore exists; use dry-run before apply and restore only from an approved recovery source if retention was configured incorrectly.
