# ADR-0011: Automate ACME TLS rotation outside SOPS

- **Status:** Accepted
- **Date:** 2026-09-04
- **Related:** ADR-0006, ADR-0007, Tasks 4.2, 4.3, 5.2, 7.2

## Context

STARTTLS certificates issued by ACME are short-lived. Copying their PEM values
into SOPS on every renewal couples routine PKI maintenance to a Git release and
can leave the running gateway with an expired certificate.

## Decision

Cloudflare DNS-01 credentials remain SOPS-encrypted. TLS certificate and private
key material are owned by Certbot's local lineage and are materialized directly
as immutable, content-addressed Docker Secrets. A root-owned systemd timer runs
the reviewed renewal script daily. The script changes only the gateway TLS Secret
mounts, verifies the live STARTTLS fingerprint, and keeps old Secret versions for
rollback. Host-specific locations are installed as validated values in a
root-owned systemd EnvironmentFile, never hardcoded in repository assets.

## Consequences

- TLS PEM values must be removed from `env.*.enc`; the static SOPS reconciler no
  longer reads them.
- A TLS Secret update restarts the single gateway task briefly; zero-downtime is
  not claimed for the single-node topology.
- Enabling the production timer is the explicit authorization for future routine
  TLS rotations. Failed cutovers return non-zero and retain rollback material.
