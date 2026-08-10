# Runbook розгортання SMTP2Graph

## Task 5.4 — development single-release rehearsal

Ця процедура призначена лише для development і не використовує production host, credentials або recipients.

### Preconditions

- `deploy/config/queue-compatibility.yml` містить один exact digest зі status `development-smoke-verified` та independently reviewed release evidence.
- Host має `SERVER_ENV=dev`, development storage root є здоровим, а configuration/host backup reference зафіксовано. Планові backups ніколи не містять live `queue/` або `failed/` payloads.
- Authorized operator має local ignored `.env` з allowlisted development inputs, exact immutable `SMTP2GRAPH_IMAGE_DIGEST` і versioned Docker Secret names. Placement label деривується з `DEPLOY_ENVIRONMENT=development` як `smtp2graph_dev`; `queue-compatibility.yml` є evidence/rollback metadata, а не джерелом deploy digest.

### Run

Виконувати лише на authorised development Swarm manager.

```bash
./scripts/deploy-orchestrator-swarm.sh \
  --deploy --apply

./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph

./scripts/deploy-orchestrator-swarm.sh \
  --deploy --apply

./tests/acceptance/deployment/smoke.sh --stack-name smtp2graph
```

Перед кожним stack submission orchestration ідемпотентно викликає `init-storage.sh` для валідованого storage root і його direct `queue`/`failed` children. Репетиція не створює Docker Secrets, не надсилає SMTP test message і не змінює queue payloads. Вона підтверджує fresh deploy, no-op redeploy та read-only runtime health contract одного release.

### Verify and close

- Зберегти non-secret command output як operator evidence і виконати `scripts/check-network-policy.sh --network <effective-development-overlay> --stack-name smtp2graph`.
- Не записувати Docker Secret content, SMTP passwords або message bodies у evidence.

### Deferred rollback і duplicate risk

Live rollback rehearsal відкладено до появи другого independently reviewed fork release і declared queue-compatible pair. До того моменту не використовувати rollback command для цього single-release deployment. ADR-0008 залишається чинним: під час майбутнього rollback/recovery модель delivery є At-Least-Once, тому можливий duplicate є прийнятнішим за silent loss.
