# ScreenKit monitoring workbench

A local server and browser dashboard built from **Grafana**, **OpenTelemetry
Collector**, **Prometheus**, and **Tempo**. The repository provisions native
Grafana panels and data sources; it does not implement a telemetry server,
time-series database, chart library, or OTLP serializer.

```text
ScreenKit → ScreenOpenTelemetry → official Swift OTLP/HTTP exporter
                                       ↓
                             OpenTelemetry Collector
                               ↙                 ↘
                         Prometheus             Tempo
                               ↘                 ↙
                                      Grafana
```

## Start

Install Docker Desktop (macOS) or Docker Engine with Compose (Linux). From the
repository root:

```sh
docker compose -f Monitoring/compose.yml up -d
```

Open [the dashboard](http://127.0.0.1:3000/d/screenkit-ui). Provisioning creates it
and both data sources automatically. It is a local, anonymous **Editor** workbench
so that Tempo's native waterfall can open in Explore. The provisioned dashboard
is file-managed; UI changes cannot replace its source. No administrator account
is created. Host ports bind to loopback by default.

The published images are pinned: Grafana 13.2.3 (Ubuntu image), Tempo 3.1.0, Prometheus 3.15.0,
Collector 0.161.0. Collector 0.162.0 has architecture-specific images but no
published multi-architecture tag at setup time; 0.161.0 supports Apple Silicon
and Linux CI with the same manifest. Expect several GB of image/storage space.

Endpoints:

| Endpoint | Purpose |
| --- | --- |
| `http://127.0.0.1:3000` | Grafana dashboard and native Tempo waterfall |
| `http://127.0.0.1:4318/v1/traces` | Standard OTLP/HTTP trace receiver |
| `http://127.0.0.1:4318/v1/metrics` | Standard OTLP/HTTP metric receiver |
| `http://127.0.0.1:9090` | Prometheus queries |
| `http://127.0.0.1:3200` | Tempo API |
| `http://127.0.0.1:13133` | Collector health |

## Send Swift data

The optional [ScreenKitTelemetryMonitor](../Packages/ScreenKitTelemetryMonitor)
package supplies SDK bootstrap using the official `OpenTelemetryProtocolExporterHTTP`
product. The API-only `ScreenKitOpenTelemetry` package keeps its existing
dependency boundary. Both example apps retain their release pins.

For an immediate preview, run the Swift producer:

```sh
cd Packages/ScreenKitTelemetryMonitor
swift run ScreenKitTelemetryProducer http://127.0.0.1:4318 60
```

Its `screenkit-synthetic` service and `synthetic` source are explicitly labeled.
The timings are invented source intervals, **not measured app performance**.
Counter and histogram panels populate after ingestion; rate/percentile panels
need at least two Prometheus scrapes (5 seconds apart). Select an update's Trace
ID in the table to open Tempo's waterfall.

In a consuming iOS app, add the local package and keep one connection alive:

```swift
import ScreenKit
import ScreenKitTelemetryMonitor

@MainActor
final class CatalogTelemetry {
    let monitor = ScreenTelemetryMonitor(
        endpoint: URL(string: "http://127.0.0.1:4318")!,
        serviceName: "ScreenKitLab"
    )

    func controller(for screen: Screen<Int, Product>) -> ScreenViewController<Int, Product> {
        screen.telemetry(monitor.adapter, name: "catalog").makeViewController()
    }
}
```

`Product` and the screen's renderer belong to the app. This package uses the same
unreleased ScreenKit telemetry revision as the adapter prototype, supports iOS
18+, and does not require iOS 27 Observation APIs. Call `await monitor.shutdown()`
when its owner is finished, outside measured UI intervals. `flush()` moves SDK
queue work off the main actor; it is **not a server delivery receipt**, because
the upstream metric exporter sends asynchronously. Network sessions/policies
remain app-owned; `httpClient:` accepts the official HTTPClient abstraction.
Shutdown explicitly collects the final metrics before stopping the periodic
reader, so updates since its last tick are not silently omitted.

For a complete consuming app, open the optional
[Telemetry Lab](../ScreenKitLab/Telemetry). It connects the existing mixed-content
screen, provides an OTLP switch, and saves balanced off/on comparisons with raw
samples. Its verifier checks all expected root traces, child phases and counters
in this workbench; a successful app run alone does not imply delivery.

For a physical iPhone, loopback means the phone itself. Deliberately expose only
OTLP on the development LAN with `OTLP_BIND_ADDRESS=0.0.0.0` when starting Compose,
then use the Mac's LAN address in the app. Configure the app's development-only
local-network/HTTP policy as appropriate; do not disable ATS globally. Grafana
and database ports remain loopback-bound. This unauthenticated local receiver is
not a production or public internet deployment.

## Read the board correctly

- **Completed/other outcomes** show latest cumulative counters for active streams,
  not increases over the dashboard time range. `service.instance.id` separates
  producers; the default Swift bootstrap creates a new ID per connection.
- **Mean settled** uses cumulative histogram sum/count for active streams.
- **P50/P95/P99** use Prometheus `histogram_quantile` over rate windows. They are
  bucket estimates from source metrics, independent of trace sampling.
- **Phase mean** is per occurrence in completed updates. Phases may overlap;
  adding their durations does not give CPU time.
- **Work per update** divides renderer/cell/supplementary/reload/reconfigure rates
  by the completed update rate. A zero denominator gives no meaningful value.
- **Tempo traces** are sampled, with an explicit update parent for each phase.
  Causal links and span attributes stay in Tempo; model IDs never become labels.

The source measurement ends after snapshot application and final layout, before
client completion. It does not prove display presentation, frame rate, GPU cost,
scroll hitches, or arbitrary SwiftUI body time.

Collector maps dots to underscores and deliberately disables automatic name
suffixes; durations still arrive in seconds. The dashboard's native Grafana unit
formatter displays small values in milliseconds. Cumulative exports are handled
by the standard Collector/Prometheus pipeline rather than summed repeatedly.

Prometheus retains up to 24 hours / 256 MB. Collector expires inactive metric
streams after 5 minutes. Tempo uses local volume storage with its default
retention; monitor disk usage during long runs. Named volumes survive `down`.
The Swift batch processor has a 512-span queue. The upstream 2.5.1 exporters can
retain failed requests; this prototype does not promise bounded offline buffering
or durable/exactly-once delivery. Stop the connection when the receiver is offline
for an extended period.

## Verify and stop

The smoke-test dependencies require Python 3.10 or newer.

```sh
python3 -m venv /tmp/screenkit-monitor-venv
/tmp/screenkit-monitor-venv/bin/pip install -r Monitoring/requirements-smoke.txt
python3 Monitoring/verify.py --ready
/tmp/screenkit-monitor-venv/bin/python Monitoring/smoke.py
python3 Monitoring/verify.py --fixture /tmp/screenkit-monitor-fixture.json
```

The Linux smoke fixture uses the **official Python SDK/exporter**, with a unique
instance ID and `synthetic` source. Verification asserts cumulative count/sum,
unsuccessful-update exclusion, work counts, trace parentage, TraceQL search,
provisioning and every dashboard PromQL expression. CI also runs Playwright
against the real Grafana page and native waterfall, storing screenshots and logs.
Separate Swift and UIKit tests cover the app-owned bootstrap and visible cell
updates through the official Swift exporters. These are distinct evidence paths;
the CI fixture is not an iPhone benchmark.

```sh
docker compose -f Monitoring/compose.yml logs -f
docker compose -f Monitoring/compose.yml down
```

`down` keeps measurements in the named volumes. To discard **this workbench's**
stored measurements deliberately, add `--volumes`. Avoid global Docker prune
commands when other projects use the same Docker instance.

## Upstream references

- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Explore access roles](https://grafana.com/docs/grafana/latest/visualizations/explore/get-started-with-explore/)
- [Tempo Docker Compose example](https://github.com/grafana/tempo/tree/v3.1.0/example/docker-compose/single-binary)
- [Collector Prometheus exporter settings](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/v0.161.0/exporter/prometheusexporter)
- [Swift OTLP exporters 2.5.1](https://github.com/open-telemetry/opentelemetry-swift/tree/2.5.1)

Grafana and Tempo use AGPL-3.0; Collector and Prometheus use Apache-2.0. This
configuration runs upstream images separately and does not embed their code in
the Swift libraries.
