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
- **P2PServer struct fields**: `id: String`, `name: String`, `endpoint: NWEndpoint`, `pairingCode: String?` — No `deviceId`, `isOnline`, `lastSeen`, or `isTrusted` fields. ProximityDiscoveryManager had broken init with wrong fields.
- **connectToServer(url:) does not exist** on P2PBackend — use `connect(to: P2PServer)` instead.
