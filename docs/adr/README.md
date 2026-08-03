# Architecture Decision Records

ADR створюються лише для довготривалих архітектурних або security-рішень. Нумерація послідовна: `ADR-NNNN-short-title.md`.

Статуси: `Proposed`, `Accepted`, `Rejected`, `Superseded`. Accepted ADR не переписується; зміна рішення оформлюється новим superseding ADR.

## Index

| ADR | Decision | Status | Gate / dependency |
|---|---|---|---|
| [ADR-0001](ADR-0001-use-smtp-to-graph-not-smtp-auth.md) | SMTP-to-Graph через application-only Graph auth | Accepted | Gate C authorization |
| [ADR-0002](ADR-0002-select-smtp2graph-as-initial-gateway.md) | SMTP2Graph v1.1.5 як початковий gateway candidate | Rejected | Gate B qualification |
| [ADR-0003](ADR-0003-select-single-node-swarm-for-production-minimum.md) | Single-node Docker Swarm | Accepted | Gate D operational readiness |
| [ADR-0004](ADR-0004-use-dedicated-single-sender-mailbox.md) | Одна dedicated sender mailbox | Accepted | Gate C mailbox ownership |
| [ADR-0005](ADR-0005-restrict-graph-mail-send-to-sender-mailbox.md) | Mail.Send обмежується sender mailbox | Accepted | Gate C allowed/denied proof |
| [ADR-0006](ADR-0006-runtime-secrets-and-sops-age-policy.md) | Docker Secrets runtime boundary та SOPS + age | Accepted | Gate B compatibility; Gate C secret review |
| [ADR-0007](ADR-0007-single-instance-with-cold-recovery.md) | Single instance із cold recovery | Accepted | Gate D recovery evidence |
| [ADR-0008](ADR-0008-at-least-once-delivery-during-recovery.md) | At-Least-Once delivery під час rollback/recovery | Accepted | Task 5.4; Gate D |

`Accepted` означає прийняту baseline-архітектурну політику, а не завершене runtime-тестування. Qualification evidence залишається обов’язковим за відповідним gate.
