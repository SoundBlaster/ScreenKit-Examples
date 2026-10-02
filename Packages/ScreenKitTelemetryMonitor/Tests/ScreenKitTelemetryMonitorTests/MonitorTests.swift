import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import OpenTelemetryProtocolExporterHttp
import ScreenKit
import ScreenKitTelemetryMonitor
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
}
