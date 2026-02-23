<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="ElioChat App Icon">
</p>

<h1 align="center">ElioChat</h1>

<p align="center">
  <strong>あなたの秘密を守る、第2の脳</strong>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/elio-chat/id6757635481">
    <img src="https://img.shields.io/badge/App_Store-ダウンロード-blue?logo=apple&logoColor=white" alt="App Store">
  </a>
  <a href="https://elio.love">
    <img src="https://img.shields.io/badge/website-elio.love-purple" alt="Website">
  </a>
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

<p align="center">
  <strong>日本語</strong> | <a href="README.md">English</a>
</p>

---

## 概要

**ElioChat**は、iPhone/iPad上で完全にローカル動作するAIアシスタントアプリです。インターネット接続不要で、プライバシーを完全に保護しながら、カレンダー、リマインダー、連絡先、写真などiOSの機能と連携できます。

### なぜElioChat？ - ChatGPTより安心

| | ElioChat | ChatGPT |
|-----|------|---------|
| **オフライン動作** | 機内モードでもOK | インターネット必須 |
| **データ送信** | ゼロ（完全ローカル） | クラウドに送信 |
| **AI学習への使用** | 使用されない | 学習に使用される可能性 |
| **企業での利用** | 社内規定でChatGPT禁止でもOK | 利用規定による |
| **プライバシー** | 会話は端末内のみ | サーバーに保存 |
| **MCP対応** | 13種類の連携 | 非対応 |
| **P2P推論** | iPhone-Mac連携 | 非対応 |

---

## 機能

### ローカルLLM推論

| カテゴリ | モデル | サイズ |
|----------|--------|--------|
| **おすすめ** | Qwen3 (0.6B-8B), Gemma 3 (1B-4B), Phi-4 Mini | 500MB-5GB |
| **日本語特化** | TinySwallow 1.5B, ELYZA Llama 3 8B, Swallow 8B | 1GB-5.2GB |
| **画像認識** | Qwen3-VL (2B-8B), SmolVLM 2B | 1.1GB-5GB |
| **高効率** | LFM2 (350M-1.2B), Jan Nano (128K/1M) | 350MB-731MB |

- llama.cpp による高速推論（GGUF形式）
- ダウンロード進捗・速度・残り時間をリアルタイム表示
- デバイスに最適なモデルを自動推奨

### MCP (Model Context Protocol) 連携

ElioChatはAnthropicの[Model Context Protocol](https://modelcontextprotocol.io/)に対応した**初のiOSアプリ**です。AIとiOSシステム機能をシームレスに連携させます：

| サーバー | 機能 |
|----------|------|
| カレンダー | 予定の確認・作成・削除 |
| リマインダー | リマインダーの管理 |
| 連絡先 | 連絡先の検索・表示 |
| 位置情報 | 現在地の取得 |
| 写真 | 写真ライブラリへのアクセス |
| ファイル | ドキュメントの読み書き |
| Web検索 | DuckDuckGo匿名検索 |

### P2P推論（iPhone-Mac連携）

重い推論処理をローカルネットワーク経由でMacにオフロード：

- **Bonjour自動検出** - 同一ネットワーク上のMacを自動発見
- **セキュアペアリング** - 4桁コードによる信頼デバイス認証
- **自動再接続** - 信頼済みデバイスはアプリ起動時に自動接続
- **投機的デコード** - 小型モデルをローカル + 大型モデルをMacで実行し高速化
- **プライベートサーバー** - Macが `_eliochat._tcp` で推論サーバーとして動作
- **メッシュネットワーク** - 複数デバイスでP2P推論メッシュを構成

### チャットモード

| モード | 説明 |
|--------|------|
| **ローカル** | 端末上のみで推論（完全オフライン） |
| **クラウド** | ChatWeb API / Groq クラウドバックエンド |
| **プライベートP2P** | Macの推論パワーを活用 |
| **P2Pメッシュ** | 複数デバイスで協調推論 |
| **投機的** | ローカル下書き + リモート検証で高速化 |

### Vision（画像認識）

- 画像を添付してAIに質問可能
- カメラで撮影した写真をその場で分析
- Qwen3-VL（2B/4B/8B）、SmolVLMをサポート
- Visionモデルの自動ダウンロード提案

### 音声入力

- WhisperKitによるオンデバイス音声認識
- 日本語・英語対応
- 一度ダウンロードしたモデルはキャッシュ保存

### UI/UX

- ダーク/ライトモード対応
- リアルタイムストリーミング表示
- 会話履歴の保存・管理
- **会話検索機能** - 過去の会話をすぐに見つける
- **シェアカード** - SNS用の美しい会話画像を作成
- **会話エクスポート** - テキストやJSON形式で保存
- **Siriショートカット** - 「Hey Siri、ElioChatに聞いて」

---

## インストール

### App Storeからダウンロード

[App Store](https://apps.apple.com/app/elio-chat/id6757635481)から無料でダウンロード（広告なし）。

### ソースからビルド

**必要要件**: iOS 17.0以上、Xcode 15.0以上

```bash
git clone https://github.com/yukihamada/LocalAIAgent.git
cd LocalAIAgent
open ElioChat.xcodeproj
```

1. Xcode で Signing & Capabilities を設定
2. 実機を接続して Run (Cmd+R)

### テストの実行

```bash
# ユニットテスト（135テスト）
xcodebuild test -project ElioChat.xcodeproj -scheme ElioChat \
  -testPlan UnitTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 対応モデル

30以上のGGUF形式モデルに対応：

### おすすめ
| モデル | サイズ | 特徴 |
|--------|--------|------|
| Qwen3 0.6B | ~500MB | 全デバイス、超高速 |
| Qwen3 1.7B | ~1.2GB | 全デバイス、バランス良好 |
| Qwen3 4B | ~2.7GB | Pro以上、高性能 |
| Qwen3 8B | ~5GB | Pro Max、最高品質 |
| Gemma 3 1B | ~700MB | 全デバイス、Google最新 |
| Gemma 3 4B | ~2.5GB | Pro以上、優秀 |
| Phi-4 Mini | ~2.4GB | Pro以上、推論最強 |

### 日本語特化
| モデル | サイズ | 備考 |
|--------|--------|------|
| TinySwallow 1.5B | ~986MB | Sakana AI製、高品質 |
| ELYZA Llama 3 8B | ~5.2GB | 東大松尾研、最高峰 |
| Swallow 8B | ~5.2GB | 東工大、ビジネス文書 |

### 画像認識モデル
| モデル | サイズ | 備考 |
|--------|--------|------|
| Qwen3-VL 2B | ~1.1GB | 全デバイス |
| Qwen3-VL 4B | ~2.5GB | Pro以上 |
| Qwen3-VL 8B | ~5GB | Pro Max、最高品質 |

---

## アーキテクチャ

```
LocalAIAgent/
├── App/                    # アプリケーション層
│   ├── LocalAIAgentApp.swift
│   ├── AppState.swift      # グローバル状態管理
│   └── AppIntents.swift    # Siriショートカット
├── Agent/                  # AIエージェント
│   ├── AgentOrchestrator.swift
│   ├── ConversationManager.swift
│   └── ToolParser.swift
├── LLM/                    # 推論エンジン
│   ├── ModelLoader.swift   # モデル管理・ダウンロード
│   ├── CoreMLInference.swift
│   ├── WhisperManager.swift
│   └── Tokenizer.swift
├── ChatModes/              # マルチバックエンドチャットシステム
│   ├── ChatModeManager.swift
│   ├── Backends/           # Local, Cloud, P2P, Speculative
│   └── P2PServer/          # プライベートサーバー・メッシュ
├── Discovery/              # デバイス検出（Bonjour/QR）
├── MCP/                    # Model Context Protocol
│   ├── MCPClient.swift
│   └── Servers/            # カレンダー、リマインダー等
├── Security/               # デバイスID・キーチェーン
├── TokenEconomy/           # サブスクリプション・トークン管理
├── Views/                  # SwiftUI画面
└── Resources/              # アセット・ローカライズ
```

---

## プライバシー

ElioChatはプライバシーファーストで設計されています。

- **すべての処理が端末上で完結**
- **外部サーバーへのデータ送信なし**
- **会話履歴は端末内にのみ保存**
- **P2P接続はローカルネットワーク内のみ**
- **オープンソース** - コードを確認可能

### 必要な権限

| 権限 | 用途 |
|------|------|
| カレンダー | 予定の読み書き |
| リマインダー | リマインダーの管理 |
| 連絡先 | 連絡先の検索 |
| 位置情報 | 現在地の取得 |
| 写真 | 画像の読み込み・保存 |
| マイク | 音声入力 |
| ローカルネットワーク | P2Pデバイス検出 |

すべての権限は必要に応じてユーザーに許可を求めます。

---

## コントリビュート

プルリクエストを歓迎します！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチをプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

---

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照してください。

---

## リンク

- [ウェブサイト](https://elio.love)
- [プライバシーポリシー](https://elio.love/privacy)
- [利用規約](https://elio.love/terms)

## 謝辞

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF推論エンジン
- [Model Context Protocol](https://modelcontextprotocol.io/) - AI連携プロトコル
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - オンデバイス音声認識

---

<p align="center">
  Made with love by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
