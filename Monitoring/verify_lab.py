"""Validate a real Lab comparison report, optionally requiring every OTLP update in the backends."""
import argparse
import json
import math
import statistics
import urllib.parse
from datetime import datetime
from pathlib import Path

from verify import get, scalar, spans, wait


def validate(report):
    assert report["schema"] == 1
    assert report["configuration"] == "Release", "Debug timings are not comparable"
    assert not report["errors"], report["errors"]
    assert len(report["blocks"]) == 8
    assert report["itemCount"] == 1000
    assert report["warmups"] == 3 and report["samplesPerBlock"] == 20
    pairs = []
    for pair in range(4):
        blocks = report["blocks"][pair * 2:pair * 2 + 2]
        order = ["disabled", "otlp"] if pair % 2 == 0 else ["otlp", "disabled"]
        medians = {}
        for position, block in enumerate(blocks):
            assert (block["pair"], block["position"], block["mode"]) == (pair, position, order[position])
            assert block["contentVerified"] and block["invalidEvents"] == block["activeSpans"] == 0
            samples = block["samples"]
            assert [s["iteration"] for s in samples] == list(range(1, 21))
            assert all(math.isfinite(s["seconds"]) and s["seconds"] > 0 and s["appActive"] for s in samples)
            medians[block["mode"]] = statistics.median(s["seconds"] for s in samples)
            if block["mode"] == "disabled":
                assert block.get("instanceID") is None and block["expectedUpdates"] == 0
            else:
                assert block["instanceID"] == f'{report["runID"]}-{pair}-{position}'
                assert block["expectedUpdates"] == 24  # initial + 3 warmups + 20 samples
        pairs.append({"pair": pair, "order": order, "disabledMedianSeconds": medians["disabled"],
                      "otlpMedianSeconds": medians["otlp"], "ratio": medians["otlp"] / medians["disabled"]})
    return pairs


def verify_backend(report):
    evidence = []
    start = int(datetime.fromisoformat(report["startedAt"].replace("Z", "+00:00")).timestamp()) - 60
    end = int(datetime.fromisoformat(report["finishedAt"].replace("Z", "+00:00")).timestamp()) + 60
    for block in report["blocks"]:
        if block["mode"] != "otlp":
            continue
        instance = block["instanceID"]
        labels = 'service_name="screenkit-lab-benchmark",screenkit_telemetry_source="app",app_screen_name="Lab.MixedBenchmark",service_instance_id=' + json.dumps(instance)
        expected = block["expectedUpdates"]

        def complete_metrics():
            updates = scalar('sum(screenkit_update_count{' + labels + '})')
            completed = scalar('sum(screenkit_update_count{' + labels + ',screenkit_update_outcome="completed"})')
            count = scalar('sum(screenkit_update_settled_duration_count{' + labels + '})')
            work = scalar('sum(screenkit_work_count{' + labels + ',screenkit_work="renderer_factory"})')
            if updates == completed == count == expected and work == expected * report["itemCount"]:
                return {"updates": updates, "histogramCount": count, "rendererCalls": work}
            raise AssertionError({"instance": instance, "expectedUpdates": expected,
                                  "updates": updates, "completed": completed, "histogramCount": count, "rendererCalls": work})

        metrics = wait(complete_metrics)
        q = '{ name = "screenkit.update" && resource.service.instance.id = ' + json.dumps(instance) + ' }'
        search_url = "http://127.0.0.1:3200/api/search?" + urllib.parse.urlencode({"q": q, "limit": 1000, "start": start, "end": end})

        def complete_search():
            traces = get(search_url).get("traces", [])
            assert len(traces) <= expected, "Unexpected additional root updates"
            if len(traces) == expected:
                return traces
            raise AssertionError({"instance": instance, "expectedTraces": expected, "actualTraces": len(traces)})

        traces = wait(complete_search)
        required = {"screenkit.identity.validate", "screenkit.queue.wait", "screenkit.snapshot.prepare",
                    "screenkit.snapshot.apply", "screenkit.supplementary", "screenkit.layout"}
        verified = []
        for match in traces:
            trace_id = match["traceID"]

            def complete_trace():
                trace = list(spans(get("http://127.0.0.1:3200/api/traces/" + trace_id)))
                roots = [s for s in trace if s["name"] == "screenkit.update"]
                if len(roots) != 1 or len(trace) != len(required) + 1:
                    return None
                root = roots[0]
                assert not root.get("parentSpanId")
                children = [s for s in trace if s.get("parentSpanId") == root["spanId"]]
                assert {s["name"] for s in children} == required
                assert int(root["endTimeUnixNano"]) > int(root["startTimeUnixNano"])
                return {"traceID": trace_id, "children": len(children)}

            verified.append(wait(complete_trace))
        evidence.append({"instance": instance, "metrics": metrics, "traces": verified})
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--backend", action="store_true", help="Require Collector/Prometheus/Tempo receipt; run within five minutes of the app")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    pairs = validate(report)
    result = {
        "runID": report["runID"], "classification": "simulator-smoke" if report["simulator"] else "device-measurement",
        "pairs": pairs, "medianPairedRatio": statistics.median(p["ratio"] for p in pairs),
        "pairRatioRange": [min(p["ratio"] for p in pairs), max(p["ratio"] for p in pairs)],
        "thermalStates": sorted({s["thermalState"] for b in report["blocks"] for s in b["samples"]}),
        "lowPowerMode": report["lowPowerMode"],
        "backendVerified": args.backend,
        "backendEvidence": verify_backend(report) if args.backend else [],
        "scope": "Explicit nonanimated mixed-list update completion, including layout; not frame/GPU timing. No performance threshold established.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "backendEvidence"}, indent=2), flush=True)


if __name__ == "__main__":
    main()
