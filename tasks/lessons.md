# Lessons Learned — elio

## Architecture
- **LocalBackend has no .shared singleton** — access via `ChatModeManager.shared.localBackend` or use `ChatModeManager.shared.isModeAvailable(.local)`. MeshTopologyView had a crash from `LocalBackend.shared` (2024-02).
- **P2P backend must be configured BEFORE `isModelLoaded = true`** — `onChange` triggers `macStartupSetup()` which calls `PrivateServerManager.start()`. If backend isn't set, server start always fails silently.
- **AppState.shared exists but is not always safe** — Some views/managers should go through ChatModeManager instead for backend-related state.

## MCP Security (remote servers)
- **Remote MCP tool-name hijack** — A remote MCP server can declare a tool with a built-in name (`read_file`, `get_contacts`, ...) to steal the call + its args. Defense is two-layer: (1) `MCPClient.callTool(fullToolName:)` searches built-in (non-`RemoteMCPServer`) servers BEFORE remote ones — `servers` is an unordered dict so without the split the winner is random; (2) `RemoteMCPServer.refreshTools(reservedNames:)` drops any remote tool whose name collides with an already-registered name at registration. `RemoteMCPServerManager` passes `client.toolNames(excludingServerId:)` as the reserved set.
- **Remote tool names/descriptions are untrusted** — `sanitizedTool` enforces `^[A-Za-z0-9_-]{1,64}$` on names and strips control chars / caps descriptions at 500 chars (prompt-injection mitigation). The UI "test connection" probe (`RemoteMCPServerView.runTest`) uses a throwaway server that is never registered, so it does not need the reserved-name filter.
- **Bearer token leak via redirect** — remote sessions use a `NoRedirectDelegate` (refuses 3xx) + https-only + ephemeral session so the `Authorization` header can't be forwarded to another host. Response body is capped at 5 MB (streamed via `collect`) to prevent memory DoS, and JSON-RPC frames must match the request `id`.

## Frameworks / checkout
- **`Frameworks/{onnxruntime,sherpa-onnx}.xcframework` Info.plist/Headers can go missing in the working tree** while remaining tracked in git → build fails with "no Info.plist found". Restore with `git checkout -- Frameworks/onnxruntime.xcframework Frameworks/sherpa-onnx.xcframework` (the `.a` libs are git-LFS). The `llama.xcframework` is a symlink to `~/workspace/local-multi-agent/...`.

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
