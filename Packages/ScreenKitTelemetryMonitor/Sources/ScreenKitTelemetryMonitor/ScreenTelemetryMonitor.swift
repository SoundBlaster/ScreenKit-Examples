import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import OpenTelemetryProtocolExporterHttp
import ScreenKitOpenTelemetry

/// App-owned SDK bootstrap for the local Grafana workbench.
///
/// Export uses the official OTLP/HTTP protobuf exporters, a batch span processor
/// and a periodic metric reader. No network flush occurs in ScreenKit's callback.
/// Keep this object alive for the measured screens, then call `shutdown()`.
@MainActor
public final class ScreenTelemetryMonitor {
    public let adapter: ScreenOpenTelemetry
    public let serviceInstanceID: String
    private let tracerProvider: TracerProviderSdk
    private let meterProvider: MeterProviderSdk
    private let workers: SDKExportWorkers
    private var stopped = false

    /// `endpoint` is the Collector base URL, e.g. `http://127.0.0.1:4318`.
    /// `source` distinguishes app measurements from synthetic/test events.
    /// `compressExports` controls OTLP HTTP request compression.
    /// `httpClient` allows the app to supply its URLSession or test transport.
    public init(
        endpoint: URL, serviceName: String, source: String = "app",
        instanceID: String = UUID().uuidString,
        interval: TimeInterval = 2, sampled: Bool = true, compressExports: Bool = true,
        httpClient: any HTTPClient = BaseHTTPClient()
    ) {
        precondition(interval.isFinite && interval > 0, "Export interval must be positive and finite")
        serviceInstanceID = instanceID
        let resource = Resource(attributes: [
            "service.name": .string(serviceName), "service.instance.id": .string(instanceID),
            "screenkit.telemetry.source": .string(source)
        ])
        let traceExporter = OtlpHttpTraceExporter(endpoint: endpoint.appendingPathComponent("v1/traces"), config: .init(compression: compressExports ? .gzip : .none), httpClient: httpClient, envVarHeaders: [])
        let metricExporter = OtlpHttpMetricExporter(endpoint: endpoint.appendingPathComponent("v1/metrics"), config: .init(compression: compressExports ? .gzip : .none), httpClient: httpClient, envVarHeaders: [])
        let processor = BatchSpanProcessor(spanExporter: traceExporter, scheduleDelay: interval, maxQueueSize: 512, maxExportBatchSize: 128)
        tracerProvider = TracerProviderBuilder().with(resource: resource)
            .with(sampler: sampled ? Samplers.alwaysOn : Samplers.alwaysOff)
            .add(spanProcessor: processor).build()
        let reader = PeriodicMetricReaderBuilder(exporter: metricExporter).setInterval(timeInterval: interval).build()
        workers = SDKExportWorkers(processor: processor, reader: reader)
        meterProvider = MeterProviderSdk.builder().setResource(resource: resource)
            .registerMetricReader(reader: reader)
            .registerView(selector: InstrumentSelectorBuilder().build(), view: View.builder().build()).build()
        let meter = meterProvider.get(name: ScreenOpenTelemetry.instrumentationName)
        let buckets = [0.0001, 0.0005, 0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1]
        adapter = ScreenOpenTelemetry(
            tracer: tracerProvider.get(instrumentationName: ScreenOpenTelemetry.instrumentationName),
            metrics: ScreenOpenTelemetryMetrics(
                updateDuration: meter.histogramBuilder(name: "screenkit.update.settled.duration")
                    .setUnit("s").setExplicitBucketBoundariesAdvice(buckets).build(),
                phaseDuration: meter.histogramBuilder(name: "screenkit.update.phase.duration")
                    .setUnit("s").setExplicitBucketBoundariesAdvice(buckets).build(),
                updates: meter.counterBuilder(name: "screenkit.update.count").setUnit("{update}").build(),
                work: meter.counterBuilder(name: "screenkit.work.count").setUnit("{operation}").build()
            )
        )
    }

    /// Flushes SDK queues off the main actor. This is not a server delivery receipt:
    /// the upstream metric exporter sends asynchronously. Verify Collector/backend
    /// ingestion when using this method as a test boundary.
    public func flush() async {
        guard !stopped else { return }
        await workers.flush()
    }

    /// Collects the last metrics and stops SDK workers off the main actor.
    /// Call outside measured intervals. Like `flush()`, this is not a server receipt.
    public func shutdown() async {
        guard !stopped else { return }
        stopped = true
        await workers.shutdown()
    }
}

/// Legacy SDK interop: BatchSpanProcessor's worker uses NSCondition internally,
/// but 2.5.1 does not declare the public processor Sendable. These immutable SDK
/// references never escape. Owner flush/shutdown calls run on one serial queue;
/// SDK event recording and periodic collection use the SDK's own synchronization.
/// A dedicated queue also keeps its blocking exporter waits off the cooperative pool.
private final class SDKExportWorkers: @unchecked Sendable {
    private let processor: BatchSpanProcessor
    private let reader: PeriodicMetricReaderSdk
    private let queue = DispatchQueue(label: "com.soundblaster.ScreenKitMonitor.lifecycle")

    init(processor: BatchSpanProcessor, reader: PeriodicMetricReaderSdk) {
        self.processor = processor
        self.reader = reader
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                processor.forceFlush(timeout: 10)
                _ = reader.forceFlush()
                continuation.resume()
            }
        }
    }

    func shutdown() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                // PeriodicMetricReaderSdk.shutdown() cancels its timer without
                // collecting. Otherwise updates since its last tick disappear.
                _ = reader.forceFlush()
                processor.shutdown(explicitTimeout: 10)
                _ = reader.shutdown()
                continuation.resume()
            }
        }
    }
}
