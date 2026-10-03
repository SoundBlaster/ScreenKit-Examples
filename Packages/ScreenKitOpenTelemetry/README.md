# ScreenKitOpenTelemetry prototype

An optional Swift package that translates ScreenKit's typed update intervals
into OpenTelemetry spans and metrics. Its library depends on `OpenTelemetryApi`
only. Providers, readers, sampling, resource metadata, and exporters belong to
the consuming app. Neither example app changes its published package pins.

This is a prototype pinned to ScreenKit's `8811665` telemetry PR commit, not a released
package. After the ScreenKit API is released, replace the revision dependency
with a compatible tag before extracting this package into its own repository.

## Configure instruments in the app

The application imports `OpenTelemetrySdk` and supplies configured providers:

```swift
import OpenTelemetryApi
import OpenTelemetrySdk
import ScreenKit
import ScreenKitOpenTelemetry

// Existing application-owned providers. The meter provider must have a reader
// and a matching View registered (required by OTel Swift core 2.5.1).
let meter = meterProvider.get(name: ScreenOpenTelemetry.instrumentationName)
let metrics = ScreenOpenTelemetryMetrics(
    updateDuration: meter.histogramBuilder(name: "screenkit.update.settled.duration")
        .setUnit("s").build(),
    phaseDuration: meter.histogramBuilder(name: "screenkit.update.phase.duration")
        .setUnit("s").build(),
    updates: meter.counterBuilder(name: "screenkit.update.count")
        .setUnit("{update}").build(),
    work: meter.counterBuilder(name: "screenkit.work.count")
        .setUnit("{operation}").build()
)
let adapter = ScreenOpenTelemetry(
    tracer: tracerProvider.get(instrumentationName: ScreenOpenTelemetry.instrumentationName),
    metrics: metrics
)
let recorder = ScreenTelemetryRecorder()
let sink = ScreenTelemetryMultiplexer([ScreenSignpostTelemetry(), recorder, adapter])
let measured = screen.telemetry(sink, name: "catalog")
```

The snippet continues existing `tracerProvider`, `meterProvider`, and `screen`
values; it is not a standalone provider bootstrap. The checked-in
`TelemetryFixture` in the tests creates complete SDK providers, instruments,
an in-memory span exporter, and an explicitly collected metric reader.

In OTel Swift core 2.5.1, configure the meter provider like this, supplying your
application-owned `reader`:

```swift
let meterProvider = MeterProviderSdk.builder()
    .registerMetricReader(reader: reader)
    .registerView(
        selector: InstrumentSelectorBuilder().build(),
        view: View.builder().build()
    )
    .build()
```

Use batch span processing and a periodic reader for network export. Never
flush an exporter inside a telemetry callback. The prototype does not install
a global SDK, modify active span context, or configure an OTLP endpoint.

## Timing, identity, sampling, and outcomes

The root `screenkit.update` span measures controller update-settled time:
snapshot application and final layout, before client completion. It does not
measure display presentation, GPU completion, scrolling hitches, or arbitrary
SwiftUI body work. Phase spans use an explicit update parent; roots explicitly
ignore ambient global context. Supply known causal contexts with
`linksForUpdate`, or add later coalesced causes using `link(_:to:)`.

All metrics use source monotonic durations. Trace start uses source wall time;
trace end is anchored to wall start plus monotonic elapsed time to handle clock
corrections. Durations and work are recorded only for completed whole updates.
Cancelled/rejected/unavailable-state updates remain visible as spans and outcome
counters. Metrics are independent of trace sampling. Instance/update UUIDs are
span attributes only; stable model IDs, row contents, and titles are never labels.
`app.screen.name` follows a Development semantic convention; custom keys use
the `screenkit` namespace and schema version `1`.

## Run the prototype

From this directory:

```sh
swift test -j 2
xcodebuild -scheme ScreenKitOpenTelemetry \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
    -skipMacroValidation -parallel-testing-enabled NO \
    -resultBundlePath /tmp/ScreenKitOpenTelemetry.xcresult test
```

For an unpublished local ScreenKit checkout, prefix commands with:

```sh
SCREENKIT_TELEMETRY_PATH=/absolute/path/to/ScreenKit swift test -j 2
```

The same environment variable works with `xcodebuild`. The iOS consumer tests
exercise a real visible cell and both telemetry recipients. The instrumentation
overhead smoke test changes one row in a 1,000-item list, after three warmups,
with 20 repetitions in each mode: disabled, signposts, OTel, combined. Its JSON
attachment contains every sample, median, relative timing, build mode, OS,
animations, and exporter configuration. Export attachments with:

```sh
xcrun xcresulttool export attachments \
    --path /tmp/ScreenKitOpenTelemetry.xcresult --output-path /tmp/ScreenKitTelemetryAttachments
```

Release simulator timings still include simulator noise and fixed-order bias;
they are not device budgets. Use a physical-device Release run and alternating
mode order before setting a regression threshold. Measure the actual batch/OTLP
exporter separately; the smoke test uses an in-memory exporter, with flushing
outside the measured interval.

Raw reports must also record commit, package pins, device/toolchain, run
configuration, and any dropped events. A complete benchmark must reject
noncompleted updates, missing telemetry, or recorder overflow. The prototype
does not claim live Collector export, offline buffering, or actual display-frame
measurement.

The CI artifact includes the xcresult attachment and companion commit, toolchain,
SDK, and resolved-package inputs. See [the recorded smoke run](Benchmarks/VERIFICATION.md)
for a local iOS 18 Release example and the limits of its timing evidence.

## Sources

- [ScreenKit telemetry contract](https://github.com/SoundBlaster/ScreenKit/blob/codex/ui-telemetry/TELEMETRY.md)
- [OTel Swift instrumentation](https://opentelemetry.io/docs/languages/swift/instrumentation/)
- [OTel Swift core 2.5.1](https://github.com/open-telemetry/opentelemetry-swift-core/tree/2.5.1)
