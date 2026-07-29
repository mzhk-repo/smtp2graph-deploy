# Script runbook

## `entrypoint.sh`

- Category: 1b (deploy-adjacent runtime configuration rendering).
- Inputs: an existing tmpfs `RUNTIME_CONFIG_DIR`, mounted Docker Secret files in `DOCKER_SECRETS_DIR`, the reviewed `deploy/config/gateway-config.yml.template`, the reviewed `scripts/lib/render-config.sh` helper, and optionally `RUNTIME_CONFIG_FILE` containing only the allowlisted non-secret keys. `RUNTIME_RENDER_HELPER_FILE` is only the explicit helper mount path when the wrapper is injected into an image. SMTP policy inputs are `SMTP_ALLOWED_SOURCE_CIDRS` and `SMTP_ALLOWED_SENDER_ADDRESSES` as non-empty unique CSV lists. The bounded persistent queue inputs are an absolute non-root `SMTP2GRAPH_STORAGE_ROOT`, positive `QUEUE_MAX_BYTES` and `QUEUE_REJECT_THRESHOLD_PERCENT` from 1 through 100. The required `smtp-users` Docker Secret uses one strict TSV record per line: `username<TAB>password<TAB>sender1@example.invalid,sender2@example.invalid`.
- Side effects: atomically writes `config.yml` with mode `0600` only inside `RUNTIME_CONFIG_DIR`; in `run` mode it starts the gateway through its image-provided `startup.sh`.
- Safety: POSIX `/bin/sh` compatible; does not source input files; requires SMTP AUTH, source-IP and sender allowlists, and rejects unknown keys, missing/non-regular secrets, group/other-writable secrets, owners outside `DOCKER_SECRET_ALLOWED_UIDS` (default: root and runtime UID), malformed/duplicate TSV users and user-specific senders outside the global allowlist. Emails are normalized to lowercase; diagnostics redact credentials.
- Check: `sh -n scripts/entrypoint.sh`, `shellcheck scripts/entrypoint.sh`, `./tests/shell/test-render-config.sh`, `./tests/shell/test-entrypoint.sh`, `./tests/acceptance/runtime/run.sh`.
- Rollback: restore the prior reviewed wrapper and template together; do not reuse rendered config outside its tmpfs mount.

## `upgrade-smtp2graph-fork.sh`

- Category: 2 (manual maintenance with Git ref/worktree side effects).
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file. Без explicit `--env-file` script не читає build-plane `.env` і не запускає M365 suite.
- Side effects: fetches upstream tags, creates a temporary local `upgrade/vX.Y.Z` branch and worktree. On success it removes both; on failure it preserves them for review. It never pushes, deploys, deletes an existing branch or resolves conflicts.
- Check: `--check` validates release selection without creating a branch.
- Rollback: on a failed run, remove only the explicitly reviewed local `upgrade/vX.Y.Z` branch after confirming it is not checked out; upstream v1.1.5 is not a production rollback target.

## `purge-failed.sh`

- Category: 2 (autonomous failed-payload retention maintenance).
- Inputs: `SMTP2GRAPH_STORAGE_ROOT` (default `/data`) and explicit `--dry-run` or `--apply`. The retention is fixed at seven days; the script targets only the validated direct child `${SMTP2GRAPH_STORAGE_ROOT}/failed`.
- Side effects: `--dry-run` is the default and only reports the eligible count. `--apply` removes regular files at least seven full days old; it never follows symlinks, removes directories or accesses `${SMTP2GRAPH_STORAGE_ROOT}/queue`.
- Safety: rejects `/`, missing or symlinked storage/failed roots, cross-device traversal and unsupported arguments. File names are not emitted to logs.
- Check: `./tests/shell/test-purge-failed.sh`, `./tests/security/test-purge-failed.sh`, `shellcheck scripts/purge-failed.sh`.
- Rollback: no automated restore exists; use dry-run before apply and restore only from an approved recovery source if retention was configured incorrectly.
