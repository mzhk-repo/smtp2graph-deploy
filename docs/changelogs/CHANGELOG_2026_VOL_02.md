# CHANGELOG 2026 — Volume 02

Продовження `CHANGELOG_2026_VOL_01.md`, ротованого на soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

2026-07-29 — Task 3.2: rejected SMTP submissions do not create queue payloads
    Context: Fork receive tests rejected oversize and unauthorized submissions, but control-plane patch bundle did not assert that rejected input leaves no queue payload.
    Change: Added versioned asset `006-rejected-submission-queue-isolation.patch` with isolated SMTP receive integration coverage for oversize input, missing SMTP AUTH and authenticated sender outside the configured allowlist.
    Verification: All six assets replayed from clean `v1.1.5`; `npm run build`, 6 unit tests and 34 receive tests passed. Each new negative scenario asserts an empty `storageRoot/queue` EML list. Microsoft 365 tests were not invoked without an explicit env file.
    Risks: Evidence covers the fork's local receive/storage boundary only; deployment network policy and the full local Docker MVP harness remain later tasks.
    Rollback: Remove asset `006` and its manifest entry only through a reviewed control-plane change; no release image, deployment or persistent queue state was created.

2026-07-29 — Task 3.2: activate bounded queue threshold runtime configuration
    Context: Fork asset `005` implemented and tested capacity rejection, but the control-plane template did not render its storage settings, leaving the guard inactive at runtime.
    Change: Runtime config now renders persistent storage root, max bytes and reject threshold from strict public inputs. The wrapper validates absolute non-root path, positive capacity and a 1–100 threshold.
    Verification: Entrypoint tests verify default and strict-input rendering plus invalid-value rejection. The already replayed fork regression confirms `451` before `DATA` and no queue write when usage reaches the configured threshold.
    Risks: Capacity accounting remains fork process-local; deployment-level persistent volume and single-replica policy remain separate tasks.
    Rollback: Restore the reviewed template and wrapper pair; do not remove `005` source guard or change persistent storage paths without a separate migration review.
