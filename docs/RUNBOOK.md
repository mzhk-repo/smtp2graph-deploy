# Runbook розгортання SMTP2Graph

## Task 5.4 — development single-release rehearsal

Ця процедура призначена лише для development і не використовує production host, credentials або recipients.

### Preconditions

- Exact immutable digest має reviewed build-plane release evidence: Trivy result або exception, CycloneDX SBOM, checksums та OCI metadata.
- Host має `SERVER_ENV=dev`, development storage root є здоровим, а configuration/host backup reference зафіксовано. Планові backups ніколи не містять live `queue/` або `failed/` payloads.
- Authorized operator має local ignored `.env` з allowlisted development inputs, exact immutable `SMTP2GRAPH_IMAGE_DIGEST` і versioned Docker Secret names. Placement label деривується з `DEPLOY_ENVIRONMENT=development` як `smtp2graph_dev`; digest є єдиним image input для deploy.

### Run

Виконувати лише на authorised development Swarm manager.

```bash
./scripts/deploy-orchestrator-swarm.sh \
  --deploy --apply

./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph

./tests/observability/test-signals.sh --environment development

./scripts/deploy-orchestrator-swarm.sh \
  --deploy --apply

./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph
```

Перед кожним normal stack submission orchestration content-addressably reconciles runtime Docker Secrets із вибраного SOPS contract, атомарно оновлює names-only mapping та ідемпотентно викликає `init-storage.sh` для валідованого storage root і його direct `queue`/`failed` children. Зміна Secret content змінює task template і створює replacement task; без зміни content повторний deploy лишається no-op для task. Репетиція не надсилає SMTP test message і не змінює queue payloads. Вона підтверджує fresh deploy, no-op redeploy та read-only runtime health contract одного release.

Observability endpoints (`/livez`, `/readyz`, `/metrics`) слухають лише на encrypted overlay port `9464` і не мають host-published port. VictoriaMetrics scraper приєднаний до цього overlay та імпортує `deploy/monitoring/smtp2graph-scrape.yml` з labels `env=prod`, `service=smtp2graph`, `component=gateway`. Docker `local` logging driver є прийнятою retention policy: не більше 30 файлів по 10 MiB, без time-based retention SLA.

## Task 7.2 — Alerts і independent synthetic delivery

Моніторинговий control plane у `/opt/victoriametrics-grafana` є owner-ом Grafana dashboard, VictoriaMetrics alert rules і synthetic runner. Runner має одну репліку, надсилає контрольоване STARTTLS-повідомлення до recipient з `NONPRODUCTION_RECIPIENT_ALLOWLIST`, з'єднується з gateway лише через DNS alias `gateway` у `smtp2graph_internal_enc`, а не через `127.0.0.1`. Успішним result є SMTP acceptance та зростання `smtp2graph_delivery_attempts_total{result="succeeded"}` у VictoriaMetrics.

Період runner-а за замовчуванням — 900 секунд і не може бути меншим за 60 секунд. Він публікує status і freshness threshold (`interval + grace`, default grace 300 секунд) через Node Exporter textfile collector. Alert freshness використовує цю метрику без захардкодженого порогу. Synthetic credentials зберігаються тільки як versioned Docker Secret у monitoring stack; вони не належать до SMTP2Graph env contract, logs або evidence.

Алерти gateway покривають unavailable metrics endpoint, SMTP auth failures, Graph delivery failures/retries, storage 60/80%, non-empty failed queue і TLS certificate expiry за 30/7 днів. Grafana notification route використовує independent external SMTP provider, не SMTP2Graph. Перед закриттям incident перевірити dashboard, `up==1`, свіжий successful synthetic result і відновлення delivery counter; не копіювати body, marker, recipient чи Secret values до ticket/evidence.

На authorised monitoring manager виконати:

```bash
cd /opt/victoriametrics-grafana
./tests/test-observability-config.sh
./tests/integration/test-synthetic-and-metrics.sh
```

## Task 7.3 — Manual control-plane backup і cold recovery

Ansible schedules this procedure outside the repository. The operator runs it
at least daily to support the 24-hour configuration RPO. Backup destinations
are read only from the selected SOPS-encrypted `env.*.enc`: local host path,
rclone remote and rclone path. `rclone` credentials and the age private
recovery identity are external custody items and are never archived.
During an explicit declarative deploy or rollback, `init-storage.sh` creates
the local backup path with mode `0700` and initializes the configured rclone
path. It never creates either destination during validation-only checks.

```bash
./scripts/backup.sh --environment development \
  --env-file /absolute/path/to/env.dev.enc --check
./scripts/backup.sh --environment development \
  --env-file /absolute/path/to/env.dev.enc --apply
```

Each archive contains only the encrypted environment source, deployment and
recovery control-plane files, and a non-secret manifest. It never contains
Docker Secret payloads, host `.env`, `/data/queue`, `/data/failed`, `/data/logs`
or message content. Retention is 7 local and 30 cloud archives.

Restore only to a new or empty path on a clean host. It does not restore live
queue state or deploy automatically. After extraction, restore the age identity
from approved escrow, reconcile Docker Secrets from encrypted env, bootstrap,
deploy the approved digest, then perform health and independent synthetic
verification. Record elapsed time but do not evaluate it against an RTO.

### Verify and close

- Зберегти non-secret command output як operator evidence і виконати `scripts/check-network-policy.sh --network <effective-development-overlay> --stack-name smtp2graph`.
- Не записувати Docker Secret content, SMTP passwords або message bodies у evidence.

### Deferred rollback і duplicate risk

Live rollback rehearsal відкладено до появи другого independently reviewed fork release. До того моменту не використовувати rollback command для цього single-release deployment. Для будь-якого rollback оператор фіксує review exact digest pair у non-secret evidence та лише тоді передає `--queue-compatibility-confirmed`. ADR-0008 залишається чинним: під час майбутнього rollback/recovery модель delivery є At-Least-Once, тому можливий duplicate є прийнятнішим за silent loss.
