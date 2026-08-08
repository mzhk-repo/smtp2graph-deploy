# Script runbook

## `ci-deploy-swarm.sh`

- Category: 1b (CI-to-Swarm deployment adapter).
- Inputs: the shared workflow provides an absolute `ORCHESTRATOR_ENV_FILE`, `ENVIRONMENT_NAME`, immutable image digest in the env contract, and production-only release tag, approval context and control-plane SHA.
- Side effects: invokes only the reviewed `deploy-orchestrator-swarm.sh --env-file ... --deploy --apply` contract. It never builds, pushes, resolves tags, changes Secrets or bypasses host/environment guards.
- Safety: development rejects production context. Production rejects missing or malformed tag, approval context or SHA before invoking the orchestrator.
- Check: `bash -n scripts/ci-deploy-swarm.sh`, `./tests/shell/test-ci-deploy-swarm.sh`.

## `deploy-orchestrator-swarm.sh`

- Category: 1b (dev/prod Swarm orchestration).
- Inputs: decrypts the selected SOPS-encrypted Dotenv contract only into `/dev/shm`, strictly parses allowlisted public stack inputs and resolves `TLS_SECRET_MAPPING_FILE`. It then requires a private names-only mapping with all seven versioned Docker Secret references and merges those references over the decrypted deployment config. The loader never sources either file; host `SERVER_ENV=dev|prod` remains mandatory.
- Operations: `--check` renders and validates the canonical stack without Docker API mutation. Both environments derive the placement label from `DEPLOY_ENVIRONMENT` (`smtp2graph_dev=true` or `smtp2graph_prod=true`). Development `--deploy --apply` uses local `.env` fallback after `SERVER_ENV=dev` verification and invokes `init-storage.sh` before stack submission. Production requires `SERVER_ENV=prod`, immutable digest, `--release-tag`, `--approval-context` and a matching `--declared-deploy-ref` SHA. Rollback also requires queue-compatibility confirmation and initializes the reviewed storage boundary before submitting the stack.
- Safety: missing, incomplete, duplicate, unsafe or owner-readable-by-group/other Secret mappings fail closed. Only immutable `@sha256:` image references and safe stack/Secret/network names are accepted. The script does not use `--prune` and never deletes stacks, services, networks, configs, Secrets or queue data.
- Idempotency: repeated deploy submits the same declarative stack without cleanup or new generated state; Docker Swarm reconciles it to the declared state.
- Check: `./tests/shell/test-deploy-orchestrator.sh`, `shellcheck scripts/deploy-orchestrator-swarm.sh`, `bash -n scripts/deploy-orchestrator-swarm.sh`.
- Rollback: first assess queue compatibility, then select an explicit previously approved digest. Verify service state, live network policy and synthetic SMTP delivery before closing the rollback change.

## `reconcile-sops-secrets.sh`

- Category: 1b (SOPS + age Docker Secret reconciliation).
- Inputs: explicit absolute Dotenv-format `--env-file` encrypted by SOPS and an existing absolute `--mapping-file`. It extracts only the required encrypted Graph, SMTP and TLS values; values are never logged or sourced by a shell.
- Side effects: default mode validates and emits versioned Secret names only. `--apply` requires matching `SERVER_ENV`; production additionally needs an approval context. It decrypts only into a mode-`0700` directory under `/dev/shm`, creates missing immutable Docker Secrets and atomically updates the names-only mapping file.
- Rotation: update the encrypted value, run validation, apply to create the new content-addressed Secret, deploy through the future approved Task 5.2 orchestration, complete smoke verification, then remove the prior Secret only by an explicitly approved cleanup operation.
- Rollback: restore the explicit prior names-only mapping and redeploy after queue assessment. The reconciler never removes an existing Docker Secret.
- Check: `./tests/security/test-reconcile-sops-secrets.sh`.

## `rehearse-deployment.sh`

- Category: 1b (development deployment lifecycle rehearsal).
- Inputs: explicit development env-file, two Task 5.3-approved immutable digests, an exact pair in `deploy/config/queue-compatibility.yml`, exact allowlisted non-production recipient, SMTP username, runner-owned mode-`0600` password file under `/dev/shm`, backup reference and operator-only evidence directory.
- Side effects: performs explicit development deploy/upgrade/rollback; creates one temporary synthetic invalid Graph credential Docker Secret and a mode-`0600` temporary env-file under `/dev/shm`; submits one synthetic SMTP message. It restores the original Secret mapping before removing its own temporary Secret.
- Safety: refuses production, tags, unknown evidence/compatibility metadata, recipient outside allowlist, unsafe password/evidence paths and unsafe storage. It never reads Docker Secret content, puts passwords in arguments/logs or automatically deletes mailbox data.
- Rollback: the service model is At-Least-Once under recovery. Freeze acceptance, use only a declared compatible pair, preserve queue state and verify the emitted `X-Rehearsal-ID` with a read-only mailbox query.
- Check: `./tests/shell/test-rehearse-deployment.sh`, `bash -n scripts/rehearse-deployment.sh`.
- Current Task 5.4 scope: this script is retained for a future two-release compatibility rehearsal and must not be run for the current single-release development smoke.

## `init-storage.sh`

- Category: 1b (dev/prod persistent-storage initialization).
- Inputs: explicit canonical `--storage-root`; it must be an absolute non-symlink directory, or have an existing non-symlink ancestor below `/` when `--apply` initializes it. Only the validated root and its direct `queue` and `failed` children are in scope.
- Side effects: default mode is validation-only. `--apply` requires `--environment development|production`, matching `SERVER_ENV`, a privileged operator, and corrects the root plus direct children to UID/GID `65532` and mode `0700` without recursive ownership changes. The runtime can then create its required direct `/data/temp` path.
- Safety: refuses `/`, symlink components, recursive ownership changes and non-empty child directories with incompatible owner/mode; it does not traverse, log or mutate message payloads.
- Rollback: no automatic ownership rollback. Restore the explicit prior ownership only after a queue/recovery review.
- Check: `./tests/security/test-container-hardening.sh`.

## `bootstrap-swarm-host.sh`

- Category: 1b (dev/prod Swarm host bootstrap).
- Inputs: strict-parsed development `.env` or explicit production env-file з `DEPLOY_ENVIRONMENT=development|production`, `SWARM_OVERLAY_NETWORK`, `SMTP2GRAPH_STORAGE_HOST_PATH`, private/approved `SMTP_ALLOWED_SOURCE_CIDRS` і matching host `SERVER_ENV`; node label деривується з environment.
- Side effects: default/`--check` є read-only. Explicit `--apply` вимагає Swarm manager і privileged operator, створює лише missing encrypted overlay, current-node label `smtp2graph_dev=true` або `smtp2graph_prod=true`, storage root/direct children та atomically applies rendered nftables table. Production additionally needs `--approval-context`.
- Safety: відмовляється від production, public CIDR, unsafe network name, non-manager Docker access, unencrypted existing overlay, symlinked/root storage path і не робить stack deploy, Secret reconciliation чи cleanup.
- Check: `./tests/security/test-bootstrap-swarm-host.sh`.

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
- Inputs: `SWARM_OVERLAY_NETWORK` and reviewed `deploy/swarm/stack.yml`/nftables policy files.
- Safety: validates host publish mode, no routing mesh, encrypted overlay and loaded nftables allowlist/deny rule; it fails closed when Docker API access is unavailable. `0.0.0.0` listener output is not treated as public exposure by itself.

## `render-network-policy.sh`

- Category: 1b (non-production firewall policy rendering).
- Inputs: `SMTP_ALLOWED_SOURCE_CIDRS` as a comma-separated RFC1918 or explicitly approved CGNAT (`100.64.0.0/10`) IPv4 CIDR list and an explicit absolute output path.
- Safety: refuses public/IPv6 CIDR, renders from the reviewed template atomically and never applies nftables rules.

## `entrypoint.sh`

- Category: 1b (deploy-adjacent runtime configuration rendering).
- Inputs: an existing tmpfs `RUNTIME_CONFIG_DIR`, mounted Docker Secret files in `DOCKER_SECRETS_DIR`, the reviewed `deploy/config/gateway-config.yml.template`, the reviewed `scripts/lib/render-config.sh` helper, and optionally `RUNTIME_CONFIG_FILE` containing only the allowlisted non-secret keys. `RUNTIME_RENDER_HELPER_FILE` is only the explicit helper mount path when the wrapper is injected into an image. `GRAPH_SENDER_MAILBOX` is the canonical single-mailbox runtime sender; deploy derives the global SMTP sender allowlist from it. SMTP policy also requires `SMTP_ALLOWED_SOURCE_CIDRS`, positive `SMTP_MAX_SESSIONS_PER_IP`, and positive `SMTP_MESSAGES_PER_MINUTE`, rendered with a fixed 60-second window. The bounded persistent queue inputs are an absolute non-root `SMTP2GRAPH_STORAGE_ROOT`, positive `QUEUE_MAX_BYTES` and `QUEUE_REJECT_THRESHOLD_PERCENT` from 1 through 100. The required `smtp-users` Docker Secret uses one strict TSV record per line: `username<TAB>password<TAB>sender1@example.invalid,sender2@example.invalid`; for the current MVP its sender scope must equal `GRAPH_SENDER_MAILBOX`.
- Side effects: atomically writes `config.yml` with mode `0600` only inside `RUNTIME_CONFIG_DIR`; in `run` mode it starts the gateway through its image-provided `startup.sh`.
- Safety: POSIX `/bin/sh` compatible; does not source input files; requires SMTP AUTH, source-IP and sender allowlists, and rejects unknown keys, missing/non-regular secrets, group/other-writable secrets, owners outside `DOCKER_SECRET_ALLOWED_UIDS` (default: root and runtime UID), malformed/duplicate TSV users and user-specific senders outside the global allowlist. Emails are normalized to lowercase; diagnostics redact credentials.
- Check: `sh -n scripts/entrypoint.sh`, `shellcheck scripts/entrypoint.sh`, `./tests/shell/test-render-config.sh`, `./tests/shell/test-entrypoint.sh`, `./tests/acceptance/runtime/run.sh`.
- Rollback: restore the prior reviewed wrapper and template together; do not reuse rendered config outside its tmpfs mount.

## `upgrade-smtp2graph-fork.sh`

- Category: 2 (manual maintenance with Git ref/worktree side effects).
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file, optional safe local `--test-image NAME:TAG`, optional `--target-branch BRANCH`, optional `--push`. `GRAPH_SENDER_MAILBOX` is the canonical sender for qualification; the script passes its legacy `MAILBOX` alias only to the fork test process. `ADDITIONALRECIPIENT` and `DENIED_MAILBOX` remain distinct positive/negative qualification inputs. Без explicit `--env-file` script не читає build-plane `.env` і не запускає M365 suite.
- Side effects: fetches upstream tags, creates a temporary local `upgrade/vX.Y.Z` branch and worktree. With `--target-branch BRANCH`, upon 100% successful local regressions it updates/creates the target branch in the build repository to point to the patched commit before removing the temporary worktree. With `--push`, it additionally performs `git push --force-with-lease origin BRANCH` in the build repository. With `--test-image`, after successful local regressions it builds a local Docker image from this worktree; the caller removes that image. On success automation removes the worktree and temporary branch; on failure it preserves them for review. It never deploys, deletes an existing branch or resolves conflicts.
- Check: `--check` validates release selection without creating a branch.
- Examples:
  - Check release availability: `./scripts/upgrade-smtp2graph-fork.sh --build-repo /opt/smtp2graph-build --release v1.1.5 --check`
  - Apply patches and run local regressions: `./scripts/upgrade-smtp2graph-fork.sh --build-repo /opt/smtp2graph-build --release v1.1.5 --apply`
  - Apply patches and update target build-repo branch: `./scripts/upgrade-smtp2graph-fork.sh --build-repo /opt/smtp2graph-build --release v1.1.5 --apply --target-branch v1.1.6`
  - Apply patches, update branch and force push to origin: `./scripts/upgrade-smtp2graph-fork.sh --build-repo /opt/smtp2graph-build --release v1.1.5 --apply --target-branch v1.1.6 --push`
  - Apply patches and build local test image: `./scripts/upgrade-smtp2graph-fork.sh --build-repo /opt/smtp2graph-build --release v1.1.5 --apply --test-image smtp2graph-test:local`
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
