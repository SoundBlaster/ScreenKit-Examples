import Foundation
import ScreenKit
import ScreenKitTelemetryMonitor

/// Synthetic input for exploring the dashboard. Never presented as UI timings.
@main
struct Producer {
    enum ArgumentError: Error { case invalidRepetitionCount }
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        let address = arguments.count > 1 ? arguments[1] : "http://127.0.0.1:4318"
        guard let endpoint = URL(string: address), ["http", "https"].contains(endpoint.scheme), endpoint.host != nil else {
            throw URLError(.badURL)
        }
        let repetitions = arguments.count > 2 ? Int(arguments[2]) ?? 60 : 60
        guard (1...3600).contains(repetitions) else { throw ArgumentError.invalidRepetitionCount }
        let monitor = ScreenTelemetryMonitor(endpoint: endpoint, serviceName: "screenkit-synthetic", source: "synthetic", interval: 1)
        let screenID = UUID()
        print("Synthetic ScreenKit events → \(endpoint). These are invented durations, not UI measurements.")
        for index in 0..<repetitions {
            let start = ScreenTelemetryTimestamp.now()
            let root = ScreenTelemetryInterval(updateID: UUID(), screenID: screenID, screenName: "catalog-demo", kind: .state, phase: .update, animated: false, start: start)
            monitor.adapter.record(.began(root))
            let elapsed = Double(12 + (index * 7) % 34) / 1000
            for (phase, offset, duration) in [(ScreenTelemetryPhase.stateRead, 0.0, 0.001), (.snapshotPrepare, 0.001, elapsed*0.3), (.snapshotApply, elapsed*0.35, elapsed*0.5), (.layout, elapsed*0.85, elapsed*0.1)] {
                let interval = ScreenTelemetryInterval(updateID: root.updateID, screenID: screenID, screenName: root.screenName, kind: .state, phase: phase, animated: false, start: timestamp(start, offset))
                monitor.adapter.record(.began(interval))
                monitor.adapter.record(.ended(interval, at: timestamp(start, offset+duration), outcome: .completed, counts: nil))
            }
            var counts = ScreenTelemetryCounts()
            counts.rendererFactoryCalls = 1000; counts.cellProviderCalls = 12; counts.reconfiguredItems = 1
            monitor.adapter.record(.ended(root, at: timestamp(start, elapsed), outcome: index % 17 == 16 ? .cancelled : .completed, counts: counts))
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        await monitor.flush()
        // Allow the official asynchronous metric HTTP request to reach the receiver.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        await monitor.shutdown()
        print("Producer stopped. Inspect Grafana / Collector for delivery; SDK flush is not a receipt.")
    }

    private static func timestamp(_ start: ScreenTelemetryTimestamp, _ seconds: Double) -> ScreenTelemetryTimestamp {
        .init(date: start.date.addingTimeInterval(seconds), uptimeNanoseconds: start.uptimeNanoseconds+UInt64(seconds*1e9))
    }
}
