"""Verify actual provisioned Grafana, Prometheus values and Tempo parentage."""
import argparse
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def get(url):
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)


def wait(check, timeout=90):
    deadline = time.monotonic()+timeout
    last = None
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                return result
        except (OSError, ValueError, AssertionError) as error:
            last = error
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for ingestion/readiness: {last}")


def query(expression):
    result = get("http://127.0.0.1:9090/api/v1/query?"+urllib.parse.urlencode({"query": expression}))
    assert result["status"] == "success", result
    return result["data"]["result"]


def scalar(expression):
    result = query(expression)
    return float(result[0]["value"][1]) if result else None


def spans(value):
    if isinstance(value, dict):
        if "name" in value and "spanId" in value:
            yield value
        for child in value.values():
            yield from spans(child)
    elif isinstance(value, list):
        for child in value:
            yield from spans(child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ready", action="store_true")
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--output", type=Path, default=Path("/tmp/screenkit-monitor-verification.json"))
    args = parser.parse_args()
    dashboard = wait(lambda: get("http://127.0.0.1:3000/api/dashboards/uid/screenkit-ui").get("dashboard"))
    assert len(dashboard["panels"]) >= 10
    wait(lambda: scalar('up{job="screenkit-otlp"}') == 1)
    print("Grafana provisioning and Collector scrape are ready", flush=True)
    if args.ready:
        return
    if not args.fixture:
        parser.error("--fixture is required unless --ready is used")
    fixture = json.loads(args.fixture.read_text())
    labels = f'service_instance_id="{fixture["instance"]}"'
    expression = 'sum(screenkit_update_count{'+labels+'})'
    def complete_metrics():
        updates = scalar(expression)
        count = scalar('sum(screenkit_update_settled_duration_count{'+labels+'})')
        total = scalar('sum(screenkit_update_settled_duration_sum{'+labels+'})')
        operations = scalar('sum(screenkit_work_count{'+labels+',screenkit_work="renderer_factory"})')
        if (updates == fixture["updates"] and count == fixture["completed"]
                and total is not None and math.isclose(total, fixture["durationSum"], rel_tol=1e-6)
                and operations == fixture["completed"]*1000):
            return count, total, operations
        return None
    # Wait for every signal, since exporters and scrapes run independently.
    count, total, operations = wait(complete_metrics)
    # Cumulative samples have been exported repeatedly. Counts must not multiply.
    def complete_trace():
        value = get("http://127.0.0.1:3200/api/traces/"+fixture["traceIDs"][0])
        return value if len(list(spans(value))) >= 5 else None
    trace = wait(complete_trace)
    trace_spans = list(spans(trace))
    roots = [s for s in trace_spans if s["name"] == "screenkit.update"]
    assert len(roots) == 1 and not roots[0].get("parentSpanId"), trace
    children = [s for s in trace_spans if s.get("parentSpanId") == roots[0]["spanId"]]
    assert {s["name"] for s in children} == {"screenkit.state.read", "screenkit.snapshot.prepare", "screenkit.snapshot.apply", "screenkit.layout"}, trace
    q = '{ name = "screenkit.update" && resource.service.instance.id = "'+fixture["instance"]+'" }'
    wait(lambda: get("http://127.0.0.1:3200/api/search?"+urllib.parse.urlencode({"q":q,"limit":50})).get("traces"))
    checked_queries = 0
    for panel in dashboard["panels"]:
        for target in panel.get("targets", []):
            if "expr" in target:
                expr = target["expr"]
                for key in ("service", "screen", "kind", "source"):
                    expr = expr.replace("${"+key+":regex}", ".*")
                expr = expr.replace("$__rate_interval", "1m")
                query(expr)  # Every provisioned PromQL expression must parse/execute.
                checked_queries += 1
    result = dict(fixture=fixture, metricCount=count, metricDurationSum=total, rendererCalls=operations, traceChildren=len(children), checkedQueries=checked_queries, dashboardUID=dashboard["uid"])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+"\n")
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
