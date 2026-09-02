# ADR-0010: Remove mandatory cold-recovery RTO

- **Status:** Accepted
- **Date:** 2026-09-01
- **Supersedes:** RTO consequence in ADR-0007
- **Related:** Task 7.3; Gate D

## Context

The project retains tested cold recovery and a 24-hour configuration RPO, but
does not have an approved operational basis for a mandatory recovery-time
target. Treating an unmeasured target as an acceptance criterion would make
Gate D evidence misleading.

## Decision

Cold recovery remains mandatory, but its elapsed time is recorded as operator
evidence rather than accepted against a fixed RTO. Manual backups must be run
at least daily to support the configuration RPO. Each backup creates a local
copy and an rclone-managed cloud copy; neither includes mail payloads.

## Consequences

- Task 7.3 and Gate D require a practical restore, secret rebind, deploy and
  synthetic verification, but no time threshold.
- Ansible owns scheduling outside this repository.
- ADR-0007 remains accepted except for its RTO consequence.
