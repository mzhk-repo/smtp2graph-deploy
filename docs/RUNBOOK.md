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

Перед кожним stack submission orchestration ідемпотентно викликає `init-storage.sh` для валідованого storage root і його direct `queue`/`failed` children. Репетиція не створює Docker Secrets, не надсилає SMTP test message і не змінює queue payloads. Вона підтверджує fresh deploy, no-op redeploy та read-only runtime health contract одного release.

Observability endpoints (`/livez`, `/readyz`, `/metrics`) слухають лише на encrypted overlay port `9464` і не мають host-published port. VictoriaMetrics scraper має бути приєднаний до цього overlay та імпортувати `deploy/monitoring/smtp2graph-scrape.yml`; без цього metrics endpoint існує, але не є dashboard/alert signal. Docker `local` logging driver обмежує host logs розміром і кількістю файлів; central logging owner окремо підтверджує 30-day time retention.

### Verify and close

- Зберегти non-secret command output як operator evidence і виконати `scripts/check-network-policy.sh --network <effective-development-overlay> --stack-name smtp2graph`.
- Не записувати Docker Secret content, SMTP passwords або message bodies у evidence.

### Deferred rollback і duplicate risk

Live rollback rehearsal відкладено до появи другого independently reviewed fork release. До того моменту не використовувати rollback command для цього single-release deployment. Для будь-якого rollback оператор фіксує review exact digest pair у non-secret evidence та лише тоді передає `--queue-compatibility-confirmed`. ADR-0008 залишається чинним: під час майбутнього rollback/recovery модель delivery є At-Least-Once, тому можливий duplicate є прийнятнішим за silent loss.
