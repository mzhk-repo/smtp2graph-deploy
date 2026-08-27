# CHANGELOG 2026 — Volume 03

Продовження `CHANGELOG_2026_VOL_02.md`, ротованого після досягнення soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

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

2026-08-27 — Release policy: digest-only deployment input
    Context: The same release digest and evidence references were maintained in both encrypted deployment contracts and `deploy/config/queue-compatibility.yml`, although normal deployment already consumed only the immutable digest from the environment contract.
    Change: Removed `queue-compatibility.yml` and its mandatory script parsing. `SMTP2GRAPH_IMAGE_DIGEST` is now the only deployment image input; immutable Trivy, CycloneDX, checksum and OCI evidence remains in the build-plane release. ADR-0009 records the policy. Upgrade, rollback and recovery still require an operator-reviewed immutable digest pair, preserved queue state and explicit `--queue-compatibility-confirmed`.
    Verification: Shell syntax, deploy-orchestrator and two-digest rehearsal regressions passed. The tests prove normal deploy works without release metadata and rollback still requires explicit operator confirmation.
    Risks: The local machine-readable allowlist is removed, so operator evidence must record the reviewed release artifacts and compatibility assessment before rollback. Automatic rollback remains disabled.
    Rollback: Restore the reviewed metadata policy only with a superseding ADR and matching script/test changes. Never downgrade a live gateway without queue assessment, an explicit digest and post-change smoke/synthetic verification.
