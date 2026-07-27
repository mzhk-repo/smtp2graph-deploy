# AI_CONTEXT.md

## Project Summary

`smtp2graph` is an infrastructure project for a private SMTP-to-Microsoft Graph gateway. It enables Grafana, Moodle, DSpace, Koha, and Matomo to send mail through Microsoft 365 while Microsoft Entra Security Defaults remain enabled. The target is a secure, maintainable production minimum, not a general-purpose mail platform.

Upstream SMTP2Graph v1.1.5 was the initial gateway candidate and is rejected by Gate B. A minimal fork is a remediation path only; it is not a production component until a new exact digest passes Gate B.

## Current Status

- The project is in the planning stage; no production gateway implementation is present.
- `docs/SPEC.md` defines the approved requirements baseline.
- `docs/ROADMAP.md` defines the implementation sequence, quality gates, and acceptance work.
- `docs/AI_CONTEXT.md` is the compact entry point for future agents.
- Task 1.1 inventory is complete. The Koha-derived GitHub workflow and deployment script are quarantined outside their executable paths and are not SMTP2Graph-ready. They may be replaced or selectively adapted only through a reviewed roadmap task.
- Task 1.2 local quality baseline is complete. `make validate` runs pinned Markdown, YAML, and shell-format checks plus `git diff --check`; Gitleaks and ShellCheck remain CI-owned checks.
- Task 1.3 experimental configuration contract is complete. `.env.example` contains safe development values and versioned-secret-name placeholders only; `verify-env.sh --example-only` validates the allowlisted keys without sourcing an environment file.
- Task 1.4 documentation baseline is complete. `README.md`, `AI_CONTEXT.md`, the changelog index/active volume, roadmap documentation map, and the roadmap phase transition map are present and linked.
- Task 2.1 ADR baseline is complete. `docs/adr/ADR-0001` through `ADR-0007` record the SMTP-to-Graph boundary, initial gateway candidate, Swarm topology, sender mailbox, Graph mailbox scope, secret boundary, and cold-recovery model. Task 2.5 rejected upstream SMTP2Graph v1.1.5 in ADR-0002; Phase 3 remains blocked pending a new fork candidate and Gate B.
- Task 2.3 runtime compatibility spike is complete with synthetic inputs. The prototype renders configuration in tmpfs, supports certificate-file and client-secret fallback modes, and passes non-root/read-only startup, listener, stop/restart and secret-surface checks; Graph token and delivery behavior remain unqualified.
- Task 2.4 protocol qualification is complete against an isolated token/Graph mock. MIME and queue-restart checks pass, but Graph `Retry-After` is ignored, `ErrorAccessDenied` does not move payloads to failed state, and SMTP `250` precedes proven durable enqueue. Task 2.5 therefore rejected upstream v1.1.5.
- Gateway fork integration contract is defined. The current repository remains control plane; the build-plane checkout is available at `/opt/smtp2graph-build` on branch `patched-v1.1.5`, remote `mzhk-repo/smtp2graph-build`, HEAD `8d99940`. Commits `6d23ee0` and `3483c5b` implement the three remediation areas and their queue regression coverage; `8d99940` adds the access-denied regression case. The fork still has no recorded immutable release digest or completed Gate B approval.
- Fork Step 6 non-production Microsoft 365 checks pass for both client-secret and certificate paths: 10 positive delivery/proxy client-secret scenarios, the `DENIED_MAILBOX` negative scenario, one certificate-only synthetic delivery, and display-name qualification. The denied scenario proves `ErrorAccessDenied` is moved to `mailroot/failed` after SMTP acknowledgement. Exchange Online replaces the synthetic MIME `From` display name with mailbox display name `noreply`; a single mailbox therefore cannot provide client-specific visible names.

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

- Rejected upstream gateway: SMTP2Graph v1.1.5, immutable digest recorded in `deploy/config/gateway-version.md`. A minimal fork is the selected remediation path, but it has no qualified digest or production approval; it must close the three Critical Gate B blockers and supply Trivy scan/exception, Syft CycloneDX SBOM, OCI metadata and non-production Microsoft 365 evidence.
- Fork release interface: `/opt/smtp2graph-build` is the local build-plane checkout for `ghcr.io/mzhk-repo/smtp2graph-build`. The shared CI/CD workflow automatically builds, pushes and deploys `dev` to development and `main` to production when invoked by its caller; it does not yet record the three agreed Gate B supply-chain artifacts. The control plane may consume only a verified digest paired with fork source, Trivy scan/exception record, CycloneDX SBOM, OCI labels and Gate B evidence as defined in `docs/FORK_INTEGRATION.md`.
- Runtime/orchestration: Docker Swarm, single node, one service replica.
- Secrets: Docker Secrets, SOPS + age.
- Identity and mail delivery: Microsoft Entra ID, Microsoft Graph, Exchange Online RBAC for Applications.
- Configuration/deployment: reviewed declarative Swarm manifests and idempotent shell scripts.
- Local quality: GNU Make, project-local pre-commit 4.6.0, and hooks frozen to immutable commits.
- Configuration contract: experimental until Gate B; non-secret settings and secret references are separated in `deploy/config/env-contract.keys`.
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
- Normal mail volume is below 10 messages per minute. Per-client baseline limits are five concurrent sessions per IP and 30 messages per minute; Moodle needs an additional throttle decision.
- Messages may contain password-reset links and limited personal data.
- Operational logs are retained for 30 days. Failed payloads are retained for at most 7 days. Security/audit metadata is retained for 30 days.
- Availability target is 99.5% per month. RTO is 60 minutes. Configuration RPO assumption is 24 hours.
- Direct TCP/443 egress to Microsoft identity endpoints and Microsoft Graph is available; no HTTP proxy is required.
- VictoriaMetrics + Grafana is the selected monitoring stack. Entra client-secret and TLS-certificate expiry alerts must warn at 30 days and be critical at 7 days.

## Open Questions

- Which owners may approve the protected branches, releases and GHCR package for `mzhk-repo/smtp2graph-build`?
- How will the shared CI/CD workflow pass, verify and deploy the exact GHCR digest rather than mutable `main`/`dev` tags?
- Does the fork pass Gate B with a new immutable digest, Trivy scan/exception record, CycloneDX SBOM and OCI labels?
- What TLS certificate source and trust model will clients use?
- What non-production test tenant/mailbox and recipient allowlist are available?
- What is the final independent alert transport and who owns on-call response?
- What approved SOPS age recipient, recovery custody, CI trust boundary, and secret naming convention will be used?

## Last Updated

2026-07-27 — Task 2.5 fork checkout is available at `/opt/smtp2graph-build` on `patched-v1.1.5` (`8d99940`) with the three remediation areas and access-denied regression coverage. Non-production Microsoft 365 delivery, denied-mailbox, certificate-credential and display-name checks pass. Exchange Online replaces the synthetic MIME display name with mailbox display name `noreply`, so production must use the already approved per-service mailbox model. The fork remains unapproved until exact-digest Gate B evidence is complete. A non-active CI/CD caller template now resides in the build plane; it must not be activated before its explicit blockers are closed.
