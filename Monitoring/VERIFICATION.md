# Workbench verification

Local checks on 2026-10-02 used Xcode 27.1, an iOS 18.6 iPhone 16 Pro simulator,
and Docker Desktop on Apple Silicon with the images pinned in `compose.yml`.

| Evidence | Result | Boundary |
| --- | --- | --- |
| `swift test -j 2` | 2 tests passed | Official Swift HTTP exporters, protobuf bodies, signal paths, sampling-independent metrics; injected HTTP client |
| Release `ScreenKitTelemetryMonitor-Package` tests on iOS 18.6 | 3 tests passed, no failures/skips/runtime warnings | A visible UIKit cell changes from Before to After; source events reach the official exporters using an injected HTTP client |
| Official Python SDK → Collector → Prometheus/Tempo | 20 roots; 19 completed; duration sum 0.399 s; 19,000 renderer operations | Synthetic data, not measured UI performance; cumulative re-exports do not multiply counts |
| Tempo API and TraceQL | One update parent and four phase children; search succeeds | Backend ingestion and parentage, independently of the Swift client test |
| Provisioned dashboard queries | All 10 PromQL expressions execute | Native backend query compatibility |
| Playwright against Grafana | Desktop dashboard, native trace waterfall, mobile chart and trace table | Actual browser interaction, with screenshots and browser-error log |
| Swift producer → real workbench | `screenkit-synthetic` updates and phases appear in Grafana/Tempo | Official Swift SDK network path; producer timings are invented |

The iOS result bundle is `/tmp/ScreenKit-Monitor-iOS18-final.xcresult`.
Local backend evidence is `/tmp/screenkit-monitor-verification.json` and browser
artifacts are under `/tmp/screenkit-monitor-browser/`. Temporary artifacts may be
removed; CI uploads fresh evidence for each run for 14 days.

Reproduce the backend/browser checks with the commands in [README](README.md).
For the iOS test, use `xcodebuild -scheme ScreenKitTelemetryMonitor-Package
-configuration Release ... test` from the optional package directory; select a
simulator installed on the host. The workflow uses Xcode 27 and iOS 27.0;
that CI runtime result is separate from the local iOS 18.6 proof above.

No physical-device benchmark, display/frame/GPU measurement, public deployment,
or bounded offline delivery is claimed by these checks.
