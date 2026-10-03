import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import ScreenKit
import ScreenKitOpenTelemetry
import XCTest

extension MetricData {
    var histogramPoints: [HistogramPointData] { data.points.compactMap { $0 as? HistogramPointData } }
}

final class SpanCollector: SpanExporter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SpanData] = []
    var spans: [SpanData] { lock.withLock { storage } }
    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        lock.withLock { storage.append(contentsOf: spans) }
        return .success
    }
    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode { .success }
    func shutdown(explicitTimeout: TimeInterval?) {}
}

// This test reader has no timer; its mutable registration is protected by a lock.
final class ManualMetricReader: MetricReader, @unchecked Sendable {
    private let lock = NSLock()
    private var producer: (any MetricProducer)?
    func register(registration: any CollectionRegistration) { lock.withLock { producer = registration as? any MetricProducer } }
    func collect() -> [MetricData] { lock.withLock { producer?.collectAllMetrics() ?? [] } }
    func forceFlush() -> ExportResult { .success }
    func shutdown() -> ExportResult { .success }
    func getAggregationTemporality(for instrument: InstrumentType) -> AggregationTemporality { .cumulative }
    func getDefaultAggregation(for instrument: InstrumentType) -> Aggregation { Aggregations.defaultAggregation() }
}

@MainActor
final class TelemetryFixture {
    let collector = SpanCollector()
    let reader = ManualMetricReader()
    let tracerProvider: TracerProviderSdk
    let meterProvider: MeterProviderSdk
    let adapter: ScreenOpenTelemetry

    init(sampled: Bool = true, links: @escaping (ScreenTelemetryInterval) -> [SpanContext] = { _ in [] }) {
        tracerProvider = TracerProviderBuilder()
            .with(sampler: sampled ? Samplers.alwaysOn : Samplers.alwaysOff)
            .add(spanProcessor: SimpleSpanProcessor(spanExporter: collector))
            .build()
        meterProvider = MeterProviderSdk.builder().registerMetricReader(reader: reader)
            .registerView(selector: InstrumentSelectorBuilder().build(), view: View.builder().build()).build()
        let meter = meterProvider.get(name: ScreenOpenTelemetry.instrumentationName)
        let buckets = [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.02, 0.05, 0.1, 0.5, 1]
        let metrics = ScreenOpenTelemetryMetrics(
            updateDuration: meter.histogramBuilder(name: "screenkit.update.settled.duration")
                .setUnit("s").setExplicitBucketBoundariesAdvice(buckets).build(),
            phaseDuration: meter.histogramBuilder(name: "screenkit.update.phase.duration")
                .setUnit("s").setExplicitBucketBoundariesAdvice(buckets).build(),
            updates: meter.counterBuilder(name: "screenkit.update.count").setUnit("{update}").build(),
            work: meter.counterBuilder(name: "screenkit.work.count").setUnit("{operation}").build()
        )
        adapter = ScreenOpenTelemetry(
            tracer: tracerProvider.get(instrumentationName: ScreenOpenTelemetry.instrumentationName),
            metrics: metrics, linksForUpdate: links
        )
    }
}

final class ScreenOpenTelemetryTests: XCTestCase {
    @MainActor
    func testSpanTreeUsesSourceClocksAndMetricsHaveUnitsWithoutCorrelationLabels() async throws {
        let fixture = TelemetryFixture()
        let update = interval(.update)
        let prepare = interval(.snapshotPrepare, updateID: update.updateID, screenID: update.screenID)
        fixture.adapter.record(.began(update))
        fixture.adapter.record(.began(prepare))
        fixture.adapter.record(.ended(prepare, at: end(prepare, seconds: 0.01), outcome: .completed, counts: nil))
        var counts = ScreenTelemetryCounts()
        counts.rendererFactoryCalls = 1000
        counts.reconfiguredItems = 1000
        fixture.adapter.record(.ended(update, at: end(update, seconds: 0.05), outcome: .completed, counts: counts))
        fixture.tracerProvider.forceFlush()

        let spans = fixture.collector.spans
        XCTAssertEqual(spans.count, 2)
        let root = try XCTUnwrap(spans.first { $0.name == "screenkit.update" })
        let child = try XCTUnwrap(spans.first { $0.name == "screenkit.snapshot.prepare" })
        XCTAssertNil(root.parentSpanId)
        XCTAssertEqual(child.parentSpanId, root.spanId)
        XCTAssertEqual(child.traceId, root.traceId)
        XCTAssertEqual(root.startTime, update.start.date)
        XCTAssertEqual(root.endTime.timeIntervalSince(root.startTime), 0.05, accuracy: 0.000001)
        XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
        XCTAssertEqual(fixture.adapter.invalidEventCount, 0)

        let metrics = fixture.reader.collect()
        let duration = try XCTUnwrap(metrics.first { $0.name == "screenkit.update.settled.duration" })
        XCTAssertEqual(duration.unit, "s")
        let point = try XCTUnwrap(duration.histogramPoints.first)
        XCTAssertEqual(point.count, 1)
        XCTAssertEqual(point.sum, 0.05, accuracy: 0.000001)
        for metric in metrics {
            for point in metric.data.points {
                XCTAssertNil(point.attributes["screenkit.update.id"])
                XCTAssertNil(point.attributes["screenkit.screen.instance.id"])
            }
        }
        let work = try XCTUnwrap(metrics.first { $0.name == "screenkit.work.count" })
        XCTAssertEqual(work.data.points.compactMap { ($0 as? LongPointData)?.value }.reduce(0, +), 2000)
    }

    @MainActor
    func testMetricsStillRecordWhenTraceSamplingIsDisabled() async throws {
        let fixture = TelemetryFixture(sampled: false)
        let update = interval(.update)
        fixture.adapter.record(.began(update))
        fixture.adapter.record(.ended(update, at: end(update, seconds: 0.02), outcome: .completed, counts: .init()))
        fixture.tracerProvider.forceFlush()
        XCTAssertTrue(fixture.collector.spans.isEmpty)
        let duration = try XCTUnwrap(fixture.reader.collect().first { $0.name == "screenkit.update.settled.duration" })
        XCTAssertEqual(duration.histogramPoints.first?.count, 1)
        XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
    }

    @MainActor
    func testCancellationIsCountedWithoutACompletedDurationAndConcurrentRootsStayIndependent() async throws {
        let fixture = TelemetryFixture()
        let first = interval(.update)
        let second = interval(.update)
        fixture.adapter.record(.began(first))
        fixture.adapter.record(.began(second))
        let phase = interval(.snapshotPrepare, updateID: first.updateID, screenID: first.screenID)
        fixture.adapter.record(.began(phase))
        fixture.adapter.record(.ended(phase, at: end(phase, seconds: 0.01), outcome: .completed, counts: nil))
        fixture.adapter.record(.ended(first, at: end(first, seconds: 0.03), outcome: .cancelled, counts: .init()))
        fixture.adapter.record(.ended(second, at: end(second, seconds: 0.04), outcome: .completed, counts: .init()))
        fixture.tracerProvider.forceFlush()
        let roots = fixture.collector.spans.filter { $0.name == "screenkit.update" }
        XCTAssertEqual(Set(roots.map(\.traceId)).count, 2)
        XCTAssertTrue(roots.allSatisfy { $0.parentSpanId == nil })
        let metrics = fixture.reader.collect()
        let duration = try XCTUnwrap(metrics.first { $0.name == "screenkit.update.settled.duration" })
        XCTAssertEqual(duration.histogramPoints.reduce(0) { $0 + $1.count }, 1)
        let updates = try XCTUnwrap(metrics.first { $0.name == "screenkit.update.count" })
        XCTAssertEqual(updates.data.points.compactMap { ($0 as? LongPointData)?.value }.reduce(0, +), 2)
        XCTAssertFalse(metrics.contains { $0.name == "screenkit.update.phase.duration" })
        XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
    }

    @MainActor
    func testExplicitCausalLinksDoNotBecomeAmbientParents() async throws {
        let causeFixture = TelemetryFixture()
        let cause = causeFixture.tracerProvider.get(instrumentationName: "test").spanBuilder(spanName: "interaction").startSpan()
        defer { cause.end() }
        let fixture = TelemetryFixture(links: { _ in [cause.context] })
        let update = interval(.update)
        fixture.adapter.record(.began(update))
        fixture.adapter.link([cause.context], to: update.updateID)
        fixture.adapter.record(.ended(update, at: end(update, seconds: 0.01), outcome: .completed, counts: .init()))
        fixture.tracerProvider.forceFlush()
        let span = try XCTUnwrap(fixture.collector.spans.first)
        XCTAssertNil(span.parentSpanId)
        XCTAssertEqual(span.links.count, 2)
        XCTAssertTrue(span.links.allSatisfy { $0.context == cause.context })
    }

    @MainActor
    func testReversedClockIsDiagnosedWithoutRecordingZeroDuration() async throws {
        let fixture = TelemetryFixture()
        let update = interval(.update)
        fixture.adapter.record(.began(update))
        let reversed = ScreenTelemetryTimestamp(date: update.start.date, uptimeNanoseconds: 0)
        fixture.adapter.record(.ended(update, at: reversed, outcome: .completed, counts: .init()))
        XCTAssertEqual(fixture.adapter.invalidEventCount, 1)
        XCTAssertEqual(fixture.adapter.activeSpanCount, 0)
        XCTAssertFalse(fixture.reader.collect().contains { $0.name == "screenkit.update.settled.duration" })
    }

    private func interval(_ phase: ScreenTelemetryPhase, updateID: UUID = UUID(), screenID: UUID = UUID()) -> ScreenTelemetryInterval {
        ScreenTelemetryInterval(
            updateID: updateID, screenID: screenID, screenName: "catalog", kind: .state,
            phase: phase, animated: false,
            start: ScreenTelemetryTimestamp(date: Date(timeIntervalSince1970: 100), uptimeNanoseconds: 1_000_000_000)
        )
    }
    private func end(_ interval: ScreenTelemetryInterval, seconds: Double) -> ScreenTelemetryTimestamp {
        // Deliberately move wall time backwards. Monotonic duration must survive.
        ScreenTelemetryTimestamp(date: Date(timeIntervalSince1970: 1), uptimeNanoseconds: interval.start.uptimeNanoseconds + UInt64(seconds * 1_000_000_000))
    }
}
