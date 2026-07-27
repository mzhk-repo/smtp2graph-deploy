# План тестування

## Gate B — кваліфікація display name

### TB-GATE-B-DISPLAY-NAME-001 — Поведінка Exchange Online для MIME `From` display name

- **Мета:** встановити, чи зберігає Exchange Online display name із MIME-заголовка `From`, коли шлюз надсилає від імені однієї дозволеної mailbox.
- **Середовище:** isolated non-production Microsoft 365 tenant; synthetic mailbox і recipient; application-only Graph access. Реальні credentials, message bodies та Message-ID не є evidence-артефактами.
- **Вхід:** `From: "SMTP2Graph Display Name Qualification" <MAILBOX>`.
- **Перевірка:** `received.from.emailAddress.address` дорівнює `MAILBOX`; `received.from.emailAddress.name` не дорівнює synthetic MIME display name.
- **Команда:** `./node_modules/.bin/mocha test/02send/05displayName.spec.ts` у `/opt/smtp2graph-build`.
- **Результат 2026-07-27:** тест пройшов. Exchange Online замінив synthetic display name на display name mailbox `noreply`.
- **Наслідок:** одна mailbox не може надавати окремі видимі display name клієнтам. Для production використовувати погоджену в ADR-0004 модель окремих service mailbox і sender allowlist.
