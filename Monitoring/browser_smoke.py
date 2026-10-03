"""Verify Grafana's native dashboard and trace waterfall with Playwright."""
import argparse
import json
import re
from pathlib import Path
from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/screenkit-monitor-browser"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    messages = []
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch()
        page = browser.new_page(viewport={"width": 1440, "height": 1600}, device_scale_factor=1)
        page.on("pageerror", lambda error: messages.append(str(error)))
        try:
            page.goto("http://127.0.0.1:3000/d/screenkit-ui", wait_until="domcontentloaded")
            expect(page.get_by_text("Completed updates · active counters", exact=True)).to_be_visible(timeout=60000)
            completed = page.get_by_role("region", name="Completed updates · active counters", exact=True)
            expect(completed.get_by_text(re.compile(r"^[1-9][0-9]*(?:[.,][0-9]+)?\s*[kKMGT]?$"), exact=True).first).to_be_visible(timeout=60000)
            expect(page.get_by_text("Mean settled · active histograms", exact=True)).to_be_visible()
            traces = page.get_by_text("Recent sampled update traces · open a Trace ID for waterfall", exact=True)
            traces.scroll_into_view_if_needed()
            expect(page.get_by_text("screenkit.update", exact=True).first).to_be_visible(timeout=60000)
            page.screenshot(path=str(args.output/"dashboard-desktop.png"), full_page=True)
            # Tempo supplies the native trace-ID link and its native waterfall.
            trace_link = page.get_by_role("link", name=re.compile(r"[0-9a-f]{32}")).first
            expect(trace_link).to_be_visible(timeout=30000)
            trace_link.click()
            expect(page.get_by_text("screenkit.snapshot.prepare", exact=False).first).to_be_visible(timeout=60000)
            expect(page.get_by_text("screenkit.layout", exact=False).first).to_be_visible()
            page.screenshot(path=str(args.output/"trace-waterfall.png"), full_page=True)
            page.set_viewport_size({"width":390, "height":844})
            page.goto("http://127.0.0.1:3000/d/screenkit-ui", wait_until="domcontentloaded")
            expect(page.get_by_text("Completed updates · active counters", exact=True)).to_be_visible(timeout=60000)
            completed = page.get_by_role("region", name="Completed updates · active counters", exact=True)
            expect(completed.get_by_text(re.compile(r"^[1-9][0-9]*(?:[.,][0-9]+)?\s*[kKMGT]?$"), exact=True).first).to_be_visible(timeout=60000)
            page.screenshot(path=str(args.output/"dashboard-mobile.png"))
            # Grafana renders panels lazily: exercise off-screen mobile panels
            # rather than treating a screenshot of empty placeholders as proof.
            chart = page.get_by_role("region", name="Settled time percentiles", exact=True)
            chart.scroll_into_view_if_needed()
            expect(chart.get_by_text("p50", exact=True)).to_be_visible(timeout=60000)
            chart.screenshot(path=str(args.output/"dashboard-mobile-chart.png"))
            mobile_traces = page.get_by_role("region", name="Recent sampled update traces · open a Trace ID for waterfall", exact=True)
            mobile_traces.scroll_into_view_if_needed()
            expect(mobile_traces.get_by_role("link", name=re.compile(r"[0-9a-f]{32}")).first).to_be_visible(timeout=60000)
            mobile_traces.screenshot(path=str(args.output/"dashboard-mobile-traces.png"))
            assert not messages, messages
        finally:
            (args.output/"browser-errors.json").write_text(json.dumps(messages, indent=2)+"\n")
            (args.output/"browser-text.txt").write_text(page.locator("body").inner_text())
            page.screenshot(path=str(args.output/"last-browser-state.png"), full_page=True)
            browser.close()
    print("Grafana dashboard, native trace waterfall and mobile layout passed")


if __name__ == "__main__":
    main()
