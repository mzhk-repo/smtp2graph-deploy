# План тестування

## Task 3.2 — Privacy-safe SMTP logs

### TB-POLICY-LOG-001 — SMTP body та attachment markers не потрапляють у gateway logs

- **Мета:** довести, що receive path не записує message body або attachment content у console чи Winston file logs.
- **Середовище:** isolated local fork worktree від clean upstream `v1.1.5` з versioned patch bundle.
- **Вхід:** runtime-generated synthetic UUID markers у SMTP text body та attachment filename/content; значення не зберігаються у Git, test output або evidence.
- **Перевірка:** після успішної SMTP submission markers відсутні зі stdout/stderr gateway process і всіх файлів `logs/` у temporary base directory.
- **Команда:** `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply` у control plane.
- **Результат 2026-07-29:** `test/01receive/11logPrivacy.spec.ts` пройшов як частина 35 receive tests; markers не знайдено в жодній перевіреній log surface.
- **Межі:** test не є evidence для deployment log driver, Swarm/host log retention або external log aggregation; ці surfaces належать наступним deployment/observability tasks.

## Gate B — кваліфікація display name

### TB-GATE-B-DISPLAY-NAME-001 — Поведінка Exchange Online для MIME `From` display name

- **Мета:** встановити, чи зберігає Exchange Online display name із MIME-заголовка `From`, коли шлюз надсилає від імені однієї дозволеної mailbox.
- **Середовище:** isolated non-production Microsoft 365 tenant; synthetic mailbox і recipient; application-only Graph access. Реальні credentials, message bodies та Message-ID не є evidence-артефактами.
- **Вхід:** `From: "SMTP2Graph Display Name Qualification" <MAILBOX>`.
- **Перевірка:** `received.from.emailAddress.address` дорівнює `MAILBOX`; `received.from.emailAddress.name` не дорівнює synthetic MIME display name.
- **Команда:** `./node_modules/.bin/mocha test/02send/05displayName.spec.ts` у `/opt/smtp2graph-build`.
- **Результат 2026-07-27:** тест пройшов. Exchange Online замінив synthetic display name на display name mailbox `noreply`.
- **Наслідок:** одна mailbox не може надавати окремі видимі display name клієнтам. Для production використовувати погоджену в ADR-0004 модель окремих service mailbox і sender allowlist.
