import Foundation
import OpenTelemetryApi
import ScreenKit

/// Application-created instruments, configured with units by its SDK.
///
/// OTel Swift 2.5.1's API builder protocol does not expose `setUnit`; its SDK
/// builder does. Accepting instruments preserves an API-only adapter dependency
/// while allowing the application to configure seconds, bucket boundaries,
/// views, and its own meter provider correctly.
public struct ScreenOpenTelemetryMetrics {
    /// A seconds histogram named `screenkit.update.settled.duration`.
    public var updateDuration: any DoubleHistogram
    /// A seconds histogram named `screenkit.update.phase.duration`.
    public var phaseDuration: any DoubleHistogram
    /// A counter named `screenkit.update.count`, including terminal outcomes.
    public var updates: any LongCounter
    /// A counter named `screenkit.work.count`, distinguished by `screenkit.work`.
    public var work: any LongCounter

    /// Creates instruments independently of the adapter's trace sampling policy.
    public init(
        updateDuration: any DoubleHistogram, phaseDuration: any DoubleHistogram,
        updates: any LongCounter, work: any LongCounter
    ) {
        self.updateDuration = updateDuration
        self.phaseDuration = phaseDuration
        self.updates = updates
        self.work = work
    }
}

/// Translates ScreenKit interval boundaries into explicit-parent OTel spans and metrics.
///
/// The application owns providers and exporters. Use a batch span processor and
/// periodic metric reader for network export; `record` never flushes or installs
/// global context. Metrics come from source events, including unsampled traces.
@MainActor
public final class ScreenOpenTelemetry: ScreenTelemetrySink {
    /// The instrumentation scope applications should use when creating providers.
    public static let instrumentationName = "com.soundblaster.ScreenKitOpenTelemetry"
    /// The prototype's telemetry schema version.
    public static let schemaVersion = "1"
    /// Unexpected duplicate, orphan, or reversed interval events.
    public private(set) var invalidEventCount = 0
    /// Spans retained until their source intervals end.
    public var activeSpanCount: Int { spans.count }

    private let tracer: any Tracer
    private var metrics: ScreenOpenTelemetryMetrics
    private let linksForUpdate: (ScreenTelemetryInterval) -> [SpanContext]
    private var spans: [UUID: any Span] = [:]
    private var updates: [UUID: any Span] = [:]
    private var completedPhases: [UUID: [(ScreenTelemetryPhase, Double)]] = [:]

    /// Creates an adapter with explicitly supplied instruments and causal links.
    ///
    /// Root updates do not inherit ambient global context. `linksForUpdate` may
    /// supply causes known when the update begins. Additional coalesced causes
    /// can be attached with `link(_:to:)` while the update remains active.
    public init(
        tracer: any Tracer, metrics: ScreenOpenTelemetryMetrics,
        linksForUpdate: @escaping (ScreenTelemetryInterval) -> [SpanContext] = { _ in [] }
    ) {
        self.tracer = tracer
        self.metrics = metrics
        self.linksForUpdate = linksForUpdate
    }

    /// Adds explicit causes to an active update without changing its parent.
    public func link(_ contexts: [SpanContext], to updateID: UUID) {
        guard let span = updates[updateID] else { return }
        for context in contexts { span.addLink(spanContext: context) }
    }

    /// Records an interval and its monotonic duration, preserving source timestamps.
    public func record(_ event: ScreenTelemetryEvent) {
        switch event {
        case let .began(interval):
            guard spans[interval.id] == nil else { invalidEventCount += 1; return }
            let builder = tracer.spanBuilder(spanName: interval.phase.spanName)
                .setSpanKind(spanKind: .internal)
                .setStartTime(time: interval.start.date)
            if interval.phase == .update {
                guard updates[interval.updateID] == nil else { invalidEventCount += 1; return }
                builder.setNoParent()
                for context in linksForUpdate(interval) { builder.addLink(spanContext: context) }
            } else {
                guard let parent = updates[interval.updateID] else { invalidEventCount += 1; return }
                builder.setParent(parent)
            }
            let span = builder.startSpan()
            span.setAttributes(attributes(interval))
            // Correlation IDs belong only to spans, never histogram/counter dimensions.
            span.setAttribute(key: "screenkit.screen.instance.id", value: .string(interval.screenID.uuidString))
            span.setAttribute(key: "screenkit.update.id", value: .string(interval.updateID.uuidString))
            spans[interval.id] = span
            if interval.phase == .update { updates[interval.updateID] = span }

        case let .ended(interval, timestamp, outcome, counts):
            guard let span = spans.removeValue(forKey: interval.id) else { invalidEventCount += 1; return }
            let phases = interval.phase == .update ? completedPhases.removeValue(forKey: interval.updateID) ?? [] : []
            if interval.phase == .update { updates.removeValue(forKey: interval.updateID) }
            span.setAttribute(key: "screenkit.update.outcome", value: .string(outcome.rawValue))
            guard let duration = timestamp.elapsedSeconds(since: interval.start) else {
                invalidEventCount += 1
                span.status = .error(description: "Reversed monotonic timestamp")
                span.end(time: interval.start.date)
                return
            }
            // Anchor span time to its original wall start plus monotonic elapsed
            // time. Wall-clock adjustments must not create negative trace durations.
            span.end(time: interval.start.date.addingTimeInterval(duration))
            var labels = attributes(interval)
            labels["screenkit.update.outcome"] = .string(outcome.rawValue)
            if interval.phase == .update {
                metrics.updates.add(value: 1, attributes: labels)
                guard outcome == .completed else { return }
                metrics.updateDuration.record(value: duration, attributes: labels)
                for (phase, elapsed) in phases {
                    var phaseLabels = labels
                    phaseLabels["screenkit.phase"] = .string(phase.rawValue)
                    metrics.phaseDuration.record(value: elapsed, attributes: phaseLabels)
                }
                if let counts {
                    let work: [(String, Int)] = [
                        ("renderer_factory", counts.rendererFactoryCalls),
                        ("cell_provider", counts.cellProviderCalls),
                        ("supplementary_update", counts.supplementaryUpdates),
                        ("reload_item", counts.reloadedItems),
                        ("reconfigure_item", counts.reconfiguredItems)
                    ]
                    for (name, count) in work where count > 0 {
                        labels["screenkit.work"] = .string(name)
                        metrics.work.add(value: count, attributes: labels)
                    }
                }
            } else if outcome == .completed {
                completedPhases[interval.updateID, default: []].append((interval.phase, duration))
            }
        }
    }

    private func attributes(_ interval: ScreenTelemetryInterval) -> [String: AttributeValue] {
        [
            "app.screen.name": .string(interval.screenName),
            "screenkit.update.kind": .string(interval.kind.rawValue),
            "screenkit.update.animated": .bool(interval.animated),
            "screenkit.telemetry.schema.version": .string(Self.schemaVersion)
        ]
    }
}

private extension ScreenTelemetryPhase {
    var spanName: String {
        switch self {
        case .update: "screenkit.update"
        case .schedulingWait: "screenkit.scheduling.wait"
        case .stateRead: "screenkit.state.read"
        case .identityValidation: "screenkit.identity.validate"
        case .queueWait: "screenkit.queue.wait"
        case .snapshotPrepare: "screenkit.snapshot.prepare"
        case .snapshotApply: "screenkit.snapshot.apply"
        case .supplementary: "screenkit.supplementary"
        case .layout: "screenkit.layout"
        }
    }
}
