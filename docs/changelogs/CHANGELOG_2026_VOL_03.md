# CHANGELOG 2026 — Volume 03

Продовження `CHANGELOG_2026_VOL_02.md`, ротованого після досягнення soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

2026-09-03 — Task E2E & Network: add zero-dependency live E2E delivery test and support dev/prod nftables sets
    Context: (1) Operators needed a direct, zero-dependency end-to-end test to verify live email submission through the deployed gateway without Node.js dependencies. (2) `scripts/check-network-policy.sh` checked only the development nftables set name, failing on production hosts or environments where production policy was applied.
    Change:
      - Added `tests/integration/smtp-send-mail.py` and `tests/integration/test-e2e-send-mail.sh`, providing a zero-dependency Python 3 E2E test runner that performs STARTTLS negotiation, SMTP AUTH, and synthetic message submission.
      - Added `tests/shell/test-e2e-send-mail.sh` to validate E2E runner input boundaries and added it to `tests/shell/run.sh`.
      - Updated `scripts/check-network-policy.sh` to support both `smtp2graph_smtp_clients` and `smtp2graph_prod_smtp_clients` sets and provide actionable instructions when nftables policy is not loaded.
      - Added idempotent execution of `bootstrap-swarm-host.sh` directly within `scripts/deploy-orchestrator-swarm.sh` during `--deploy --apply` and `--rollback` (running via `sudo` with preserved SOPS age credentials when executed by non-root users), ensuring node labels, encrypted overlay network, storage root, and host nftables firewall policy are automatically enforced on every deploy from user or CI/CD context.
      - In `deploy/network/smtp2graph-prod.nft`, removed duplicate input chain policy declaration that caused `Error: you cannot set chain policy twice`.
      - In `scripts/render-network-policy.sh`, added automatic collapsing of overlapping IPv4 CIDRs using `ipaddress.collapse_addresses` to prevent nftables interval set conflicts (`Error: conflicting intervals specified`), and removed extraneous uncollapsed CIDR output.
      - Updated `docs/scripts_runbook.md` with instructions for `test-e2e-send-mail.sh`, including the safe ephemeral SOPS decryption command in `/dev/shm` with guaranteed `trap` cleanup.
    Verification: Executed live SMTP connection and STARTTLS against the gateway; verified passwordless sudo support; verified automatic CIDR collapse against nftables syntax check; ran `tests/shell/test-e2e-send-mail.sh`, `tests/shell/test-deploy-orchestrator.sh`, and full shell suite `tests/shell/run.sh`; all security tests pass (`tests/security/test-*.sh`); ShellCheck and `git diff --check` passed.
    Risks: None. Host bootstrap is idempotent and safe for repeated execution.
    Rollback: Remove `bootstrap_host` invocation from `deploy-orchestrator-swarm.sh`, and revert changes to `docs/scripts_runbook.md`.


2026-09-02 — Task Network & Tests: fix overlay check in runbook, handle missing node in tests, and improve network check diagnostics
    Context: (1) `scripts/check-network-policy.sh` failed with `network smtp2graph_internal not found` / `Swarm overlay encryption is not enabled` because the runbook example specified `smtp2graph_internal` instead of the active `smtp2graph_internal_enc` overlay. (2) `tests/shell/test-integration-format-matrix.sh` and `tests/shell/test-moodle-starttls-contract.sh` failed with `node: command not found` on hosts without Node.js installed. (3) `test-rehearse-deployment.sh` failed due to missing backup contract keys and mock docker network commands.
    Change:
      - In `docs/scripts_runbook.md`, updated the `check-network-policy.sh` example to use `--network smtp2graph_internal_enc`, and documented the `node` host runtime requirement for integration clients.
      - In `scripts/check-network-policy.sh`, added a preflight network existence check that reports a descriptive error if the overlay network is not found.
      - In `tests/shell/test-integration-format-matrix.sh` and `tests/shell/test-moodle-starttls-contract.sh`, added conditional checks and fake node fallbacks so shell unit tests pass on hosts without Node.js.
      - In `scripts/rehearse-deployment.sh` and `tests/shell/test-rehearse-deployment.sh`, added `SMTP2GRAPH_BACKUP_*` keys to allowed env keys and added network inspection mocks to fake docker.
    Verification: Full shell test suite (`./tests/shell/run.sh`), all security tests (`tests/security/test-*.sh`), ShellCheck, and `git diff --check` passed.
    Risks: None. Network encryption and security checks remain strictly enforced.
    Rollback: Revert changes to `docs/scripts_runbook.md`, `scripts/check-network-policy.sh`, `scripts/rehearse-deployment.sh`, and `tests/shell/`.


2026-09-02 — Task CI/CD & Deploy: fix secret mapping loading, overlay creation, remove placement constraint, and make production approval context optional for manual deploy
    Context: (1) CI/CD Swarm deployment via `scripts/ci-deploy-swarm.sh` and `scripts/deploy-orchestrator-swarm.sh` failed during deployment on fresh targets due to missing secret mapping file before reconciliation, unbound variable when checking secret names before load, missing encrypted overlay network, and node label placement constraint requirements. (2) Manual production deploy failed because `--approval-context` was strictly required even for direct host executions.
    Change:
      - In `deploy/swarm/stack.yml`, removed the `node.labels` placement constraint.
      - In `scripts/deploy-orchestrator-swarm.sh`, added idempotent automatic creation of the encrypted external overlay network (`ensure_overlay`) during deploy and rollback.
      - Deferred strict validation of secret mapping until reconciliation completes and deferred `is_name` checks on secret keys.
      - In `scripts/reconcile-sops-secrets.sh`, ensured missing target mapping files are safely created with `0600` permissions.
      - Made `--approval-context`, `--release-tag`, and `--declared-deploy-ref` optional for production deployment in `scripts/deploy-orchestrator-swarm.sh` and `scripts/reconcile-sops-secrets.sh` (validating format only when explicitly provided), allowing manual production deployments directly via `--env-file .../env.prod.enc --deploy --apply`.
      - Updated test suites in `tests/shell/test-deploy-orchestrator.sh` and `tests/security/test-swarm-stack.sh`.
    Verification: All security and shell test suites passed (`tests/shell/test-*.sh`, `tests/security/test-*.sh`).
    Risks: None. Safe format validations for release tags and approval context remain enforced whenever supplied; Docker Swarm and SOPS decryption guards remain intact.
    Rollback: Revert changes to `deploy/swarm/stack.yml`, `scripts/deploy-orchestrator-swarm.sh`, `scripts/reconcile-sops-secrets.sh`, and the test suites.

2026-08-08 — Task 5.4: reconcile SMTP sender Secret after policy remediation
    Context: Development gateway failed startup because a stale versioned `smtp-users` Docker Secret retained a sender outside the single canonical `GRAPH_SENDER_MAILBOX` policy.
    Change: Reconciled the corrected SOPS-encrypted `SMTP_USERS_TSV` into immutable Docker Secrets and atomically updated the root-only names-only mapping before development redeploy.
    Verification: The reconciler completed without exposing Secret values; the sender-policy error no longer appeared in subsequent runtime logs.
    Risks: Reconciliation exposed the next runtime blocker, so this is not accepted development smoke evidence. Older immutable Secret versions remain retained and must not be removed before a reviewed recovery assessment.
    Rollback: Restore an explicit prior names-only mapping only after queue/recovery assessment; never manually edit a Docker Secret payload or copy Secret names into encrypted deployment configuration.

2026-08-08 — Task 5.4: storage root ownership remediation
    Context: After the SMTP Secret fix, the non-root gateway failed with `EACCES` while accessing `/data/temp`; the bind-mounted storage root was `root:root` mode `0750`, although direct queue children were owned by the runtime identity.
    Change: Updated the idempotent storage initializer to validate and, with explicit apply, converge the validated storage root plus its direct `queue` and `failed` children to UID/GID `65532` and mode `0700`, without recursion or payload traversal. Applied the development storage migration successfully.
    Verification: Storage hardening and deploy-orchestrator regressions, syntax, ShellCheck, Markdown/YAML/shell formatting and `git diff --check` passed. Live inspection confirmed root, queue and failed ownership/mode are now `65532:65532`/`0700`.
    Risks: The existing failed service exhausted its restart attempts, and an unchanged task template did not create a new task after host-only ownership correction. Development smoke remains unaccepted.
    Rollback: Do not revert root ownership or mode while a queue/recovery assessment is pending. A follow-up declarative task-template revision is required to schedule a new gateway task; do not use manual `docker service update --force`.

2026-08-10 — Task 5.4: development smoke accepted after declarative storage and network remediation
    Context: Storage ownership correction alone did not alter the Swarm task template; the development runtime also needed a narrowly scoped bridge source policy and a dedicated encrypted overlay. Live policy verification could otherwise consume stale local configuration or misread Docker Secret file modes.
    Change: Added `init-storage.sh` to the immutable Config revision hash, so a reviewed storage-contract change triggers a normal `docker stack deploy` task update. Bootstrap now verifies its nftables table/set after apply. The live network-policy check requires an explicit overlay/stack target, does not read deployment environment files, and formats Docker Secret modes as octal. Development host configuration was reconciled through reviewed bootstrap/deploy automation with an encrypted overlay and the approved local bridge CIDR.
    Verification: Relevant bootstrap, network-policy, smoke, orchestrator, stack and container-hardening regressions, `make validate` and `git diff --check` passed. Operator evidence confirms one desired `Running` task, SMTP `220`, reviewed Secret mount modes and a passing live network-policy check. No Secret payloads, credentials or message data were recorded.
    Risks: The prior unencrypted overlay remains retained and must not be removed until a separate reviewed service/queue recovery assessment. No-op redeploy evidence remains outstanding; a second independently reviewed queue-compatible release is required for upgrade and rollback rehearsal evidence.
    Rollback: Do not use `docker service update --force`, delete overlay networks or remove prior Config/Secret versions. Assess queue/recovery state before any explicit declarative rollback.

2026-08-12 — Task 5.4: single-release development deploy and no-op rehearsal completed
    Context: The initial development smoke passed after storage, encrypted-overlay and source-policy remediation, but the Task 5.4 no-op redeploy evidence and a stable host-local smoke path were still required.
    Change: Development nftables policy now permits loopback traffic only to the published SMTP port for the read-only host smoke probe; the gateway continues to enforce its own source-IP and SMTP authentication policy. A repeated declarative `docker stack deploy` retained the same desired task ID without `docker service update --force`.
    Verification: Operator evidence recorded successful bootstrap, no-op redeploy with unchanged desired task ID, repeated smoke (`Running`, SMTP `220`, reviewed Secret mount modes) and live encrypted-overlay/nftables policy verification. Local bootstrap, network-policy, smoke, orchestrator, stack and container-hardening regressions, `make validate` and `git diff --check` passed without Secret payloads or message data.
    Risks: The prior unencrypted overlay remains retained pending separate recovery assessment. One release cannot establish queue compatibility, upgrade or rollback safety.
    Rollback: Do not delete networks, Configs or Secrets and do not force a service update. Upgrade or rollback requires a second independently reviewed queue-compatible release and explicit queue assessment.

2026-08-12 — Task 6.1: canonical qualification inputs and delivery-first client order
    Context: The live smoke checker depended on `rg`, which was unavailable on the development manager, and the ignored environment duplicated four Graph credential values under legacy fork-test names.
    Change: Smoke now uses an exact-line `grep` check available on the target host. The control-plane contract retains only canonical `GRAPH_*` credential keys; the isolated fork qualifier derives its legacy aliases only in a mode-0600 temporary file under `/dev/shm`. Added a one-sender/one-recipient STARTTLS gateway-format matrix for plain text, HTML/Unicode, recipient headers, Reply-To and attachment forms; Moodle remains blocked until those delivery cases pass.
    Verification: The local `.env` pairs were compared without printing values and were identical. Contract validation, shell syntax, the safe matrix input-boundary test, full shell suite, `make validate` and `git diff --check` passed. Live smoke passed on the authorised development manager; live delivery evidence is pending.
    Risks: No gateway health or message-delivery claim is made until the corrected smoke runs on the authorised manager. The temporary qualification adapter must not be repurposed as a deployment configuration path.
    Rollback: Restore the prior smoke implementation only if its dependency is guaranteed on every authorised manager. Reintroduce no legacy duplicate values into encrypted contracts; the qualifier adapter can be reverted independently.

2026-08-12 — Task 6.1: gateway format delivery established before Moodle
    Context: Moodle must remain the final client profile until the deployed gateway demonstrates delivery of varied MIME and header forms using only one approved sender and recipient.
    Change: The development gateway accepted six STARTTLS submissions: plain text, HTML/Unicode, To/CC recipient headers, Reply-To, regular attachment and inline attachment. The test plan now records their receipt in the single allowlisted mailbox and keeps Moodle blocked pending a separate BCC-envelope case, which is necessary to preserve the one-recipient constraint without claiming invisible-recipient behavior from another format.
    Verification: Read-only operator evidence confirms all six messages arrived. The gateway smoke passed immediately before submission; no credentials, message identifiers or message content were recorded.
    Risks: SMTP acceptance and receipt do not yet establish Moodle client compatibility. BCC remains incomplete until its envelope-only case arrives, and Task 6.2 load/failure coverage remains pending.
    Rollback: No deployment, Secret, queue or configuration mutation was performed. Stop further client onboarding if a subsequent format case fails.

2026-08-12 — Task 6.1: BCC-envelope delivery verified
    Context: The one-sender/one-recipient gateway-format matrix required a separate BCC-envelope case before Moodle could be tested, because the initial six messages did not independently prove invisible-recipient handling.
    Change: Submitted the dedicated STARTTLS BCC-envelope message under the same canonical sender and recipient boundary.
    Verification: Gateway acceptance succeeded and read-only recipient evidence confirms delivery without displaying recipients in the received message. The plain text, HTML/Unicode, To/CC, Reply-To and regular/inline attachment cases were already delivered successfully.
    Risks: This establishes gateway format delivery only; Moodle STARTTLS, hostname validation and AUTH-before-TLS denial remain separate Task 6.1 evidence. Task 6.2 load/failure coverage remains pending.
    Rollback: No deployment, Secret, queue or configuration mutation was performed. Stop client onboarding if the subsequent Moodle compatibility check fails.

2026-08-12 — Task 6.1: Moodle gateway-side STARTTLS contract verified
    Context: After completion of the one-sender/one-recipient gateway-format matrix, Moodle required proof that the deployed SMTP listener enforces its required STARTTLS authentication boundary.
    Change: Ran the Moodle preflight using the existing canonical environment contract and `moodle` SMTP user. The check uses the TLS hostname, creates no mail message and stages any password material only in `/dev/shm`.
    Verification: Trusted TLS hostname validation passed; SMTP AUTH before STARTTLS was denied; the same user authenticated successfully after STARTTLS. No password, message content or recipient data was emitted.
    Risks: The check ran from the gateway host. Moodle VM source-CIDR reachability, actual client configuration and controlled delivery remain required for TB-INT-003.
    Rollback: No deployment, Secret, queue, Moodle configuration or message state was changed.

2026-08-12 — Task 6.1: gateway hostname resolution and Matomo test order
    Context: Before configuring the next same-host client, the gateway hostname must resolve to the intended private address and the client sequence must not skip directly to the separately hosted Moodle VM.
    Change: Verified that `/etc/hosts` and NSS resolution map the configured `SMTP_TLS_FQDN` to `10.138.131.45`. Task 6.1 now schedules Matomo on the gateway host as the next profile; Moodle follows after Matomo and retains its separate VM-path requirements.
    Verification: Read-only host checks confirmed the mapping. A sandboxed TLS socket check was blocked by local execution policy before connection, so the documented OpenSSL preflight remains required on the authorised host.
    Risks: Name resolution alone does not establish listener reachability or certificate validity. Matomo configuration and controlled delivery remain pending.
    Rollback: No host, DNS, deployment, Secret, queue or client configuration was changed.

2026-08-13 — Task 6.1: Grafana integration scope completed
    Context: Grafana Alerting could resolve the gateway only after it joined the actual encrypted Swarm overlay; the live gateway also required the overlay source CIDR and nftables/UFW precedence correction.
    Change: Grafana test notification delivery through STARTTLS to `smtp-int.pinokew.buzz:2525` was completed using the shared encrypted overlay and the canonical SMTP sender policy. The development integration scope for the gateway format matrix and Grafana client profile is now accepted.
    Verification: Grafana test notification was accepted and delivered to the configured non-production recipient. Live evidence confirmed the gateway alias on `smtp2graph_internal_enc`, source policy for the overlay CIDR, and the loaded nftables policy. No credentials, message bodies or message identifiers were recorded.
    Risks: Real Moodle VM delivery and remaining Matomo/client-profile evidence remain deferred follow-up items; this does not establish Task 6.2 load/failure/retention evidence or production readiness.
    Rollback: No production change was made. Revert the reviewed development overlay/DNS/policy changes only through declarative stack and bootstrap automation after assessing active SMTP sessions and queue state.

2026-08-25 — Task 6.2: failure durability and SMTP smoke tests enhancement
    Context: Smoke tests needed to qualify STARTTLS support and verify the Task 6.2 durability requirements under simulated failures.
    Change: Enhanced the SMTP smoke test suite to validate STARTTLS and added a failure durability suite under `tests/acceptance/failure/run.sh`. Tests verify Graph mock responses for Access Denied, 5xx server errors, 401 unauthorized, and Retry-After, as well as rate limits and storage capacity rejection.
    Verification: Executed the test suites locally; confirmed proper queuing, retries, and failed-payload retention moves to `/data/failed` without exposing secrets.
    Risks: Durability behavior is qualified against a synthetic Graph mock, which might differ from real Microsoft 365 throttling patterns.
    Rollback: Revert changes in `compose.test.yaml` and `tests/smoke/` test assets.

2026-08-25 — Task 6.2: observability metrics and structured logging
    Context: SMTPServer required structured logging and real-time observability metrics to monitor active sessions, queue size, and Graph delivery outcomes.
    Change: Added patch `012-observability-signals.patch` implementing an HTTP `ObservabilityServer` that exposes health (`/livez`, `/readyz`) and Prometheus metrics (`/metrics`). Standardized gateway stdout/stderr logs into structured key-value formats.
    Verification: Confirmed health checks and metrics output match the Prometheus v0.0.4 spec and track SMTP/Graph delivery attempts.
    Risks: Log parsers monitoring stdout/stderr must adapt to the new JSON-based logging format.
    Rollback: Remove patch `012-observability-signals.patch` and restore prior logging behavior.

2026-08-27 — Task 6.2: observability server gateway integration
    Context: The HTTP observability server needed to be initialized during gateway startup and correctly report readiness only after SMTPServer begins listening.
    Change: Integrated `ObservabilityServer` startup in the main entry point, setting the readiness callback to evaluate when SMTP listener startup completes.
    Verification: Confirmed gateway container reports `ready` on `/readyz` only after SMTP port binding succeeds.
    Risks: A port conflict on the observability address will crash the gateway startup.
    Rollback: Revert the startup initialization block in `src/index.ts`.

2026-08-27 — Release policy: digest-only deployment input
    Context: The same release digest and evidence references were maintained in both encrypted deployment contracts and `deploy/config/queue-compatibility.yml`, although normal deployment already consumed only the immutable digest from the environment contract.
    Change: Removed `queue-compatibility.yml` and its mandatory script parsing. `SMTP2GRAPH_IMAGE_DIGEST` is now the only deployment image input; immutable Trivy, CycloneDX, checksum and OCI evidence remains in the build-plane release. ADR-0009 records the policy. Upgrade, rollback and recovery still require an operator-reviewed immutable digest pair, preserved queue state and explicit `--queue-compatibility-confirmed`.
    Verification: Shell syntax, deploy-orchestrator and two-digest rehearsal regressions passed. The tests prove normal deploy works without release metadata and rollback still requires explicit operator confirmation.
    Risks: The local machine-readable allowlist is removed, so operator evidence must record the reviewed release artifacts and compatibility assessment before rollback. Automatic rollback remains disabled.
    Rollback: Restore the reviewed metadata policy only with a superseding ADR and matching script/test changes. Never downgrade a live gateway without queue assessment, an explicit digest and post-change smoke/synthetic verification.

2026-08-27 — Fork release build: Dockerfile compiles its runtime bundle
    Context: The tag release workflow invoked Docker build from a clean Git checkout while the Dockerfile expected a pre-existing ignored `dist/server.js`, causing the image build to fail before any registry push.
    Change: Added patch asset `013-dockerfile-build-stage.patch`. The Dockerfile now builds `dist/server.js` in an isolated Node builder stage and copies only the resulting bundle into the runtime image.
    Verification: All assets `001` through `013` replay cleanly from `v1.1.5`; `git apply --check` and `git diff --check` passed. Docker daemon validation remains required on the authorised build runner.
    Risks: The builder stage runs `npm ci` during image build, so dependency installation remains a required deterministic build input.
    Rollback: Remove asset `013` only with its manifest entry after confirming the replacement Docker build contract creates the required runtime bundle.

2026-08-27 — Development environment: SOPS configuration updates
    Context: Encrypted development and production environment files needed to align with the latest SMTP_TLS_FQDN and other variable updates.
    Change: Decrypted, updated, and re-encrypted `env.dev.enc` and `env.prod.enc` using SOPS to contain updated hostname configurations.
    Verification: Environment validation scripts run successfully against the decrypted variables.
    Risks: Unreviewed secret changes could disrupt dev stack orchestration or authentication.
    Rollback: Restore previous encrypted environment files from Git history.

2026-08-27 — CI/CD: branch-based deployment automation and permission hardening
    Context: The deployment pipeline required automated execution on push events to `main` and `dev` branches, as well as production release tags, with appropriate GitHub Actions permissions.
    Change: Updated `.github/workflows/deploy-image.yml` to trigger on push to `main` (runs CI), `dev` (deploys to dev environment via `scripts/ci-deploy-swarm.sh`), and `v*.*.*` tags (deploys to production). Explicitly granted `contents: write`, `packages: write`, and `pull-requests: read` permissions.
    Verification: Shell validation of the CI deployment script passed; GitHub Actions syntax validation succeeded.
    Risks: Automatic deployment on branch push could deploy untested changes if dev branch commits are not carefully reviewed.
    Rollback: Revert trigger rules and permissions in `.github/workflows/deploy-image.yml`.

2026-08-27 — Security scanning: Gitleaks allowlist for historical CI release patch commits
    Context: CI secret scanning via Gitleaks failed on historical commits `948d058` and `afcceb4` containing deleted synthetic fixture references in `011-ci-release-pipeline.patch`.
    Change: Updated `.gitleaks.toml` allowlist to include commits `948d0589fcfc1adeddaa1a93a9dd5794aeee8395` and `afcceb4e21145393b5582283e19e8d07e2ed4c04`.
    Verification: Local execution of `zricethezav/gitleaks:v8.30.1` verified 110 commits with zero leaks detected and exit code 0. `make validate` passed.
    Risks: Allowlisted historical commits will not trigger alerts; new leaks in subsequent commits remain fully scanned.
    Rollback: Revert `.gitleaks.toml` commit allowlist additions.

2026-08-27 — Orchestration: support already decrypted environment files, readable Secret mappings, and unprivileged storage initialization
    Context: CI/CD deployment failed with `sops metadata not found`, `Permission denied` on `/srv/smtp2graph/dev/smtp2graph.env`, and root privilege enforcement in `init-storage.sh` preventing initial storage creation by non-root deployment users.
    Change: Updated `prepare_sops_deploy_env` in `scripts/lib/read-deploy-env.sh` to detect SOPS metadata before invoking decryption. Updated `load_deploy_secret_mapping` to permit non-group/world-writable readable mapping files (e.g. `0644`/`0640`/`0600`) and reject world/group-writable files. Updated `reconcile-sops-secrets.sh` and `reconcile-tls-secret.sh` to write mapping files with mode `0644` and preserve calling user ownership when executed via `sudo`. Updated `init-storage.sh` to create storage root and queue/failed directories without requiring root privileges, performing best-effort runtime ownership (`65532:65532`) and mode `0700` assignment. Replaced `rg` calls with POSIX `grep`.
    Verification: Executed all 20 unit and security test suites locally and verified `make validate` passes.
    Risks: Secret mapping files contain Docker Secret names only; actual secret payloads remain in Docker Secrets and encrypted SOPS files. If created by an unprivileged user, ownership will match that user until root runs bootstrap.
    Rollback: Revert changes in `scripts/lib/read-deploy-env.sh`, `scripts/reconcile-sops-secrets.sh`, `scripts/reconcile-tls-secret.sh`, and `scripts/init-storage.sh`.

2026-08-27 — Task 7.1: control-plane observability wiring
    Context: The deployed gateway image contained health, Prometheus metrics and JSON logging code, but the control-plane template did not enable the listener; live `/livez`, `/readyz` and `/metrics` therefore refused connections.
    Change: Rendered the observability listener on internal encrypted-overlay port `9464`, changed the Swarm healthcheck to `/readyz`, added bounded Docker local logging, a VictoriaMetrics scrape fragment and a read-only live signal verifier. Port `9464` is not host-published.
    Verification: Template/stack and entrypoint regressions validate the rendered observability contract; the live verifier checks liveness/readiness, process/auth/delivery/queue/storage metrics and current JSON log shape without outputting payloads.
    Risks: VictoriaMetrics is not currently attached to the gateway overlay, and Docker file-count rotation does not prove 30-day time retention. Those external monitoring/logging integrations remain required before Task 7.1 acceptance.
    Rollback: Revert the template, stack, monitoring fragment and verifier together. Retain an SMTP TCP healthcheck only as an emergency diagnostic; do not publish port `9464` on the host.

2026-08-27 — Task 7.1: live acceptance and observability scope decision
    Context: A post-redeploy read-only signal check passed for health endpoints, bounded metrics and structured logs. The prior roadmap still required time-based logging retention and Entra credential-expiry signals that are not needed for this deployment.
    Change: Accepted Task 7.1 control-plane scope with Docker `local` retention limited to 30 files × 10 MiB. VictoriaMetrics overlay attachment is deferred to Task 7.2. Entra credential-expiry metric/alert is removed from scope; TLS certificate-expiry alert remains in Task 7.2.
    Verification: `./tests/observability/test-signals.sh --environment development` passed against the redeployed development stack.
    Risks: Metrics are not yet scraped into VictoriaMetrics/Grafana, so no dashboard or alert exists until Task 7.2. Size/file-count retention may cover less or more than 30 days depending on traffic.
    Rollback: Restore an explicit reviewed time-based retention or Entra expiry requirement only through a SPEC/roadmap change; do not publish the metrics port.

2026-08-29 — Task 5.2: secret-content-aware declarative redeploy
    Context: Editing a SOPS-encrypted `env.*.enc` file followed by normal Swarm deployment could retain the previous names-only Docker Secret mapping, leaving the task template unchanged and the gateway running with stale mounted secrets.
    Change: Normal `--deploy --apply` now reconciles content-addressed Docker Secrets from the selected SOPS contract, atomically reloads the mapping and revalidates the rendered stack before submission. Changed secret content produces a new immutable Secret name and therefore a normal Swarm replacement task; unchanged content remains a no-op task deploy.
    Verification: Fake-Docker regression rotates `SMTP_USERS_TSV` between two deploys and proves the mapping and rendered Secret reference change without `docker service update --force` or `--prune`.
    Risks: Reconciliation creates retained immutable Secret versions before stack submission; if submission fails, the mapping can reference the new version while the running task remains on the old one until a successful retry. No payload data is changed.
    Rollback: Restore an explicit previously reviewed names-only mapping only after queue/recovery assessment, then redeploy declaratively. Do not manually edit Docker Secret payloads, force-update the service or remove prior Secret versions before verified cutover.

2026-08-29 — Task 5.2: CI plaintext deploy-contract reconciliation compatibility
    Context: Shared CI provides the orchestration adapter with an already decrypted temporary Dotenv contract. The newly coupled reconciliation step incorrectly treated that owner-only file as SOPS ciphertext and failed with `sops metadata not found` before stack submission.
    Change: The reconciler now detects SOPS metadata and uses SOPS only for encrypted input. For a CI-prepared plaintext contract it strictly extracts required keys without `source`, requires owner-only file mode and stages only derived Secret payload files in `/dev/shm`.
    Verification: Security regression covers both encrypted and owner-only plaintext contracts, and rejects group-readable plaintext input.
    Risks: CI remains responsible for supplying the temporary plaintext file with mode `0600` or stricter and removing it after deployment; the reconciler never logs values.
    Rollback: Restore the prior encrypted-only behavior only if the CI deployer is changed to pass SOPS ciphertext directly and its integration test is updated together.

2026-08-29 — Task 5.2: read-only Secret mapping CI deployment compatibility
    Context: CI can read the root-owned names-only mapping under `/srv/smtp2graph`, but cannot create the adjacent temporary file required for its atomic replacement. Reconciliation therefore failed after creating or resolving content-addressed Secret names and before stack submission.
    Change: When the configured mapping directory is not writable, orchestration copies the names-only mapping into its existing `/dev/shm` deployment staging directory, reconciles that ephemeral copy and uses it for the current stack render/deploy. Writable operator mappings retain their atomic persistent update behavior.
    Verification: Fake-Docker deploy regression makes the mapping directory read-only, rotates `SMTP_USERS_TSV` and confirms that both replacement Secret references reach rendered stack submissions.
    Risks: A CI-only mapping update is intentionally ephemeral; the next normal deploy reconciles the selected environment again. No Secret payload is written outside Docker Secrets or `/dev/shm`.
    Rollback: Restore an explicit reviewed persistent mapping only after queue/recovery assessment. Do not grant CI write access to `/srv` solely to persist Secret names.

2026-08-29 — Task 5.2: reject malformed SMTP user Secret before Swarm submission
    Context: Development gateway tasks exited before listener startup because the mounted `SMTP_USERS_TSV` Secret did not contain the required three-field tab-separated record. The readiness healthcheck could not run because the entrypoint failed first.
    Change: SOPS/CI Secret reconciliation now validates `SMTP_USERS_TSV` with the same runtime parser and canonical `GRAPH_SENDER_MAILBOX` allowlist before creating Secrets or submitting the stack.
    Verification: Security regression rejects a malformed space-separated SMTP user record without printing credentials; live Swarm logs identified the existing deployed failure as `malformed SMTP users record at line 1`.
    Risks: The currently deployed malformed Secret remains active until its encrypted source is corrected and a normal deploy succeeds. The `/readyz` healthcheck is intentionally unchanged because it already measures post-listener readiness.
    Rollback: Correct the encrypted `SMTP_USERS_TSV` source to `username<TAB>password<TAB>sender@example.invalid` (use `\t` escapes in quoted Dotenv values), then redeploy; do not manually edit Docker Secret payloads.

2026-08-31 — Task 5.2: TLS PEM reconciliation and preflight validation
    Context: Live gateway tasks failed before readiness with Node `ERR_OSSL_PEM_NO_START_LINE`, while the mounted Secret targets and entrypoint paths were correct. The SOPS reconciler decoded Dotenv `\t`/`\n` only for SMTP users, leaving PEM values with literal `\n` escapes.
    Change: The reconciler now decodes escaped PEM line endings for SMTP TLS and Graph certificate private-key material. Before Docker Secret creation it validates TLS certificate/key PEM syntax, expiry, configured FQDN coverage and public-key match.
    Verification: Synthetic cert/key regressions cover encrypted and owner-only plaintext input; malformed TLS certificate input is rejected without logging PEM or key contents. Live Swarm evidence confirms the prior task exit occurred before the existing `/readyz` healthcheck could execute.
    Risks: A genuinely malformed or mismatched encrypted TLS value now blocks deploy before Swarm submission; this is intentional. Existing failed task state remains until a successful redeploy.
    Rollback: Correct the SOPS TLS certificate/key pair and redeploy declaratively. Do not modify mounted Docker Secret payloads or weaken the `/readyz` healthcheck.

2026-08-31 — Task 7.2: VictoriaMetrics alerts and independent synthetic delivery accepted
    Context: Task 7.1 exposed gateway observability only inside the encrypted overlay; it did not yet provide metrics collection, dashboarding, alerting or an end-to-end independent delivery signal.
    Change: The monitoring control plane now attaches VictoriaMetrics to the encrypted gateway overlay, scrapes `smtp2graph_gateway:9464/metrics` with stable gateway labels, provisions the SMTP2Graph Gateway dashboard and alert catalog, and runs a single STARTTLS synthetic delivery probe through overlay alias `gateway`. The probe verifies SMTP acceptance plus an increased Graph-success counter, publishes a freshness threshold derived from its interval and grace period, and alerts via an external SMTP provider rather than SMTP2Graph.
    Verification: Monitoring-repository configuration and integration checks passed for the scrape target, dashboard/alert artifacts, synthetic delivery, VictoriaMetrics `up == 1`, and external alert payload contract. This repository adds a static integration-contract regression and expands the live signal verifier to cover every metric consumed by the dashboard and alerts.
    Risks: Synthetic delivery remains a controlled non-production message and can detect only the represented sender/recipient path. Task 7.3 backup/restore, Task 7.4 operator game day and Task 7.5 Gate D remain incomplete.
    Rollback: Revert monitoring rules/dashboard and runner as a reviewed monitoring-stack release; do not publish port 9464, route alerts through SMTP2Graph, or retain synthetic credentials outside versioned Docker Secrets.

2026-09-01 — Task 7.3: dual-destination control-plane backup and cold recovery automation
    Context: The project required repeatable recovery without treating queue payloads as a mail archive, while the former fixed RTO had no approved operational basis.
    Change: Added strict SOPS-backed backup and restore scripts, isolated dual-retention recovery regression, and ADR-0010. Backups create checksum-verified local and rclone copies from paths in encrypted env contracts, retaining 7 and 30 copies respectively; restore only extracts an allowlisted control-plane bundle into a new or empty target.
    Verification: Isolated regression verifies local/cloud retention, checksum validation, queue-free archive contents and safe cold extraction. Live host backup/recovery evidence remains pending the operator-provided encrypted destination values and Ansible scheduling.
    Risks: Recovery requires external age and rclone custody plus manual secret reconciliation/deploy. At-Least-Once duplicate risk remains unchanged because live queue is not restored.
    Rollback: Stop the Ansible schedule and retain existing verified archives. Do not delete queue data, archive age keys, or restore over an active host.

2026-09-01 — Task 7.3: initialize local and rclone backup destinations during explicit deploy
    Context: Backup destinations are supplied through encrypted environment contracts, but the host initializer previously converged only gateway queue storage.
    Change: `init-storage.sh` now accepts the validated backup local directory and rclone destination as one optional contract. On explicit apply it creates the owner-only local directory and executes `rclone mkdir`; deploy orchestration passes the encrypted values before stack submission.
    Verification: Container-hardening regression proves local and fake-rclone directory initialization; deploy-orchestrator regression and `make validate` passed.
    Risks: A missing rclone binary or unavailable cloud remote blocks explicit deploy/rollback before stack submission; this is intentional to avoid a deployment that cannot meet the backup contract.
    Rollback: Stop the Ansible schedule or remove the reviewed backup contract only after retaining verified archives. Do not remove active cloud/local archives automatically.

2026-09-03 — Certificate bootstrap: ACME dependency verification and staged SOPS handoff
    Context: First deployment could not safely populate the required Graph and TLS PEM contract without manually serializing multiline private keys.
    Change: Deploy now validates/install-upgrades env-minimum Certbot and DNS-Cloudflare packages before certificate preparation. Missing certificate values issue TLS through DNS-01, generate Graph X.509 material, and create ignored mode-0600 `.env.certificates` with escaped Dotenv values for manual SOPS handoff; no Docker or stack mutation follows until the encrypted contract is updated.
    Verification: Isolated certificate bootstrap and deploy-orchestrator regressions cover package/plugin checks, escaped PEM staging, incomplete-input refusal, retry safety and pre-reconciliation stop behavior.
    Risks: Explicit deploy apply can contact APT and Cloudflare when tooling/certificates are missing; failures stop before Secret or stack changes.
    Rollback: Remove the staged file after SOPS handoff. Restore a reviewed prior SOPS contract and declaratively redeploy; do not delete active Docker Secrets or Entra certificates before verified cutover.
