# SMTP2Graph deployment and rollback runbook

## Task 5.4 development rehearsal

This procedure is development-only and must not be pointed at a production host, production credentials or production recipients.

### Preconditions

- Task 5.3 has approved the current and candidate immutable image digests and retained their Trivy, Syft and OCI evidence.
- `deploy/config/queue-compatibility.yml` contains both evidence-backed images and their explicit compatible pair.
- The host has `SERVER_ENV=dev`, the development storage root is healthy, and a configuration/host backup reference is recorded. Routine backups never include live `queue/` or `failed/` payloads.
- The selected recipient exactly matches `NONPRODUCTION_RECIPIENT_ALLOWLIST`.
- Protected CI creates the test SMTP password file only below `/dev/shm`, owned by the runner and mode `0600`; the file is removed by CI cleanup.

### Run

Run only from the authorised development Swarm manager. Store the generated non-secret evidence file in an operator-only directory.

```bash
./scripts/rehearse-deployment.sh \
  --env-file /approved/path/development.env \
  --current-digest IMAGE@sha256:CURRENT \
  --candidate-digest IMAGE@sha256:CANDIDATE \
  --recipient approved-test-mailbox@example.invalid \
  --smtp-user rehearsal-client \
  --password-file /dev/shm/smtp2graph-rehearsal-password \
  --backup-reference backup-reference-id \
  --evidence-dir /approved/operator-only/evidence \
  --apply
```

The script creates a temporary invalid Graph credential Secret, submits one synthetic STARTTLS SMTP message, upgrades to the candidate digest, rolls back to the current digest and restores the normal credential mapping. It removes only its own `smtp2graph_rehearsal_graph_cred_*` Secret after the service no longer references it.

### Verify and close

- Read the generated evidence file and run `tests/acceptance/deployment/smoke.sh` plus `scripts/check-network-policy.sh --env-file <development-env>`.
- Use a read-only query against the non-production mailbox to confirm the reported `X-Rehearsal-ID`; do not place message bodies or credentials in evidence.
- Confirm that the queue drained. Do not automatically delete the mailbox test message.

### Rollback and duplicate risk

Freeze new acceptance before an emergency rollback. The rollback command requires an explicit immutable digest and a pair declared in `queue-compatibility.yml`. This service uses At-Least-Once delivery during rollback/recovery: if Graph accepted a message before an interrupted queue cleanup, a replay can produce a duplicate. Prefer this over silent loss, record the affected interval, and investigate duplicates from metadata without logging message content.
