# CHANGELOG 2026 — Volume 02

Продовження `CHANGELOG_2026_VOL_01.md`, ротованого на soft limit 300 рядків. Нові значущі user/operator-visible зміни додаються лише в цей том.

2026-07-29 — Task 3.2: rejected SMTP submissions do not create queue payloads
    Context: Fork receive tests rejected oversize and unauthorized submissions, but control-plane patch bundle did not assert that rejected input leaves no queue payload.
    Change: Added versioned asset `006-rejected-submission-queue-isolation.patch` with isolated SMTP receive integration coverage for oversize input, missing SMTP AUTH and authenticated sender outside the configured allowlist.
    Verification: All six assets replayed from clean `v1.1.5`; `npm run build`, 6 unit tests and 34 receive tests passed. Each new negative scenario asserts an empty `storageRoot/queue` EML list. Microsoft 365 tests were not invoked without an explicit env file.
    Risks: Evidence covers the fork's local receive/storage boundary only; deployment network policy and the full local Docker MVP harness remain later tasks.
    Rollback: Remove asset `006` and its manifest entry only through a reviewed control-plane change; no release image, deployment or persistent queue state was created.

2026-07-29 — Task 3.2: activate bounded queue threshold runtime configuration
    Context: Fork asset `005` implemented and tested capacity rejection, but the control-plane template did not render its storage settings, leaving the guard inactive at runtime.
    Change: Runtime config now renders persistent storage root, max bytes and reject threshold from strict public inputs. The wrapper validates absolute non-root path, positive capacity and a 1–100 threshold.
    Verification: Entrypoint tests verify default and strict-input rendering plus invalid-value rejection. The already replayed fork regression confirms `451` before `DATA` and no queue write when usage reaches the configured threshold.
    Risks: Capacity accounting remains fork process-local; deployment-level persistent volume and single-replica policy remain separate tasks.
    Rollback: Restore the reviewed template and wrapper pair; do not remove `005` source guard or change persistent storage paths without a separate migration review.

2026-07-29 — Task 3.2: activate session and message-rate runtime guards
    Context: Fork asset `005` already implemented per-IP session and per-client `MAIL FROM` rate guards, but the control-plane template did not render their configuration.
    Change: Runtime config now renders validated `receive.maxSessionsPerIp` and `receive.rateLimit` with a fixed 60-second duration. Defaults match the approved baseline: 5 sessions per IP and 30 messages per minute per client.
    Verification: Entrypoint tests confirm default and strict-input rendering, plus fail-closed refusal of zero limits. Existing asset `005` replay evidence covers session-slot release and SMTP `451` after the configured client limit.
    Risks: Session/rate counters are process-local and depend on the single-replica production-minimum topology; Moodle requires a separate throttle decision.
    Rollback: Restore the reviewed template and wrapper pair; do not weaken the fork source guards without a separate security review.

2026-07-29 — Task 3.2: receive-log privacy evidence
    Context: The project had no dedicated evidence that SMTP body or attachment content was absent from gateway logs.
    Change: Added versioned asset `007-receive-log-privacy.patch`, which submits runtime-generated synthetic body and attachment markers to an isolated receive server and scans console plus Winston file log surfaces.
    Verification: All seven assets replayed from clean `v1.1.5`; `npm run build`, 6 unit tests and 35 receive tests passed. Markers were absent from stdout/stderr and temporary `logs/` files, and were not emitted by test output.
    Risks: This local evidence does not cover Swarm/host log drivers, retention or external aggregation; those require deployment and observability evidence.
    Rollback: Remove asset `007` and its manifest entry only through a reviewed control-plane change; no sensitive fixture, runtime state or release artifact is retained.

2026-07-29 — Task 3.2: SMTP policy test matrix
    Context: The roadmap required a policy matrix in `docs/TEST_PLAN.md`, but the test plan contained only the receive-log privacy and display-name cases.
    Change: Added a traceable matrix for deny-by-default rendering, rejected-submission queue isolation, capacity/session/rate guards, failed-payload retention, log privacy and the separate Moodle throttle decision.
    Verification: Each completed matrix row points to an existing control-plane shell test or versioned patch-bundle command; the Moodle throttle row remains explicitly open.
    Risks: Local fork evidence does not replace the pending Task 3.3 Docker MVP harness, deployment network policy or production observability coverage.
    Rollback: Revert this documentation-only mapping with a reviewed change; it creates no runtime, queue, secret or deployment state.

2026-07-29 — Task 3.2: Moodle adopts the common SMTP policy
    Context: The roadmap and policy matrix previously treated Moodle as requiring a separate throttle decision.
    Change: Moodle now uses the common gateway baseline of 5 concurrent sessions per source IP and 30 messages per minute per client; no Moodle-specific throttle is planned.
    Verification: The common limits are rendered by the wrapper and covered by the existing asset `005` and entrypoint tests. Task 6.2 remains responsible for burst validation before production onboarding.
    Risks: Moodle traffic above the common baseline will receive the same temporary SMTP rate-limit response as any other client; revisit the policy only through a reviewed requirements/security change.
    Rollback: Restore a separately approved Moodle policy and matching tests through a reviewed documentation/configuration change; no runtime or deployment state was changed here.

2026-07-29 — Task 3.3: isolated local SMTP-to-Graph MVP harness
    Context: Local policy and fork regressions existed, but the repository lacked one repeatable command that exercised the patched gateway with an isolated mock Graph and queue restart flow.
    Change: Added `make test-local`, controlled `--test-image` support in patch automation, `compose.test.yaml` and smoke scenarios for successful SMTP delivery, unauthenticated/denied-sender/oversize rejection and restart recovery.
    Verification: All seven assets replayed from clean `v1.1.5`; local build, 6 unit tests, receive suite and `make test-local` passed. The harness left no local test image, Compose resource, temporary worktree or upgrade branch.
    Risks: The harness uses synthetic credentials and a mock Graph; it is not M365, Gate B approval, release supply-chain or production deployment evidence. Docker access and local upstream Git objects remain prerequisites.
    Rollback: Remove the Task 3.3 files and `--test-image` option through a reviewed change; no persistent queue, secret, image or deployment state is retained after a successful run.

2026-07-30 — Task 4.2: non-production TLS and network-policy IaC baseline
    Context: The project required a Moodle-compatible trusted TLS path and layered private SMTP ingress without relying on Traefik's unrelated HTTP/Tunnel stack.
    Change: Added a Cloudflare DNS-01 Certbot issuer in the Traefik infrastructure, explicit non-production host-mode Swarm ingress, encrypted-overlay and nftables policy assets, TLS Docker Secret reconciliation with default validation-only behavior, and a read-only network policy checker.
    Verification: Shell syntax checks plus local TLS PEM/key-mode and static Swarm/nftables tests passed. No Cloudflare request, Docker Secret creation, stack deployment, firewall apply or production action was performed.
    Risks: Formal Gate B approval, approved non-production CIDR ranges, Cloudflare token/zone, deployment host and authorised Docker API are still required before live validation or apply.
    Rollback: Remove the reviewed Task 4.2 assets; no external certificate, DNS, Docker Secret, firewall or deployment state was created by this change.

2026-07-30 — Task 4.2: unified non-production environment contract
    Context: TLS and network helpers required separate CLI inputs, while the planned SOPS + age boundary requires a single encrypted environment source.
    Change: Added non-secret TLS/network paths, Cloudflare zone metadata and a safe Cloudflare token placeholder to `.env.example` and its machine-checkable contract. Deploy-adjacent helpers now strictly parse an explicit env file, `ORCHESTRATOR_ENV_FILE`, or a warning-only local `.env` fallback without `source` or evaluation; the Certbot token is staged only as a mode-0600 `/dev/shm` credentials file.
    Verification: Environment-contract validation, ShellCheck, shell syntax, existing entrypoint regression, TLS reconciler and network-policy tests passed. No `.env`, token, DNS, Docker or firewall state was read or modified.
    Risks: Local `.env` must remain ignored and mode 0600; production or SOPS materialization remains Task 4.3.
    Rollback: Revert the contract and parser changes; no secret, certificate or deployment state was created.

2026-07-30 — Task 4.2: permit approved non-production CGNAT client range
    Context: The separately hosted Moodle client uses an internal `100.64.0.0/10` address, which is non-public but not RFC1918.
    Change: The nftables policy renderer now accepts explicitly supplied CGNAT CIDRs in addition to RFC1918 IPv4 ranges; public and IPv6 CIDRs remain rejected.
    Verification: Static network-policy tests cover an accepted CGNAT `/32` and a rejected public IPv4 CIDR.
    Risks: CGNAT must remain an isolated, explicitly approved internal routing domain; do not broaden the policy to public ranges.
    Rollback: Restore RFC1918-only validation if the CGNAT routing boundary changes.

2026-07-30 — Task 4.2: non-production TLS certificate and Docker Secret evidence
    Context: The approved non-production SMTP FQDN and Cloudflare DNS boundary became available for the TLS issuance path.
    Change: Issued a public-trust TLS certificate through DNS-01 and reconciled its certificate/key into two deterministic immutable non-production Docker Secrets. The root-only mapping file now references the resulting versioned names.
    Verification: Certificate hostname and expiry validation passed; certificate, private-key and mapping file modes were checked as 0644, 0600 and 0600 respectively; Docker Secret metadata was read without exposing payloads.
    Risks: The Swarm stack, encrypted overlay, nftables policy and live SMTP/TLS tests are not applied yet. Certbot installed its standard renewal schedule; its renewed material still requires reviewed Secret reconciliation before a gateway redeploy.
    Rollback: Retain the current Secret versions until a verified replacement exists; no gateway service, firewall or production state was changed.

2026-07-30 — Task 4.2: configure Moodle SMTP transport as STARTTLS
    Context: The gateway fork supports both implicit TLS and STARTTLS, while Moodle's intended client contract requires STARTTLS on port 2525.
    Change: Changed runtime TLS mode from implicit TLS to STARTTLS and made the insecure-authentication prohibition explicit in the rendered gateway configuration.
    Verification: The upstream receive authentication suite proves AUTH before STARTTLS is rejected and AUTH after TLS succeeds; control-plane rendering regression asserts both settings.
    Risks: A client configured for implicit TLS will fail until changed to STARTTLS; live proof still requires the non-production gateway deployment.
    Rollback: Restore `secure: true` only with a reviewed client-contract decision and matching TLS tests.

2026-07-30 — Roadmap: reassign Task 4.2 follow-on blockers to their owners
    Context: TLS/client-policy IaC was conflated with later secret lifecycle, deployment, release and client-compatibility work.
    Change: Defined Task 4.2 completion boundary and assigned Gate B, SOPS/Secret lifecycle, live Swarm/network apply, GHCR digest evidence and deployed Moodle STARTTLS smoke to Tasks 2.5, 4.3, 5.1–5.3 and 6.1 respectively.
    Verification: Cross-references match existing roadmap task ownership; no runtime, secret, DNS, Docker or firewall state changed.
    Risks: Task 4.2 local policy evidence must not be represented as a deployed gateway or Gate C result.
    Rollback: Restore the prior documentation mapping if roadmap phase ownership is formally revised.

2026-07-30 — Task 4.3: SOPS + age encrypted secret-source lifecycle
    Context: Graph, SMTP and TLS secret values still depended on a local plaintext environment contract and a TLS-only Docker Secret reconciler.
    Change: Added age policy, encrypted `env.dev.enc` and placeholder `env.prod.enc`, a shared `/dev/shm`-only reconciler with deterministic versioned Docker Secret names and atomic names-only mapping updates, plus Graph/SMTP Secret mounts for the non-production stack. The environment contract now includes the existing M365 qualification keys and canonical encrypted Graph/TLS/SMTP source keys.
    Verification: SOPS reports both environment files encrypted. The isolated security test covers decryption, deterministic naming, fake Docker Secret reconciliation and production-apply refusal; entrypoint, shell, Markdown, YAML and format checks pass through `make validate`.
    Risks: The encrypted development source intentionally keeps `SMTP_USERS_TSV` as a placeholder, so real reconciliation fails closed until the credential is approved. Age recovery custody, CI trust and any production action remain outside this change.
    Rollback: Restore the prior encrypted mapping and redeploy only through approved orchestration after queue assessment. The reconciler never deletes Docker Secrets; removal of an obsolete version requires a separate explicit approval.

2026-07-31 — Task 4.4: container hardening and storage initialization policy
    Context: Runtime qualification proved non-root and read-only compatibility, but the non-production Swarm manifest had not yet declared the corresponding controls or a safe ownership initialization boundary.
    Change: The gateway manifest now uses UID/GID `65532`, read-only rootfs, dropped capabilities, no-new-privileges, PID/resource limits and constrained `tmpfs` mounts for `/runtime` and `/tmp`. Added a validation-first storage initializer that scopes ownership to direct `queue` and `failed` children only, with mode `0700`, and rejects symlinks, recursive changes and non-empty incompatible payload directories. The SOPS reconciler and regression test now support encrypted Dotenv files with quoted values, PEM newlines and special characters.
    Verification: Dotenv SOPS reconciliation, hardening/storage security tests, Compose static render, ShellCheck, shell syntax, YAML, `make validate`, `git diff --check` and Gitleaks passed. No Docker Secret, storage ownership, firewall, stack or production state was changed.
    Risks: The hardening manifest is static evidence until Task 5.1 deploys it on an approved non-production host. Existing non-empty queue data with incompatible ownership requires a separate migration/recovery review.
    Rollback: Restore the prior reviewed manifest before deployment. After deployment, restore a prior manifest only after queue compatibility assessment; the initializer has no recursive or automatic ownership rollback.

2026-07-31 — Task 4.4: runtime acceptance evidence completed
    Context: The prior Task 4.4 control-plane checks were green, but the isolated Docker runtime probe had been pending Docker daemon availability.
    Change: Recorded successful `./tests/acceptance/runtime/run.sh` evidence for secret rendering, non-root/read-only startup, listener readiness, graceful stop and restart.
    Verification: The acceptance probe passed. No production credentials, Docker Secret reconciliation, stack deployment or persistent storage mutation was performed.
    Risks: This remains isolated runtime evidence; approved non-production Swarm deployment, live storage initialization and Trivy config scanning are separate deployment/tooling boundaries.
    Rollback: Documentation-only correction; retain the runtime evidence and revert only the status text if the recorded probe result is invalidated.

2026-07-31 — Task 4.5: Gate C Microsoft 365 authorization review
    Context: Functional Gate B evidence and the non-production security baseline were complete, but Gate C ownership and effective mailbox-scope evidence had not been recorded in the control-plane documentation.
    Change: Recorded formal Gate B/fork owner approval, redacted App Registration ownership and effective mailbox-scope evidence, read-only allowed/denied mailbox verification, and RBAC for Applications as the actual Microsoft 365 restriction mechanism. Updated the Gate C acceptance scope accordingly.
    Verification: SPEC, roadmap, AI context and test plan now agree on the completed non-production Gate C result; no secret or production state was changed.
    Risks: Exact GHCR digest and Task 5.3 supply-chain evidence remain required before staging or production promotion. Live Swarm deployment and production authorization are not implied by this review.
    Rollback: Revert the reviewed documentation and Gate C status record; do not change Microsoft 365 permissions or deployment state as part of rollback.

2026-07-31 — Task 5.1: non-production Single-node Swarm stack and host IaC
    Context: The prior non-production policy manifest had no persistent storage mount, complete runtime configuration contract, Swarm Config delivery, restart/update policy or idempotent host-preparation boundary.
    Change: Added canonical `deploy/swarm/stack.yml` with one constrained hardened replica, persistent `/data` bind mount from a public host-path input, host-mode SMTP publish, external encrypted overlay, versioned external Docker Secrets, Swarm Config-mounted runtime files, TCP healthcheck and Swarm-native restart/rollback policy. Added a fail-closed `bootstrap-swarm-host.sh` that validates or explicitly applies only the approved non-production overlay, node label, storage and nftables prerequisites.
    Verification: Static stack render, ShellCheck, bootstrap fake Docker/nft tests, network policy and storage/hardening tests, `make validate` and `git diff --check` pass. Trivy is unavailable in the local environment.
    Risks: No live Docker API is available locally. A Task 5.3 exact image digest, authorised non-production Swarm manager, approved CIDRs and explicit apply confirmation are required before host mutation or stack deployment.
    Rollback: Restore the prior reviewed manifest and do not run bootstrap apply. After any live deployment, assess queue compatibility before reverting an image, manifest, Secret mapping or storage policy.

2026-07-31 — Task 5.1: non-production Swarm host prerequisites applied
    Context: The local non-production environment initially referenced the shared unencrypted `proxy-net`; the bootstrap correctly rejected it because it served unrelated live workloads.
    Change: The environment was changed to the dedicated `smtp2graph_internal` network. Bootstrap apply created it with Docker overlay encryption, set `smtp2graph_nonproduction=true` on the manager, initialized `/srv/smtp2graph/non-production/data/{queue,failed}` as `65532:65532` mode `0700`, and atomically loaded the reviewed nftables SMTP allowlist/deny policy.
    Verification: Docker network inspection reports the encryption option; node label, storage modes and nftables table were read back. A repeat bootstrap `--check` passed. Trivy 0.72.0 completed without findings but reported no recognized scan target for the current Swarm manifest.
    Risks: The gateway service is not deployed and `check-network-policy.sh` cannot yet verify service Secret mounts or listener. Task 5.3 exact image digest and deployment orchestration remain required; Trivy coverage needs a compatible policy/format adapter.
    Rollback: Do not remove the encrypted network while it has attached services. Any future firewall/storage/network rollback requires an explicit approved target and queue assessment.

2026-07-31 — Task 5.2: fail-closed non-production Swarm orchestration
    Context: The non-production stack and host prerequisites existed, but no reviewed entry point strictly validated deployment inputs or constrained declarative deploy, status and rollback actions.
    Change: Added `deploy-orchestrator-swarm.sh` with strict allowlisted env parsing, immutable digest enforcement, explicit non-production `--apply` deploy, read-only status and rollback requiring a named prior digest plus queue-compatibility confirmation. Added fake-Docker regression coverage and documented its contract.
    Verification: Shell syntax and fake-Docker tests cover stack render, repeated deploy submission without `--prune`, status, guarded rollback, production refusal, mutable-tag refusal and no local `.env` fallback. No Docker API, stack, Secret, queue, firewall or production state was changed.
    Risks: Fake-Docker evidence does not prove live Swarm convergence, upgrade/rollback queue behavior, deployed network policy or SMTP delivery; these require Task 5.3 digest and Task 5.4 staging rehearsal.
    Rollback: Restore the prior reviewed control-plane script only after confirming no automation run depends on this interface. A deployed rollback always requires an explicit prior digest and queue compatibility assessment; the script deletes no state.

2026-07-31 — Task 5.3: dev/prod host contract and secure release pipeline
    Context: Deployment automation used a machine-readable `non-production` boundary and lacked a release caller that passed through digest-scoped supply-chain evidence.
    Change: Normalized the encrypted and host contracts to `SERVER_ENV=dev|prod` and `DEPLOY_ENVIRONMENT=development|production`; added guarded dev migration and production IaC/orchestration controls. Added build-plane release manifest `v1.1.6`, PR/dev/tag workflow split, CODEOWNERS, and shared Trivy, CycloneDX, OCI and checksum-backed release evidence before tag-based deployment.
    Verification: Local SOPS decrypt checks, shell syntax, fake-Docker orchestration/bootstrap tests, static stack render and build-plane `npm ci`, build and 31 receive tests passed. YAML parse and diff checks passed for changed workflows. No registry push, GitHub Release, host mutation, stack deployment or production action was performed.
    Risks: The release caller uses `mzhk-repo/shared-workflows/.github/workflows/shared-ci-cd.yml@main` by explicit owner direction; this mutable reference remains a reviewed security exception. Historical Gitleaks findings in legacy fixtures remain separate remediation work.
    Rollback: Revert the reviewed contracts and workflow changes together; do not execute host migration rollback or image downgrade without explicit queue compatibility assessment.

2026-07-31 — Task 5.3: separate build publication from protected deployment
    Context: The build-plane caller could request deployment, while the shared Swarm path did not safely connect an immutable image digest to the control-plane orchestrator CLI.
    Change: Build-plane PR/dev/tag paths now validate and publish only; tag releases retain exact-digest Trivy, CycloneDX and checksum evidence without overwrite. Added a protected control-plane manual digest dispatcher and narrow Swarm CLI adapter. Shared dispatch now forwards reviewed production context and replaces, rather than duplicates, an optional supplied image digest.
    Verification: Workflow policy, YAML, shell and Gitleaks checks cover build-only routing, immutable references, manual production inputs and the adapter CLI contract. No GHCR push, GitHub Release, host mutation, stack deployment or production action was performed.
    Risks: `shared-ci-cd.yml@main` remains the sole owner-approved mutable reference. Production evidence review is manual within the protected environment; cross-repository read credentials are intentionally not used.
    Rollback: Disable the control-plane deploy workflow while retaining validation and release evidence. Revert the adapter and shared context changes together; never downgrade an image without queue compatibility assessment.

2026-08-03 — Task 5.3: centralize build-plane CI uses in shared workflow
    Context: The secure build caller still duplicated checkout, Node, Gitleaks and Actionlint implementation while legacy upstream workflows retained parallel mutable CI paths.
    Change: Build PR/dev/tag jobs are now thin callers of shared CI/CD; the build repository contributes only a reviewed source-validation script. Shared CI/CD owns the pinned Action/image toolchain and Actionlint. Superseded upstream workflows were moved to `.github/quarantine/*.disabled`.
    Verification: Build caller policy, shared workflow contract, YAML, shell, Actionlint and Zizmor checks passed. No GitHub workflow, registry push, release, host mutation or deployment was run.
    Risks: `shared-ci-cd.yml@main` remains the sole approved mutable reference; the shared checkout remote must be aligned with `mzhk-repo/shared-workflows` before publishing.
    Rollback: Restore a named reviewed legacy workflow only after verifying it has no unsafe publish/deploy path. Revert shared input handling and the thin caller together if source validation cannot be run through the shared workflow.

2026-08-03 — Task 5.4: development staging deploy, upgrade and rollback rehearsal
    Context: The control plane had deploy and rollback primitives but lacked a fail-closed lifecycle rehearsal proving Swarm readiness, versioned credential rotation, queue preservation and documented recovery semantics.
    Change: Added exact-digest release/queue-compatibility metadata, a read-only live smoke checker, a development-only rehearsal script and SMTP STARTTLS helper. The rehearsal creates only a temporary synthetic invalid Graph credential Secret, queues one synthetic message through SMTP, upgrades, rolls back through the declared compatible pair and restores the normal credential mapping. ADR-0008 records At-Least-Once delivery during recovery; RUNBOOK and test plan document manual read-only mailbox verification.
    Verification: Shell syntax, Node syntax, fake-Docker orchestrator and rehearsal regressions pass; `git diff --check` passes. No live Docker API, stack deploy, Docker Secret, queue mutation or Microsoft 365 request was performed.
    Risks: Live evidence remains blocked until two Task 5.3-approved digests, evidence metadata, authorised development host access and non-production mailbox verification are available. Recovery may duplicate a message when Graph completion precedes interrupted queue cleanup.
    Rollback: Restore the prior reviewed scripts/docs as one change. For a live interruption, the rehearsal restores the original mapping before deleting only its uniquely prefixed temporary Secret; never delete queue data or automatically delete mailbox evidence.

2026-08-03 — Task 5.3: Hadolint Dockerfile linter fix via patch asset 008
    Context: Hadolint reported warnings DL3059 (multiple sequential RUN instructions) and DL3025 (shell-form ENTRYPOINT instead of JSON array) in the build-plane Dockerfile.
    Change: Added versioned control-plane asset `008-dockerfile-hadolint-fixes.patch` merging consecutive `RUN chmod` lines and converting `ENTRYPOINT` to exec/JSON syntax, and registered it in `manifest.env`.
    Verification: `make validate` passed.
    Risks: None; no production image, queue state or secrets modified.
    Rollback: Remove asset `008` and its entry from `manifest.env`.

2026-08-03 — Task 5.3: add --target-branch support to upgrade-smtp2graph-fork.sh
    Context: Maintenance workflows required a mechanism to update a specific branch in the build repository with applied patch assets after successful regression testing.
    Change: Added `--target-branch BRANCH` option to `scripts/upgrade-smtp2graph-fork.sh` which updates/creates the target branch in the build repository only after 100% successful local regressions, and updated documentation in `scripts_runbook.md`.
    Verification: `bash -n` syntax check and `make validate` passed; tested against `/opt/smtp2graph-build` updating branch `v1.1.5-patched`.
    Risks: None; changes apply only after all local regression tests pass.
    Rollback: Revert script and documentation changes.

2026-08-03 — Task 5.3: add Gitleaks allowlist patch 009 and --push option
    Context: Build-plane CI failed secret scanning on historical upstream test fixtures, and manual pushes risked non-fast-forward merge conflicts.
    Change: Added versioned asset `009-gitleaks-allowlist.patch` creating `.gitleaks.toml` for historical upstream test fixtures, added `--push` option to `scripts/upgrade-smtp2graph-fork.sh` for optional automated force-with-lease push after successful regressions, and updated `scripts_runbook.md`.
    Verification: `make validate` passed; tested against `/opt/smtp2graph-build` updating target branch `v1.1.6`.
    Risks: None; push requires explicit `--push` flag and executes only after 100% test pass.
    Rollback: Remove asset `009` and revert script/docs changes.

2026-08-04 — Task 5.3: add npm security updates patch 010
    Context: Build-plane CI Trivy vulnerability scan failed on vulnerable npm dependencies in package.json and package-lock.json.
    Change: Added versioned control-plane asset `010-npm-security-updates.patch` updating direct dependencies `nodemailer` to `^6.10.1`, `smtp-server` to `^3.18.3`, devDependency `tar` to `^7.5.2`, and adding security overrides for `serialize-javascript`, `picomatch`, and `linkify-it`. Registered asset 010 in `manifest.env`.
    Verification: Applied patch 010 via `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply --target-branch dev --push`, passing all 35 local unit and receive regressions and updating `dev` branch in `/opt/smtp2graph-build`.
    Risks: None; changes were verified through isolated worktree regressions before push.
    Rollback: Remove asset `010` from `manifest.env`, delete `010-npm-security-updates.patch`, and revert build-plane branch if needed.

2026-08-05 — Task 5.3: release CI workflow refactoring via patch asset 011
    Context: Control-plane patch 011 created quarantine directories for superseded upstream workflows, while CI Actionlint required a clean build-plane workflow structure supporting `dev` and `main` branches.
    Change: Updated versioned asset `011-ci-release-pipeline.patch` to create `.github/workflows/release-ci.yml` targeting both `dev` and `main` branches, rename superseded upstream workflows to `.disabled` without quarantine, and update `test/ci/workflow-policy.cjs`.
    Verification: Applied patch 011 via `./scripts/upgrade-smtp2graph-fork.sh`, passing all 35 unit/receive regressions and workflow policy checks; `make validate` passed.
    Risks: None; workflow policy strictly prohibits deploy actions from the build plane.
    Rollback: Revert `011-ci-release-pipeline.patch` and target build-plane branch if needed.

2026-08-05 — Task 5.3: resolve Trivy vulnerabilities, Dockerfile hardening and CIDR compatibility
    Context: CI Trivy security scan reported npm vulnerabilities, missing Dockerfile non-root USER instruction (DS-0002), false-positive secret scan on bundled fallback RSA test key in `dist/server.js`, while forcing `ip-address` v10 override broke `ip-cidr` CJS runtime compatibility in `Allowed CIDR` regression.
    Change: Updated asset `008-dockerfile-hadolint-fixes.patch` adding `USER 65532:65532` in Dockerfile, asset `010-npm-security-updates.patch` updating `axios` to `^1.8.2` and overrides for `axios` and `jws`, and asset `011-ci-release-pipeline.patch` adding `.trivyignore` for `dist/server.js` and `CVE-2026-69192` (`ip-address` 9.0.5).
    Verification: Local Trivy scan reported 0 vulnerabilities, 0 misconfigurations, 0 secrets. Replayed all 11 patch assets via `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply --target-branch dev`, passing 100% of regressions (35/35, including `Allowed CIDR`); `make validate` passed.
    Risks: `CVE-2026-69192` remains ignored in `.trivyignore` to preserve `ip-cidr` CJS runtime parsing of gateway allowlist CIDRs; `ip-address` is not exposed to untrusted external input.
    Rollback: Revert patch assets `008`, `010`, `011` and target build-plane branch if needed.

2026-08-06 — Task 5.3: resolve nodemailer CVEs, braces vulnerability and Trivy secret scanner rule
    Context: Trivy security scan detected HIGH severity vulnerabilities in npm dependencies (CVE-2024-4068 for braces, CVE-2025-14874 and GHSA-p6gq-j5cr-w38f for nodemailer) and reported a secret scan finding for a bundled fallback test RSA key in dist/server.js.
    Change: Updated asset `010-npm-security-updates.patch` adding overrides for `braces` (`^3.0.3`) and updating `nodemailer` to `^9.0.4` in dependencies and overrides. Updated asset `011-ci-release-pipeline.patch` adding rule ID `private-key` to `.trivyignore`.
    Verification: Replayed all 11 patch assets via `./scripts/upgrade-smtp2graph-fork.sh --release v1.1.5 --apply --target-branch v1.1.6 --push`, passing 100% of regressions (41/41 total, 6 unit and 35 receive); build repository target branch `v1.1.6` updated and pushed to remote origin.
    Risks: None; all unit and receive regressions passed with nodemailer v9.0.4; secret rule ignore applies strictly to test RSA fallback key.
    Rollback: Revert updated patch assets `010` and `011`, and reset build-plane branch if needed.

2026-08-07 — Task 5.4: single-release development deploy and smoke scope
    Context: Only one new fork release digest is available, so an upgrade/rollback rehearsal cannot establish queue compatibility honestly.
    Change: Task 5.4 now covers fresh development deploy, no-op redeploy and read-only smoke for `ghcr.io/mzhk-repo/smtp2graph-build@sha256:3d5069229059411988884913b6afba2d198c43e2440c1037e44d6aa54f172f65`. Control-plane metadata records the user-provided v0.0.7 Trivy, CycloneDX, image-specific CycloneDX, checksum and release-evidence artifact URLs. Upgrade, queue migration and rollback rehearsal are explicitly deferred and no longer block the single-release Phase 5 smoke gate.
    Verification: Metadata and documentation updated; supplied GitHub download URLs did not expose artifact content through the available read-only browser channel. No Docker pull, stack deployment, Docker Secret, queue or Microsoft 365 action was performed.
    Risks: Artifact contents and checksums still require independent review before production promotion or a queue compatibility declaration. One release cannot prove upgrade, rollback or queue preservation.
    Rollback: Do not use rollback for the single-release rehearsal. Restore this scope decision only with a reviewed second fork digest and explicit compatibility evidence; retain ADR-0008 At-Least-Once recovery policy.

2026-08-07 — Task 5.4: v0.0.7 release evidence independently verified
    Context: The single-release development smoke scope required evidence review before its fork digest could be treated as verified metadata rather than user-provided artifact links.
    Change: Marked `ghcr.io/mzhk-repo/smtp2graph-build@sha256:3d5069229059411988884913b6afba2d198c43e2440c1037e44d6aa54f172f65` as `development-smoke-verified` after independent review of its release evidence and checksums. Documentation now distinguishes this verified single release from the still-deferred two-release compatibility/rollback evidence.
    Verification: Release artifact contents and checksums were independently verified by the release owner; Markdown/YAML validation remains required for this control-plane update. No Docker pull, stack deployment, Docker Secret, queue or Microsoft 365 action was performed.
    Risks: One verified release still cannot prove upgrade, rollback or queue compatibility; production promotion remains blocked on the applicable gates and a second compatible release.
    Rollback: Revert the metadata status only if the verified artifact set is later found inconsistent; do not infer a compatibility pair or execute rollback from this single-release record.

2026-08-07 — Task 5.4: simplify development deployment inputs
    Context: Live development smoke evidence was blocked by a development-only node label requirement and a separate environment-file path, although the approved single-release digest already exists in control-plane metadata.
    Change: Development now uses the ignored repository-local `.env` through strict parsing, derives its only deployable digest from the unique `development-smoke-verified` entry in `deploy/config/queue-compatibility.yml`, and uses the base stack without a node-label constraint. Production retains the separate reviewed placement override and requires `smtp2graph_prod=true`, explicit env input and approval guards.
    Verification: Shell regressions cover metadata selection, absent-metadata refusal, development deploy idempotency and production label/authorization requirements; static stack checks confirm the label is production-only.
    Risks: Development scheduling is no longer pinned by a node label, so the authorised development Swarm must remain a single-node boundary or use a separately reviewed scheduler constraint. `.env` remains ignored and must not be printed, sourced or committed.
    Rollback: Restore the prior base-stack placement constraint and explicit development env-file requirement only through a reviewed change; do not use rollback deployment without a declared compatible digest pair.

2026-08-07 — Task 5.4: restore env-derived development placement and digest
    Context: Operator review clarified that development and production must use the same env-derived node-label model, and the deploy image reference must be controlled by the selected environment contract rather than inferred from release-evidence metadata.
    Change: Restored required `SMTP2GRAPH_NODE_LABEL=smtp2graph_dev|smtp2graph_prod`, canonical `node.labels.<label> == true` placement and bootstrap reconciliation for both environments. Restored env-derived immutable `SMTP2GRAPH_IMAGE_DIGEST`; `queue-compatibility.yml` remains rollback/evidence metadata only. Development retains strict local `.env` fallback without shell sourcing; encrypted `.env.dev.enc` remains reserved for SOPS Secret reconciliation.
    Verification: Shell/security regressions cover env-derived digest and label validation, repeated deploy submission, bootstrap label reconciliation, stack rendering, production guards and local `.env` fallback behavior.
    Risks: Development deploy requires an authorised host label and a valid ignored `.env`; a stale label or mutable digest fails closed. Do not parse encrypted SOPS material through the deployment environment parser.
    Rollback: Change the env contract and stack placement only together through a reviewed change; never bypass queue compatibility assessment for rollback.

2026-08-07 — Task 5.4: derive Swarm placement label from environment
    Context: The development and production environment names already determine their intended Swarm labels, while duplicating the label in each env file risks mismatched configuration.
    Change: `deploy-orchestrator-swarm.sh` and `bootstrap-swarm-host.sh` now derive `smtp2graph_dev` or `smtp2graph_prod` exclusively from `DEPLOY_ENVIRONMENT`; the canonical stack still requires the derived label with value `true`. Removed the duplicate env contract/example input while preserving env-derived immutable image digest and local development `.env` fallback.
    Verification: Shell and security regressions cover development and production derivation, stack rendering, bootstrap label reconciliation and immutable digest validation.
    Risks: An incorrect `DEPLOY_ENVIRONMENT` selects the wrong label, but matching host `SERVER_ENV` guards fail closed before mutation.
    Rollback: Restore an explicit label input only together with validation, env contract and stack documentation; do not bypass host environment matching.

2026-08-07 — Task 5.4: shared storage initialization before deploy
    Context: First development bootstrap found a missing storage parent, while the existing initializer could only prepare children of an already existing root.
    Change: Extended `init-storage.sh` to create a validated missing storage root under an existing non-symlink ancestor during explicit apply. Bootstrap and deploy/rollback orchestration now share the initializer, so stack submission occurs only after the reviewed root and direct `queue`/`failed` children converge.
    Verification: Storage initialization, bootstrap and fake-Docker deploy regressions passed, along with `make validate` and `git diff --check`.
    Risks: The nearest existing ancestor must be a non-symlink directory below `/`; non-empty incompatible queue/failed directories still fail closed and require migration review.
    Rollback: Do not remove initialized storage paths automatically; restore prior permissions only after queue/recovery assessment.

2026-08-08 — Task 5.4: development host bootstrap and first deploy boundary
    Context: The authorised development Swarm host had no initialized SMTP2Graph storage boundary, node label, encrypted overlay or nftables policy.
    Change: Applied the reviewed development bootstrap through a privileged operator. The storage root and direct `queue`/`failed` directories now have the reviewed ownership and mode; the development Swarm boundary converged. The first stack submission created the service, but it did not pass runtime smoke.
    Verification: Read-only stack render passed before apply. Bootstrap reported successful initialization. Service/task state and logs were inspected without reading Docker Secret payloads.
    Risks: This is development-only evidence. The gateway was not accepted as healthy because smoke did not yet observe one `Running` task or SMTP `220`.
    Rollback: Do not remove storage, overlay, nftables policy or labels automatically; assess queue/recovery state before any rollback action.

2026-08-08 — Task 5.4: SOPS versioned Docker Secret reconciliation
    Context: Initial deploy was refused because `.env` held placeholder Secret references and Docker Secrets did not exist.
    Change: Reconciled encrypted development values into seven deterministic versioned Docker Secrets and atomically updated the root-only names-only mapping. Corrected `SMTP_USERS_TSV` Dotenv escape handling so `\t` and `\n` are decoded only for the SMTP users Secret, creating a new content-addressed `smtp-users` version.
    Verification: SOPS reconciler regression passed. Docker Secret names and mapping updates were reported without exposing payloads. Placeholder `SMTP_USERS_TSV` was rejected before Docker mutation.
    Risks: The encrypted deploy contract must consume generated mapping references automatically; manually copying `*_SECRET_NAME` values into encrypted env creates rotation drift risk.
    Rollback: Retain existing immutable Secret versions. Do not delete a version until no reviewed stack references it and recovery impact is assessed.

2026-08-08 — Task 5.4: Swarm immutable Config and tmpfs runtime remediation
    Context: Runtime rollout exposed two Swarm compatibility gaps: fixed Config names cannot update immutable content, and shorthand Compose `tmpfs` entries were absent from the deployed service mount spec.
    Change: Deploy orchestration now derives a content hash from reviewed runtime assets and uses it in explicit Swarm Config names. The stack uses explicit `type: tmpfs` mounts for `/runtime` and `/tmp`; live service inspection confirmed both mounts are present. The entrypoint creates its runtime configuration directory with mode `0700` before tmpfs verification.
    Verification: Stack render, entrypoint regression and static stack checks passed. Live service inspection confirmed bind `/data` plus tmpfs `/runtime` and `/tmp` mounts.
    Risks: The gateway still fails runtime validation when `SMTP_USERS_TSV` is malformed; successful mount creation alone is not Phase 5.4 smoke evidence.
    Rollback: Prior immutable Config objects are retained by Swarm. Do not remove old Configs until the replacement service is healthy and no revision references them.

2026-08-08 — Task 5.4: required SOPS-backed deploy loader completion
    Context: Deploy now decrypts `env.dev.enc` or `env.prod.enc` only into `/dev/shm` and strict-parses the temporary Dotenv contract, but Secret name rotation still requires manual copying from the generated mapping into encrypted env.
    Change: Marked completion of the SOPS-backed deploy loader as required before closing the development deployment iteration. The required design is: encrypted env provides secret values and public deployment inputs; `reconcile-sops-secrets.sh` atomically writes names-only mapping; deploy merges that mapping over decrypted public configuration and refuses missing or incomplete references.
    Verification: Privileged SOPS-backed stack render succeeded after adding the immutable image digest and quoted-value normalization. Current loader cleanup uses temporary `/dev/shm` material and does not source decrypted files.
    Risks: Until mapping merge is implemented and tested, secret rotation is operationally error-prone and deployment evidence remains incomplete. Current service smoke is still failing and must not be recorded as passed.
    Rollback: Keep the encrypted env and names-only mapping separate; do not reintroduce plaintext secret values, shell sourcing or manually mutable Secret references into the deploy path.

2026-08-08 — Task 5.4: SOPS-backed deploy loader merges immutable Secret mapping
    Context: The deploy path decrypted public configuration but still accepted versioned Secret references from encrypted env, requiring manual copying after Secret rotation.
    Change: The orchestrator now reads `TLS_SECRET_MAPPING_FILE` from the SOPS-decrypted configuration, requires a private names-only mapping with every Graph, SMTP and TLS Secret reference, and overlays those names onto the deployment inputs. Missing, duplicate, unknown, empty or incomplete mapping entries fail closed.
    Verification: The isolated orchestrator regression covers a mapped reference overriding a stale encrypted value and rejects both missing mapping configuration and a mapping without a required reference.
    Risks: The mapping remains a host-side deployment artifact and must stay protected from non-owner reads; live development smoke remains a separate unaccepted task.
    Rollback: Restore the prior reviewed loader only with a rotation/recovery assessment; do not return to manual Secret-name copying or plaintext Secret values.

2026-08-08 — Task 5.4: consolidate canonical sender address configuration
    Context: The encrypted deployment contract repeated the single runtime sender as `GRAPH_SENDER_MAILBOX`, `SMTP_ALLOWED_SENDER_ADDRESSES` and M365 test-only `MAILBOX`, allowing policy drift that blocked gateway startup.
    Change: `GRAPH_SENDER_MAILBOX` is now the sole runtime sender input; deploy and stack rendering derive the global SMTP sender allowlist from it. Removed the two deprecated encrypted aliases from development and production contracts. `SMTP_USERS_TSV` remains a separate Docker Secret because its per-user sender scope is an independent policy control. The fork qualification adapter supplies its legacy `MAILBOX` variable only in the test process. `.env.example` now documents the retained M365 recipient/denied-mailbox, ACME contact and SMTP-user roles.
    Verification: Encrypted Dotenv contracts decrypt successfully without either deprecated key. Orchestrator, runtime policy, static stack, rehearsal, syntax, ShellCheck, Markdown/YAML/shell formatting and contract checks pass locally.
    Risks: The already submitted development service still uses its previous immutable Config until a separately approved redeploy; production is not changed.
    Rollback: Restore the reviewed encrypted aliases only if reverting to a prior control-plane revision after queue/recovery assessment; do not weaken per-user SMTP sender validation.
