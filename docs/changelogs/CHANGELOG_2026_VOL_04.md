# CHANGELOG 2026 — Volume 04

Продовження `CHANGELOG_2026_VOL_03.md`, ротованого після досягнення soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

2026-09-04 — Deploy orchestration: fail closed for missing Certbot version floors
    Context: An environment contract created before the Certbot version fields caused deployment to terminate under Bash strict mode with an unhelpful `CERTBOT_MIN_VERSION: unbound variable` error.
    Change: The Swarm orchestrator now validates both required Certbot version keys before accessing them and reports the missing key explicitly. Added a shell regression for the missing `CERTBOT_MIN_VERSION` contract.
    Verification: `tests/shell/test-deploy-orchestrator.sh`.
    Risks: Older encrypted environment contracts still require the documented public version fields before deployment can proceed; the change does not introduce implicit version defaults.
    Rollback: Revert the preflight and regression together only if Certbot version floors are removed from the deployment contract.

2026-09-04 — TLS: automate ACME STARTTLS Secret rotation outside SOPS
    Context: Manual copying of short-lived ACME PEM values into SOPS coupled ordinary certificate renewal to Git changes and full deployments.
    Change: TLS PEM is no longer part of the static SOPS reconciliation contract. A root-owned systemd timer runs a reviewed renewal job that obtains the Certbot lineage with DNS-01, creates immutable TLS Docker Secrets, updates only the gateway TLS mounts, verifies the STARTTLS fingerprint and updates the names-only mapping only after success.
    Verification: Isolated Certbot/Docker/SOPS renewal preparation, static Secret reconciliation, Graph certificate preparation and host bootstrap regressions passed.
    Risks: The singleton gateway briefly restarts for a TLS Secret update; old Secret versions are retained for rollback. Existing encrypted TLS PEM values must be removed from `env.*.enc` through an operator SOPS migration.
    Rollback: Disable `smtp2graph-tls-renew.timer`, restore the prior TLS Secret names through the mapping/service rollback path, and verify STARTTLS before re-enabling automation.

2026-09-05 — Deploy orchestration: reconcile TLS Secret mapping with required host privileges
    Context: A non-root CI deployment could create TLS Docker Secrets but could not atomically replace the persistent names-only mapping under root-owned `/srv/smtp2graph/<environment>`, causing `mktemp` to fail with `Permission denied`.
    Change: The orchestrator now invokes only the TLS renewal/Secret preparation step through `sudo` when the deploy caller is non-root, preserving its required SOPS and server-environment inputs. The remaining Secret reconciliation and stack deploy path remain unprivileged.
    Verification: `tests/shell/test-deploy-orchestrator.sh` asserts the non-root deploy path invokes the TLS renewal helper through `sudo`.
    Risks: Non-root deploy callers require `sudo` authorization for the reviewed TLS renewal helper; this is already required later for host bootstrap.
    Rollback: Restore the direct TLS renewal invocation only after the persistent TLS Secret mapping is moved to a safely writable, equally protected host location.

2026-09-05 — TLS Secret reconciliation: accept protected pre-existing Certbot lineage under sudo
    Context: Existing ACME lineage files created by the non-root deployment user remained correctly owner-only but were rejected after TLS preparation began running through `sudo`, because the reconciler required root ownership.
    Change: When invoked by `sudo`, the TLS reconciler now accepts a protected certificate or key owned by either root or the original `SUDO_UID`; group- and world-writable inputs remain rejected.
    Verification: `tests/security/test-reconcile-tls-secret.sh` simulates the root/sudo-owner boundary and preserves the writable-private-key rejection check.
    Risks: The exception is limited to the original sudo caller and only applies while the file has safe permissions.
    Rollback: Revert the sudo-owner allowance only after Certbot lineage ownership is reconciled to root before TLS Secret preparation.
