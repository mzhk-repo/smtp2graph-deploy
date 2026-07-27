# Контракт інтеграції gateway fork

**Статус:** погоджений design contract; gateway source repository ще не створено.

## Межа репозиторіїв

| Область | Репозиторій | Відповідальність |
|---|---|---|
| Control plane | `mzhk-repo/smtp2graph` | IaC, deployment digest pinning, qualification evidence, integration tests і документація |
| Build plane | `mzhk-repo/smtp2graph-build` (створити) | Fork source, локальні патчі, gateway unit/regression tests, Docker build та публікація в GHCR |

Поточний repository не містить gateway source tree, не збирає gateway image і не є GitHub fork network. Build repository має містити повну історію upstream або відтворюваний import exact tag. Це усуває конфлікт між upstream application code та control-plane файлами.

## Вихідна база й remotes

- Перший fork baseline: upstream `SMTP2Graph/SMTP2Graph` tag `v1.1.5`, commit `3a1ab485ed6c50265889cb230d8fbf73e2587e06`.
- `origin` у build repository: writable `https://github.com/mzhk-repo/smtp2graph-build.git`.
- `upstream`: read-only `https://github.com/SMTP2Graph/SMTP2Graph.git`.
- `upstream` ніколи не є ціллю `push`; mutable upstream branch не є deployment input.

Якщо GitHub fork network потрібна для upstream pull request, current control-plane repository слід окремо перейменувати, щоб звільнити назву `smtp2graph`, і лише потім створювати network fork. До такого окремого рішення build repository є звичайним Git repository з явним `upstream` remote; це не послаблює provenance або patch control.

## Гілки й захист патчів

| Ref | Призначення | Правило |
|---|---|---|
| `upstream/v1.1.5` | Локальний immutable reference до upstream tag | Не змінюється й не є release branch |
| `mzhk/v1.1.5-gate-b` | Серія трьох reviewable remediation commits | Protected; зміни лише через PR |
| `upgrade/v1.1.6` | Тимчасова гілка перенесення патчів на новий upstream tag | Створюється для кожного upgrade; merge лише після full regression і Gate B applicability review |
| `fork-v1.1.5.1` | Signed release tag fork | Єдиний source input для build pipeline |

Заборонено виконувати `git pull upstream main` або merge mutable upstream branch у `mzhk/*`. Для нового upstream release pipeline має бути таким:

```bash
git fetch upstream --tags --prune
git switch --create "upgrade/vX.Y.Z" "vX.Y.Z"
git rebase --onto "vX.Y.Z" "v1.1.5" "mzhk/v1.1.5-gate-b"
git range-diff "v1.1.5...mzhk/v1.1.5-gate-b" "vX.Y.Z...HEAD"
```

Конфлікт під час rebase зупиняє upgrade. Його не можна розв'язувати автоматично або обхідним видаленням патчу. Кожен перенесений commit потребує review, тестів і оновленого patch inventory.

## Обов'язковий patch inventory

Build repository веде `docs/PATCH_INVENTORY.md`. Для кожного патчу потрібні: upstream base commit, fork commit SHA, owner, причина, upstream issue/PR (якщо є), affected files, regression tests і статус перенесення на нові upstream release.

Початковий inventory міститиме рівно три remediation items:

1. bounded exponential backoff із jitter та Graph `Retry-After` у delta-seconds і HTTP-date;
2. класифікація permanent Graph error і atomic transfer з live queue до `failed`;
3. durable SMTP acknowledgement після rename та `fsync` queue file і directory.

## Shared CI/CD: фактичний caller contract

Неактивний caller template зберігається у build repository за шляхом
`.github/quarantine/main.yml.disabled`. Він не є GitHub Actions workflow, доки
окремий reviewed change не перенесе його до `.github/workflows/` після закриття
activation blockers. Koha-specific template більше не належить control-plane
repository.

Build repository викликає reusable workflow `shared-workflows/.github/workflows/shared-ci-cd-swarm.yml`. Сам shared workflow має лише trigger `workflow_call`; він не визначає гілки. Caller workflow має реалізовувати й зберігати такий mapping:

| Caller push | `environment_name` | `deploy` | Очікуваний результат |
|---|---|---:|---|
| `dev` | `development` | `true` | GHCR build/push і автоматичний deploy у development |
| `main` | `production` | `true` | GHCR build/push і автоматичний deploy у production |

Для обох гілок caller передає `build_and_push_docker: true`, `docker_image_name: smtp2graph-build`, шлях до orchestration script та мінімально необхідні shared secrets. `push_docker_image` не потрібен за `deploy: true`, оскільки shared workflow у цьому режимі вже пушить image.

Приклад структури caller (імена secret mappings належать конкретному репозиторію):

```yaml
on:
  push:
    branches: [main, dev]

jobs:
  deploy-development:
    if: github.ref_name == 'dev'
    uses: mzhk-repo/shared-workflows/.github/workflows/shared-ci-cd-swarm.yml@<immutable-commit>
    with:
      environment_name: development
      deploy: true
      build_and_push_docker: true
      docker_image_name: smtp2graph-build
    secrets: inherit

  deploy-production:
    if: github.ref_name == 'main'
    uses: mzhk-repo/shared-workflows/.github/workflows/shared-ci-cd-swarm.yml@<immutable-commit>
    with:
      environment_name: production
      deploy: true
      build_and_push_docker: true
      docker_image_name: smtp2graph-build
    secrets: inherit
```

`secrets: inherit` у прикладі допустимий лише для trusted same-organization reusable workflow. Для менш широкого trust boundary caller має явно передавати тільки secrets, перелічені у workflow contract. `main` та production environment мають бути protected; автоматичний production deploy є поточною policy, а не Gate B approval.

Поточний quarantined template використовує mutable `@main` на явний запит
repository owner. Це тимчасовий security exception: до activation reference
має бути замінений на immutable commit SHA після review shared workflow.

## Поточна поведінка build і deploy

Shared workflow спершу виконує CI checks, file-system Trivy scan, Gitleaks, Hadolint і compose validation. Якщо `build_and_push_docker: true`, він будує `ghcr.io/${owner}/smtp2graph-build`; metadata-action створює branch tag (`main` або `dev`) і SHA tag. За push у `main` або `dev` image пушиться, бо `deploy: true`.

Після CI job `cd-deploy` отримує deployment credentials: SSH, Tailscale OAuth і SOPS age private key. Він decrypts environment file, підключається до remote host, checkout-ить exact caller commit (`DEPLOY_REF=${github.sha}`), потім виконує local orchestration script або Swarm compose fallback. Отже shared CI/CD фактично виконує автоматичний deploy у відповідне середовище; він не є build-only workflow.

Remote deployment зобов'язаний використовувати immutable image digest у manifest/config, а не branch tags `main` чи `dev`. Поточний shared workflow не передає build digest як reusable-workflow output і не може сам гарантувати це правило: orchestration script має отримати або resolve/verify digest fail-closed до `docker stack deploy`.

## Supply-chain evidence Gate B

Для Gate B погоджено рівно три supply-chain evidence-артефакти, кожен прив'язаний до exact fork image digest:

1. Trivy image scan exact digest; кожен дозволений Critical/High finding має Formal Exception Record з owner, rationale, expiry і compensating controls.
2. CycloneDX SBOM, згенерований Syft.
3. OCI labels для fork release tag, source revision і upstream base commit.

Поточний shared workflow надає GHCR build/push, але ще не створює ці три артефакти для exact digest. Digest залишається обов'язковим ідентифікатором image, бо саме він є target Trivy scan, SBOM і OCI metadata record. Provenance attestation, signature verification та окремий reusable-workflow output не входять до Gate B supply-chain scope. Для GHCR використовується scoped `GITHUB_TOKEN`; long-lived registry token не потрібний.

### Container metadata contract

Fork Dockerfile pin-ить multi-platform base image `node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293` і встановлює OCI labels. Qualification/release build зобов'язаний передавати `VERSION`, `VCS_REF`, `RELEASE_TAG` і `UPSTREAM_BASE`; значення `unknown` або `unreleased` позначають локальний build, який не може бути Gate B evidence. Обов'язкові labels: `org.opencontainers.image.source`, `revision`, `version`, `ref.name`, `base.name` і `upstream.base`.

## Передача у control plane

Після успішного qualification release PR у `mzhk-repo/smtp2graph` оновлює тільки fork release metadata: source tag, upstream base commit, `ghcr.io` immutable digest, Trivy scan/exception record, CycloneDX SBOM, OCI labels і Gate B applicability record. Deployment manifest ніколи не посилається на mutable tag. Поточні `main`/`dev` deploys не можуть просувати новий candidate у production до появи цього evidence та Gate B decision.

Upstream v1.1.5 digest та його evidence не переносяться на fork. Кожен fork digest проходить повторні blocker, MIME, restart, scan/SBOM і non-production Microsoft 365 checks до рішення Gate B.

## Ліцензія й rollback

Fork зберігає GPL-3.0 license text, copyright notices, upstream attribution і повний відповідний source/patch history для кожного поширеного image. Видалення або revert fork release означає повернення control-plane лише на попередній approved digest після queue compatibility review; upstream `v1.1.5` не може бути rollback target, бо він rejected.
