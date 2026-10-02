# ScreenKitTelemetryMonitor

An optional app-owned SDK bootstrap for the [Grafana monitoring workbench](../../Monitoring).
It connects the `ScreenKitOpenTelemetry` adapter to the **official Swift OTLP/HTTP
exporters**. API-only instrumentation, SDK/export, and the monitoring backend stay
in separate modules. It uses the adapter's unreleased ScreenKit revision.

```swift
import ScreenKitTelemetryMonitor

let monitor = ScreenTelemetryMonitor(
    endpoint: URL(string: "http://127.0.0.1:4318")!,
    serviceName: "ScreenKitLab"
)
let controller = screen.telemetry(monitor.adapter, name: "catalog").makeViewController()
```

Run this on `@MainActor` and retain the monitor for the screen's lifetime. Call
`await monitor.shutdown()` after finishing, outside the measured update path.
Shutdown collects metrics once more before stopping the periodic reader; neither
shutdown nor flush confirms server receipt. Verify ingestion separately.
`httpClient:` supports a custom app-owned URLSession through the official
`BaseHTTPClient`. No global OTel provider or active context is installed.

```sh
swift test -j 2
swift run ScreenKitTelemetryProducer http://127.0.0.1:4318 60
```

The producer labels its invented timings `synthetic`. The monitor's default
`source` is `app`; tests use `ui-test`. The [workbench README](../../Monitoring)
describes timing/retention/sampling boundaries, SDK failure limitations, UIKit
consumer verification and standard backend evidence.
