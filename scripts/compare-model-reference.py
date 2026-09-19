#!/usr/bin/env python3
"""CI-only b8500 upstream simple.cpp reference; reuse the simulator's real file."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

assert os.environ.get("GITHUB_ACTIONS") == "true"
model = Path(sys.argv[1])
source = Path(os.environ["RUNNER_TEMP"]) / "llama-reference"
subprocess.run(["git", "clone", "--depth", "1", "--branch", "b8500",
                "https://github.com/ggml-org/llama.cpp.git", str(source)], check=True)
build = source / "build"
subprocess.run(["cmake", "-S", str(source), "-B", str(build), "-G", "Ninja",
                "-DCMAKE_BUILD_TYPE=Release", "-DGGML_METAL=ON", "-DGGML_METAL_EMBED_LIBRARY=ON",
                "-DGGML_NATIVE=OFF", "-DGGML_OPENMP=OFF", "-DLLAMA_BUILD_TESTS=OFF",
                "-DLLAMA_BUILD_EXAMPLES=ON", "-DLLAMA_BUILD_TOOLS=OFF",
                "-DLLAMA_BUILD_SERVER=OFF", "-DLLAMA_BUILD_APP=OFF"], check=True)
subprocess.run(["cmake", "--build", str(build), "--target", "llama-simple", "-j", "3"], check=True)
prompt = "<|im_start|>system\nAnswer briefly. /no_think<|im_end|>\n<|im_start|>user\nWhat is 2 + 2? Reply with the number only.<|im_end|>\n<|im_start|>assistant\n"
results = {"version": "b8500", "commit": subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip(),
           "sha256": hashlib.file_digest(model.open("rb"), "sha256").hexdigest(), "runs": []}
for backend, layers in [("native-cpu", "0"), ("native-metal", "99")]:
    for template, text in [("no-thinking", prompt + "<think></think>\n"), ("original", prompt)]:
        start = time.monotonic()
        try:
            completed = subprocess.run([str(build / "bin/llama-simple"), "-m", str(model), "-n", "64",
                                        "-ngl", layers, text], capture_output=True, text=True, timeout=300)
        except subprocess.TimeoutExpired as error:
            # A reference timeout is evidence, not a reason to lose all partial
            # Metal diagnostics or skip the next comparison.
            completed = subprocess.CompletedProcess(error.cmd, 124,
                (error.stdout or b"").decode(errors="replace"),
                (error.stderr or b"").decode(errors="replace"))
        name = f"model-reference-{backend}-{template}"
        Path(f"build/{name}.log").write_text(completed.stderr)
        results["runs"].append({"backend": backend, "template": template, "prompt": text,
                               "stdout": completed.stdout, "returncode": completed.returncode,
                               "seconds": time.monotonic() - start})
        Path("build/model-reference.json").write_text(json.dumps(results, indent=2))
        print(json.dumps(results["runs"][-1]), flush=True)
