# Real-model iOS simulator verification — 2026-09-20 JST

## Verdict: download/load verified; inference correctness FAILED

This is a real network/model integration test, not the 128-byte fixture test.
Do not describe this result as physical iPhone verification or successful inference.
No review submission/upload was performed by these runs. Parent reports build58
attached to both ASC versions and is handling Mac review separately.

## Evidence

- First run: https://github.com/yukihamada/elio/actions/runs/35455232069
  - Commit `9d4f655ba687957973acfd0c77841b3a2baf03d6`.
  - Actual model download 157.148 s, exact SHA-256 matched, load 36.074 s.
  - XCTest stopped at its default 10-minute allowance during inference.
  - Normal app startup also downloaded Qwen3.5-2B and attempted free ChatWeb
    registration (404). No paid inference API was used.
- Isolated run: https://github.com/yukihamada/elio/actions/runs/35456866815
  - Commit `a5dea74388c18b419e19dc2c4d2496cc352da77e`.
  - Xcode 26.2 (17C52), arm64 iPhone 17 Pro **simulator**, iOS 26.2 (23C54).
  - CI-only minimal SwiftUI entry point removes AppState/onboarding startup;
    production ModelLoader/CoreMLInference/LlamaInference are unmodified.
  - Metal validation disabled; production `auto` acceleration, no CPU override.
  - XCTest: **1 executed, 1 failed, 0 skipped** (xcresult summary independently read).
  - Failure: `Arithmetic smoke prompt must produce the answer`.

| Measurement | Isolated run |
|---|---|
| Model | `eliochat-1.7b-v3`, ElioChat-1.7B-Instruct-v3-Q5_K_M.gguf |
| Download path | Production `ModelLoader.downloadModel`, public HF HTTPS redirects/URLSession |
| Actual bytes | **1,257,875,104** |
| SHA-256 | `82652c12c33044a23e66f55fc8ecdb67bd05bb5a968b7a1f4134ee086ba5638a` |
| Full download | **30.546 s** |
| 90% / 100% | **27.952 s / 30.546 s**, 91–99% also recorded |
| Load + context creation | **31.138 s**, `isLoaded=true` |
| First stream callback | **56.667 s** (callbacks batch up to four tokens; not first-token latency) |
| Generation | **693.643 s**, 64-token limit, 16 stream callbacks |
| Prompt | `What is 2 + 2? Reply with the number only.` (ChatML; temperature 0) |
| Actual output | `E!odeextr!odeoen!odeved!odeHallo!odeoen!odeved!odeHallo!…` |

Full output and 90–100% progress timestamps are retained in artifact
`review-verification` → `work/elio/elio/build/full-model-evidence.json`;
environment metadata is alongside it. `TestResults.xcresult` is in the same artifact.
**Important evidence caveat:** this run's JSON `stage: passed` is a recording bug:
the async XCTest assertion continued executing. The failed xcresult and run status
are authoritative; the output is invalid. A subsequent source-only correction uses
an explicit throwing guard and records `validation_failed`; that correction has
syntax validation but has not been rerun with the model.

## Scope and limits for iOS review

- Verified: fresh, uncached full network download through app code; exact file
  identity; completion beyond 90%; GGUF load/context creation; actual streaming
  inference execution (no canned output or cloud model).
- **Failed:** meaningful/correct answer. Root cause **unverified**: no evidence yet
  isolates model quality, simulator Metal/backend, or inference implementation.
- Unverified: physical iPhone memory/Metal/performance, TestFlight build58 binary,
  actual onboarding/chat UI, background/foreground, interrupted full-download
  resume, low-storage/slow-network full-model behavior. This test targets the
  explicitly requested ElioChat 1.7B model, not every catalog model/default Qwen.
- Build58 application code was not changed by this work. New commits only add
  tests, CI harness and documentation. The runner's minimal host is ephemeral and
  upload is explicitly disabled for `full_model=true`.
- Models/frameworks were downloaded only on CI. Local artifacts contain JSON and
  XCTest diagnostics, not model weights. No secrets were provided to this job.

## Next diagnostic

Compare the same file/prompt on CI CPU reference and simulator Metal to isolate
the invalid output; retain the current failed result. A valid CPU result alone
would not establish real-iPhone/Metal readiness. iOS should not be called verified
for resubmission based on this evidence.
