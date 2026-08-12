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
    Change: Smoke now uses an exact-line `grep` check available on the target host. The control-plane contract retains only canonical `GRAPH_*` credential keys; the isolated fork qualifier derives its legacy aliases only in a mode-0600 temporary file under `/dev/shm`. Task 6.1 records a one-sender/one-recipient, gateway-format-first matrix; Moodle remains blocked until the prior format cases pass.
    Verification: The local `.env` pairs were compared without printing values and were identical. Shell, contract and documentation checks remain required; live smoke and delivery evidence are pending.
    Risks: No gateway health or message-delivery claim is made until the corrected smoke runs on the authorised manager. The temporary qualification adapter must not be repurposed as a deployment configuration path.
    Rollback: Restore the prior smoke implementation only if its dependency is guaranteed on every authorised manager. Reintroduce no legacy duplicate values into encrypted contracts; the qualifier adapter can be reverted independently.
