#if canImport(UIKit)
import Dispatch
import ScreenKit
import ScreenKitOpenTelemetry
import UIKit
import XCTest

@MainActor
final class ControllerTelemetryTests: XCTestCase {
    struct Item: Identifiable {
        let id: Int
        var title: String
    }
    private func renderer() -> ScreenCellRenderer<Item> {
        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> { cell, _, item in
            var content = cell.defaultContentConfiguration()
            content.text = item.title
            cell.contentConfiguration = content
        }
        return ScreenCellRenderer { collection, path, item in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: item)
        }
    }

    func testRealControllerFansOutOneUpdateToSignpostsRawEventsAndOTel() async throws {
        let fixture = TelemetryFixture()
        let recorder = ScreenTelemetryRecorder()
        let sink = ScreenTelemetryMultiplexer([ScreenSignpostTelemetry(), recorder, fixture.adapter])
        let renderer = renderer()
        let controller = Screen([Item(id: 1, title: "Before")]) { _ in renderer }
            .telemetry(sink, name: "catalog").makeViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        _ = try await update(controller, items: [Item(id: 1, title: "After")])
        fixture.tracerProvider.forceFlush()
        let cell = try XCTUnwrap(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
        XCTAssertEqual((cell.contentConfiguration as? UIListContentConfiguration)?.text, "After")
        XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
        XCTAssertEqual(fixture.adapter.invalidEventCount, 0)
        XCTAssertEqual(recorder.droppedEventCount, 0)
        let updateEvents = recorder.events.compactMap { event -> ScreenTelemetryInterval? in
            guard case let .ended(interval, _, .completed, _) = event, interval.phase == .update else { return nil }
            return interval
        }
        XCTAssertEqual(updateEvents.count, 2) // initial + explicit update
        let spans = fixture.collector.spans.filter { $0.name == "screenkit.update" }
        XCTAssertEqual(spans.count, updateEvents.count)
        for event in updateEvents {
            XCTAssertTrue(spans.contains { $0.attributes["screenkit.update.id"] == .string(event.updateID.uuidString) })
        }
        let metrics = fixture.reader.collect()
        let duration = try XCTUnwrap(metrics.first { $0.name == "screenkit.update.settled.duration" })
        XCTAssertEqual(duration.histogramPoints.reduce(0) { $0 + $1.count }, 2)
    }

    /// A smoke comparison, not a device performance gate. Raw repetitions and
    /// environment metadata are attached so timing noise remains visible.
    func testInstrumentationOverheadReport() async throws {
        struct ModeReport: Codable {
            let name: String
            let elapsedSeconds: [Double]
            let medianSeconds: Double
            let relativeToDisabled: Double
            let events: Int
            let spans: Int
            let droppedEventCount: Int
            let invalidEventCount: Int
        }
        struct Report: Codable {
            let scenario: String
            let environment: String
            let os: String
            let build: String
            let itemCount: Int
            let repetitions: Int
            let animation: Bool
            let modes: [ModeReport]
        }
        #if DEBUG
        let build = "Debug; smoke only"
        #else
        let build = "Release; simulator smoke only"
        #endif
        var reports: [ModeReport] = []
        var baseline = 0.0
        for mode in ["disabled", "signposts", "otel", "combined"] {
            let fixture = TelemetryFixture()
            let recorder = ScreenTelemetryRecorder()
            let renderer = renderer()
            var items = (0..<1000).map { Item(id: $0, title: "Product \($0)") }
            var screen = Screen(items) { _ in renderer }
            switch mode {
            case "signposts": screen = screen.telemetry(ScreenSignpostTelemetry(), name: "catalog")
            case "otel": screen = screen.telemetry(fixture.adapter, name: "catalog")
            case "combined":
                screen = screen.telemetry(ScreenTelemetryMultiplexer([ScreenSignpostTelemetry(), recorder, fixture.adapter]), name: "catalog")
            default: break
            }
            let controller = screen.makeViewController()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            // Equal warmup and visible content for every mode.
            for revision in 0..<3 {
                items[0].title = "Warmup \(revision)"
                _ = try await update(controller, items: items)
            }
            var samples: [Double] = []
            for revision in 0..<20 {
                items[0].title = "Revision \(revision)"
                samples.append(try await update(controller, items: items))
            }
            let cell = try XCTUnwrap(controller.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)))
            XCTAssertEqual((cell.contentConfiguration as? UIListContentConfiguration)?.text, "Revision 19")
            let sorted = samples.sorted()
            let median = (sorted[9] + sorted[10]) / 2
            fixture.tracerProvider.forceFlush() // Outside the measured interval.
            if mode == "disabled" { baseline = median }
            reports.append(ModeReport(
                name: mode, elapsedSeconds: samples, medianSeconds: median, relativeToDisabled: median / baseline,
                events: recorder.events.count, spans: fixture.collector.spans.count,
                droppedEventCount: recorder.droppedEventCount, invalidEventCount: fixture.adapter.invalidEventCount
            ))
            XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
            XCTAssertEqual(fixture.adapter.invalidEventCount, 0)
            XCTAssertEqual(recorder.droppedEventCount, 0)
            window.isHidden = true
            window.rootViewController = nil
        }
        let report = Report(
            scenario: "one-visible-row-update-stable-id", environment: "iOS Simulator; no network exporter",
            os: UIDevice.current.systemVersion, build: build, itemCount: 1000, repetitions: 20, animation: false, modes: reports
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ScreenKit instrumentation overhead"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["SCREENKIT_TELEMETRY_REPORT_DIR"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("overhead.json"))
        }
    }

    private func update(_ controller: ScreenViewController<Int, Item>, items: [Item]) async throws -> Double {
        let completed = expectation(description: "Snapshot and final layout completed")
        var elapsed: Double?
        let start = DispatchTime.now().uptimeNanoseconds
        controller.setItems(items, animated: false) {
            // Capture at the controller completion boundary, before XCTest
            // fulfillment and async resumption add harness work to the sample.
            elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 10)
        return try XCTUnwrap(elapsed)
    }
}
#endif
