import Foundation
import ScreenKit
import ScreenKitTelemetryMonitor
import UIKit

/// An app workload, measured by one external clock in both modes. It deliberately
/// uses explicit updates: their completion is a public, identical timing boundary.
@MainActor
enum LabBenchmark {
    enum Mode: String, Codable { case disabled, otlp }

    struct Sample: Codable {
        let iteration: Int
        let seconds: Double
        let thermalState: Int
        let appActive: Bool
    }

    struct Block: Codable {
        let pair: Int
        let position: Int
        let mode: Mode
        let instanceID: String?
        let expectedUpdates: Int
        let samples: [Sample]
        let invalidEvents: Int
        let activeSpans: Int
        let contentVerified: Bool

        var median: Double { LabBenchmark.median(samples.map(\.seconds)) }
    }

    struct Report: Encodable {
        let schema: Int = 1
        let runID: String
        let startedAt: Date
        let finishedAt: Date
        let operatingSystem: String
        let device: String
        let simulator: Bool
        let configuration: String
        let viewportWidth: Double
        let viewportHeight: Double
        let displayScale: Double
        let contentSizeCategory: String
        let lowPowerMode: Bool
        let endpoint: String
        let itemCount: Int
        let warmups: Int
        let samplesPerBlock: Int
        let pacingSeconds: Double
        let exportIntervalSeconds: Double
        let screenKitRevision: String
        let patchworkVersion: String
        let blocks: [Block]
        let errors: [String]

        var disabledMedian: Double { median(for: .disabled) }
        var otlpMedian: Double { median(for: .otlp) }

        private func median(for mode: Mode) -> Double {
            LabBenchmark.median(blocks.filter { $0.mode == mode }.flatMap { $0.samples.map(\.seconds) })
        }

        func data() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        }
    }

    static let items = 1_000
    static let warmups = 3
    static let samples = 20
    static let pairs = 4
    static let pacing = 0.05
    // Shorter than the monitor default, so real export overlaps each sample block.
    static let exportInterval = 0.25

    static func run(in navigation: UINavigationController, endpoint: URL) async -> Report {
        let start = Date()
        let runID = UUID().uuidString
        var blocks: [Block] = []
        var errors: [String] = []
        navigation.view.isUserInteractionEnabled = false
        defer { navigation.view.isUserInteractionEnabled = true }

        for pair in 0..<pairs {
            // Balance both orders within one run. Keep every sample and block.
            let order: [Mode] = pair.isMultiple(of: 2) ? [.disabled, .otlp] : [.otlp, .disabled]
            for (position, mode) in order.enumerated() {
                let block = await runBlock(
                    in: navigation, endpoint: endpoint, mode: mode,
                    pair: pair, position: position, runID: runID
                )
                blocks.append(block)
                if !block.contentVerified || block.invalidEvents != 0 || block.activeSpans != 0 {
                    errors.append("Invalid block \(pair)/\(position): content or telemetry lifecycle check failed")
                }
                if block.samples.contains(where: { !$0.appActive }) {
                    errors.append("Invalid block \(pair)/\(position): app was not active throughout sampling")
                }
            }
        }
#if targetEnvironment(simulator)
        let simulator = true
        let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? UIDevice.current.model
#else
        let simulator = false
        var info = utsname()
        uname(&info)
        let machineSize = MemoryLayout.size(ofValue: info.machine)
        let device = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: machineSize) { String(cString: $0) }
        }
#endif
#if DEBUG
        let configuration = "Debug"
#else
        let configuration = "Release"
#endif
        return Report(
            runID: runID, startedAt: start, finishedAt: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            device: device, simulator: simulator, configuration: configuration,
            viewportWidth: Double(navigation.view.bounds.width), viewportHeight: Double(navigation.view.bounds.height),
            displayScale: Double(navigation.traitCollection.displayScale),
            contentSizeCategory: navigation.traitCollection.preferredContentSizeCategory.rawValue,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            endpoint: endpoint.absoluteString, itemCount: items, warmups: warmups,
            samplesPerBlock: samples, pacingSeconds: pacing, exportIntervalSeconds: exportInterval,
            screenKitRevision: "8811665c7d860efc2a11c8709a21fe39232b4e07", patchworkVersion: "0.1.3",
            blocks: blocks, errors: errors
        )
    }

    private static func runBlock(
        in navigation: UINavigationController, endpoint: URL, mode: Mode,
        pair: Int, position: Int, runID: String
    ) async -> Block {
        // Disabled creates neither SDK providers nor a sink. The binary is the same.
        let monitor = mode == .otlp ? ScreenTelemetryMonitor(
            endpoint: endpoint, serviceName: "screenkit-lab-benchmark", source: "app",
            instanceID: "\(runID)-\(pair)-\(position)", interval: exportInterval
        ) : nil
        var screen = Screen(rows(iteration: 0), renderer: MixedContentProbe.makeRenderers())
            .title { "\(pair + 1)/\(pairs) · \(mode.rawValue.uppercased())" }
            .layout { .list(using: .init(appearance: .insetGrouped), layoutEnvironment: $0) }
        if let monitor { screen = screen.telemetry(monitor.adapter, name: "Lab.MixedBenchmark") }
        let controller = screen.makeViewController()
        navigation.isToolbarHidden = true
        navigation.setViewControllers([controller], animated: false)
        navigation.view.layoutIfNeeded()
        var measured: [Sample] = []
        var contentVerified = true
        for iteration in 1...(warmups + samples) {
            let next = rows(iteration: iteration)
            // Preparation and pacing are outside the measured interval in BOTH modes.
            let thermalState = ProcessInfo.processInfo.thermalState.rawValue
            let seconds: Double = await withCheckedContinuation { continuation in
                let start = DispatchTime.now().uptimeNanoseconds
                controller.setItems(next, animated: false) {
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
                    continuation.resume(returning: elapsed)
                }
            }
            // A real, visible legacy cell must show the new payload and reordered ID.
            let cell = controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? ProbeLegacyCell
            contentVerified = contentVerified && cell?.label.text == "UIKit cell\n" + next[0].detail
            if iteration > warmups {
                measured.append(Sample(
                    iteration: iteration - warmups, seconds: seconds, thermalState: thermalState,
                    appActive: UIApplication.shared.applicationState == .active
                ))
            }
            try? await Task.sleep(for: .seconds(pacing))
        }
        // Stop timers/export workers before the next baseline block. Flush/shutdown
        // are outside measurements; backend verification is a separate required gate.
        navigation.setViewControllers([], animated: false)
        let invalidEvents = monitor?.adapter.invalidEventCount ?? 0
        let activeSpans = monitor?.adapter.activeSpanCount ?? 0
        await monitor?.shutdown()
        return Block(
            pair: pair, position: position, mode: mode, instanceID: monitor?.serviceInstanceID,
            expectedUpdates: monitor == nil ? 0 : 1 + warmups + samples, samples: measured,
            invalidEvents: invalidEvents, activeSpans: activeSpans, contentVerified: contentVerified
        )
    }

    private static func rows(iteration: Int) -> [ProbeRow] {
        let rows = (0..<items).map { id in
            let row = ProbeRow(id: id)
            row.revision = iteration
            return row
        }
        // Rotate by four so all four real Patchwork renderer families remain visible.
        let offset = iteration * 4 % items
        return Array(rows[offset...] + rows[..<offset])
    }

    private nonisolated static func median(_ values: [Double]) -> Double {
        let values = values.sorted()
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}
