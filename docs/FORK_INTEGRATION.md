# Контракт інтеграції gateway fork

**Статус:** погоджений design contract; gateway source repository ще не створено.

## Межа репозиторіїв

| Область | Репозиторій | Відповідальність |
|---|---|---|
| Control plane | `mzhk-repo/smtp2graph-deploy` | IaC, deployment digest pinning, qualification evidence, integration tests і документація |
| Build plane | `mzhk-repo/smtp2graph-build` (створити) | Fork source, локальні патчі, gateway unit/regression tests, Docker build та публікація в GHCR |

Поточний repository не містить gateway source tree, не збирає gateway image і не є GitHub fork network. Build repository має містити повну історію upstream або відтворюваний import exact tag. Це усуває конфлікт між upstream application code та control-plane файлами.

## Вихідна база й remotes

- Перший fork baseline: upstream `SMTP2Graph/SMTP2Graph` tag `v1.1.5`, commit `3a1ab485ed6c50265889cb230d8fbf73e2587e06`.
- `origin` у build repository: writable `https://github.com/mzhk-repo/smtp2graph-build.git`.
- `upstream`: read-only `https://github.com/SMTP2Graph/SMTP2Graph.git`.
- `upstream` ніколи не є ціллю `push`; mutable upstream branch не є deployment input.


## Versioned patch automation

Control plane зберігає reviewed application patch bundle у
`patches/smtp2graph/v1.1.5/`. `scripts/upgrade-smtp2graph-fork.sh` застосовує
його до explicit або latest stable upstream tag в isolated local worktree та
залишає local `upgrade/vX.Y.Z` branch для review. Bundle, а не історія fork
commits, є source of truth. Скрипт не виконує push, PR, deploy або automatic
conflict resolution; деталі й recovery описані у `docs/UPSTREAM_PATCH_AUTOMATION.md`.

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

## Release supply-chain evidence — Task 5.3

Task 5.3 є єдиним власником GHCR build/push і трьох supply-chain evidence-артефактів, кожен з яких прив'язаний до exact fork image digest:

1. Trivy image scan exact digest; кожен дозволений Critical/High finding має Formal Exception Record з owner, rationale, expiry і compensating controls.
2. CycloneDX SBOM, згенерований Syft.
3. OCI labels для fork release tag, source revision і upstream base commit.

Поточний shared workflow надає GHCR build/push, але ще не створює ці три артефакти для exact digest. Digest залишається обов'язковим ідентифікатором image, бо саме він є target Trivy scan, SBOM і OCI metadata record. Functional Gate B не виконує build/push і не генерує release artifacts; Task 5.3 передає їх у control plane та вимагає перевірки застосовності перед staging/production promotion. Provenance attestation, signature verification та окремий reusable-workflow output не входять до погодженого scope. Для GHCR використовується scoped `GITHUB_TOKEN`; long-lived registry token не потрібний.

## Передача у control plane

Upstream v1.1.5 digest та його evidence не переносяться на fork. Кожен fork source revision проходить повторні blocker, MIME, restart і non-production Microsoft 365 checks до functional Gate B decision; кожен Task 5.3 fork digest окремо проходить scan/SBOM та release-evidence review до staging або production promotion.

## Ліцензія й rollback

Fork зберігає GPL-3.0 license text, copyright notices, upstream attribution і повний відповідний source/patch history для кожного поширеного image.
