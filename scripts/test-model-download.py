#!/usr/bin/env python3
"""Exercise the production URLSession delegate with tiny localhost fixtures.

No app, models, third-party frameworks, credentials or external network required.
Compile the exact delegate from ModelLoader.swift to keep this test usable in a
sparse checkout with the system Swift compiler.
"""
import http.server
import pathlib
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
PAYLOAD = b"GGUF" + bytes(124)


class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/valid")
            self.end_headers()
            return
        if self.path == "/stall":
            self.send_response(200)
            self.send_header("Content-Length", str(len(PAYLOAD) * 10))
            self.end_headers()
            self.wfile.write(PAYLOAD)
            self.wfile.flush()
            time.sleep(2)
            return
        status = 404 if self.path == "/missing" else 200
        data = b"not a model" if self.path in ("/missing", "/html") else PAYLOAD
        if self.path == "/empty":
            data = b""
        self.send_response(status)
        if self.path != "/unknown-size":
            self.send_header("Content-Length", str(len(data) + (100 if self.path == "/truncated" else 0)))
        self.end_headers()
        self.wfile.write(data)


HARNESS = r'''
let baseURL = CommandLine.arguments[1]
let cases: [(String, Bool, Int64)] = [
    ("valid", true, 142), ("redirect", true, 128),
    ("unknown-size", true, 128), ("missing", false, 128),
    ("html", false, 128), ("empty", false, 128),
    ("truncated", false, 128), ("stall", false, 1280)
]
for (path, shouldSucceed, estimate) in cases {
    let done = DispatchSemaphore(value: 0)
    let queue = DispatchQueue(label: "fixture.\(path)")
    let operations = OperationQueue()
    operations.maxConcurrentOperationCount = 1
    operations.underlyingQueue = queue
    var completions = 0
    var reachedComplete = false
    var observedServerSize = false
    let delegate = DownloadDelegate(
        expectedSize: estimate, validatesGGUF: true,
        callbackQueue: queue, stallTimeoutSeconds: 0.2,
        progressHandler: { progress, _, total, _, _ in
            if progress == 1 { reachedComplete = true }
            if total == 128 { observedServerSize = true }
        },
        completionHandler: { result in
            completions += 1
            switch result {
            case .success(let url):
                precondition(shouldSucceed, "accepted invalid response: \(path)")
                precondition(reachedComplete)
                precondition((try? Data(contentsOf: url).count) == 128)
                try! FileManager.default.removeItem(at: url)
            case .failure:
                precondition(!shouldSucceed, "valid fixture failed: \(path)")
                precondition(!reachedComplete, "false 100% on failure: \(path)")
            }
            done.signal()
        })
    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: operations)
    let task = session.downloadTask(with: URL(string: "\(baseURL)/\(path)")!)
    delegate.attach(task: task)
    task.resume()
    precondition(done.wait(timeout: .now() + 5) == .success, "hung: \(path)")
    session.invalidateAndCancel()
    Thread.sleep(forTimeInterval: 0.3)
    queue.sync {
        precondition(completions == 1, "double completion: \(path)")
        if path == "valid" { precondition(observedServerSize, "used stale catalog size") }
    }
    print("PASS \(path)")
}
print("8 download integration cases passed")
'''


def main():
    source = (ROOT / "LocalAIAgent/LLM/ModelLoader.swift").read_text()
    delegate = source.split("// MARK: - Download Delegate\n", 1)[1].split(
        "/// Delegate to handle redirects for HEAD requests", 1
    )[0]
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="elio-download-test-") as directory:
            directory = pathlib.Path(directory)
            swift = directory / "main.swift"
            swift.write_text("import Foundation\n" + delegate + HARNESS)
            binary = directory / "download-tests"
            subprocess.run(["swiftc", "-swift-version", "5", str(swift), "-o", str(binary)], check=True)
            subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}"], check=True, timeout=30)
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
