# ADR-0002: Select SMTP2Graph as the initial gateway candidate

- **Status:** Rejected
- **Date:** 2026-07-22
- **Related:** `docs/SPEC.md` sections 2, 4, 5, 14; `docs/FORK_INTEGRATION.md`; Gate B; Tasks 2.2–2.5, 5.3

## Context

The project needs one maintainable SMTP-to-Graph component for the production minimum. SMTP2Graph was the initial candidate because its stated feature set includes SMTP server support, Graph relay, SMTP authentication, TLS, IP and sender allowlists, rate limiting, brute-force protection and a local queue. The v1.1.5 release and image digest were recorded as a qualification candidate. A synthetic runtime spike passed certificate-file and client-secret rendering plus non-root/read-only startup, but the Gate B review found Critical delivery and durability defects.

## Decision

Reject upstream SMTP2Graph v1.1.5, pinned to the multi-platform digest recorded in [`deploy/config/gateway-version.md`](../../deploy/config/gateway-version.md), as a production gateway component. Gate B confirmed three Critical blockers: Graph `Retry-After` is ignored; permanent Graph errors can remain in the live queue rather than atomically moving to `failed`; and SMTP `250` precedes confirmed durable queue persistence.

The roadmap selects a minimal fork of the exact upstream release as a remediation path only. It is not an approved production component. Functional candidate qualification is decided in Gate B; GHCR build/push, immutable digest and digest-scoped release evidence are deferred to Task 5.3 and are mandatory before staging or production promotion.

## Alternatives Considered

- Standalone Docker Compose with host-managed secrets — rejected for the production minimum because the selected baseline requires Swarm-native secret handling and controlled deployment.
- Minimal fork of exact v1.1.5 — selected as the remediation path because the three blockers are localized; it requires a new digest-scoped qualification.
- Custom Python production minimum — fallback if the fork cannot be maintained safely; it requires a new ADR and a full Gate B.
- Exchange Online connector relay — rejected because it does not provide the required application-only Graph boundary and client policy model.
- A different upstream gateway — retained as a fallback; it requires a full Gate B.

## Consequences

- Upstream v1.1.5 is prohibited as a production component; its existing digest, scan and runtime evidence cannot be transferred automatically to a fork.
- The qualification wrapper remains a synthetic prototype and does not approve any production secret lifecycle.
- The fork must implement and test `Retry-After`, permanent-error-to-`failed`, and durable SMTP acknowledgement behavior without MIME, BCC, UTF-8, attachment or restart regressions.
- A successful functional fork review requires the three remediation behaviors, non-production Microsoft 365 checks and a new Gate B decision record. Task 5.3 separately requires immutable image digest, Trivy image scan with Formal Exception Record where needed, CycloneDX SBOM through Syft and OCI metadata labels before staging or production promotion.
- Synthetic fixtures and isolated tenant resources remain required for protocol and runtime tests.

## Поточний стан remediation

Історичне рішення про відхилення upstream не змінюється. Remediation виконується в окремому build-plane checkout `/opt/smtp2graph-build` (`mzhk-repo/smtp2graph-build`, branch `patched-v1.1.5`), що походить від exact upstream `v1.1.5`. Наявні source commits `6d23ee0`, `3483c5b` і `8d99940` реалізують та покривають regression-тестами відповідно `Retry-After`, atomic permanent-error-to-`failed` і durable SMTP acknowledgement. Поточний checkout та його локальні тестові зміни не є release artifact і не можуть бути джерелом production deployment.

У non-production Microsoft 365 tenant пройдено 10 client-secret delivery/proxy scenarios, окремий `DENIED_MAILBOX` → `ErrorAccessDenied` → `failed` scenario і certificate-only send-and-read scenario. Certificate test конфігурує gateway через thumbprint і path до private key та не передає `appReg.secret`; ключ не виводився у логи. Це є функціональним evidence fork, але не замінює digest-scoped release qualification.

Кваліфікація display name 2026-07-27 показала, що Exchange Online замінює synthetic MIME `From` display name на display name mailbox `noreply`. Отже, одна mailbox не підтримує окремі видимі імена клієнтів; production має використовувати погоджену в ADR-0004 модель окремих service mailbox. Functional Gate B для fork revision `0fbb699` завершений: повторний review fork source revision і functional evidence не виявив Critical gaps, а формальне owner approval записане в control-plane evidence. GHCR build/push, immutable exact digest, Trivy image scan із Formal Exception Record за потреби, Syft CycloneDX SBOM, OCI metadata labels та artifact retention належать виключно Task 5.3 і є обов'язковими перед staging або production promotion.

До виконання Task 5.3 заборонено activation CI/CD template і production deployment fork; використання локального `private.key` як production secret також заборонене. Перенесення ключа в SOPS-encrypted `env.*.enc` і versioned Docker Secret lifecycle є окремою Task 4.3 та потребує окремо погодженого cutover.
