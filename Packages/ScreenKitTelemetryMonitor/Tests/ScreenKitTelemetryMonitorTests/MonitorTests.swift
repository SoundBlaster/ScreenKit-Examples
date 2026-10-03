import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenTelemetryProtocolExporterHttp
import OpenTelemetryProtocolExporterCommon
import ScreenKit
import ScreenKitOpenTelemetry
import ScreenKitTelemetryMonitor
import SwiftProtobuf
import XCTest

/// Injected HTTPClient exercises official exporters without another receiver.
final class CapturingClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []
    var requests: [URLRequest] { lock.withLock { storage } }
    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        lock.withLock { storage.append(request) }
        completion(.success(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    }
}

final class MonitorTests: XCTestCase {
    private struct MetricFixture: Decodable, Equatable {
        struct Resource: Decodable, Equatable {
            let serviceName: String
            let telemetrySource: String
            enum CodingKeys: String, CodingKey {
                case serviceName = "service.name"
                case telemetrySource = "screenkit.telemetry.source"
            }
        }
        struct Metric: Decodable, Equatable {
            let name: String
            let unit: String
            let type: String
            let value: Int64?
            let count: UInt64?
            let attributes: [String: String]
        }
        let resource: Resource
        let scope: String
        let metrics: [Metric]
    }

    @MainActor
    func testShutdownExportsUpdatesBeforeTheFirstPeriodicTick() async throws {
        let client = CapturingClient()
        let monitor = ScreenTelemetryMonitor(endpoint: URL(string: "http://127.0.0.1:4318")!, serviceName: "shutdown", interval: 3600, httpClient: client)
        let interval = ScreenTelemetryInterval(updateID: UUID(), screenID: UUID(), screenName: "catalog", kind: .sections, phase: .update, animated: false, start: .now())
        monitor.adapter.record(.began(interval))
        monitor.adapter.record(.ended(interval, at: .now(), outcome: .completed, counts: .init()))
        XCTAssertTrue(client.requests.isEmpty)
        // No explicit flush: a short-lived screen must not lose its last metrics.
        await monitor.shutdown()
        XCTAssertEqual(Set(client.requests.compactMap { $0.url?.path }), ["/v1/traces", "/v1/metrics"])
        let requestCount = client.requests.count
        await monitor.shutdown()
        XCTAssertEqual(client.requests.count, requestCount)
    }

    @MainActor
    func testOfficialExportersUseSignalPathsAndProtobufOffTheCallback() async throws {
        let client = CapturingClient()
        let monitor = ScreenTelemetryMonitor(endpoint: URL(string: "http://127.0.0.1:4318")!, serviceName: "test", interval: 3600, httpClient: client)
        let interval = ScreenTelemetryInterval(updateID: UUID(), screenID: UUID(), screenName: "catalog", kind: .state, phase: .update, animated: false, start: .now())
        monitor.adapter.record(.began(interval))
        monitor.adapter.record(.ended(interval, at: .now(), outcome: .completed, counts: .init()))
        XCTAssertTrue(client.requests.isEmpty, "Recording source events must not synchronously export HTTP")
        await monitor.flush()
        let requests = client.requests
        XCTAssertEqual(Set(requests.compactMap { $0.url?.path }), ["/v1/traces", "/v1/metrics"])
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Content-Type") == "application/x-protobuf" && !($0.httpBody?.isEmpty ?? true) })
        XCTAssertEqual(monitor.adapter.activeSpanCount, 0)
        XCTAssertEqual(monitor.adapter.invalidEventCount, 0)
        await monitor.shutdown()
        await monitor.shutdown() // Idempotent owner shutdown.
    }

    @MainActor
    func testMetricsExportWhenTraceSamplingIsDisabled() async throws {
        let client = CapturingClient()
        let monitor = ScreenTelemetryMonitor(endpoint: URL(string: "http://127.0.0.1:4318")!, serviceName: "unsampled", interval: 3600, sampled: false, httpClient: client)
        let interval = ScreenTelemetryInterval(updateID: UUID(), screenID: UUID(), screenName: "catalog", kind: .state, phase: .update, animated: false, start: .now())
        monitor.adapter.record(.began(interval))
        monitor.adapter.record(.ended(interval, at: .now(), outcome: .completed, counts: .init()))
        await monitor.flush()
        XCTAssertTrue(client.requests.contains { $0.url?.path == "/v1/metrics" })
        XCTAssertFalse(client.requests.contains { $0.url?.path == "/v1/traces" })
        await monitor.shutdown()
    }

    @MainActor
    func testOfficialExporterSendsScreenMetricsMatchingFixture() async throws {
        let client = CapturingClient()
        let monitor = ScreenTelemetryMonitor(
            endpoint: URL(string: "http://127.0.0.1:4318")!,
            serviceName: "screenkit-fixture-test", source: "fixture",
            interval: 3600, compressExports: false, httpClient: client
        )
        let start = ScreenTelemetryTimestamp(date: Date(timeIntervalSince1970: 100), uptimeNanoseconds: 1_000_000_000)
        let updateID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let screenID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let update = ScreenTelemetryInterval(
            updateID: updateID, screenID: screenID, screenName: "fixture-catalog",
            kind: .sections, phase: .update, animated: false, start: start
        )
        let phase = ScreenTelemetryInterval(
            updateID: updateID, screenID: screenID, screenName: "fixture-catalog",
            kind: .sections, phase: .snapshotPrepare, animated: false,
            start: .init(date: start.date, uptimeNanoseconds: 1_100_000_000)
        )
        monitor.adapter.record(.began(update))
        monitor.adapter.record(.began(phase))
        monitor.adapter.record(.ended(phase, at: .init(date: start.date, uptimeNanoseconds: 1_300_000_000), outcome: .completed, counts: nil))
        var counts = ScreenTelemetryCounts()
        counts.reconfiguredItems = 2
        monitor.adapter.record(.ended(update, at: .init(date: start.date, uptimeNanoseconds: 1_500_000_000), outcome: .completed, counts: counts))
        await monitor.flush()

        let metricRequest = try XCTUnwrap(client.requests.first { $0.url?.path == "/v1/metrics" })
        XCTAssertEqual(metricRequest.httpMethod, "POST")
        XCTAssertEqual(metricRequest.value(forHTTPHeaderField: "Content-Type"), "application/x-protobuf")
        let body = try XCTUnwrap(metricRequest.httpBody)
        let request = try Opentelemetry_Proto_Collector_Metrics_V1_ExportMetricsServiceRequest(serializedBytes: body)
        let resourceMetrics = try XCTUnwrap(request.resourceMetrics.first)
        let resourceAttributes = Dictionary(uniqueKeysWithValues: resourceMetrics.resource.attributes.compactMap { pair in
            stringValue(pair.value).map { (pair.key, $0) }
        })
        let scopeMetrics = try XCTUnwrap(resourceMetrics.scopeMetrics.first)
        XCTAssertEqual(scopeMetrics.scope.name, ScreenOpenTelemetry.instrumentationName)
        let actualResource = MetricFixture.Resource(
            serviceName: try XCTUnwrap(resourceAttributes["service.name"]),
            telemetrySource: try XCTUnwrap(resourceAttributes["screenkit.telemetry.source"])
        )
        let actualMetrics = try scopeMetrics.metrics.map { metric -> MetricFixture.Metric in
            let type: String
            let value: Int64?
            let count: UInt64?
            let attributes: [String: String]
            switch metric.data {
            case .sum(let sum):
                type = "sum"
                value = sum.dataPoints.reduce(Int64.zero) { $0 + $1.asInt }
                count = nil
                attributes = try XCTUnwrap(sum.dataPoints.first).attributes.compactMapValues(stringValue)
            case .histogram(let histogram):
                type = "histogram"
                value = nil
                count = histogram.dataPoints.reduce(UInt64.zero) { $0 + $1.count }
                attributes = try XCTUnwrap(histogram.dataPoints.first).attributes.compactMapValues(stringValue)
            default:
                throw NSError(domain: "ScreenKitTelemetryMonitorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unexpected metric data type for \(metric.name)"])
            }
            return .init(name: metric.name, unit: metric.unit, type: type, value: value, count: count, attributes: attributes)
        }.sorted { $0.name < $1.name }
        let actual = MetricFixture(resource: actualResource, scope: scopeMetrics.scope.name, metrics: actualMetrics)
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "screen-update-metrics", withExtension: "json", subdirectory: "Fixtures"))
        let expected = try JSONDecoder().decode(MetricFixture.self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(actual, expected)
        await monitor.shutdown()
    }

    private func stringValue(_ value: Opentelemetry_Proto_Common_V1_AnyValue) -> String? {
        switch value.value {
        case .stringValue(let value): value
        case .boolValue(let value): String(value)
        case .intValue(let value): String(value)
        case .doubleValue(let value): String(value)
        default: nil
        }
    }
}

private extension Array where Element == Opentelemetry_Proto_Common_V1_KeyValue {
    func compactMapValues(_ transform: (Opentelemetry_Proto_Common_V1_AnyValue) -> String?) -> [String: String] {
        Dictionary(uniqueKeysWithValues: compactMap { pair in transform(pair.value).map { (pair.key, $0) } })
    }
}
