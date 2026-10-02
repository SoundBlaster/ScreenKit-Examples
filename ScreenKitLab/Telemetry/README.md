# Telemetry Lab

Open `ScreenKitLabTelemetry.xcodeproj`, select its shared scheme and an iOS 18+
simulator, and run. The scheme uses **Release without the debugger**. Start the
[Grafana workbench](../../Monitoring) first:

```sh
docker compose -f Monitoring/compose.yml up -d
open ScreenKitLabTelemetry.xcodeproj
```

The optional project compiles the same `ScreenKitLab/Sources` as the normal Lab.
It adds the app-owned SDK bootstrap and the comparison runner, selected with
`SCREENKIT_TELEMETRY`. Its separate bundle ID is
`com.soundblaster.screenkit.lab.telemetry`. The normal native project retains
ScreenKit **0.3.0** and Patchwork **0.1.3**, without an OTel SDK dependency.
This project pins ScreenKit's telemetry implementation to revision
`8811665c7d860efc2a11c8709a21fe39232b4e07`, Patchwork to **0.1.3**, and the official
OTel Swift SDK/exporters to **2.5.1**. The root ScreenKit revision takes precedence
over Patchwork's transitive ScreenKit requirement. No Tuist or project generation
step is needed.

## Interact with the real screen

The default screen is the existing Lab `MixedContentProbe`: legacy collection
cells, `UIContentConfiguration`, SwiftUI islands and existing UIViews. Update,
layout, reverse, remove and restore still use the original implementations.
The telemetry configuration requests explicit content/layout refresh on every
OS, so even native UIKit Observation changes pass through a measured ScreenKit
update and resized legacy views receive the same layout boundary.
`OTLP on/off` rebuilds the screen with a fresh SDK instance or no sink/providers.
Switching resets the Lab demo state. The scene owns the SDK, and switching closes
its workers outside any measured update.

Set the scheme environment variable `SCREENKIT_OTLP_ENDPOINT` to the Collector
base URL (default `http://127.0.0.1:4318`). It must not contain credentials, a query
or a fragment. Only local networking is exempted from ATS. For a physical device,
follow the workbench's explicit LAN setup and use the Mac's address, not loopback.

Open [Grafana](http://127.0.0.1:3000/d/screenkit-ui), choose service `screenkit-lab`
and source `app`. Native update spans and phase histograms come from ScreenKit;
the app does not fabricate interval events. Cumulative metrics expire from the
Collector after five minutes without export; historical samples/traces remain
subject to the workbench retention settings.

## Reproduce the comparison

Choose **Actions → Compare** or use the repeatable simulator command from the repository root:

```sh
xcrun simctl list devices available
python3 Monitoring/run_lab.py --device SIMULATOR_UUID --output /tmp/lab-run-1
python3 Monitoring/verify_lab.py --report /tmp/lab-run-1/report.json \
  --backend --output /tmp/lab-run-1/verification.json
```

Use a new output directory each time. The runner builds the selected revision,
records toolchain/source hashes and simulator metadata, installs and launches the
app, then copies its atomic JSON report. It targets only the exact simulator
UUID supplied. Run verification promptly (within five minutes) while the
Collector's cumulative series are still active. No Python dependencies are
needed for these two commands. An existing package cache can be supplied with
`--packages PATH`; `--derived-data PATH` chooses the build directory.

Both modes use one binary, the original four Patchwork renderers, 1,000 rows,
three unmeasured warmups and 20 measured updates per block. Four pairs alternate
`disabled → otlp` and `otlp → disabled`. Each update replaces the payloads while
preserving IDs and rotates the list by four items. The visible legacy cell must
show the expected new ID and content after every update. There is no animation.

An external monotonic clock starts immediately before `setItems` and stops in
its completion, before resuming the awaiting task. Model preparation, 50 ms
pacing, checks, reporting, SDK startup/flush/shutdown are outside that interval
in **both** modes. The disabled mode creates no sink or SDK providers. OTLP uses
100% trace sampling, batch export and a **250 ms export interval** so export
overlaps each block; this is more aggressive than the monitor's 2-second default.

The JSON includes every sample, pair/order, thermal state, app foreground state,
configuration, runtime, pins and exporter instance. **Share report** exports the
same file. The verifier requires eight complete blocks, valid visible content,
zero invalid events/active spans and Release. With `--backend`, it additionally
requires all 96 root updates, their six child phases each, histogram counts and
96,000 renderer factory calls in Prometheus/Tempo. It reports each pair's medians
and ratio, keeping the variability visible. No samples are discarded.

## What this proves

This measures the completion of explicit mixed-list updates, including diffable
snapshot application and a layout pass. It does **not** measure displayed frames,
FPS, GPU work, interactive scrolling or automatic state-update scheduling. Those
need separate scenarios and Instruments traces. Simulator numbers are integration
smoke evidence; do not use them as a device performance budget or claim a speedup
from noisy ratios below one. SDK shutdown alone is not a delivery receipt.

CI builds the telemetry app in Release and exercises the original screen and
endpoint validation on iOS 27. The local backend comparison is a separate gate;
the CI UI job does not require Docker or claim network-delivery evidence.
