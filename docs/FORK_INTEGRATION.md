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

Build repository викликає reusable dispatcher
`mzhk-repo/shared-workflows/.github/workflows/shared-ci-cd.yml@main` лише для
валідації, build і GHCR push. Він не передає `deploy: true` та не отримує
deployment secrets. Caller routes are fixed as follows:

| Caller event | `environment_name` | `deploy` | Expected result |
|---|---|---:|---|
| PR to `dev` | n/a | n/a | validation only, no package/deploy permissions or secrets |
| push to `dev` | `development` | `false` | build and push development image only |
| tag `vX.Y.Z` | `production` | `false` | build/push, exact-digest Trivy, CycloneDX, checksums and non-overwritable GitHub Release |

`shared-ci-cd.yml@main` is the sole reviewed mutable-reference exception by
owner direction. Every other Action and container image reference is pinned to
an immutable commit SHA or digest. `secrets: inherit` remains limited to the
trusted same-organization shared workflow.

## Поточна поведінка build і deploy

Shared workflow runs source checks, filesystem Trivy, Gitleaks, Hadolint and
Compose validation. A build caller may set `build_and_push_docker: true` and
`push_docker_image: true`; its image digest remains an optional shared input,
not a deployment instruction.

Deployment belongs only to the control plane `workflow_dispatch` workflow. It
accepts an explicit `IMAGE@sha256:...`, invokes the shared Swarm path with
`build_and_push_docker: false`, and runs `scripts/ci-deploy-swarm.sh` on the
remote host. The wrapper maps only the reviewed context to
`deploy-orchestrator-swarm.sh --env-file ... --deploy --apply`; production
also requires release tag, approval context and exact control-plane SHA.

## Release supply-chain evidence — Task 5.3

Task 5.3 є єдиним власником GHCR build/push і трьох supply-chain evidence-артефактів, кожен з яких прив'язаний до exact fork image digest:

1. Trivy image scan exact digest; кожен дозволений Critical/High finding має Formal Exception Record з owner, rationale, expiry і compensating controls.
2. CycloneDX SBOM, згенерований Syft.
3. OCI labels для fork release tag, source revision і upstream base commit.

The tag path generates these artifacts for the exact digest and refuses an
existing GitHub Release tag. Before production deploy, the protected
environment approver manually verifies the Release URL plus Trivy/SBOM hashes
entered in the control-plane dispatch. No cross-repository read token or App
credential is used. Functional Gate B does not perform build/push.

## Historical Gitleaks classification

Five historical upstream records are limited to API-key-like example values in
`config.example.yml` and `test/readme.md`, plus the old self-signed
`test/localhost.key`. The current source uses explicit non-secret markers and
generates the localhost TLS pair at receive-test runtime; no Gitleaks baseline,
allowlist or exception is added. A full history scan remains expected to report
the immutable upstream commits until a separately approved history-rewrite
decision exists.

## Передача у control plane

Upstream v1.1.5 digest та його evidence не переносяться на fork. Кожен fork source revision проходить повторні blocker, MIME, restart і non-production Microsoft 365 checks до functional Gate B decision; кожен Task 5.3 fork digest окремо проходить scan/SBOM та release-evidence review до staging або production promotion.

## Ліцензія й rollback

Fork зберігає GPL-3.0 license text, copyright notices, upstream attribution і повний відповідний source/patch history для кожного поширеного image.
