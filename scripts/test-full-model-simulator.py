#!/usr/bin/env python3
"""Run the production-path XCTest on a fresh CI-only iOS simulator.

No model curl/cache and no API credentials: ModelLoader downloads inside the app.
Only JSON and xcresult are retained; the 1.26 GB model stays on the CI runner.
"""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("Large-model test is restricted to GitHub Actions")
    runtime = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
    simulator = run("xcrun", "simctl", "create", "Elio Full Model Verification",
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", runtime)
    build = Path("build")
    build.mkdir(exist_ok=True)
    (build / "full-model-environment.json").write_text(json.dumps({
        "commit": os.environ["GITHUB_SHA"], "run": os.environ["GITHUB_RUN_ID"],
        "runtime": runtime, "simulator": simulator,
        "xcode": run("xcodebuild", "-version"),
        "architecture": run("uname", "-m"),
        "physicalDevice": False,
    }, indent=2))
    subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True)
    common = ["-destination", f"platform=iOS Simulator,id={simulator}",
              "-parallel-testing-enabled", "NO"]
    subprocess.run(["xcodebuild", "build-for-testing", "-project", "ElioChat.xcodeproj",
                    "-scheme", "ElioChat", "-configuration", "Debug",
                    "-derivedDataPath", "build/full-model", *common,
                    "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO"], check=True)
    specs = list(Path("build/full-model/Build/Products").glob("*.xctestrun"))
    if len(specs) != 1:
        raise RuntimeError(f"Expected exactly one xctestrun, got {len(specs)}")
    spec = specs[0]
    content = plistlib.loads(spec.read_bytes())
    targets = []

    def inject(value):
        if isinstance(value, dict):
            if "TestBundlePath" in value:
                value.setdefault("EnvironmentVariables", {})["ELIO_CI_FULL_MODEL"] = "1"
                targets.append(value["TestBundlePath"])
            for child in list(value.values()):
                inject(child)
        elif isinstance(value, list):
            for child in value:
                inject(child)

    inject(content)
    if not targets:
        raise RuntimeError("No test targets to enable; refuse an accidental skip")
    spec.write_bytes(plistlib.dumps(content))
    try:
        subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", str(spec),
                        *common, "-only-testing:LocalAIAgentTests/ModelLoaderTests/testRealModelDownloadLoadAndInference",
                        "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "1200",
                        "-resultBundlePath", "TestResults.xcresult"], check=True)
    finally:
        container = run("xcrun", "simctl", "get_app_container", simulator, "love.elio.app", "data")
        evidence = Path(container) / "Documents/full-model-evidence.json"
        if evidence.exists():
            shutil.copyfile(evidence, build / evidence.name)
            print(evidence.read_text(), flush=True)
    result = json.loads((build / "full-model-evidence.json").read_text())
    if result.get("stage") != "passed":
        raise RuntimeError("The real-model test did not reach its final assertions")


if __name__ == "__main__":
    main()
