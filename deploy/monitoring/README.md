# SMTP2Graph monitoring integration

The gateway exposes unauthenticated `/livez`, `/readyz`, and Prometheus
`/metrics` on port `9464`. The port is deliberately not published on the host;
it is reachable only from services attached to `SWARM_OVERLAY_NETWORK`.

Import `smtp2graph-scrape.yml` into the VictoriaMetrics configuration and attach
the VictoriaMetrics scraper to the same encrypted external overlay. The target
uses the stack service DNS name `smtp2graph_gateway`; adjust it only if the
reviewed `SWARM_STACK_NAME` changes. The imported job must retain labels
`env=prod`, `service=smtp2graph` and `component=gateway`; dashboard, alert and
synthetic-delivery queries rely on this exact contract.

The monitoring control plane owns `SMTP2GRAPH_METRICS_TARGET` and renders it as
`smtp2graph_gateway:9464`. Its synthetic runner reaches the gateway by the
reviewed overlay DNS alias (`gateway`), uses STARTTLS, and writes only aggregate
freshness/status metrics for Node Exporter. Its alert notification path must use
an external SMTP provider rather than SMTP2Graph, preventing a gateway outage
from suppressing its own alert.

The gateway's Docker `local` logging driver bounds on-host logs to 30 rotated
10 MiB files. This size/file-count bound is the accepted log-retention policy;
there is no time-based retention SLA.

After a declarative deploy, run:

```bash
./tests/observability/test-signals.sh --environment development
```

The check reads service metadata, performs loopback probes inside the running
gateway container, and does not submit SMTP mail or print metrics/log payloads.

After the monitoring stack is deployed, run its reviewed checks from
`/opt/victoriametrics-grafana`:

```bash
./tests/test-observability-config.sh
./tests/integration/test-synthetic-and-metrics.sh
```

The second check submits one controlled non-production synthetic message. Keep
only redacted aggregate evidence; do not retain its recipient, message marker,
SMTP credentials, or Docker Secret payload.
