# AI_CONTEXT.md

## Project Summary

`smtp2graph` is an infrastructure project for a private SMTP-to-Microsoft Graph gateway. It enables Grafana, Moodle, DSpace, Koha, and Matomo to send mail through Microsoft 365 while Microsoft Entra Security Defaults remain enabled. The target is a secure, maintainable production minimum, not a general-purpose mail platform.

Upstream SMTP2Graph v1.1.5 was the initial gateway candidate and is rejected by Gate B. A minimal fork is a remediation path only; functional Gate B qualifies source behavior, while Task 5.3 alone builds/pushes a GHCR release and records its exact digest-scoped supply-chain evidence before staging or production promotion.

## Current Status

- The project is in the planning stage; no production gateway implementation is present.
- `docs/SPEC.md` defines the approved requirements baseline.
- `docs/ROADMAP.md` defines the implementation sequence, quality gates, and acceptance work.
- `docs/AI_CONTEXT.md` is the compact entry point for future agents.
- Task 1.1 inventory is complete. The Koha-derived GitHub workflow and deployment script are quarantined outside their executable paths and are not SMTP2Graph-ready. They may be replaced or selectively adapted only through a reviewed roadmap task.
- Task 1.2 local quality baseline is complete. `make validate` runs pinned Markdown, YAML, and shell-format checks plus `git diff --check`; Gitleaks and ShellCheck remain CI-owned checks.
- Task 1.3 experimental configuration contract is complete. `.env.example` contains safe development values and versioned-secret-name placeholders only; `verify-env.sh --example-only` validates the allowlisted keys without sourcing an environment file.
- Task 1.4 documentation baseline is complete. `README.md`, `AI_CONTEXT.md`, the changelog index/active volume, roadmap documentation map, and the roadmap phase transition map are present and linked.
- Task 2.1 ADR baseline is complete. `docs/adr/ADR-0001` through `ADR-0007` record the SMTP-to-Graph boundary, initial gateway candidate, Swarm topology, sender mailbox, Graph mailbox scope, secret boundary, and cold-recovery model. Task 2.5 rejected upstream SMTP2Graph v1.1.5 in ADR-0002; all functional evidence for fork revision `0fbb699` and formal Gate B owner approval are complete. Exact GHCR digest and Task 5.3 supply-chain evidence remain pending before staging or production promotion.
- Task 2.3 runtime compatibility spike is complete with synthetic inputs. The prototype renders configuration in tmpfs, supports certificate-file and client-secret fallback modes, and passes non-root/read-only startup, listener, stop/restart and secret-surface checks; Graph token and delivery behavior remain unqualified.
- Task 2.4 protocol qualification is complete against an isolated token/Graph mock. MIME and queue-restart checks pass, but Graph `Retry-After` is ignored, `ErrorAccessDenied` does not move payloads to failed state, and SMTP `250` precedes proven durable enqueue. Task 2.5 therefore rejected upstream v1.1.5.
- Task 3.1 local runtime wrapper is complete. POSIX `scripts/entrypoint.sh` renders the reviewed `deploy/config/gateway-config.yml.template` only into an existing tmpfs mount, reads mounted Docker Secret files, strictly parses an optional allowlisted non-secret input file without `source`, and fails closed for missing, writable or unsuitable secret files. Docker Secret ownership is allowlisted explicitly (root and runtime UID by default). Shell and isolated Docker tests cover certificate/client-secret modes, non-root/read-only startup, listener, graceful stop/restart, missing-secret, weak-permission and unsafe-input cases.
- Gateway fork integration contract is defined. The current repository remains control plane; the build-plane checkout is available at `/opt/smtp2graph-build` on branch `v1.1.5-patched`, remote `mzhk-repo/smtp2graph-build`, baseline HEAD `0fbb699`. Its reviewed remediation commits cover Graph retry, permanent error to `failed`, durable enqueue and qualification tests. The Dockerfile pins its Node base image and defines the OCI release-metadata contract; the fork still has no recorded immutable release digest or completed Gate B approval.
- Task 3.2 policy/storage source work is now captured as `005-smtp-policy-and-storage-guards.patch` in the v1.1.5 control-plane bundle and was replayed successfully from clean `v1.1.5` in an isolated worktree. The local uncommitted build-plane copy remains disposable development state; only the versioned asset and its recorded replay evidence are valid review inputs.
- Task 3.2 control-plane SMTP policy rendering is complete for the local runtime boundary. The reviewed template requires SMTP AUTH, non-empty source-IP and global sender allowlists, and Docker Secret-backed per-user credentials/sender allowlists. `smtp-users` uses strict TSV records; parsing is shell-only, fail-closed, lowercases email addresses and redacts credentials in diagnostics. Deployment-level network policy, Docker Secret lifecycle and production per-service onboarding remain later tasks.
- Task 3.2 rejected-submission queue isolation is complete in the replayable fork test bundle. Asset `006-rejected-submission-queue-isolation.patch` exercises the actual receive server with isolated storage and proves that oversize input, missing SMTP authentication and an authenticated sender outside the allowlist create no `.eml` payload in `queue/`.
- Task 3.2 storage threshold guard is active in the local runtime boundary. The reviewed template and wrapper render validated `storage.rootPath`, `storage.maxBytes` and `storage.rejectThresholdPercent`; the fork regression in asset `005` proves threshold rejection with SMTP `451` before `DATA` and no new queue payload.
- Task 3.2 session and message-rate guards are active in the local runtime boundary. The reviewed template and wrapper render validated `receive.maxSessionsPerIp` and `receive.rateLimit` with a fixed 60-second window; asset `005` covers session-slot release and SMTP `451` when a client exceeds the configured message limit.
- Task 3.2 receive-log privacy is qualified in the replayable fork test bundle. Asset `007-receive-log-privacy.patch` submits runtime-generated body and attachment markers, then proves their absence from gateway stdout/stderr and local Winston file logs; Swarm, host and external aggregation surfaces remain later deployment/observability work.
- Task 3.2 failed-payload retention helper is complete for the local maintenance boundary. `scripts/purge-failed.sh` defaults to dry-run and uses only the validated `${SMTP2GRAPH_STORAGE_ROOT}/failed` directory, retaining payloads for seven days and never traversing or mutating queue data. Shell/security tests cover dry-run/apply behavior and unsafe-root refusal.
- Task 3.3 local end-to-end MVP harness is complete. `make test-local` applies all versioned fork assets to a clean temporary `v1.1.5` worktree, runs local regressions, builds an ephemeral local image and starts an internal Compose network with synthetic `/dev/shm` secrets plus mock Graph. It covers successful SMTP delivery, unauthenticated/denied-sender/oversize rejection without queue payloads and restart delivery after a transient mock timeout. It never reads M365 credentials or deploys; temporary Docker resources, image, worktree and branch are removed after the run.
- Task 4.2 non-production TLS material is issued through the isolated Cloudflare DNS-01 Certbot issuer and reconciled into versioned Docker Secrets. The certificate hostname/expiry and private-key/mapping modes were verified without exposing private material. Swarm stack, encrypted overlay, nftables policy and live SMTP checks remain unapplied pending the deployment boundary.
- Task 4.3 SOPS + age control-plane implementation is complete for local/non-production validation: `.sops.yaml` protects Dotenv-format `env.dev.enc` and `env.prod.enc`; the shared reconciler extracts only allowlisted values into `/dev/shm`, creates deterministic immutable Graph/SMTP/TLS Docker Secret names and atomically updates a names-only mapping. `--apply` is fail-closed for production and has not created Docker Secrets; age recovery custody and CI trust remain owner decisions.
- Task 4.4 container hardening control plane is complete for the non-production manifest: the gateway runs as UID/GID `65532`, uses a read-only root filesystem, drops all capabilities, enables no-new-privileges, caps PIDs/resources and provides `/runtime` plus `/tmp` as constrained tmpfs mounts. The validation-first storage initializer creates only `queue`/`failed` with mode `0700` and refuses symlinked roots, recursive ownership changes or non-empty incompatible payload directories. The runtime acceptance probe now passes secret rendering, non-root/read-only startup, listener, stop and restart; stack deployment and storage apply remain Task 5.1 work.
- Task 5.1 non-production Swarm host prerequisites are applied and verified: encrypted overlay `smtp2graph_internal`, node label `smtp2graph_nonproduction=true`, `/srv/smtp2graph/non-production/data/{queue,failed}` with UID/GID `65532` and mode `0700`, plus the deny-by-default nftables SMTP boundary. `deploy/swarm/stack.yml` defines the pending hardened stateful service with versioned external Docker Secrets, Swarm Config-mounted runtime files, persistent `/data`, TCP healthcheck and Swarm-native restart/update policy. No gateway stack or image has been deployed; a Task 5.3 image digest remains required.
- Task 5.2 non-production Swarm orchestration is complete in the control plane. `scripts/deploy-orchestrator-swarm.sh` strictly parses only allowlisted stack inputs and Secret names without `source` or local `.env` fallback. It validates rendered configuration, submits only explicit `--apply` non-production deploys, provides read-only status, and requires an explicit immutable digest plus queue-compatibility confirmation for rollback. Fake-Docker regression covers repeated declarative deploy submission, fail-closed production/tag/input handling and rollback guardrails; no live stack deployment was performed.
- The runtime template uses STARTTLS (`receive.secure: false`) with `allowInsecureAuth: false`; implicit TLS/SMTPS is not the Moodle transport contract. The upstream fork test suite proves insecure AUTH is denied until STARTTLS succeeds.
- Control plane is the sole source of truth for every gateway fork source change. All build-plane modifications must be delivered as versioned patch assets under `patches/smtp2graph/<upstream-version>/`, applied by reviewed automation from this repository to an isolated worktree, and verified before a build-plane commit. Manual/untracked changes in `/opt/smtp2graph-build` are disposable development state only and must never be a review, release, deployment or Gate B input. Upstream drift/conflict fails closed; automation performs no push, PR or deploy; M365 suite may finish documented `PARTIAL` when ignored test inputs are absent.
- Functional evidence for fork candidate `0fbb699` is complete: runtime compatibility, protocol/MIME, queue durability/restart, Graph retry and permanent-error handling, client-secret and certificate credential paths, 10 positive delivery/proxy scenarios, `DENIED_MAILBOX`, and Exchange display-name behavior are all qualified. The denied scenario proves `ErrorAccessDenied` is moved to `mailroot/failed` after SMTP acknowledgement. Exchange Online replaces the synthetic MIME `From` display name with mailbox display name `noreply`; a single mailbox therefore cannot provide client-specific visible names. The redacted decision record and formal Gate B owner approval are recorded; exact GHCR digest and Task 5.3 supply-chain evidence remain separate pending items.
- Task 4.5 Gate C review is complete. Formal owner approval for the Gate B fork candidate, redacted App Registration ownership and effective mailbox-scope evidence, read-only allowed/denied mailbox verification, and the selected RBAC for Applications mechanism are recorded as completed non-production evidence. Gate C does not require a separate credential expiry, rotation or revocation procedure in the current project baseline.

## Key Decisions

- Use Microsoft Graph application-only authentication; do not enable Exchange Online SMTP AUTH, app passwords, mailbox passwords, or Security Defaults exceptions.
- Production minimum is one SMTP gateway instance on a single-node Docker Swarm host.
- Use one dedicated sender mailbox for the MVP: `noreply@ldubgd.edu.ua`; production uses one dedicated mailbox per service with service-specific sender allowlists.
- Restrict application `Mail.Send` to the approved mailbox through Exchange Online RBAC for Applications.
- Prefer certificate-based Graph credentials if the pinned gateway supports safe file-based use; a runtime client secret is an explicitly documented fallback.
- Use Docker Secrets mounted at `/run/secrets/`. Encrypted static environment material uses SOPS + age; plaintext production secrets must not persist in Git, images, `.env` files, CI artifacts, logs, or container environment.
- Deploy a pinned image digest, not a mutable image tag.
- SMTP ingress is internal only. TLS is mandatory for Moodle and all routed SMTP traffic. Plain SMTP inside Swarm is allowed only after verifying an encrypted overlay network.
- The service has no admin UI, custom HTTP API, database, external message broker, Kubernetes, or active-active HA in v1.0.

## Architecture Snapshot

```text
Allowed internal SMTP clients
  -> internal firewall/network policy
  -> SMTP-to-Graph gateway (SMTP auth, IP/sender/size/rate policy)
  -> bounded persistent queue and privacy-safe operational logs
  -> Microsoft Entra token endpoint (HTTPS)
  -> Microsoft Graph sendMail (HTTPS)
  -> Exchange Online

Independent monitoring checks gateway health and synthetic delivery.
```

The target queue is durable but bounded to 1 GiB. At 80% utilization, new SMTP sessions or `MAIL FROM` submissions must receive a temporary `421` or `451` response and must not be accepted into the queue. For Graph HTTP `429`, qualification and tests must confirm handling of `Retry-After` with bounded exponential backoff.

## Tech Stack

- Rejected upstream gateway: SMTP2Graph v1.1.5, immutable digest recorded in `deploy/config/gateway-version.md`. A minimal fork is the selected remediation path; its three Critical functional blockers and non-production Microsoft 365 evidence are closed for revision `0fbb699`. Task 5.3 alone creates its qualified GHCR digest, Trivy scan/exception, Syft CycloneDX SBOM and OCI metadata before staging or production promotion.
- Fork release interface: `/opt/smtp2graph-build` is the local build-plane checkout for `ghcr.io/mzhk-repo/smtp2graph-build`. The shared CI/CD workflow builds, pushes and deploys only when invoked by its caller in Task 5.3; it is not a Phase 2 activity. The control plane may consume only a verified Task 5.3 digest paired with fork source, Trivy scan/exception record, CycloneDX SBOM and OCI labels as defined in `docs/FORK_INTEGRATION.md`.
- Runtime/orchestration: Docker Swarm, single node, one service replica.
- Secrets: Docker Secrets, SOPS + age.
- Identity and mail delivery: Microsoft Entra ID, Microsoft Graph, Exchange Online RBAC for Applications.
- Configuration/deployment: reviewed declarative Swarm manifests and idempotent shell scripts.
- Local quality: GNU Make, project-local pre-commit 4.6.0, and hooks frozen to immutable commits.
- Configuration contract: experimental until Gate B; non-secret settings and secret references are separated in `deploy/config/env-contract.keys`. Task 3.1 adds an explicit runtime YAML template; its rendered output is confined to tmpfs and is never a repository artifact.
- CI/CD: gateway build-plane має неактивний caller template у `.github/quarantine/main.yml.disabled`; він зберігає `@main` як temporary mutable exception і не може бути активований до Gate B, reviewed orchestrator, protected environments та immutable shared-workflow pin.
- Observability: VictoriaMetrics and Grafana, plus an independent notification channel.

## Security Constraints

- Never add secrets, tokens, private keys, SMTP passwords, decrypted SOPS content, or sensitive MIME samples to the repository, test fixtures, logs, command arguments, or CI output.
- Do not expose SMTP publicly or use host networking, privileged containers, Docker socket mounts, or mutable production tags.
- Enforce deny-by-default source IP/subnet, unique SMTP credentials, exact sender allowlist, a 25 MiB message limit, and rate/session limits.
- Graph authorization must prove allowed-mailbox success and out-of-scope mailbox denial before production.
- Run non-root where the chosen image supports it; use least privilege, `no-new-privileges`, dropped capabilities, and a read-only root filesystem when compatible.
- `/data/queue` is restricted to the service identity and operators. `/data/failed` must use mode `0700` and failed payloads are purged after at most 7 days.
- Do not log message bodies, attachments, tokens, passwords, reset URLs, or sensitive headers.
- Planned backups exclude `/data/queue` and `/data/failed`; restoring queue state can cause duplicate delivery.

## Repository Structure

```text
README.md
Makefile
docs/
  SPEC.md          # requirements and source of truth
  ROADMAP.md       # implementation plan and gates
  AI_CONTEXT.md    # this compact context
  adr/             # ADR policy; records are added with accepted decisions
deploy/
  README.md        # deployment boundary; no runtime manifests yet
  config/
    env-contract.keys  # machine-checkable experimental configuration contract
tests/
  README.md        # test policy; suites are added with implementation tasks
  shell/
    test-verify-env.sh # negative tests for the example-only contract validator
scripts/
  validate.sh      # non-mutating local quality entry point
  verify-env.sh    # validates .env.example without sourcing it
  lib/             # shared script contract; no runtime helpers yet
  quarantine/
    deploy-orchestrator-swarm.koha.sh.disabled  # non-executable, fail-closed legacy template
.github/
  # no active workflows; the gateway CI/CD template lives in the build-plane quarantine
```

Expected future paths are defined in the roadmap: `deploy/swarm/`, `deploy/config/`, `deploy/monitoring/`, test suites, `docs/RUNBOOK.md`, `docs/TEST_PLAN.md`, and `docs/scripts_runbook.md`.

## Initial Template Inventory

| Asset | Decision | Rationale and reusable scope |
|---|---|---|
| `.github/quarantine/main.koha.yml.disabled` | Removed | Koha-specific CI/CD template перенесено з control plane. Adapted inactive gateway caller template now belongs to `/opt/smtp2graph-build/.github/quarantine/main.yml.disabled`; it retains `@main` only as an explicit temporary exception. |
| `scripts/quarantine/deploy-orchestrator-swarm.koha.sh.disabled` | Replace | Unsafe as an SMTP2Graph orchestrator: it contains Koha/MariaDB volume assumptions, missing local dependencies, and active Docker Swarm mutation paths. Repository-root resolution, strict Bash mode, cleanup traps, and staged validation are patterns to adapt only after review. |
| `docs/hello-world.md` | Remove | Ignored local prompt scratchpad, not project documentation. Removal is deferred because the working tree already contains a user change. |
| `.gitignore` | Keep | Correctly keeps the local prompt scratchpad out of future commits; extend it only as real generated or secret-bearing paths are introduced. |

The runtime-mounted `.agents/` and `.codex/` directories are empty environment artifacts, not tracked project templates. Git metadata is outside the template inventory.

## Important Documents

| Document | Purpose | Priority |
|---|---|---|
| `docs/SPEC.md` | Requirements, architecture, security baseline, production acceptance, approval gates | Highest |
| `docs/ROADMAP.md` | Ordered implementation tasks, files, checks, risks, rollback notes | High |
| `docs/adr/ADR-*.md` | Accepted long-lived architectural decisions, once created | High for covered decisions |
| `docs/RUNBOOK.md` | Operating, deploy, recovery, and incident procedures, once created | Operational source of truth |
| `docs/TEST_PLAN.md` | Detailed test cases and evidence, once created | Test source of truth |
| `CHANGELOG.md` and `docs/changelogs/` | Append-only change index and active volume | Significant user/operator-visible changes |

If this file conflicts with `docs/SPEC.md`, `docs/ROADMAP.md`, or an applicable ADR, the source document takes precedence. Resolve ambiguity by updating the source document first, then this file when the change affects compact agent context.

## Implementation Rules for AI Agents

1. Read this file first, then read the smallest relevant source section before changing anything.
2. Follow the roadmap order. Do not implement production deployment before Gate B; do not use production authorization before Gate C; do not release before Gate D.
3. Make small, reviewable, idempotent changes. Validate each change with the task-specific commands from the roadmap.
4. Do not invent upstream SMTP2Graph behavior. Qualify secret-file support, non-root/read-only compatibility, SMTP acknowledgement semantics, queue durability, Graph `Retry-After`, MIME/BCC/attachment behavior, and display-name behavior with evidence.
5. Use IaC and reviewed automation for infrastructure changes. Avoid manual production configuration.
6. Classify scripts as validation, deploy-adjacent, or autonomous. Do not `source` an orchestrator environment file; use strict parsing or pass it directly to tools.
7. Keep documentation focused. Update SPEC for approved requirement changes, ADRs for durable decisions, RUNBOOK for operational changes, and this file after accepted ADRs or material milestones.
8. Preserve unrelated working-tree changes. Do not reset, overwrite, or delete user work.

## Known Assumptions

- Grafana, DSpace, Koha, and Matomo run on the same Docker Swarm host; Moodle runs on another VM under the same hypervisor.
- Normal mail volume is below 10 messages per minute. All clients, including Moodle, use the per-client baseline limits of five concurrent sessions per IP and 30 messages per minute.
- Messages may contain password-reset links and limited personal data.
- Operational logs are retained for 30 days. Failed payloads are retained for at most 7 days. Security/audit metadata is retained for 30 days.
- Availability target is 99.5% per month. RTO is 60 minutes. Configuration RPO assumption is 24 hours.
- Direct TCP/443 egress to Microsoft identity endpoints and Microsoft Graph is available; no HTTP proxy is required.
- VictoriaMetrics + Grafana is the selected monitoring stack. Entra client-secret and TLS-certificate expiry alerts must warn at 30 days and be critical at 7 days.

## Open Questions

- Which owners may approve the protected branches, releases and GHCR package for `mzhk-repo/smtp2graph-build`?
- How will the shared CI/CD workflow pass, verify and deploy the exact GHCR digest rather than mutable `main`/`dev` tags?
- Which named owners must approve the completed functional Gate B evidence for fork revision `0fbb699`?
- Can Task 5.3 produce and retain the immutable GHCR digest, Trivy scan/exception record, CycloneDX SBOM and OCI labels required for staging/production promotion?
- What TLS certificate source and trust model will clients use?
- What non-production test tenant/mailbox and recipient allowlist are available?
- What is the final independent alert transport and who owns on-call response?
- What approved SOPS age recipient, recovery custody, CI trust boundary, and secret naming convention will be used?
- Which exact non-production IPv4 CIDR ranges, deployment host and Docker API boundary are approved for Task 4.2 apply?

## Last Updated

2026-07-31 — Task 4.3 SOPS files use encrypted Dotenv syntax and the reconciler extracts allowlisted values without `source`. Task 4.4 adds non-production container hardening and validation-first storage initialization for runtime UID/GID `65532`; the runtime acceptance probe passes secret rendering, non-root/read-only startup, listener, stop and restart. Task 5.1 applies and verifies the non-production encrypted overlay, node label, storage and nftables prerequisites. Task 5.2 adds fail-closed non-production orchestration with strict env parsing, explicit deploy/rollback guards and fake-Docker evidence; gateway stack deployment remains pending Task 5.3 digest.
