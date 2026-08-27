# ADR-0009: Use digest-only deployment inputs and external release evidence

- **Status:** Accepted
- **Date:** 2026-08-27
- **Supersedes:** release-evidence storage aspect of Task 5.4 metadata
- **Related:** `docs/SPEC.md` sections 6, 9, 13, 14; ADR-0008; Tasks 5.3, 5.4; Gate D

## Context

Maintaining the same immutable image digest, release URLs and compatibility pairs in both encrypted deployment environment files and control-plane YAML duplicated release bookkeeping. The deployable image is already an explicit, immutable `SMTP2GRAPH_IMAGE_DIGEST` in the reviewed environment contract.

## Decision

The environment contract is the sole control-plane input for a normal deployment image and contains only the immutable digest. Release evidence (Trivy result or exception, CycloneDX SBOM, checksums and OCI metadata) remains immutable in the build-plane release artifacts; it is not copied into `deploy/config/`.

`queue-compatibility.yml` is removed. Upgrade, rollback and recovery remain manual operations: an operator must explicitly pass `--queue-compatibility-confirmed` only after reviewing the exact two release artifacts, preserving queue state and recording the assessment in operator evidence. No automatic rollback is enabled.

## Consequences

- Releasing a new image requires updating only `SMTP2GRAPH_IMAGE_DIGEST` in the selected encrypted environment contract.
- Normal deploy validates the digest format but does not query a local release allowlist.
- A rollback still requires an explicit immutable target digest, compatibility assessment, queue preservation and post-change smoke/synthetic verification.
- The two-digest rehearsal is the practical compatibility evidence; its operator evidence records the exact digests and result.
