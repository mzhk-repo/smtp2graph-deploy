# ADR-0008: Prefer At-Least-Once delivery during rollback and recovery

- **Status:** Accepted
- **Date:** 2026-08-03
- **Related:** `docs/SPEC.md` sections 6, 9, 13, 14; Task 5.4; Gate D

## Context

A gateway can receive Graph acceptance for a queued MIME item before an interruption prevents durable removal of that item. Rollback, cold recovery or replay can then submit the same item again. Trying to guarantee exactly-once delivery would require an external idempotency store or distributed coordination, neither of which is part of the production minimum.

## Decision

Treat delivery as **At-Least-Once** during rollback, recovery and queue replay. Preserve a durably accepted queue item until the gateway records successful completion; when the completion boundary is uncertain, operators prefer a possible duplicate over silent message loss.

Rollback must be explicit, use a declared queue-compatible immutable digest pair, preserve queue state, and record the affected time window. Operators verify service health, queue drain and an independent synthetic delivery after rollback. A unique rehearsal identifier is retained only as non-sensitive operational evidence; mailbox cleanup is never automatic.

## Alternatives Considered

- Exactly-once delivery with distributed locks or an external idempotency database — rejected for v1.0 because it adds a stateful component and new failure modes.
- At-Most-Once delivery by deleting uncertain queue items — rejected because it risks silent message loss.
- Uncontrolled replay — rejected because queue compatibility and operator evidence remain mandatory.

## Consequences

- Clients and operators must tolerate duplicate mail during exceptional recovery paths.
- Runbooks must freeze acceptance, assess queue compatibility and document duplicate risk before rollback.
- Task 5.4 verifies no queue loss across upgrade/rollback, but cannot prove absence of duplicates under every interrupted Graph-completion timing.
- A future exactly-once requirement requires a new ADR and an approved stateful architecture.
