# Real-model iOS simulator verification — 2026-09-20 JST

## Final update: CPU/Metal isolation and verified simulator fix

**Normal responses now verified**, commit `c55a7138033a471dec787f27d77877325be87ae7`.

### Causal comparison (not an assertion relaxation)

Run https://github.com/yukihamada/elio/actions/runs/35458861049 (`1fb6d34`)
used the identical GGUF SHA, simulator, linked llama framework, prompt, Q8 KV
settings and generation code. Changing only `inferenceMode` to CPU (0 GPU layers):

- CPU original prompt: `<think>\n\n</think>\n\n4` (40.432 s).
- CPU no-thinking prefix: `A: 4\n</think>\n\n4` (59.075 s).
- Production auto/Metal: the same `E!odeextr!odeoen...` corruption reproduced.
- MTL0 reported Apple2/Common1, no simdgroup reduction/matrix multiplication,
  no unified memory and **0 MB recommended working set** in the simulator.

Root cause isolated to selecting this simulator Metal offload path based on
host RAM alone (`InferenceMode.gpuLayers`). This is **not evidence of a bad model
or real-iPhone Metal failure**. The precise incorrect Metal kernel is unverified.
Fix: `LlamaInference.swift:47–60` returns zero GPU layers at compile time for
`targetEnvironment(simulator)`. Real-device/Catalyst layer policy is unchanged.

### Tokenizer / template / version findings

- The GGUF itself reports `general.architecture=qwen3`, name
  `Photon 1.7B Instruct v1 Merged`, GPT2/Qwen2 BPE, 151936 tokens,
  BOS/padding 151643, EOS 151645, `add_bos_token=false`; 28 metadata keys
  contain **no tokenizer.chat_template**. The misleading name is real, but
  selecting by ElioChat filename already uses Qwen ChatML in production.
- Both original ChatML and `<think></think>` prefix produced intelligible CPU
  answers. Production `generateWithMessages(...settings:)` also passed Japanese
  below. Tokenizer/template mismatch does not explain this A/B corruption.
- Independent native upstream `llama-simple` built from **b8500 /
  342d6125bcda31f8bbda5df4a74afcf4b2d8c681** on the runner read the same file.
  CPU no-thinking output ends in `4`; original prompt generates coherent
  reasoning but reaches 64-token limit before a final answer.
- Existing iOS XCFramework release has **no source revision provenance** in
  release notes. Its exact version remains unverified; it was not replaced.
  Same-binary CPU success vs Metal failure rules out a version change as the
  necessary explanation. Catalyst source dependency is b8500.
- Native b8500 Metal comparisons now preserve timeout stdout/stderr:
  both prompts generated coherent reasoning about 2+2=4 but **timed out at
  300 s (returncode 124)**. This is not Mac app inference completion. Runner
  native GPU is also MTL0 with no simdgroup support, not representative hardware.

### Verified corrected path

Run https://github.com/yukihamada/elio/actions/runs/35460934037 — **SUCCESS**.
Downloaded xcresult independently reports **1 passed / 0 failed / 0 skipped**.

| Measurement | Corrected default ModelLoader → load → inference |
|---|---|
| Full bytes / SHA | 1,257,875,104 / unchanged exact SHA above |
| Download | 12.871 s |
| 90% → 100% | 11.960 s → 12.870 s |
| Load | 6.031 s (backend already initialized by comparison) |
| Arithmetic generation | 61.327 s, `<think>\n\n</think>\n\n4` |
| Japanese generation | 75.822 s, `はい、日本の首都は東京です。` |

Arithmetic assertion strengthened from contains("4") to final answer exactly
"4" after thinking tags. Japanese check requires 東京 via the production message
formatter, on the same loaded context. All weights and inference stay on CI.

Regression run https://github.com/yukihamada/elio/actions/runs/35463074103 —
**SUCCESS**, same commit: 194 ordinary tests passed, opt-in real-model test
skipped (195 total/1 skipped/0 failed); iOS and Catalyst build, both HealthKit
binary audits, Mac Release 20-second launch passed. No uploads in either run.

Evidence artifact `review-verification` includes `full-model-evidence.json`,
`full-model-environment.json`, `model-reference.json`, native reference logs and
xcresult. Local small-evidence copies:
`/var/folders/sf/mj3cxbp93352t_5chc3wpjwc0000gn/T/sente/elio-full-model-35460934037/work/elio/elio/`
and sibling `elio-full-model-35458861049`. No local model downloads.

### Build58 / review decision

- This fix changes **simulator-only code**, so no new iOS device or Catalyst
  build is required solely to incorporate it. Existing build58 was not replaced,
  uploaded again, or submitted. App binary dependency provenance beyond CI
  remains unverified; do not claim TestFlight binary identity from source tests.
- CPU-tested real file is not intrinsically broken. Nevertheless **real iPhone
  Metal, shipping Mac Catalyst full inference, UI/background/resume remain
  unverified**. Mac native reference timeouts are not a green Mac test.
- Report simulator DL/load/inference success precisely; maintain the parent's
  submission hold until real-device/shipping-backend verification resolves the
  remaining gate. A production-backend fix, if later needed, requires a new build.

The earlier failures below are retained as historical evidence.

---

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
