"""Build and run a Release Lab comparison on one explicitly selected iOS simulator."""
import argparse
import hashlib
import json
import os
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "com.soundblaster.screenkit.lab.telemetry"


def command(*args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Exact simulator UUID (never a physical device)")
    parser.add_argument("--derived-data", type=Path, default=Path("/tmp/ScreenKit-LabTelemetry-DD"))
    parser.add_argument("--packages", type=Path, help="Optional existing Xcode package checkout cache")
    parser.add_argument("--endpoint", default="http://127.0.0.1:4318")
    parser.add_argument("--output", type=Path, required=True, help="New evidence directory for this run")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    matches = [(runtime, d) for runtime, group in devices.items() for d in group if d["udid"] == args.device]
    if len(matches) != 1 or ".iOS-" not in matches[0][0]:
        parser.error("--device must identify one available iOS simulator")
    runtime, device = matches[0]
    build = ["xcodebuild", "-quiet", "-project", "ScreenKitLabTelemetry.xcodeproj", "-scheme", "ScreenKitLabTelemetry",
             "-configuration", "Release", "-destination", f"platform=iOS Simulator,id={args.device}",
             "-derivedDataPath", str(args.derived_data), "-skipMacroValidation", "ONLY_ACTIVE_ARCH=YES", "build"]
    if args.packages:
        build += ["-clonedSourcePackagesDirPath", str(args.packages.resolve())]
    print("Building Release Lab…", flush=True)
    with (args.output / "build.log").open("w") as log:
        subprocess.run(build, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    files = command("git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    inputs = {
        "commit": command("git", "rev-parse", "HEAD"), "status": command("git", "status", "--porcelain"),
        "toolchain": command("xcodebuild", "-version"), "runtime": runtime, "device": device,
        "command": build,
        "sourceSHA256": {f: hashlib.sha256((ROOT / f).read_bytes()).hexdigest() for f in files
                         if Path(f).suffix in {".swift", ".pbxproj", ".resolved", ".xcscheme", ".plist", ".py"}},
    }
    (args.output / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    if device["state"] != "Booted":
        command("xcrun", "simctl", "boot", args.device)
    command("xcrun", "simctl", "bootstatus", args.device, "-b")
    app = args.derived_data / "Build/Products/Release-iphonesimulator/ScreenKitLabTelemetry.app"
    command("xcrun", "simctl", "install", args.device, str(app))
    container = Path(command("xcrun", "simctl", "get_app_container", args.device, BUNDLE, "data"))
    report = container / "Documents/telemetry-benchmark.json"
    previous = report.read_bytes() if report.exists() else None
    environment = dict(os.environ, SIMCTL_CHILD_SCREENKIT_OTLP_ENDPOINT=args.endpoint)
    command("xcrun", "simctl", "launch", "--terminate-running-process", args.device, BUNDLE,
            "--telemetry-off", "--telemetry-benchmark", env=environment)
    print("Running balanced comparison in the visible app…", flush=True)
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if report.exists():
            content = report.read_bytes()
            if content != previous:
                (args.output / "report.json").write_bytes(content)
                print(f"Report: {args.output / 'report.json'}", flush=True)
                return
        time.sleep(2)
    raise TimeoutError("No new Lab report within 180 seconds; inspect the app and simulator logs")


if __name__ == "__main__":
    main()
