#!/usr/bin/env python3
"""Check built app/embedded binaries for HealthKit and optionally smoke-launch."""
import argparse
import pathlib
import plistlib
import re
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("app", type=pathlib.Path)
parser.add_argument("--launch", action="store_true")
args = parser.parse_args()
app = args.app.resolve()
assert app.is_dir(), "Built app missing"
pattern = re.compile(rb"HealthKit|NSHealth(?:Share|Update)|com\.apple\.developer\.healthkit|HKHealthStore", re.I)
mach_magic = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
binaries = []
for path in app.rglob("*"):
    if not path.is_file():
        continue
    with path.open("rb") as file:
        magic = file.read(4)
    if magic in mach_magic:
        binaries.append(path)
        data = subprocess.check_output(["strings", "-a", str(path)])
        assert not pattern.search(data), f"HealthKit binary reference: {path.relative_to(app)}"
        linked = subprocess.check_output(["otool", "-L", str(path)])
        assert not pattern.search(linked), f"HealthKit link: {path.relative_to(app)}"
    elif path.suffix in (".plist", ".strings", ".entitlements"):
        try:
            data = repr(plistlib.loads(path.read_bytes())).encode()
        except plistlib.InvalidFileException:
            data = path.read_bytes()
        assert not pattern.search(data), f"HealthKit metadata: {path.relative_to(app)}"
assert binaries, "No Mach-O binaries found"
print(f"PASS: HealthKit absent from metadata and {len(binaries)} Mach-O binaries")

if args.launch:
    plist = app / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    log = pathlib.Path("build/mac-launch.log")
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as output:
        process = subprocess.Popen([str(executable)], stdout=output, stderr=subprocess.STDOUT)
        try:
            time.sleep(20)
            assert process.poll() is None, f"Mac launch exited with {process.returncode}; see {log}"
            print("PASS: Mac Catalyst release stayed alive for 20 seconds (fresh CI user)")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
