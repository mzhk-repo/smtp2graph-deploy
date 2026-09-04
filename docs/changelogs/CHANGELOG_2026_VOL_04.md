# CHANGELOG 2026 — Volume 04

Продовження `CHANGELOG_2026_VOL_03.md`, ротованого після досягнення soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

2026-09-04 — Deploy orchestration: fail closed for missing Certbot version floors
    Context: An environment contract created before the Certbot version fields caused deployment to terminate under Bash strict mode with an unhelpful `CERTBOT_MIN_VERSION: unbound variable` error.
    Change: The Swarm orchestrator now validates both required Certbot version keys before accessing them and reports the missing key explicitly. Added a shell regression for the missing `CERTBOT_MIN_VERSION` contract.
    Verification: `tests/shell/test-deploy-orchestrator.sh`.
    Risks: Older encrypted environment contracts still require the documented public version fields before deployment can proceed; the change does not introduce implicit version defaults.
    Rollback: Revert the preflight and regression together only if Certbot version floors are removed from the deployment contract.
