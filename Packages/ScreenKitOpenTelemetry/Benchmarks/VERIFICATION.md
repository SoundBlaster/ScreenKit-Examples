# Telemetry prototype verification — 2026-10-02

The [raw Release simulator report](2026-10-02-ios18-release.json) contains all
20 samples per mode, event/span counts, dropped/invalid-event counts, and the
scenario configuration. [Companion inputs](2026-10-02-ios18-release-inputs.json)
record the ScreenKit revision, harness checksum, package pins, Xcode/SDK, device,
exporter, and host-load limitation.

## Executed checks

- OTel contract: five host tests passed, including explicit parents/links,
  source clocks, units, cancellation, and metrics with trace sampling disabled.
- Public consumer: seven tests passed on iOS 18.6 in Release, including a real
  visible cell update through ScreenKit, shared raw/signpost/OTel events, and the
  four-mode overhead report. There were no failures, skips, dropped events, or
  invalid events.
- ScreenKit's source contract and DocC are checked in its companion PR:
  [ScreenKit #14](https://github.com/SoundBlaster/ScreenKit/pull/14).

The local result bundle is `ScreenKit-OTel-iOS18-final-20261002.xcresult`.
CI saves its own xcresult and companion measurement inputs on every run.

## Interpret the timings

The report changes one visible row in a 1,000-item list without animation.
Each mode has three warmups and 20 measured updates. Timing starts immediately
before `setItems` and stops in its completion callback after final layout,
before XCTest fulfillment or async resumption.

This run used a shared development host, with core verification compiling
concurrently. Modes ran in a fixed order: disabled, signposts, OTel, combined.
The disabled median was about 7.42 ms; the later medians ranged from 5.80 to
6.54 ms. Those differences demonstrate host/order noise, not a speedup from
instrumentation or a proof of zero overhead. Do not use the ratios as regression
budgets. The sampler was always-on; export was in-memory, with explicit flushing
outside the measured interval. Real batch/OTLP export overhead is unmeasured.

## Next measurement gate

Repeat on a physical device in Release, alternate/randomize mode order across
multiple rounds, keep the host idle, and include the application-owned batch
processor and exporter. Establish uncertainty and budgets before comparing
equivalent UIKit, ScreenKit, Patchwork, and SwiftUI scenarios. Display frames,
hitches, CPU attribution, offline buffering, and a live Collector are outside
this prototype's verified scope.
