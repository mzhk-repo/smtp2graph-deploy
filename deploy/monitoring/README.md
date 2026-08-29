# SMTP2Graph monitoring integration

The gateway exposes unauthenticated `/livez`, `/readyz`, and Prometheus
`/metrics` on port `9464`. The port is deliberately not published on the host;
it is reachable only from services attached to `SWARM_OVERLAY_NETWORK`.

Import `smtp2graph-scrape.yml` into the VictoriaMetrics configuration and attach
the VictoriaMetrics scraper to the same encrypted external overlay. The target
uses the stack service DNS name `smtp2graph_gateway`; adjust it only if the
reviewed `SWARM_STACK_NAME` changes.

The gateway's Docker `local` logging driver bounds on-host logs to 30 rotated
10 MiB files. This size/file-count bound is the accepted log-retention policy;
there is no time-based retention SLA.

After a declarative deploy, run:

```bash
./tests/observability/test-signals.sh --environment development
```

The check reads service metadata, performs loopback probes inside the running
gateway container, and does not submit SMTP mail or print metrics/log payloads.
