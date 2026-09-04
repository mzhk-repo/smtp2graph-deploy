# smtp2graph

Приватний SMTP-to-Microsoft Graph gateway для внутрішніх сервісів. Upstream SMTP2Graph v1.1.5 відхилено на Gate B; production runtime ще не реалізований. Наступним candidate буде окремий мінімальний fork лише після нової digest-scoped qualification.

## Документація

- [`docs/SPEC.md`](docs/SPEC.md) — погоджені вимоги та security baseline.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — порядок реалізації та quality gates.
- [`docs/AI_CONTEXT.md`](docs/AI_CONTEXT.md) — компактний актуальний контекст.
- [`docs/adr/README.md`](docs/adr/README.md) — індекс базових architecture/security decisions.
- [`docs/FORK_INTEGRATION.md`](docs/FORK_INTEGRATION.md) — межа control-plane/build repositories, GHCR release contract і безпечне оновлення fork.
- [`docs/CERTIFICATE_RUNBOOK.md`](docs/CERTIFICATE_RUNBOOK.md) — первинний випуск і ручна ротація TLS/Graph certificates.
- [`CHANGELOG.md`](CHANGELOG.md) — індекс томів changelog.

## Локальні prerequisites

- GNU Make 4.3 або новіший;
- Git;
- Python 3.12 із модулем `venv`;
- мережевий доступ лише під час першого завантаження pinned development hooks.

## Безпечні локальні команди

Підготувати ізольований toolchain у `.venv/` і `.cache/pre-commit/`:

```bash
make bootstrap
```

Запустити non-mutating перевірки Markdown, YAML, shell formatting і whitespace:

```bash
make validate
```

`make validate` не читає `.env` файли, не отримує secrets і не звертається до Docker або production. `gitleaks` і `ShellCheck` виконуються на CI-рівні з конфігураціями `.gitleaks.toml` та `.shellcheckrc`.

## Configuration contract

[`.env.example`](.env.example) містить лише safe development values та імена майбутніх Docker Secrets. Він не є production env-файлом і не повинен копіюватися в `.env`.

Machine-checkable ключі визначені у [`deploy/config/env-contract.keys`](deploy/config/env-contract.keys). Перевірка не використовує `source`, не друкує values і доступна окремо:

```bash
make verify-env
```

Contract є experimental до Gate B. Qualification candidate version/digest зафіксовано в [`deploy/config/gateway-version.md`](deploy/config/gateway-version.md), але SMTP2Graph upstream keys, runtime render paths і production recipient policy буде визначено тільки після повної кваліфікації кандидата.

## Isolated runtime qualification

Task 2.3 має відтворюваний synthetic compatibility probe:

```bash
./tests/acceptance/runtime/run.sh
```

Він потребує доступного Docker daemon, створює лише тимчасові containers і synthetic certificate/secret files, використовує `network=none` та очищує ресурси після завершення. Це не є production deployment або доказом Graph delivery.

## Protocol qualification

Synthetic MIME, queue-restart та Graph failure-injection evidence описані в [`docs/TEST_PLAN.md`](docs/TEST_PLAN.md). Локальні commands не звертаються до Microsoft 365:

```bash
./tests/acceptance/protocol/run.sh
./tests/acceptance/protocol/failure-injection.sh
```

Другий command зараз завершується non-zero навмисно: він фіксує підтверджені Gate B blocker-и SMTP2Graph v1.1.5.

## Local end-to-end MVP harness

Task 3.3 надає відтворювану локальну перевірку patched gateway без Microsoft 365, production credentials або deployment:

```bash
make test-local
```

Команда потребує Docker Engine, Docker Compose v2, Node.js, OpenSSL і доступу до локального upstream checkout `/opt/smtp2graph-build` лише як до Git source для exact tag. Спочатку `scripts/upgrade-smtp2graph-fork.sh` застосовує versioned assets `001–007` до clean temporary worktree, виконує build/unit/receive regressions і збирає local ephemeral image. Потім Compose створює internal network із mock Graph, synthetic secrets у `/dev/shm`, перевіряє positive SMTP flow, відмови без AUTH/для denied sender/oversize message та queue restart. Worktree, local image, containers, network і synthetic state очищуються автоматично.

Це local functional evidence, а не Gate B approval, release image, supply-chain evidence або production deployment.

## Deployment safety

Активного deployment workflow або SMTP2Graph orchestrator у repository ще немає. Koha-derived assets ізольовані в quarantine й не повинні виконуватися. Production deployment дозволений лише після відповідних roadmap gates і reviewed IaC.
