# To Do — наступний чат

1. Додати storage initializer до declarative deployment revision/hash, щоб зміна storage contract створювала новий Swarm task через звичайний stack deploy, без `docker service update --force`.
2. Запустити локальні security/orchestrator regressions і `make validate`.
3. Подати development redeploy, підтвердити один task `Running`, SMTP banner `220` і runtime Secret mount modes; не виконувати production дій.
4. Запустити live `check-network-policy.sh` з коректним operator PATH (доступний `rg`) та зафіксувати лише non-secret evidence.
5. Додати підсумковий запис до `CHANGELOG_2026_VOL_03.md` і оновити `docs/AI_CONTEXT.md` лише після успішного development smoke.
