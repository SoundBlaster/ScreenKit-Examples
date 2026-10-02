# Real Lab verification

Verified locally on 2026-10-03 (Moscow; the reports contain UTC timestamps).
The implementation is commit `7b0f24deef766a67deaa79355e766ae8bbef9bea`.
Xcode 27.1 built one Release simulator app, reused on iOS 18.6 and iOS 27.0.
The source and executable hashes are recorded in
[provenance.json](../../Monitoring/Evidence/2026-10-03-lab/provenance.json).
The build initially used an uncommitted working tree; the recorded compiled
inputs were checked against that commit before publishing this evidence.

## Functional and delivery evidence

| Check | Result | Boundary |
| --- | --- | --- |
| Monitor package host tests | 3 passed | Official exporter serialization and final metric collection before the first periodic tick; injected HTTP client |
| Release Lab XCTest on iOS 18.6 | 2 passed; no failures, skips or runtime warnings | The original mixed screen updates visible content; invalid endpoint configuration is shown |
| iOS 27 UI interaction | Passed | Expanded legacy/UIView content, Actions menu, OTLP on/off, comparison, summary and native Share report sheet |
| Real app → Collector → Prometheus/Tempo, iOS 18.6 | Passed | 96 root updates, 576 child phases and 96,000 renderer factory calls |
| Same network gate, two iOS 27 runs | Passed for each run | Every root and its six children verified; counters and histogram counts agree |
| Grafana browser check with `source=app` | Passed; no browser errors | Desktop/mobile dashboard and native Tempo waterfall |

Each run has eight blocks, four with export enabled. Every enabled block must
deliver 24 updates: initial presentation, three warmups and 20 timed updates.
The verifier checks all four instances independently. Trace IDs and metric
receipts are retained with the raw app reports below.

The initial network check found 23 metric updates despite 24 delivered traces:
the SDK periodic reader did not collect its final data at shutdown. The monitor
now calls `forceFlush` before stopping the reader. A regression test closes it
before the first periodic tick. The recorded passing runs include this fix;
shutdown itself is still not treated as proof of backend receipt.

Local supporting artifacts:

- `/tmp/ScreenKit-LabTelemetry-iOS18-r5.xcresult`
- `/tmp/ScreenKit-Monitor-shutdown-tests.log`
- `/tmp/ScreenKit-Lab-20261003-iOS27-ui/manifest.json` and its screenshots
- `/tmp/ScreenKit-Lab-20261003-board/` (browser screenshots and empty error log)

These temporary supporting artifacts are not durable. The JSON reports and
backend verification results below are committed; CI uploads fresh XCTest and
workbench evidence with 14-day retention.

## Timing observations, not a performance budget

Each ratio is `median(OTLP samples) / median(disabled samples)` within one pair.
The summary is the median of four pair ratios; all 160 raw samples per run are
retained. Both modes use the same binary and workload. SDK lifecycle and model
preparation are outside the interval. See [README](README.md) for the full method.

| Run | Median paired ratio | Range across four pairs | Artifacts |
| --- | --- | --- | --- |
| iOS 18.6, no UI tooling | 0.982 | 0.919–1.011 | [Report](../../Monitoring/Evidence/2026-10-03-lab/ios18/report.json), [verification](../../Monitoring/Evidence/2026-10-03-lab/ios18/verification.json) |
| iOS 27.0, no UI tooling | 1.003 | 0.964–1.082 | [Report](../../Monitoring/Evidence/2026-10-03-lab/ios27-quiet/report.json), [verification](../../Monitoring/Evidence/2026-10-03-lab/ios27-quiet/verification.json) |
| iOS 27.0, UI tooling active | 1.064 | 0.983–1.251 | [Report](../../Monitoring/Evidence/2026-10-03-lab/ios27-ui/report.json), [verification](../../Monitoring/Evidence/2026-10-03-lab/ios27-ui/verification.json) |

All three reports have a 402 × 874 point viewport at 3× scale, nominal thermal
state, Low Power Mode off and foreground sampling. The UI-tooling run is kept
to make the different conditions visible. These ratios do not establish a
stable overhead, a speedup, or a performance threshold. They measure completion
of an explicit update and layout, not displayed frames, scrolling, FPS or GPU.

Reproduce with the [runner and verification commands](README.md#reproduce-the-comparison).
Archived reports can be validated offline by omitting `--backend` and writing
to a new output path. Their saved network receipts describe the original run;
the live backend gate must be run promptly after a fresh app run.

The next performance gate is repeated Release measurement on a physical iPhone,
with the same workload and Instruments evidence before adopting a budget.
