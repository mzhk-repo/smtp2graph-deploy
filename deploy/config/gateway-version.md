# SMTP2Graph qualification candidate

**Status:** Rejected by Gate B; do not use for production deployment.
**Date:** 2026-07-22
**Related:** [ADR-0002](../../docs/adr/ADR-0002-select-smtp2graph-as-initial-gateway.md), Roadmap Tasks 2.2–2.5, Gate B

## Candidate

| Field | Value |
|---|---|
| Upstream repository | [`SMTP2Graph/SMTP2Graph`](https://github.com/SMTP2Graph/SMTP2Graph) |
| Source release | [`v1.1.5`](https://github.com/SMTP2Graph/SMTP2Graph/releases/tag/v1.1.5) |
| Image repository | `docker.io/smtp2graph/smtp2graph` |
| Immutable multi-platform reference | `docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d` |
| Linux amd64 manifest | `sha256:099b9a2807bf79572821bb6dd01ab196b3387dcc4b0524a5387d8d2f460f8b08` |
| Linux arm64 manifest | `sha256:1fc2c500f58efcdd0e1a2f7c361d94c37b6b5d7014a92f8710a1612bee1d523a` |
| License | GPL-3.0, according to upstream repository metadata |

The digest was resolved from the Docker Registry manifest and then pulled by digest. The local amd64 image reported the same repository digest and image ID `sha256:3b6a42d721972d13eaabf23c3313dae5c40ae449fe187ae732bc77b3c10a3b2f`.

## Evidence collected

- GitHub identifies `v1.1.5` as the latest release, published on 2026-05-03. Its release notes include fixes for graceful container stop, file rename handling and multiple messages on one connection.
- The registry exposes amd64 and arm64 manifests plus OCI attestation manifests for the two platform manifests.
- The upstream Dockerfile uses `node:20-alpine`, exposes TCP/587, declares `/data` as a volume and starts `/bin/sh -c startup.sh`.
- Local image metadata reports `Created=2026-05-03T11:20:50.91496843Z`, `Architecture=amd64`, and no configured non-root `User`.
- Task 2.3 isolated runtime probe passed with certificate-file mode and client-secret fallback. It rendered `config.yml` only in a container tmpfs, started the candidate as UID/GID `65532:65532` with a read-only root filesystem, dropped capabilities and `no-new-privileges`, then verified listener readiness, graceful stop and clean restart.

## Qualification status

| Check | Result | Evidence / blocker |
|---|---|---|
| Exact version and digest | Pass | Registry manifest inspection and digest-pinned pull |
| Source/release identity | Preliminary pass | Upstream repository and tagged release identified; build provenance requires final review |
| License | Preliminary pass | GPL-3.0 metadata found; project compatibility review remains required |
| Image architecture | Pass for amd64/arm64 | Both platform manifests are present |
| Image signature verification | Out of Gate B scope | Signature verification is not one of the three agreed Gate B supply-chain artifacts |
| Trivy image scan | Deferred to Task 5.3 | Exact-digest scan and Formal Exception Record are required before staging/production promotion |
| CycloneDX SBOM | Deferred to Task 5.3 | Syft-generated SBOM is required before staging/production promotion |
| OCI metadata labels | Deferred to Task 5.3 | Fork release tag, source revision and upstream base commit are recorded by Task 5.3 |
| Certificate file path | Preliminary pass | Task 2.3 renders `privateKeyPath` from a Docker Secret mount and starts the candidate with a synthetic certificate |
| Client-secret fallback | Preliminary pass | Task 2.3 renders a secret-file value only into tmpfs; synthetic value is absent from inspect and logs |
| Non-root/read-only compatibility | Preliminary pass | Task 2.3 passed as UID/GID `65532:65532` with `/runtime` and `/tmp` tmpfs; the upstream image itself still has no configured `USER` |
| Protocol/MIME/queue | Partial; blockers found | See `docs/TEST_PLAN.md`: MIME and restart pass locally, but `Retry-After`, dead-letter and acknowledgement durability are unacceptable or incomplete |
| Gate B | Rejected | Task 2.5 confirmed Critical `Retry-After`, dead-letter and acknowledgement-durability blockers. A future fork requires separate digest-scoped evidence; this upstream evidence is not transferable by default. |

## Safe reproduction commands

```bash
docker buildx imagetools inspect docker.io/smtp2graph/smtp2graph:v1.1.5
docker pull docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d
docker image inspect docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d
trivy image --severity HIGH,CRITICAL --exit-code 1 docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d
syft docker.io/smtp2graph/smtp2graph@sha256:88ef2015f37ad460d7cc06fa80cf82a0318108ae696dac61a2896d5016d9545d -o cyclonedx-json
```

The last three commands are intentionally not recorded as successful: the local environment lacks Trivy and Syft, and the inspect command must be run with access to the Docker daemon. Runtime evidence is reproduced with `./tests/acceptance/runtime/run.sh`; it uses synthetic files and `network=none`, so it does not prove Graph token acquisition or delivery behavior. The image reference in this file is a qualification candidate, not an approved production deployment reference.
