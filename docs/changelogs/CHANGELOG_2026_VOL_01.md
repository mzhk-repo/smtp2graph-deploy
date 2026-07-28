2026-07-08 — Update System Specification
    Context:
    Change:
    Verification:
    Risks:
Rollback:





2026-07-21 — Task 1.1: inventory та quarantine початкових шаблонів
    Context: Koha-derived workflow і deploy-скрипт могли бути помилково сприйняті як готова SMTP2Graph automation.
    Change: Legacy workflow переміщено поза GitHub Actions discovery path; deploy-скрипт переміщено до quarantine, позбавлено executable bit і заблоковано fail-closed guard. Inventory keep/adapt/replace/remove додано до AI_CONTEXT.
    Verification: Перевірено відсутність активних workflow-файлів, syntax quarantined Bash-скрипта, гарантовану відмову його виконання, Koha-marker inventory та Git diff.
    Risks: Корисні orchestration patterns залишаються лише reference-кодом і потребують повторного security review перед адаптацією.
    Rollback: Повернути quarantined файли до початкових шляхів можна окремою reviewed зміною; deploy guard не знімати до реалізації Task 5.2/5.3.

2026-07-21 — Task 1.2: repository structure та local quality tooling
    Context: Repository не мав єдиної локальної команди статичної перевірки або зафіксованої структури для наступних roadmap-задач.
    Change: Додано мінімальні repository policy-файли, README, змістовні початкові файли для deploy/tests/scripts/lib/docs/adr та `make validate` з pinned Markdown, YAML і shfmt hooks. Gitleaks і ShellCheck залишено в CI без локального дублювання.
    Verification: `make validate`, `bash -n scripts/validate.sh` і `git diff --check` виконано успішно.
    Risks: Перший `make bootstrap` потребує мережевого доступу до pinned upstream repositories; generated `.venv` і cache виключені з Git.
    Rollback: Видалити додані tooling/policy files та каталоги окремою reviewed зміною; production/runtime state відсутній.

2026-07-22 — Task 1.3: configuration contract і безпечний `.env.example`
    Context: Потрібен був перевірний контракт public inputs і secret references без фіксації непідтвердженої SMTP2Graph schema або production values.
    Change: Додано experimental `.env.example`, machine-checkable список ключів, strict example-only validator і negative shell test. `.env` та `.env.*` ігноруються Git, окрім tracked `.env.example`.
    Verification: `./scripts/verify-env.sh --example-only`, `./tests/shell/test-verify-env.sh`, `make validate` і `git diff --check` виконано успішно.
    Risks: Contract не є upstream runtime schema та може змінитися після Gate B; production SOPS/age і Docker Secrets lifecycle визначаються лише в наступних security tasks.
    Rollback: Видалити contract, validator і test окремою reviewed зміною; production secrets або runtime state не створювалися.

2026-07-22 — Task 1.4: AI context, changelog policy та documentation map
    Context: Документаційні артефакти вже існували, але roadmap не мав компактної phase map з явними умовами переходу.
    Change: На початку `docs/ROADMAP.md` додано список Phase 1–8, результати фаз, entry/exit conditions і переходи через Phase Quality Gates та Gate B/C/D. AI_CONTEXT синхронізовано з documentation baseline.
    Verification: Перевірено внутрішні phase links, наявність README/AI_CONTEXT/changelog/documentation map і `git diff --check`.
    Risks: Phase map є навігаційним summary; детальні acceptance criteria залишаються у відповідних phase/task sections.
    Rollback: Видалити додану Phase Map section і Task 1.4 changelog entry окремою reviewed зміною; source requirements не змінювалися.

2026-07-22 — Task 2.1: ADR baseline та component decision
    Context: Архітектурні та security-рішення були погоджені в SPEC, але ще не мали окремих довготривалих decision records.
    Change: Створено ADR-0001…ADR-0007 та індекс ADR. Зафіксовано SMTP-to-Graph boundary, single-node Swarm, sender mailbox, mailbox-scoped Graph authorization, runtime secrets, single-instance topology і cold recovery; ADR-0002 залишено Proposed до Gate B.
    Verification: Перевірено обов’язкові ADR sections, статуси, roadmap/SPEC links, Markdown lint, `git diff --check` і secret scan.
    Risks: ADR-0002 не є підтвердженням upstream component readiness; production implementation залишається заблокованою до Gate B.
    Rollback: Proposed ADR можна уточнити за результатами qualification; Accepted decisions змінюються лише новим superseding ADR.

2026-07-22 — Уточнення ADR-0004: sender mailbox policy
    Context: Початковий MVP використовує одного відправника, але production-вимога потребує ізоляції поштових ідентичностей між сервісами.
    Change: ADR-0004 уточнено: `noreply@ldubgd.edu.ua` використовується лише для MVP, а перед production кожен сервіс отримує окрему dedicated mailbox і sender allowlist.
    Verification: Перевірено ADR sections, синхронізацію з AI_CONTEXT, Markdown lint і `git diff --check`.
    Risks: Production onboarding потребуватиме створення та окремого lifecycle для кількох mailbox identities.
    Rollback: MVP policy залишається доступною як тимчасовий режим; production mailbox model змінюється лише окремим superseding ADR.

2026-07-22 — Task 2.2: pinned SMTP2Graph qualification candidate
    Context: Gate B потребував exact release, immutable image digest і supply-chain evidence до runtime qualification.
    Change: Зафіксовано SMTP2Graph v1.1.5 та multi-platform digest у `deploy/config/gateway-version.md`; додано registry/release metadata, license note, platform manifests і qualification status. ADR-0002 залишається Proposed.
    Verification: Registry manifest inspection, digest-pinned pull, image metadata review, upstream release/Dockerfile review і repository validation виконані; Trivy/Syft/Cosign evidence ще не отримано.
    Risks: Відсутність vulnerability scan, SBOM/signature verification і non-root evidence блокує Gate B та production use.
    Rollback: Видалити candidate artifact і повернути ADR-0002 до стану без pinned candidate; production runtime не змінювався.

2026-07-22 — Roadmap: Syft SBOM перед production
    Context: Фінальний release pipeline потребує відтворюваного software inventory перед Production Deployment Gate.
    Change: У Task 6.3, Release Candidate Gate і Production Deployment Gate додано обов’язкову генерацію CycloneDX SBOM через Syft з exact image digest, hash/immutable artifact retention та pre-deploy verification.
    Verification: Перевірено структуру roadmap і Markdown validation; runtime pipeline не змінювався.
    Risks: Release блокується, якщо Syft artifact відсутній, не відповідає digest або не має immutable retention.
    Rollback: Вилучення candidate/release artifact не повинно обходити SBOM gate; pipeline changes відкочуються окремим reviewed commit.

2026-07-22 — Task 2.3: runtime, secrets і container compatibility spike
    Context: SMTP2Graph v1.1.5 потребував evidence для secret-file rendering, non-root/read-only execution і lifecycle signals до protocol qualification.
    Change: Додано tmpfs-only runtime wrapper і isolated Docker acceptance probe з synthetic certificate та client-secret fallback. Probe перевіряє UID/GID 65532, read-only rootfs, dropped capabilities, no-new-privileges, listener, graceful stop/restart і відсутність synthetic secret у inspect/logs.
    Verification: `./tests/acceptance/runtime/run.sh`, shell syntax checks, `make validate`, `git diff --check` і Gitleaks виконано успішно.
    Risks: Probe працює з `network=none` і synthetic inputs; він не доводить Graph token acquisition, actual delivery, Swarm Secret ownership або queue semantics.
    Rollback: Видалити prototype wrapper і acceptance probe окремою reviewed зміною; production runtime та production secrets не створювалися.

2026-07-22 — Task 2.4: protocol, MIME, queue та acknowledgement qualification
    Context: Gate B потребував фактичних evidence для MIME preservation, SMTP acknowledgement, queue restart і Graph failure behavior без production tenant.
    Change: Додано isolated TLS token/Graph mock, synthetic MIME fixture та protocol/failure-injection harness. Створено `docs/TEST_PLAN.md` із behavior matrix і Gate B gaps.
    Verification: MIME, BCC injection, UTF-8, attachment, SMTP acknowledgement ordering і queue restart пройшли; failure injection підтвердив bounded HTTP 500 retry та виявив два blocker-и.
    Risks: SMTP2Graph v1.1.5 ігнорує Graph `Retry-After` та залишає `ErrorAccessDenied` payload у queue, а не у failed state; actual Microsoft 365 evidence ще відсутній.
    Rollback: Видалити synthetic harness/fixtures окремою reviewed зміною; ADR-0002 не переводити в Accepted і production runtime не створювати.

2026-07-22 — Task 2.5 roadmap: Gate B reject і fork remediation decision
    Context: Protocol qualification виявила три Critical gaps upstream SMTP2Graph v1.1.5, тому Phase 3 не може покладатися на поточний candidate.
    Change: Roadmap фіксує Gate B reject для upstream v1.1.5, порівнює мінімальний fork, інший upstream gateway і власний Production Minimum та обирає fork із малим patch-set. Додано remediation steps, повторну digest-scoped кваліфікацію і Python fallback.
    Verification: `make validate` і `git diff --check` виконано успішно; ADR-0002 та AI_CONTEXT не змінювалися до фактичного повторного Gate B.
    Risks: Fork створює patch maintenance і license obligations; Phase 3 залишається заблокованою до повторного Gate B без Critical gaps.
    Rollback: Відкотити roadmap decision окремою reviewed зміною; вибір іншого component потребує ADR і повного Gate B для його exact digest.

2026-07-22 — Task 2.5: formal upstream Gate B rejection record
    Context: Roadmap already selected a fork remediation path, while ADR-0002, AI context and qualification artifacts still described the rejected upstream candidate as pending.
    Change: ADR-0002, its index, AI context, test plan and gateway-version artifact now consistently mark upstream SMTP2Graph v1.1.5 as Gate B `Rejected`. The records preserve the minimal fork as unqualified remediation only and retain the Phase 3 block.
    Verification: Перевірено посилання та status references; `make validate` і `git diff --check` виконано успішно.
    Risks: The selected fork still has no repository, digest, patch inventory, supply-chain evidence or repeated Gate B evidence; no production approval is implied.
    Rollback: Revert this documentation-only record in a reviewed change only if evidence invalidates the rejection decision; do not use the upstream digest for production.

2026-07-22 — Task 2.5: fork build-repository integration contract
    Context: Поточний repository є control plane, а fork має окремо збирати та публікувати пропатчений gateway image у GHCR без ризику конфлікту з IaC/evidence history.
    Change: Додано `docs/FORK_INTEGRATION.md`: межу між `mzhk-repo/smtp2graph` і майбутнім `mzhk-repo/smtp2graph-gateway`, exact upstream baseline, protected patch/upgrade flow, GHCR release interface, evidence handoff і GPL obligations. README та AI context посилаються на контракт.
    Verification: `make validate` і `git diff --check` виконано успішно.
    Risks: Build repository, branch protections, GHCR package, CI workflow та fork digest ще не створені; документ не є evidence повторного Gate B.
    Rollback: При зміні repository model оновити контракт reviewed зміною; не переносити upstream image або evidence у deployment без нового Gate B.

2026-07-24 — Task 2.5: shared CI/CD integration contract
    Context: Gateway fork має використовувати reusable Swarm/SOPS workflow, де caller push у `main` автоматично deploy-ить production, а push у `dev` — development.
    Change: `docs/FORK_INTEGRATION.md` синхронізовано з actual `workflow_call` inputs, GHCR build/push tags, automatic deploy flow, secrets і Swarm checkout. Documented digest/SBOM/provenance gaps are explicit Gate B blockers; AI context updated.
    Verification: `make validate` і `git diff --check` виконано успішно.
    Risks: Поточний workflow не повертає exact image digest і не створює SBOM/attestation; mutable branch tags не можна використати як deployment artifact.
    Rollback: Повернути попередній contract reviewed зміною; не обходити digest verification або environment protection.

2026-07-24 — Task 2.5: скорочений supply-chain scope Gate B
    Context: Для fork candidate погоджено три достатні supply-chain evidence-артефакти без provenance/signature requirements.
    Change: SPEC, roadmap, ADR-0002, gateway-version artifact, fork contract і AI context обмежують Gate B supply-chain scope до Trivy image scan exact digest із Formal Exception Record, Syft CycloneDX SBOM та OCI labels для metadata tracking. Три Critical функціональні blocker-сценарії залишаються обов'язковими.
    Verification: `make validate` і `git diff --check` виконано успішно.
    Risks: Відсутність provenance/signature evidence не має компенсувати функціональні або security defects; exception без owner/expiry/controls неприйнятний.
    Rollback: Повернути додаткові supply-chain controls окремою reviewed зміною, не послаблюючи три Critical функціональні Gate B checks.

2026-07-25 — Task 2.5: fork remediation implementation та локальні regression tests
    Context: Upstream SMTP2Graph v1.1.5 був відхилений через `Retry-After`, permanent-error-to-`failed` і durable SMTP acknowledgement blocker-и.
    Change: У окремому fork `smtp2graph-gateway` від exact tag `v1.1.5` реалізовано Graph `Retry-After` для delta-seconds та HTTP-date з bounded jittered backoff, atomic transfer permanent error у `failed`, а також durable enqueue через rename і `fsync` EML/queue directory до SMTP `250`. Додано unit та queue regression tests; TLS test зроблено сумісним з актуальним OpenSSL error text.
    Verification: 6 unit tests, `npm run build` і `npm run test:receive` (28 passed) виконано успішно у fork. Fork commits: `6d23ee0`, `3483c5b`.
    Risks: Fork ще не має release image digest, Trivy exact-digest scan/exception record, Syft CycloneDX SBOM, OCI metadata record або повторного Gate B decision.
    Rollback: Повернутися до exact upstream baseline або попереднього reviewed fork commit; upstream `v1.1.5` не є production rollback target.

2026-07-25 — Task 2.5: non-production Microsoft 365 allowed-mailbox evidence
    Context: Gate B вимагав evidence реальної Graph/Exchange Online доставки без production credentials і recipient data.
    Change: У контрольованому non-production tenant виконано synthetic `npm run test:send` suite після надання app permission `Mail.Read` для test mailbox verification. Підтверджено delivery, plain text, HTML, To/CC/BCC/Reply-To, attachments, inline attachments, відсутні From/To/CC headers і proxy flow.
    Verification: 10/10 non-production send scenarios passed. Локальний `.env` з credential values залишається ignored by Git і не виводився в logs.
    Risks: Certificate credential mode, Exchange display-name behavior і `DENIED_MAILBOX` → `ErrorAccessDenied` → `failed` evidence ще не завершені; negative test потребує deterministic Message-ID у test harness.
Rollback: Припинити використання non-production app або відкликати test secret/permission; не переносити test credentials чи messages у Git або production.

2026-07-25 — Task 2.5: локальний fork checkout зафіксовано в AI context
    Context: Control plane потребував фактичного посилання на доступний build-plane checkout після remediation implementation.
    Change: `docs/AI_CONTEXT.md` тепер посилається на `/opt/smtp2graph-gateway`, branch `patched-v1.1.5`, HEAD `8d99940` і remediation commits; зафіксовано, що fork ще не має завершеного exact-digest Gate B approval.
    Verification: Перевірено clean git state fork, remotes, HEAD і наявність remediation commits; виконано `git diff --check`.
    Risks: Локальний checkout не є immutable release artifact і не може використовуватися для production deployment.
    Rollback: Відкотити лише документаційний запис reviewed зміною; fork source та runtime state не змінювалися.

2026-07-25 — Task 2.5: non-production Microsoft 365 denied-mailbox evidence
    Context: Після 10 позитивних send scenarios залишався незавершеним Critical blocker сценарій `DENIED_MAILBOX` → `ErrorAccessDenied` → `failed`.
    Change: У fork виправлено test-harness звернення до `result.messageId`; лише `test/02send/03accessDenied.spec.ts` виконано проти non-production tenant.
    Verification: 1/1 scenario passed: SMTP submission повернув message ID, а `ErrorAccessDenied` payload знайдено в `mailroot/failed` після durable SMTP acknowledgement. Секретні значення `.env` не виводилися.
    Risks: Certificate credential mode, Exchange display-name behavior, exact fork image digest, Trivy scan/exception, Syft CycloneDX SBOM та OCI metadata ще не завершені; Gate B не пройдений.
    Rollback: Не використовувати fork у production; synthetic failed payloads очищувати за погодженою процедурою без внесення у Git.

2026-07-25 — CI/CD: gateway caller template перенесено до build plane quarantine
    Context: Koha-specific workflow у control plane не відповідав межі repository ownership і не міг безпечно будувати gateway image.
    Change: Legacy template видалено з `mzhk-repo/smtp2graph`; adapted inactive caller template додано до `/opt/smtp2graph-gateway/.github/quarantine/main.yml.disabled`. Template містить PR validation без secrets/deploy, planned `dev`/`main` mapping, least permissions, concurrency, activation blockers і mutable `@main` як explicit temporary exception.
    Verification: YAML structure, `git diff --check` і local quality checks виконуються перед handoff; файл залишається поза GitHub Actions discovery path.
    Risks: `@main` є mutable supply-chain reference; shared workflow secret interface, protected environments, orchestration script, exact digest verification і Gate B ще не готові для activation.
    Rollback: Не переносити template до `.github/workflows/`; повернути лише документаційний/template move reviewed зміною без activation або deploy.

2026-07-25 — Roadmap: CI/CD scope перенесено з Task 2.5 до Task 5.3
    Context: Task 2.5 змішував functional Gate B qualification із CI/CD build/release, digest і supply-chain automation.
    Change: Task 2.5 тепер охоплює remediation, protocol/runtime/Microsoft 365 evidence та Gate B review. Task 5.3 є власником workflow activation, build/push, exact digest, Trivy exception record, Syft CycloneDX SBOM, OCI metadata та immutable artifact retention.
    Verification: Перевірено Phase 2 → Phase 5 dependency: Gate B зберігає applicability review release evidence, а Task 5.3 не стає передумовою Phase 2.
    Risks: Перенесення не послаблює Gate B: fork не стає production component без applicable digest-scoped release evidence і Gate B decision.
    Rollback: Повернути roadmap wording reviewed зміною; не переносити CI/CD implementation назад у Gate B task без перегляду phase dependency.

2026-07-25 — Task 2.5: non-production Microsoft 365 certificate credential evidence
    Context: Certificate-file authentication was the remaining credential-mode gap for the fork Gate B review after client-secret delivery evidence.
    Change: Added an isolated certificate-only send test; gateway configuration omits `appReg.secret` and uses `AZURE_CERT_THUMBPRINT` plus `AZURE_CERT_PRIVATE_KEY_PATH`.
    Verification: 1/1 synthetic send-and-read scenario passed. The private key was not printed; its local path was corrected after repository rename and confirmed with mode `0600`.
    Risks: Exchange display-name behavior, exact fork image digest, Trivy scan/exception, Syft CycloneDX SBOM and OCI metadata remain incomplete; Gate B is not passed.
    Rollback: Do not use the fork in production; retain the local key only until a separately approved SOPS + age and versioned Docker Secret cutover.

2026-07-25 — Консолідований стан виконаних Gate B і CI/CD ітерацій
    Context: Control/build repositories перейменовано на `/opt/smtp2graph-deploy` і `/opt/smtp2graph-build`; потрібно зафіксувати фактичний status і blockers після certificate credential qualification.
    Change: У build plane додано неактивний CI/CD caller template, Gate B CI/CD scope перенесено до Task 5.3, виконано client-secret delivery/proxy, denied-mailbox і certificate-only Microsoft 365 checks; Task 4.3 доповнено SOPS-encrypted `GRAPH_CERT_PRIVATE_KEY_PEM` → versioned Docker Secret lifecycle.
    Verification: 10 positive client-secret scenarios, 1 denied-mailbox scenario і 1 certificate-only synthetic send-and-read scenario passed; `git diff --check` і example-only env contract passed.
    Open items: `make validate` блокується stale pre-commit manifest cache, що посилається на старий `/opt/smtp2graph/.cache/pre-commit`; `tsc --noEmit` у build plane блокується pre-existing missing `jsbn` typings; Gate B лишається blocked до display-name qualification та exact fork digest, Trivy scan/exception, Syft CycloneDX SBOM і OCI metadata.
    Risks: Не активувати CI/CD, не використовувати fork у production і не видаляти local `private.key` до окремо approved SOPS + age / Docker Secret cutover.
    Rollback: Відкотити лише documentation/test/template changes reviewed commits; не відкочувати на rejected upstream image.

2026-07-25 — ADR-0002: актуалізовано remediation status відхиленого upstream gateway
    Context: Після fork remediation та non-production Microsoft 365 checks ADR мав відображати актуальний evidence status, не змінюючи historical Gate B rejection upstream SMTP2Graph v1.1.5.
    Change: ADR-0002 посилається на fork integration/Task 5.3 і документує build-plane checkout, remediation commits, client-secret/denied-mailbox/certificate-only evidence, а також межу між функціональною qualification та release evidence.
    Verification: Документаційний запис звірено з активним changelog і фактичним Gate B status; upstream ADR status залишається `Rejected`.
    Open items: Display-name qualification, exact fork digest, Trivy scan/exception, Syft CycloneDX SBOM, OCI metadata labels; `make validate` має stale pre-commit cache issue, а `tsc --noEmit` у build plane — pre-existing `jsbn` typings issue.
    Risks: ADR не є новим Gate B decision або production approval; CI/CD template лишається inactive, а `private.key` не можна переносити чи видаляти до окремо approved SOPS + age / Docker Secret cutover.
    Rollback: Відкотити цей документаційний status update reviewed зміною; не скасовувати upstream rejection без нового digest-scoped Gate B decision.

2026-07-27 — Task 2.5: non-production Exchange display-name qualification
    Context: Gate B вимагав встановити, чи може одна sender mailbox передавати різні client display name через MIME `From`.
    Change: У fork додано isolated send scenario з synthetic display name. У control plane додано test plan та оновлено ADR-0002 і AI context з фактичним результатом.
    Verification: `test/02send/05displayName.spec.ts` пройшов у non-production tenant. Exchange Online зберіг адресу відправника, але замінив synthetic MIME display name на mailbox display name `noreply`.
    Risks: Одна mailbox не забезпечує окрему видиму ідентичність клієнтів; production має використовувати погоджену per-service mailbox model. Gate B досі blocked до exact fork digest, Trivy scan/exception, Syft CycloneDX SBOM та OCI metadata.
    Rollback: Відкотити test і documentation record окремою reviewed зміною лише якщо non-production evidence визнано неактуальним; не трактувати qualification як Gate B approval або production authorization.

2026-07-27 — Task 5.3 preparation: pinned base image та OCI metadata contract
    Context: Exact fork digest, Trivy scan і Syft SBOM потребують відтворюваного build input та release metadata, прив'язаних до одного image digest.
    Change: Fork Dockerfile pin-ить multi-platform `node:20-alpine` base image digest і додає OCI labels для source, revision, version, release tag, base image та upstream base. Local builds з `unknown` або `unreleased` metadata явно не є release evidence.
    Verification: Registry manifest digest базового образу розв'язано через `docker buildx imagetools inspect`; local metadata build без push пройшов і підтвердив усі required OCI labels.
    Risks: Підготовчий patch не створює fork image digest, Trivy record, CycloneDX SBOM або immutable artifact retention; CI/CD лишається inactive.
    Rollback: Повернути Dockerfile і contract окремою reviewed зміною; не підміняти fork release mutable base-image tag або local image ID.

2026-07-27 — Roadmap: GHCR release evidence deferred to Task 5.3
    Context: Exact fork digest, GHCR build/push, Trivy, Syft and OCI release-artifact generation previously overlapped with functional Gate B, creating a Phase 2 → Task 5.3 dependency conflict.
    Change: SPEC, roadmap, ADR-0002, fork integration contract and AI context now separate functional Gate B from release supply-chain work. Task 5.3 exclusively owns GHCR build/push, exact digest, Trivy scan/exception, CycloneDX SBOM, OCI metadata and immutable artifact retention; these gate staging/production promotion, not Phase 3 entry.
    Verification: Documentation cross-references and phase/task ownership reviewed; `make validate` and `git diff --check` run after the documentation change.
    Risks: A functional Gate B pass is not production approval and cannot authorize a deployment without Task 5.3 release evidence.
    Rollback: Restore the prior gate boundary only through a reviewed SPEC/roadmap/ADR change; do not perform GHCR build/push outside Task 5.3.

2026-07-27 — Task 2.5: versioned upstream patch automation
    Context: Fork upgrade safety could not depend on replaying historical commit SHA values or mutable branch history.
    Change: Control plane now owns a checksummed v1.1.5 patch bundle, manifest and manual isolated-worktree upgrade script. It applies reviewed fixes and qualification tests to a local upgrade branch, then runs local and, when configured, Microsoft 365 regressions without push, PR or deploy authority.
    Verification: Shell syntax and read-only `--check` completed; bundle checksums are recorded in the manifest.
    Risks: Upstream drift, empty patches and M365 test input gaps require manual review; a local regression pass is not a Gate B decision or release evidence.
    Rollback: Remove only an explicitly reviewed local upgrade branch and revise the versioned patch bundle; rejected upstream v1.1.5 remains ineligible as a production rollback target.

2026-07-28 — Task 2.5: simplified patch manifest
    Context: Per-file SHA-256 and Git object IDs duplicated integrity guarantees already supplied by the versioned control-plane repository.
    Change: Manifest now retains only upstream remote, base tag, Node requirement and ordered safe patch filenames. The script strictly parses the list without sourcing the manifest.
    Verification: Shell syntax and manifest parser validation executed.
    Risks: Git repository integrity and reviewed commits remain required; a manually copied bundle outside Git has no separate checksum layer.
    Rollback: Restore a reviewed manifest version from Git history if an external distribution policy later requires detached checksums.
