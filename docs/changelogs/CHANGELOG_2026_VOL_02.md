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
