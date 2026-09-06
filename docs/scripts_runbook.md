# Script runbook

## `prepare-certificate-env.sh`

- Category: 1b (certificate bootstrap and manual rotation).
- Inputs: explicit SOPS env and optional absolute staging path. `--apply` is required only for Graph certificate issuance/generation; `--rotate-graph` is explicit.
- Side effects: writes only Graph certificate/key staging material to ignored mode-`0600` `.env.certificates`; STARTTLS is owned by `renew-tls-certificate.sh`.
- Safety: all decrypted values and Cloudflare credentials are staged only in `/dev/shm`; PEM values are never printed. A pending staging file is reused rather than silently replaced.
- Check: `./tests/security/test-prepare-certificate-env.sh`, `bash -n scripts/prepare-certificate-env.sh`.
- Follow [`CERTIFICATE_RUNBOOK.md`](CERTIFICATE_RUNBOOK.md) for Entra onboarding, SOPS handoff, rotation, and staging deletion.

## `renew-tls-certificate.sh`

- Category: 2 (scheduled ACME maintenance).
- Inputs: SOPS-encrypted deployment contract, Certbot DNS-01 token, local Certbot lineage and names-only Docker Secret mapping. Host paths are read from the contract; systemd passes only validated project/env/age-key paths through `/etc/smtp2graph/tls-renewal.env`.
- Side effects: `--apply` renews when due, creates missing immutable TLS Secrets, updates only `smtp-tls-cert`/`smtp-tls-key` service mounts and atomically records names after a matching STARTTLS fingerprint probe. `--prepare-only` does not require a service update.
- Safety: a `/dev/shm` lock and protected temporary Cloudflare credentials prevent overlap or persistence; failed update/probe requests a Swarm rollback. The script never prints PEM values or removes old Secrets.
- Check: `./tests/security/test-renew-tls-certificate.sh`, `bash -n scripts/renew-tls-certificate.sh`.

## `backup.sh` / `restore.sh`

- Category: 2 (manual backup and cold-recovery automation).
- Inputs: explicit `--environment`, SOPS-encrypted `--env-file`, and backup destinations only from the encrypted contract. Restore additionally requires a local archive or a safe rclone archive name, a new/empty absolute target and exact `--confirm-target`.
- Side effects: `backup.sh --apply` creates a checksum-paired allowlisted archive locally and in rclone, then applies 7-local/30-cloud retention. `restore.sh --apply` extracts only a verified control-plane bundle and never deploys.
- Safety: no `source`; age/rclone credentials, Docker Secret payloads, queue, failed payloads and logs are excluded. Restore never overwrites an active host/storage root. Ansible owns scheduling outside this repository.
- Check: `./tests/recovery/cold-restore.sh`, `bash -n scripts/backup.sh scripts/restore.sh`.
- Manual backup validation (does not create files or contact rclone):
  ```bash
  ./scripts/backup.sh --environment development \
    --env-file /opt/smtp2graph-deploy/env.dev.enc --check
  ```
- Manual backup apply: creates the local archive, uploads it to the configured `gdrive-backup:smtp2graph/dev` path and rotates only recognized archive/checksum pairs. Run only through the approved Ansible/operator procedure that provides the age identity:
  ```bash
  ./scripts/backup.sh --environment development \
    --env-file /opt/smtp2graph-deploy/env.dev.enc --apply
  ```
- Manual restore validation verifies an existing local archive and target without extraction:
  ```bash
  ./scripts/restore.sh --environment development \
    --env-file /opt/smtp2graph-deploy/env.dev.enc \
    --backup /srv/smtp2graph/backups/smtp2graph-development-YYYYMMDDTHHMMSSZ.tar.gz \
    --target /srv/smtp2graph/recovery/control-plane \
    --confirm-target /srv/smtp2graph/recovery/control-plane --check
  ```
- Restore apply extracts only to the named new/empty target. Reconcile secrets, bootstrap, deploy and run smoke/synthetic checks separately after extraction:
  ```bash
  ./scripts/restore.sh --environment development \
    --env-file /opt/smtp2graph-deploy/env.dev.enc \
    --backup /srv/smtp2graph/backups/smtp2graph-development-YYYYMMDDTHHMMSSZ.tar.gz \
    --target /srv/smtp2graph/recovery/control-plane \
    --confirm-target /srv/smtp2graph/recovery/control-plane --apply
  ```

## `tests/recovery/cold-restore.sh`

- Category: 1a (isolated recovery regression).
- Manual run: executes only temporary `/dev/shm` fixtures and a fake rclone remote; it does not access Google Drive, Docker, SOPS production values or host storage.
  ```bash
  ./tests/recovery/cold-restore.sh
  ```
- Expected result: local/cloud retention, checksum verification, queue-free archive and safe extraction all pass.

## `ci-deploy-swarm.sh`

- Category: 1b (CI-to-Swarm deployment adapter).
- Inputs: the shared workflow provides an absolute `ORCHESTRATOR_ENV_FILE`, `ENVIRONMENT_NAME`, immutable image digest in the env contract, and production-only release tag, approval context and control-plane SHA.
- Side effects: invokes only the reviewed `deploy-orchestrator-swarm.sh --env-file ... --deploy --apply` contract. It never builds, pushes or resolves tags; the orchestrator reconciles versioned runtime Secrets from the selected SOPS contract before submitting the stack.
- Safety: development rejects production context. Production rejects missing or malformed tag, approval context or SHA before invoking the orchestrator.
- Check: `bash -n scripts/ci-deploy-swarm.sh`, `./tests/shell/test-ci-deploy-swarm.sh`.

## `tests/observability/test-signals.sh`

- Category: 1a (read-only deployed observability verification).
- Inputs: optional safe stack name and explicit `--environment development|production`.
- Side effects: none. The check reads Swarm service metadata, probes the gateway's loopback-only observability listener from inside its running container, and inspects current logs in memory without printing metric or log payloads.
- Safety: requires exactly one running gateway container; refuses a missing readiness healthcheck, unbounded Docker logging policy, unavailable metrics, or sensitive/high-cardinality metric fields. It does not submit SMTP mail, read Docker Secrets, or change runtime state.
- Check: `./tests/observability/test-signals.sh --environment development` after declarative deploy.

## `deploy-orchestrator-swarm.sh`

- Category: 1b (dev/prod Swarm orchestration).
- Inputs: decrypts the selected SOPS-encrypted Dotenv contract only into `/dev/shm`, strictly parses allowlisted public stack inputs and resolves `TLS_SECRET_MAPPING_FILE`. `SMTP_TLS_FQDN` is attached as the private DNS alias of the gateway endpoint on `SWARM_OVERLAY_NETWORK`; client stacks join that external encrypted overlay and resolve the same TLS name without `extra_hosts` or the host-published SMTP port. The loader then requires a private names-only mapping with all seven versioned Docker Secret references and merges those references over the decrypted deployment config. The loader never sources either file; host `SERVER_ENV=dev|prod` remains mandatory.
- Operations: `--check` renders and validates the canonical stack without Docker API mutation. Both environments derive the placement label from `DEPLOY_ENVIRONMENT` (`smtp2graph_dev=true` or `smtp2graph_prod=true`). Development `--deploy --apply` idempotently invokes `bootstrap-swarm-host.sh` (ensuring node label, encrypted overlay network, storage root, and nftables policy are applied), reconciles content-addressed runtime Secrets from the selected SOPS contract, reloads the atomic names-only mapping, and invokes `init-storage.sh` before stack submission. If the configured mapping directory is not writable by CI, it is copied to `/dev/shm` and used only for that deploy; a changed secret name still changes the task template and Swarm creates a replacement task. Unchanged secret content leaves the task template unchanged. Production applies the same reconciliation and host bootstrap only after `SERVER_ENV=prod`, immutable digest, `--release-tag`, `--approval-context` and a matching `--declared-deploy-ref` SHA are validated. Normal deploy reads only the immutable digest from the environment contract. Rollback additionally requires an operator-reviewed exact digest pair and `--queue-compatibility-confirmed` before it initializes storage and submits the stack.
- Safety: missing, incomplete, duplicate, unsafe or owner-readable-by-group/other Secret mappings fail closed. Only immutable `@sha256:` image references and safe stack/Secret/network names are accepted. The script does not use `--prune` and never deletes stacks, services, networks, configs, Secrets or queue data.
- Idempotency: repeated deploy submits the same declarative stack without cleanup or new generated state; Docker Swarm reconciles it to the declared state.
- Exception: `--secret-mapping-already-reconciled` is development-only and reserved for the reviewed two-release rehearsal, whose temporary invalid credential mapping must remain intact while testing queue recovery. Normal deploy and every production deploy always reconcile SOPS secret content first.
- Manual development deploy: run only on the authorised privileged development Swarm manager, after successful host bootstrap. If the approved age identity is private to the operator account, pass only its path into the privileged process; do not copy the identity to `/root`, relax its permissions or print its contents:
  ```bash
  cd /opt/smtp2graph-deploy
   sh -c '
    export SOPS_AGE_KEY_FILE=/home/pinokew/.config/sops/age/keys.txt
    exec ./scripts/deploy-orchestrator-swarm.sh \
      --env-file /opt/smtp2graph-deploy/env.dev.enc \
      --deploy --apply
  '
  ```
- Check: `./tests/shell/test-deploy-orchestrator.sh`, `shellcheck scripts/deploy-orchestrator-swarm.sh`, `bash -n scripts/deploy-orchestrator-swarm.sh`.
- Rollback: first assess queue compatibility, then select an explicit previously approved digest. Verify service state, live network policy and synthetic SMTP delivery before closing the rollback change.

## `reconcile-sops-secrets.sh`

- Category: 1b (SOPS + age Docker Secret reconciliation).
- Inputs: explicit absolute Dotenv-format `--env-file` encrypted by SOPS, or an owner-only plaintext file supplied by the CI deployer after its controlled decryption, and an existing absolute `--mapping-file`. It extracts only Graph and SMTP values; values are never logged or sourced by a shell. Group- or world-readable plaintext input is rejected. Escaped `\n` is decoded only for Graph PEM material, while TLS is reconciled from the Certbot lineage by `renew-tls-certificate.sh`.
- Side effects: default mode validates and emits versioned Secret names only. `--apply` requires matching `SERVER_ENV`; production additionally needs an approval context. SOPS values are decrypted only into a mode-`0700` directory under `/dev/shm`; owner-only CI plaintext is staged only there before creating missing immutable Docker Secrets and atomically updating the names-only mapping file.
- Rotation: Graph/SMTP rotation updates encrypted values; TLS rotation is automatic through the dedicated ACME renewal job. Neither reconciler removes an existing Docker Secret.
- Rollback: restore the explicit prior names-only mapping and redeploy after queue assessment. The reconciler never removes an existing Docker Secret.
- Check: `./tests/security/test-reconcile-sops-secrets.sh`.

## `rehearse-deployment.sh`

- Category: 1b (development deployment lifecycle rehearsal).
- Inputs: explicit development env-file, two immutable digests with independently reviewed build-plane release evidence, exact allowlisted non-production recipient, SMTP username, runner-owned mode-`0600` password file under `/dev/shm`, backup reference and operator-only evidence directory.
- Side effects: performs explicit development deploy/upgrade/rollback; creates one temporary synthetic invalid Graph credential Docker Secret and a mode-`0600` temporary env-file under `/dev/shm`; submits one synthetic SMTP message. It restores the original Secret mapping before removing its own temporary Secret.
- Safety: refuses production, tags, recipient outside allowlist, unsafe password/evidence paths and unsafe storage. The operator records external release-evidence review and the successful two-digest compatibility result in the evidence directory. It never reads Docker Secret content, puts passwords in arguments/logs or automatically deletes mailbox data.
- Rollback: the service model is At-Least-Once under recovery. Freeze acceptance, use only a declared compatible pair, preserve queue state and verify the emitted `X-Rehearsal-ID` with a read-only mailbox query.
- Check: `./tests/shell/test-rehearse-deployment.sh`, `bash -n scripts/rehearse-deployment.sh`.
- Current Task 5.4 scope: this script is retained for a future two-release compatibility rehearsal and must not be run for the current single-release development smoke.

## `init-storage.sh`

- Category: 1b (dev/prod persistent-storage initialization).
- Inputs: explicit canonical `--storage-root`; optional backup local directory, rclone remote and rclone path must be supplied together. Local paths must be absolute non-symlink directories; rclone names/paths are strictly validated.
- Side effects: default mode is validation-only. `--apply` requires `--environment development|production` and matching `SERVER_ENV`; it converges the storage root to the invoking user and runtime GID `65532` with mode `0770`, its direct queue/failed children to UID/GID `65532` mode `0700`, creates the owner-only local backup directory for the invoking user and invokes `rclone mkdir` for the configured cloud path. The runtime can then create its required direct `/data/temp` path and scan storage metrics.
- Safety: refuses `/`, symlink components, recursive ownership changes and non-empty child directories with incompatible owner/mode; it does not traverse, log or mutate message payloads. Cloud mutation occurs only with explicit `--apply`.
- Rollback: no automatic ownership rollback. Restore the explicit prior ownership only after a queue/recovery review.
- Check: `./tests/security/test-container-hardening.sh`.
- Manual validation reports the required queue/failed, local backup and rclone destination work without changing host or cloud state:
  ```bash
  ./scripts/init-storage.sh \
    --storage-root /srv/smtp2graph/dev/data \
    --backup-local-dir /srv/smtp2graph/backups \
    --backup-rclone-remote gdrive-backup \
    --backup-rclone-path smtp2graph/dev
  ```
- Manual apply creates/corrects the supplied storage root, creates the local backup directory as `0700`, and performs `rclone mkdir`. Use the actual storage root from the selected encrypted environment contract:
  ```bash
  ./scripts/init-storage.sh \
    --storage-root /srv/smtp2graph/dev/data \
    --backup-local-dir /srv/smtp2graph/backups \
    --backup-rclone-remote gdrive-backup \
    --backup-rclone-path smtp2graph/dev \
    --environment development --apply
  ```

## `bootstrap-swarm-host.sh`

- Category: 1b (dev/prod Swarm host bootstrap).
- Inputs: strict-parsed development `.env` or explicit production env-file з `DEPLOY_ENVIRONMENT=development|production`, `SWARM_OVERLAY_NETWORK`, `SMTP2GRAPH_STORAGE_HOST_PATH`, private/approved `SMTP_ALLOWED_SOURCE_CIDRS` і matching host `SERVER_ENV`; node label деривується з environment.
- Side effects: default/`--check` є read-only. Explicit `--apply` вимагає Swarm manager і privileged operator, створює лише missing encrypted overlay, current-node label `smtp2graph_dev=true` або `smtp2graph_prod=true`, storage root/direct children та atomically applies rendered nftables table. Production additionally needs `--approval-context`.
- Safety: відмовляється від production, public CIDR, unsafe network name, non-manager Docker access, unencrypted existing overlay, symlinked/root storage path і не робить stack deploy, Secret reconciliation чи cleanup. The reviewed SMTP nftables chain runs immediately before UFW's filter-priority INPUT chain, so only its explicit loopback/source-CIDR accept rules can precede the host default drop. It relies only on base host tools, including `grep`, rather than requiring `rg`.
- Manual development apply: run only on the authorised privileged development Swarm manager. The root process must be able to decrypt the selected SOPS file; where the approved age identity is stored in the operator's mode-`0600` key file, use its path only as follows. Do not copy the identity to `/root`, alter its permissions or include key material in a command, log or environment file:
  ```bash
  cd /opt/smtp2graph-deploy
  sudo sh -c '
    export SOPS_AGE_KEY_FILE=/home/pinokew/.config/sops/age/keys.txt
    exec ./scripts/bootstrap-swarm-host.sh \
      --env-file /opt/smtp2graph-deploy/env.dev.enc \
      --apply
  '
  ```
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
- Inputs: explicit safe `--network OVERLAY_NAME`, optional `--stack-name NAME`, and reviewed `deploy/swarm/stack.yml`/nftables policy files. It does not read `.env` or decrypt SOPS material.
- Safety: validates host publish mode, no routing mesh, encrypted overlay and loaded nftables allowlist/deny rule; it fails closed when Docker API access is unavailable. It relies on base host `grep`, not `rg`. `0.0.0.0` listener output is not treated as public exposure by itself.
  ```bash
  cd /opt/smtp2graph-deploy
    sudo ./scripts/check-network-policy.sh \
      --network smtp2graph_internal_enc
  ```

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
- Inputs: explicit build repo, upstream tag or `--latest`, reviewed patch bundle, optional ignored M365 env file, optional safe local `--test-image NAME:TAG`, optional `--target-branch BRANCH`, optional `--push`. Canonical Graph inputs are `GRAPH_TENANT_ID`, `GRAPH_CLIENT_ID`, `GRAPH_CLIENT_SECRET` and `GRAPH_CERTIFICATE_THUMBPRINT`; the script derives the fork's legacy names only in a mode-`0600` temporary Dotenv file under `/dev/shm`. `GRAPH_SENDER_MAILBOX` is the canonical sender for qualification; the script likewise supplies its legacy `MAILBOX` alias only to the fork test process. `ADDITIONALRECIPIENT` and `DENIED_MAILBOX` remain distinct positive/negative qualification inputs. Без explicit `--env-file` script не читає build-plane `.env` і не запускає M365 suite.
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

## `tests/integration/run-gateway-format-matrix.sh`

- Category: 1a (non-production Task 6.1 gateway format submission).
- Prerequisites: `node` (Node.js runtime, e.g. `sudo apt-get install -y nodejs`) is required on the host to execute the JavaScript client.
- Side effects: sends seven synthetic format messages through STARTTLS to the one allowlisted recipient: plain text, HTML/Unicode, To/CC headers, a separate BCC-envelope case, Reply-To, attachment and inline attachment. `--case bcc-envelope` sends only that outstanding case. It uses no Moodle profile.
- Safety: certificate validation is enabled with `SMTP_TLS_FQDN`; the password is read only from its file and never placed in arguments or output. The runner rejects group/other-readable input files and does not persist message identifiers or content as evidence.
- Check: `./tests/shell/test-integration-format-matrix.sh`.

## `tests/integration/check-moodle-starttls-contract.sh`

- Category: 1a (Task 6.1 non-production Moodle SMTP preflight).
- Prerequisites: `node` (Node.js runtime, e.g. `sudo apt-get install -y nodejs`) is required on the host to execute the JavaScript client.
- Inputs: explicit owner-only development env file and optional connect host/port. It strictly reads `SMTP_TLS_FQDN` and `SMTP_LISTEN_PORT`; by default it extracts the `moodle` record from `SMTP_USERS_TSV`, but an explicit owner-only `--password-file` can replace that source on the Moodle VM. It does not source an environment file.
- Side effects: when it extracts the password, it writes only to a mode-`0600` temporary file below a mode-`0700` directory in `/dev/shm`, then removes it through an exit trap. It submits no SMTP message.
- Safety: verifies trusted TLS against `SMTP_TLS_FQDN`, asserts AUTH is denied before STARTTLS and succeeds after STARTTLS, and never prints credentials or SMTP commands. Do not copy `.env` to Moodle; run there with an approved temporary password file and the gateway FQDN to establish the actual client-network path.
- Check: `./tests/shell/test-moodle-starttls-contract.sh`.

## `tests/integration/test-e2e-send-mail.sh`

- Category: 1a (live end-to-end SMTP delivery verification).
- Prerequisites: `python3` (uses standard library `smtplib` and `ssl`, zero external dependencies).
- Inputs: optional `--env-file FILE` (or manual `--smtp-user`, `--password-file`, `--sender`, `--recipient`), optional `--smtp-host` (default `127.0.0.1`), `--smtp-port` (default `2525`), and `--insecure`.
- Side effects: connects to the live gateway, performs STARTTLS, authenticates, and submits a synthetic test email. Verifies `250 OK` acceptance by the gateway.
- Safety: does not print passwords or tokens; supports mode-`0600` password files or auto-extracts temporary credentials to `/dev/shm` from an owner-only env file.
- Safe execution with ephemeral SOPS decryption in `/dev/shm`:
  ```bash
  cd /opt/smtp2graph-deploy
  bash -c '
    set -euo pipefail
    stage_dir=$(mktemp -d /dev/shm/smtp2graph-e2e.XXXXXX)
    chmod 700 "$stage_dir"
    decrypted_env="$stage_dir/decrypted.env"
    trap "rm -rf -- \"\$stage_dir\"" EXIT
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    sops --decrypt --input-type dotenv --output-type dotenv /opt/smtp2graph-deploy/env.dev.enc > "$decrypted_env"
    chmod 600 "$decrypted_env"
    ./tests/integration/test-e2e-send-mail.sh \
      --env-file "$decrypted_env" \
      --insecure
  '
  ```
  *(Для продакшн замініть `/opt/smtp2graph-deploy/env.dev.enc` на `/opt/smtp2graph-deploy/env.prod.enc`)*.
- Manual execution with pre-existing password file:
  ```bash
  ./tests/integration/test-e2e-send-mail.sh \
    --smtp-host 127.0.0.1 --smtp-port 2525 \
    --smtp-user <USER> --password-file <PASSWORD_FILE> \
    --sender <SENDER_EMAIL> --recipient <RECIPIENT_EMAIL> \
    --insecure
  ```
- Check: `./tests/shell/test-e2e-send-mail.sh`.

## `purge-failed.sh`

- Category: 2 (autonomous failed-payload retention maintenance).
- Inputs: `SMTP2GRAPH_STORAGE_ROOT` (default `/data`) and explicit `--dry-run` or `--apply`. The retention is fixed at seven days; the script targets only the validated direct child `${SMTP2GRAPH_STORAGE_ROOT}/failed`.
- Side effects: `--dry-run` is the default and only reports the eligible count. `--apply` removes regular files at least seven full days old; it never follows symlinks, removes directories or accesses `${SMTP2GRAPH_STORAGE_ROOT}/queue`.
- Safety: rejects `/`, missing or symlinked storage/failed roots, cross-device traversal and unsupported arguments. File names are not emitted to logs.
- Check: `./tests/shell/test-purge-failed.sh`, `./tests/security/test-purge-failed.sh`, `shellcheck scripts/purge-failed.sh`.
- Rollback: no automated restore exists; use dry-run before apply and restore only from an approved recovery source if retention was configured incorrectly.
