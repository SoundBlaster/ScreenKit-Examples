"""Generate labeled synthetic data with the official Python OTel SDK for CI."""
import argparse
import json
import time
import uuid
from pathlib import Path

from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.metrics.view import ExplicitBucketHistogramAggregation, View
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import set_span_in_context


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", default="http://127.0.0.1:4318")
    parser.add_argument("--output", type=Path, default=Path("/tmp/screenkit-monitor-fixture.json"))
    parser.add_argument("--count", type=int, default=20)
    args = parser.parse_args()
    if not 3 <= args.count <= 120:
        parser.error("count must be between 3 and 120")
    instance = str(uuid.uuid4())
    resource = Resource.create({"service.name": "screenkit-ci", "service.instance.id": instance, "screenkit.telemetry.source": "synthetic"})
    traces = TracerProvider(resource=resource)
    traces.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=args.endpoint+"/v1/traces"), schedule_delay_millis=1000))
    reader = PeriodicExportingMetricReader(OTLPMetricExporter(endpoint=args.endpoint+"/v1/metrics"), export_interval_millis=1000)
    meters = MeterProvider(resource=resource, metric_readers=[reader], views=[View(instrument_name="screenkit.update.*.duration", aggregation=ExplicitBucketHistogramAggregation([.001, .005, .01, .02, .05, .1, .5, 1]))])
    tracer = traces.get_tracer("com.soundblaster.ScreenKitOpenTelemetry")
    meter = meters.get_meter("com.soundblaster.ScreenKitOpenTelemetry")
    duration = meter.create_histogram("screenkit.update.settled.duration", unit="s")
    phase_duration = meter.create_histogram("screenkit.update.phase.duration", unit="s")
    updates = meter.create_counter("screenkit.update.count", unit="{update}")
    work = meter.create_counter("screenkit.work.count", unit="{operation}")
    labels = {"app.screen.name": "catalog-ci", "screenkit.update.kind": "state", "screenkit.update.animated": False, "screenkit.telemetry.schema.version": "1"}
    trace_ids, completed, elapsed_sum = [], 0, 0.0
    for index in range(args.count):
        start = time.time_ns()
        elapsed = .012 + index*.001
        outcome = "cancelled" if index == args.count-1 else "completed"
        span_labels = dict(labels, **{"screenkit.update.id": str(uuid.uuid4()), "screenkit.screen.instance.id": instance, "screenkit.update.outcome": outcome})
        root = tracer.start_span("screenkit.update", start_time=start, attributes=span_labels)
        trace_ids.append(format(root.get_span_context().trace_id, "032x"))
        for name, phase, offset, seconds in [("screenkit.state.read", "stateRead", 0, .001), ("screenkit.snapshot.prepare", "snapshotPrepare", .001, .003), ("screenkit.snapshot.apply", "snapshotApply", .004, elapsed-.005), ("screenkit.layout", "layout", elapsed-.001, .001)]:
            child = tracer.start_span(name, context=set_span_in_context(root), start_time=start+int(offset*1e9), attributes=span_labels)
            child.end(end_time=start+int((offset+seconds)*1e9))
            if outcome == "completed":
                phase_duration.record(seconds, dict(labels, **{"screenkit.phase": phase, "screenkit.update.outcome": outcome}))
        root.end(end_time=start+int(elapsed*1e9))
        counter_labels = dict(labels, **{"screenkit.update.outcome": outcome})
        updates.add(1, counter_labels)
        if outcome == "completed":
            completed += 1
            elapsed_sum += elapsed
            duration.record(elapsed, counter_labels)
            for name, count in [("renderer_factory", 1000), ("cell_provider", 12), ("reconfigure_item", 1)]:
                work.add(count, dict(counter_labels, **{"screenkit.work": name}))
        time.sleep(1)
    if not traces.force_flush(timeout_millis=10000) or not meters.force_flush(timeout_millis=10000):
        raise RuntimeError("SDK flush failed")
    traces.shutdown()
    meters.shutdown()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(service="screenkit-ci", instance=instance, traceIDs=trace_ids, updates=args.count, completed=completed, durationSum=elapsed_sum), indent=2)+"\n")
    print(f"Synthetic fixture: {args.count} roots, {completed} completed; {args.output}")


if __name__ == "__main__":
    main()
