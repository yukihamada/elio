# ElioChat v1.2.38 (Build 49) リリースノート

## 日本語

### バグ修正・改善

#### 1. LLM推論のUIフリーズを修正
オンデバイスAI推論（LlamaInference）がメインスレッドをブロックし、トークン生成中にUIがフリーズする問題を修正しました。推論ループ全体を専用のバックグラウンドキューに移動し、トークンコールバックはメインキューにディスパッチするようにしました。これにより、長文生成中もスムーズにスクロール・操作できます。

#### 2. Web検索のセマフォデッドロックを修正
WebSearchServerのネットワーク接続チェックが、毎回NWPathMonitorを生成しセマフォで同期的にブロックしていた問題を修正しました。共有NetworkMonitorインスタンスを使用するasyncメソッドに変更し、デッドロックのリスクとリソースリークを解消しました。

#### 3. Mac Catalyst対応の強化
- KokoroTTS・ReazonSpeech のMac Catalystスタブを追加（コンパイルエラー解消）
- onnxruntime/sherpa-onnx フレームワークをiOS限定に設定（macOSビルドエラー解消）
- ブリッジングヘッダーに `TargetConditionals.h` を追加
- App Sandbox エンタイトルメントを有効化（Mac App Store要件）
- QRスキャン画面にMac用手動入力UIを追加

### 新機能
- **Elio ID**: 各デバイスに `XXXX-XXXX` 形式の短い識別子を割り当て、P2Pフレンド検索に対応
- **チャットView最適化**: StreamingBufferパターンでトークンストリーミング中のSwiftUI再評価を削減
- **DMドラフト保存**: ダイレクトチャットの入力中テキストを会話ごとに自動保存・復元
- **キーボードショートカット**: Cmd+K でConnect画面を表示（Mac Catalyst）
- **アプリカテゴリ**: Productivity に設定（Mac App Store表示用）

---

## English

### Bug Fixes & Improvements

#### 1. Fixed UI freeze during on-device LLM inference
Resolved an issue where on-device AI inference (LlamaInference) blocked the main thread, causing the UI to freeze during token generation. The entire inference loop has been moved to a dedicated background DispatchQueue, with token callbacks dispatched to the main queue. Scrolling and interaction now remain smooth during long text generation.

#### 2. Fixed semaphore deadlock in web search
Resolved an issue where WebSearchServer's network connectivity check created a new NWPathMonitor and blocked synchronously with a semaphore on every call. Replaced with an async method using a shared NetworkMonitor instance, eliminating deadlock risk and resource leaks.

#### 3. Enhanced Mac Catalyst support
- Added Mac Catalyst stubs for KokoroTTS and ReazonSpeech (fixes compilation errors)
- Set onnxruntime/sherpa-onnx frameworks to iOS-only (fixes macOS build errors)
- Added `TargetConditionals.h` to bridging header
- Enabled App Sandbox entitlement (required for Mac App Store)
- Added manual code input UI for QR scan screen on Mac

### New Features
- **Elio ID**: Assigns each device a short `XXXX-XXXX` identifier for P2P friend discovery
- **Chat view optimization**: StreamingBuffer pattern reduces SwiftUI re-evaluation during token streaming
- **DM draft persistence**: Auto-saves and restores in-progress text per direct chat conversation
- **Keyboard shortcut**: Cmd+K opens the Connect screen (Mac Catalyst)
- **App category**: Set to Productivity for Mac App Store listing
