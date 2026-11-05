## Summary

This PR hardens SMTP2Graph for reliable SMTP-to-Microsoft Graph delivery in an internal production environment.

It addresses delivery durability, Graph error handling, SMTP policy enforcement, runtime security, observability, and reproducible CI/release validation while preserving the existing SMTP client interface.

## Changes

### Delivery reliability

- Respect `Retry-After` for Graph throttling responses with bounded retry handling.
- Persist messages before returning SMTP `250`, preventing acknowledgement before durable enqueue.
- Move permanent delivery failures, including `ErrorAccessDenied`, to the `failed` queue.
- Preserve queued messages across gateway restarts.
- Add regression coverage for retry, queue durability, restart recovery, and permanent failures.

### SMTP policy and storage protection

- Require SMTP authentication and enforce source-IP and sender allowlists.
- Add per-user sender restrictions.
- Reject oversized submissions before queue persistence.
- Add bounded storage-threshold protection.
- Enforce per-IP session limits and message-rate limits.
- Prevent rejected submissions from creating queue payloads.
- Add failed-message retention handling with isolated queue and failed directories.

### Security and privacy

- Support runtime certificate and client-secret credential paths without embedding secrets in the image.
- Improve non-root and read-only filesystem compatibility.
- Harden the container build and runtime configuration.
- Remove static TLS test key material and generate test fixtures at runtime.
- Prevent message bodies and attachment content from appearing in gateway logs.
- Add Gitleaks and Trivy configuration for the reviewed source and image build.

### Observability

- Add `/livez` and `/readyz` health endpoints.
- Add bounded Prometheus metrics for delivery, retry, failure, and queue behavior.
- Add structured JSON logging.
- Add tests covering the observability contract.

### CI and release hygiene

- Quarantine superseded upstream workflows so they cannot execute accidentally.
- Add source-specific CI validation and workflow policy tests.
- Pin the Docker base image and improve Dockerfile lint compliance.
- Add reproducible release metadata and release validation.
- Update dependencies and package-lock metadata.

## Validation

The following validation has been completed:

- TypeScript build and unit tests.
- SMTP receive and policy regression tests.
- Retry and durable enqueue tests.
- Permanent-error and rejected-submission isolation tests.
- Log privacy tests.
- TLS and authentication regression tests.
- Observability endpoint and metrics tests.
- Dockerfile and CI workflow validation.
- Local end-to-end SMTP-to-Graph validation using an isolated mock Graph service.

## Compatibility and scope

The existing SMTP protocol and client-facing configuration model are preserved. The changes are intended for authenticated internal SMTP clients and do not add public SMTP relay functionality.

This PR contains gateway source, tests, container, and CI/release changes only. Deployment orchestration, Swarm infrastructure, secret reconciliation, and production promotion remain the responsibility of the separate control-plane repository.