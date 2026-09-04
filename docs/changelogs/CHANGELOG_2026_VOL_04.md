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
