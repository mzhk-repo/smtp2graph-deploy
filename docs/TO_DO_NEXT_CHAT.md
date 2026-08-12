# To Do — наступний чат

## Поточний стан

- Task 6.1 gateway format matrix завершено: plain text, HTML/Unicode, To/CC, BCC envelope, Reply-To, regular та inline attachments доставлені на одну allowlisted скриньку-одержувача.
- Gateway-side Moodle STARTTLS preflight пройдено: TLS hostname validation, AUTH denial до STARTTLS і AUTH success після STARTTLS. Moodle VM/profile ще не налаштований і не тестувався.
- Наступний клієнтський profile — Matomo на тому ж host, що й smtp2graph. Moodle іде після Matomo.
- `SMTP_TLS_FQDN` у development contract: `smtp-int.pinokew.buzz`; `/etc/hosts` має мапити його на `10.138.131.45`.
- Для FQDN traffic додано `10.138.131.45/32` у `SMTP_ALLOWED_SOURCE_CIDRS` в `env.dev.enc`; зміна ще не застосована до nftables і runtime gateway.
- `bootstrap-swarm-host.sh`, `check-network-policy.sh` і smoke не потребують `rg`; вони використовують `grep`.

## Наступні кроки

1. На authorised privileged development Swarm manager застосувати host policy і declarative stack:

   ```bash
   cd /opt/smtp2graph-deploy

   ./scripts/bootstrap-swarm-host.sh \
     --env-file /opt/smtp2graph-deploy/env.dev.enc \
     --apply

   ./scripts/deploy-orchestrator-swarm.sh \
     --env-file /opt/smtp2graph-deploy/env.dev.enc \
     --deploy --apply
   ```

   Не змінювати права `/srv/smtp2graph/dev/smtp2graph.env`: це root-only names-only Secret mapping, який deploy має читати лише в privileged operator context.

2. Перевірити live policy, health і FQDN STARTTLS:

   ```bash
   ./scripts/check-network-policy.sh \
     --network smtp2graph_internal \
     --stack-name smtp2graph

   ./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph

   openssl s_client -starttls smtp \
     -connect smtp-int.pinokew.buzz:2525 \
     -verify_hostname smtp-int.pinokew.buzz \
     -brief </dev/null
   ```

   Очікування: network-policy і smoke — `PASS`; OpenSSL знаходить STARTTLS і успішно верифікує TLS hostname. Ці команди не відправляють листів.

3. Якщо FQDN STARTTLS успішний, перейти до Matomo profile: перевірити його поточний SMTP config, налаштувати STARTTLS на `smtp-int.pinokew.buzz:2525`, використати user `moodle` лише якщо це свідомо погоджена тимчасова single-user policy, і відправити одне контрольоване повідомлення на єдиний `NONPRODUCTION_RECIPIENT_ALLOWLIST` recipient. Не передавати пароль у чат, аргументах чи logs.

4. Після Matomo SMTP acceptance і read-only підтвердження доставки: оновити Task 6.1 matrix, `docs/AI_CONTEXT.md` і активний changelog. Лише після цього переходити до Moodle VM preflight і Moodle-controlled delivery.

## Верифікація змін у репозиторії

```bash
make validate
./tests/shell/run.sh
git diff --check
```
