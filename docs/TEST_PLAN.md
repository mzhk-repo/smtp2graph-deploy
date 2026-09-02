# План тестування

## Task 7.3 — Backup, restore і cold recovery

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-REC-001 | Backup creates checksum-verified local and rclone copies, retains 7/30 archives, and excludes queue, failed, logs and Secret payloads. | `./tests/recovery/cold-restore.sh` | Isolated fake-rclone regression; live destination values remain only in `env.*.enc`. |
| TB-REC-002 | Restore accepts only a verified allowlisted archive and extracts only to a new or empty target. | `./tests/recovery/cold-restore.sh` | Does not rebind secrets, deploy or modify a live host. |
| TB-REC-003 | Cold-host recovery re-establishes age custody, Secret mapping, bootstrap, immutable deploy and independent synthetic delivery. | Redacted operator runbook evidence | Elapsed time is recorded without a fixed RTO; queue is not restored and duplicate risk remains At-Least-Once. |

## Task 7.2 — Alerts і independent synthetic delivery

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-OBS-001 | VictoriaMetrics reaches the gateway only on encrypted overlay DNS `smtp2graph_gateway:9464`; scrape has stable `env=prod`, `service=smtp2graph`, `component=gateway` labels and port 9464 is not host-published. | `./tests/shell/test-monitoring-contract.sh`; `/opt/victoriametrics-grafana/tests/test-observability-config.sh` | Static control-plane plus authorised monitoring-stack validation. |
| TB-OBS-002 | Dashboard and alerts cover metrics availability, auth, delivery failure/retry, 60/80% storage, failed queue and TLS expiry at 30/7 days. | `/opt/victoriametrics-grafana/tests/test-observability-config.sh` | Validates monitoring-repository artifacts; no centralized mail-content logging. |
| TB-OBS-003 | Synthetic STARTTLS submission to allowlisted non-production recipient is accepted and causes `smtp2graph_delivery_attempts_total{result="succeeded"}` to increase; fresh failure is independently alerted. | `/opt/victoriametrics-grafana/tests/integration/test-synthetic-and-metrics.sh` and redacted operator evidence | Requires authorised monitoring manager, deployed non-production gateway and external notification channel. Password, recipient, marker and message body are not evidence. |

Task 7.2 status: **Completed for the deployed monitoring integration**. Task 7.3 backup/restore, Task 7.4 game day/runbook handoff and Task 7.5 Gate D remain required before production readiness.

## Task 6.1 — Integration та client compatibility suite

### Scope and execution order

Task 6.1 development integration scope is complete for the gateway format matrix, Grafana and the gateway-side Moodle STARTTLS contract. All positive delivery cases use the canonical `GRAPH_SENDER_MAILBOX`; approved non-production recipients may be selected from the configured test allowlist. Credentials, message bodies and message identifiers are never retained as evidence. Real Moodle VM delivery and remaining client profiles are explicitly deferred evidence, not silently treated as passed.

| ID | Profile / format | Preconditions | Expected evidence | Status |
|---|---|---|---|---|
| TB-INT-001 | Gateway delivery: plain text and HTML/Unicode | Task 5.4 smoke passes; one sender and one recipient are configured. | SMTP acceptance and read-only recipient verification for both formats. | Passed 2026-08-12 |
| TB-INT-002 | Gateway delivery: To/CC/BCC, Reply-To, attachment and inline attachment | TB-INT-001 passes; same sender and recipient policy remains in force. | SMTP acceptance and read-only recipient verification of each supported format. | Passed 2026-08-12; BCC envelope arrived without exposing recipients |
| TB-INT-003 | Moodle STARTTLS, hostname validation and AUTH-before-TLS denial | TB-INT-001 and TB-INT-002 pass; real Moodle profile and its approved source CIDR are available. | Moodle SMTP response capture and read-only recipient verification. | Partial: gateway-side TLS hostname validation, AUTH-before-TLS denial and post-TLS AUTH passed 2026-08-12; Moodle VM path and controlled delivery pending |
| TB-INT-004 | Matomo SMTP client profile on gateway host | TB-INT-001 and TB-INT-002 pass; Matomo configuration is available; the shared host resolves `smtp-int.ldubgd.edu.ua` to `10.138.131.45`. | Matomo SMTP response/log evidence and read-only recipient verification of one controlled message. | Ready |
| TB-INT-005 | Grafana Alerting SMTP client profile | Gateway STARTTLS, encrypted overlay alias and Grafana source policy are applied; Grafana service is attached to the gateway overlay. | Grafana test notification accepted by the gateway and delivered to the configured non-production recipient. | Passed 2026-08-13 |

Task 6.1 status: **Completed for the accepted development integration scope**. TB-INT-003 real Moodle VM delivery and TB-INT-004 Matomo delivery remain separate follow-up evidence items; they do not invalidate the completed gateway/Grafana integration milestone but must remain closed before claiming the full five-profile roadmap acceptance.

Before every Task 6.1 submission, run `tests/acceptance/deployment/smoke.sh`. Any failed submission or delivery check stops the matrix; it does not proceed to the next client profile.

### Gateway hostname preflight

The gateway host `/etc/hosts` and NSS resolution must map the canonical `SMTP_TLS_FQDN` to the approved private address. Confirm that the listener is reachable and the certificate matches this hostname from the authorised gateway/Matomo host before configuring a client:

```bash
openssl s_client -starttls smtp \
  -connect smtp-int.pinokew.buzz:2525 \
  -verify_hostname smtp-int.pinokew.buzz \
  -brief </dev/null
```

Expected result: a successful TLS verification and SMTP connection. This command does not authenticate or send a message.

The gateway matrix command is:

```bash
./tests/integration/run-gateway-format-matrix.sh \
  --env-file /absolute/path/to/development.env \
  --smtp-user SMTP_USERNAME \
  --password-file /dev/shm/smtp2graph-task61-password \
  --smtp-host 127.0.0.1 \
  --smtp-port 2525
```

The runner requires both files to be owner-only, validates the TLS certificate against `SMTP_TLS_FQDN`, and never prints the password, message content or recipient address. SMTP `250` confirms gateway acceptance only; each case needs a separate read-only verification in the one approved recipient mailbox before it becomes `Passed`. With one recipient, BCC is a separate envelope-only message without a visible BCC header:

```bash
./tests/integration/run-gateway-format-matrix.sh \
  --env-file /absolute/path/to/development.env \
  --smtp-user SMTP_USERNAME \
  --password-file /dev/shm/smtp2graph-task61-password \
  --case bcc-envelope
```

Moodle contract preflight uses the existing `moodle` record from `SMTP_USERS_TSV`, creates its password file only in `/dev/shm`, does not send a message, and validates that AUTH is denied before STARTTLS but accepted after trusted TLS:

```bash
./tests/integration/check-moodle-starttls-contract.sh \
  --env-file /absolute/path/to/development.env \
  --smtp-host 127.0.0.1
```

On the Moodle VM, do not copy `.env`. Use a temporary owner-only password file supplied through the approved client-configuration procedure, then run the check with `--smtp-host "${SMTP_TLS_FQDN}" --smtp-user moodle --password-file /dev/shm/smtp2graph-moodle-password`; this proves the approved source CIDR and client-to-gateway TLS path. Actual Moodle configuration and one controlled delivery remain the final TB-INT-003 evidence.

## Task 5.4 — Development staging single-release deploy і smoke rehearsal

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-DEPLOY-001 | Read-only smoke підтверджує одну desired Running task, SMTP `220` і declared Docker Secret mount modes без читання secret content. | `./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph` | Потребує authorised development Swarm manager; не виконує `docker exec`. |
| TB-DEPLOY-002 | Fresh deploy і повторний deploy одного evidence-backed immutable digest не замінюють desired running task; stack не використовує `--prune`. | `./tests/shell/test-deploy-orchestrator.sh` і live operator evidence | Fake Docker покриває CLI contract; live Swarm потрібен для фактичної convergence evidence. |
| TB-DEPLOY-003 | Один release має independently reviewed Trivy, CycloneDX, image-specific CycloneDX і checksum artifacts у immutable build-plane release artifacts. | Build-plane release evidence, exact `SMTP2GRAPH_IMAGE_DIGEST` у env contract | Другий reviewed release потрібний перед promotion або compatibility declaration. |
| TB-DEPLOY-004 | Upgrade, queue migration і rollback rehearsal deferred до другого independently reviewed queue-compatible fork release. | ADR-0008, RUNBOOK | Не блокує single-release Phase 5 smoke; не є production approval. |

## Task 5.2 — Idempotent orchestration scripts

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-ORCH-001 | Strict env parsing accepts only required deployment inputs; local `.env`, mutable image tags and unsafe values are refused. | `./tests/shell/test-deploy-orchestrator.sh` | Fake Docker boundary; no Docker API або stack state. |
| TB-ORCH-002 | Repeated development deploy submits the same canonical stack without `--prune`; status is read-only. | `./tests/shell/test-deploy-orchestrator.sh` | Fake Docker boundary; actual Swarm convergence належить Task 5.4. |
| TB-ORCH-003 | Production deploy requires `SERVER_ENV=prod`, a release tag, approval context, matching 40-character control-plane SHA and immutable digest; rollback also requires queue-compatibility confirmation. | `./tests/shell/test-deploy-orchestrator.sh` | Fake Docker boundary; live production deploy remains separately approved. |

## Task 5.1 — Single-node Swarm stack і storage/network IaC

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-SWARM-001 | Canonical stack uses only Swarm-native deployment fields, one constrained replica, host publish, persistent `/data`, reviewed Config/Secret mounts, healthcheck and no privileged/host-network/socket escape. | `./tests/security/test-swarm-stack.sh` | Static dev/prod evidence; no Docker API is required for render. |
| TB-SWARM-002 | Bootstrap rejects missing/unencrypted overlay, public CIDR, unsafe storage root and `SERVER_ENV` mismatch; explicit apply is idempotent for reviewed dev prerequisites. | `./tests/security/test-bootstrap-swarm-host.sh` | Fake Docker/nft unit boundary; no host state is mutated. |
| TB-SWARM-003 | External overlay, service Secret target modes, listener and nftables boundary are present after deploy. | `./scripts/check-network-policy.sh --network <effective-development-overlay> --stack-name smtp2graph` | Requires approved development Swarm manager and a deployed Task 5.3 digest. |
| TB-SWARM-004 | Legacy label/storage migration refuses a running gateway and symlinked paths; explicit dev apply converges on repeated execution. | `./tests/security/test-migrate-dev-host.sh` | Fake Docker and test-only `/tmp` root; no host state is mutated. |

## Task 4.2 — TLS, network і client credential boundary

| ID | Контроль | Команда / evidence | Межа |
|---|---|---|---|
| TB-TLS-001 | PEM cert covers `smtp-int.ldubgd.edu.ua`, is unexpired and matches a private key with mode 0400/0600. | `./tests/security/test-reconcile-tls-secret.sh` | Local synthetic certificate only; Cloudflare issuance is external non-production evidence. |
| TB-NET-001 | Stack uses host publish, no routing mesh, TLS key 0400 and deny-by-default nftables policy. | `./tests/security/test-network-policy.sh` | Static IaC evidence. |
| TB-NET-002 | Live overlay is encrypted and nftables policy loaded. | `./scripts/check-network-policy.sh --network <effective-overlay> --stack-name smtp2graph` | Requires authorised Docker API on non-production deployment host. |
| TB-TLS-002 | Gateway advertises STARTTLS; SMTP AUTH before upgrade is rejected and authenticated SMTP after trusted TLS succeeds. | `openssl s_client -starttls smtp -connect <FQDN>:2525 -verify_hostname <FQDN>` plus non-production SMTP client test. | Requires deployed gateway, nftables policy and encrypted overlay. |

## Task 4.5 — Gate C Microsoft 365 authorization review

| ID | Контроль | Evidence | Статус / межі |
|---|---|---|---|
| TB-GATE-C-001 | Dedicated sender mailbox, App Registration naming and ownership are approved. | Redacted Microsoft 365 owner approval and App Registration record. | Виконано для non-production Gate C review; secrets і private credentials не є evidence-артефактами. |
| TB-GATE-C-002 | Application-only authorization sends from the approved mailbox and is denied for an out-of-scope mailbox. | Redacted allowed/denied mailbox results plus read-only verification of the current configuration. | Виконано; effective scope не є tenant-wide. |
| TB-GATE-C-003 | The effective Microsoft 365 restriction mechanism is identified and documented. | Redacted policy review and read-only permission verification. | Виконано; фактичний механізм — Exchange Online RBAC for Applications. |

Gate C result: **passed** for the reviewed non-production authorization boundary. Credential expiry, rotation and revocation procedure are outside the current Gate C acceptance scope.

## Task 3.2 — SMTP policy, rate limits і storage lifecycle

### Policy matrix

| ID | Контроль / очікувана поведінка | Локальний доказ і команда | Статус / межі |
|---|---|---|---|
| TB-POLICY-001 | SMTP вимагає автентифікації; source CIDR, global sender allowlist і per-user sender scope працюють за принципом deny-by-default. | `./tests/security/test-smtp-policy.sh`; `./tests/shell/test-render-config.sh` | Перевірено для control-plane render boundary. Deployment network policy та Docker Secret lifecycle поза межами тесту. |
| TB-POLICY-002 | Oversize input, відсутній SMTP AUTH і автентифікований sender поза allowlist відхиляються без `.eml` payload у `queue/`. | `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply`; asset `006-rejected-submission-queue-isolation.patch` | Перевірено в isolated patched fork worktree. Це ще не Docker MVP harness Task 3.3. |
| TB-POLICY-003 | За configured capacity threshold новий `MAIL FROM` відхиляється SMTP `451` до `DATA`; queue payload не створюється. | `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply`; asset `005-smtp-policy-and-storage-guards.patch` | Перевірено локально для порога 80%. Capacity accounting process-local і припускає single-replica topology. |
| TB-POLICY-004 | Не більше 5 concurrent sessions на source IP та 30 messages/min/client; вивільнений session slot придатний для повторного використання. | `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply`; asset `005-smtp-policy-and-storage-guards.patch`; `./tests/shell/test-entrypoint.sh` | Перевірено локально. Wrapper рендерить погоджені defaults, а fork tests покривають session-slot release і SMTP `451` при перевищенні rate limit. |
| TB-POLICY-005 | Failed-payload retention торкається лише `${SMTP2GRAPH_STORAGE_ROOT}/failed`; default — dry-run; queue і файли молодші за сім днів не змінюються. | `./tests/shell/test-purge-failed.sh`; `./tests/security/test-purge-failed.sh` | Перевірено для local maintenance helper. Scheduling і deployment lifecycle належать до наступних задач. |
| TB-POLICY-006 | Gateway console і локальні Winston file logs не містять SMTP body або attachment markers. | `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply`; asset `007-receive-log-privacy.patch` | Перевірено в isolated patched fork worktree. Swarm, host log driver, retention і external aggregation не покриті. |
| TB-POLICY-007 | Moodle використовує загальні gateway limits: 5 concurrent sessions на source IP і 30 messages/min/client. | `./tests/shell/test-entrypoint.sh`; `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply`; asset `005-smtp-policy-and-storage-guards.patch` | Погоджений policy baseline. Task 6.2 додатково перевіряє Moodle burst behavior у межах цих загальних лімітів до production onboarding. |

## Task 3.3 — Local end-to-end MVP harness

### TB-MVP-001 — Patched local SMTP-to-Graph flow

- **Мета:** відтворювано перевірити patched gateway через SMTP і isolated mock Graph без external delivery.
- **Середовище:** clean `v1.1.5` temporary worktree з assets `001–007`, local ephemeral image, internal Compose network, loopback SMTP port і synthetic secrets у `/dev/shm`.
- **Перевірка:** позитивна SMTP submission проходить до mock Graph і queue спорожнюється; відсутній AUTH, sender поза allowlist і oversize message відхиляються без queue payload; submission під час mock timeout переживає restart gateway і доставляється після повернення mock Graph до success.
- **Команда:** `make test-local`.
- **Результат 2026-07-29:** пройшов після replay усіх семи assets, `npm run build`, 6 unit tests і receive suite. Temporary image, Compose resources, worktree й upgrade branch очищено.
- **Межі:** test не звертається до Microsoft 365 і не є Gate B approval, GHCR release evidence, deployment або production capacity test.

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
