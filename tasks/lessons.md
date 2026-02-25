# Lessons Learned — elio

## Architecture
- **LocalBackend has no .shared singleton** — access via `ChatModeManager.shared.localBackend` or use `ChatModeManager.shared.isModeAvailable(.local)`. MeshTopologyView had a crash from `LocalBackend.shared` (2024-02).
- **P2P backend must be configured BEFORE `isModelLoaded = true`** — `onChange` triggers `macStartupSetup()` which calls `PrivateServerManager.start()`. If backend isn't set, server start always fails silently.
- **AppState.shared exists but is not always safe** — Some views/managers should go through ChatModeManager instead for backend-related state.

## Build & Xcode
- **"Missing package product" in Xcode UI can be phantom** — CLI `xcodebuild` may succeed even when Xcode shows errors. Fix: quit Xcode, `rm -rf ~/Library/Developer/Xcode/DerivedData/ElioChat-*`, reopen.
- **SPM cache corruption** — Also delete `~/Library/Caches/org.swift.swiftpm` and the `xcuserdata` folder when packages refuse to resolve.
- **PIF GUID errors** — Usually DerivedData corruption, not actual project file issues. Nuclear clear of DerivedData + SPM caches resolves it.

## Git Hygiene
- **Commit by feature, not by session** — Large uncommitted diffs across 100+ files are unmanageable. Group by: core infra, P2P, features, UI, localization, build config.
- **Don't mix unrelated changes** — Keeps reverts safe and history readable.

## P2P Networking
- **P2PServer struct fields**: `id: String`, `name: String`, `endpoint: NWEndpoint`, `pairingCode: String?`, `elioId: String?` — No `deviceId`, `isOnline`, `lastSeen`, or `isTrusted` fields. ProximityDiscoveryManager had broken init with wrong fields.
- **connectToServer(url:) does not exist** on P2PBackend — use `connect(to: P2PServer)` instead.
- **New field to struct = update ALL test init calls** — When adding a field to P2PServer (e.g. `elioId`), ALL test files that construct P2PServer must be updated. Compiler errors only surface in test targets.
- **QR code format changes need handler updates** — When QR code adds new parameters (e.g. `eid`), the corresponding `handleFriendCode`/`handlePeerCode` must extract and pass the new parameter. Otherwise the data is silently lost.

## Performance
- **Array.insert(at: 0) in a loop is O(n^2)** — When building lists newest-first, collect via append then reverse() once at the end. Applied in `trimHistoryToFitContext` and `getContextMessages`.
- **DateFormatter allocation is expensive (~50us)** — Cache as static let. MessageBubble and ConversationManager were creating new formatters per call.
- **MLMultiArray subscript via NSNumber is slow** — Use `dataPointer.assumingMemoryBound(to: Float.self)` for direct memory access. Applied in CoreMLInference sampleFromLogits.
- **Accelerate.framework vDSP for softmax/argmax** — Replace element-wise loops with vectorized `vDSP_vsdiv`, `vvexpf`, `vDSP_maxvi`, `vDSP_vsorti` for 10-50x speedup on vocab-sized arrays.
- **Token dispatch batching reduces UI overhead** — Dispatching to main queue every 4 tokens instead of every token reduces context switches during fast inference. Flush on newlines for visual responsiveness.
- **Stop sequence checking with suffix optimization** — Only check the tail of generated text (up to max stop sequence length + buffer) instead of full `hasSuffix` on entire string.
- **StreamingDecoder: work with [UInt8] not String** — String concatenation creates new heap allocations. Byte buffer operations with UTF-8 boundary detection are much more efficient.
- **Unicode scalar iteration is faster than Character** — `text.unicodeScalars` avoids grapheme cluster boundary detection overhead. Used in `estimateTokens` for Japanese/CJK classification.
- **PrivateServerManagerTests fail on simulator** — Pre-existing: socket operations and compute capability detection don't work correctly in iOS Simulator. Not a real regression indicator.
