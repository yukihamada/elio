<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="Elio App Icon">
</p>

<h1 align="center">Elio</h1>

<p align="center">
  <strong>あなたの秘密を守る、第2の脳</strong>
</p>

<p align="center">
  <a href="https://elio.love">🌐 ウェブサイト</a> •
  <a href="#features">機能</a> •
  <a href="#installation">インストール</a> •
  <a href="#supported-models">モデル</a> •
  <a href="#mcp-integration">MCP</a> •
  <a href="#privacy">プライバシー</a> •
  <a href="#license">ライセンス</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/website-elio.love-purple" alt="Website">
</p>

<p align="center">
  <strong>🇯🇵 日本語</strong> | <a href="README.md">🇺🇸 English</a>
</p>

---

## 概要

**Elio**は、iPhone上で完全にローカル動作するAIアシスタントアプリです。インターネット接続不要で、プライバシーを完全に保護しながら、カレンダー、リマインダー、連絡先、ヘルスケアなどiOSの機能と連携できます。

### なぜElio？ - ChatGPTより安心

| | Elio | ChatGPT |
|-----|------|---------|
| **オフライン動作** | ✅ 機内モードでもOK | ❌ インターネット必須 |
| **データ送信** | ✅ ゼロ（完全ローカル） | ❌ クラウドに送信 |
| **AI学習への使用** | ✅ 使用されない | ⚠️ 学習に使用される可能性 |
| **企業での利用** | ✅ 社内規定でChatGPT禁止でもOK | ⚠️ 利用規定による |
| **プライバシー** | ✅ 会話は端末内のみ | ❌ サーバーに保存 |

- **MCP対応** - Model Context Protocolでシステム機能と連携
- **複数モデル対応** - Qwen3、Llama 3.2、Gemmaなど好みのモデルを選択
- **日本語対応** - UIとAI応答の両方で日本語をサポート

---

## 機能

### 🧠 ローカルLLM推論

| モデル | サイズ | 特徴 |
|--------|--------|------|
| Qwen3 4B | ~2.7GB | 高性能、日本語優秀 |
| Qwen3 8B | ~5GB | 最高性能 |
| Llama 3.2 3B | ~2GB | 軽量・高速 |
| Gemma 2 2B | ~1.5GB | 超軽量 |

- llama.cpp による高速推論
- CoreML最適化（対応モデル）
- ストリーミング出力

### 🔌 MCP (Model Context Protocol) 連携

Elioは以下のiOS機能とAIを連携させます：

| サーバー | 機能 |
|----------|------|
| 📅 Calendar | 予定の確認・作成・削除 |
| ✅ Reminders | リマインダーの管理 |
| 👥 Contacts | 連絡先の検索・表示 |
| 📍 Location | 現在地の取得 |
| 🏥 Health | ヘルスケアデータの読み取り |
| 📷 Photos | 写真ライブラリへのアクセス |
| 📁 FileSystem | ドキュメントの読み書き |
| 🔍 Web Search | DuckDuckGo匿名検索 |

### 🖼️ Vision（画像認識）

- 画像を添付してAIに質問可能
- カメラで撮影した写真をその場で分析
- Vision対応モデル（Llava、Qwen2-VLなど）をサポート

### 🎤 音声入力

- WhisperKitによるオンデバイス音声認識
- 日本語・英語対応
- 初回使用時にモデルを自動ダウンロード

### 🎨 UI/UX

- ダーク/ライトモード対応
- スワイプで操作できるオンボーディング
- リアルタイムストリーミング表示
- 会話履歴の保存・管理
- スケルトンローディングで高速な体感起動
- **会話検索機能** - 過去の会話をすぐに見つける
- **シェアカード** - SNS用の美しい会話画像を作成

### 📱 Siriショートカット

音声でElioを操作：
- 「Hey Siri、Elioに聞いて」- 会話を開始
- 「Hey Siri、Elioで予定を確認」- カレンダーを見る
- 「Hey Siri、Elioで天気を確認」- 天気をチェック
- 「Hey Siri、Elioでリマインダー作成」- リマインダー追加

### 👥 紹介プログラム

友達にElioをシェア：
- あなた専用の紹介コードを生成
- ワンタップでシェア
- 紹介した人数を確認

---

## インストール

### 必要要件

- iOS 17.0以上
- iPhone（arm64）
- Xcode 15.0以上

### ビルド手順

```bash
# リポジトリをクローン
git clone https://github.com/yukihamada/elio.git
cd elio

# Xcodeで開く
open LocalAIAgent.xcodeproj
```

1. Xcode で Signing & Capabilities を設定
2. 実機を接続して Run (⌘R)

### モデルのダウンロード

アプリ内の設定画面からモデルをダウンロードできます。初回起動時に推奨モデル（Qwen3 4B）の案内が表示されます。

---

## 対応モデル

Elioは GGUF 形式のモデルに対応しています。

```
推奨: Qwen3-4B-Q4_K_M.gguf
- バランスの取れた性能
- 日本語応答が優秀
- ~2.7GB のストレージ
```

### 対応フォーマット

- GGUF (llama.cpp)
- CoreML (一部モデル)

---

## MCP連携

ElioはAnthropicの[Model Context Protocol](https://modelcontextprotocol.io/)を採用し、AIとiOSシステム機能をシームレスに連携させます。

### 使用例

```
ユーザー: 今日の予定を教えて

Elio: カレンダーを確認しました。今日の予定は以下の通りです：
• 10:00 - 11:30 週次デザイン定例
• 13:00 - 14:00 ランチミーティング w/ 佐藤さん
• 16:00 - 17:30 プロジェクトX 進捗報告会
```

```
ユーザー: 明日の午前10時に「歯医者」のリマインダーを作成して

Elio: リマインダーを作成しました：
📋 歯医者
📅 明日 10:00
```

---

## プライバシー

Elioはプライバシーファーストで設計されています。

- ✅ **すべての処理が端末上で完結**
- ✅ **外部サーバーへのデータ送信なし**
- ✅ **会話履歴は端末内にのみ保存**
- ✅ **オープンソース** - コードを確認可能

### 必要な権限

| 権限 | 用途 |
|------|------|
| カレンダー | 予定の読み書き |
| リマインダー | リマインダーの管理 |
| 連絡先 | 連絡先の検索 |
| 位置情報 | 現在地の取得 |
| ヘルスケア | 健康データの読み取り |
| 写真 | 画像の読み込み・保存 |
| マイク | 音声入力 |

すべての権限は必要に応じてユーザーに許可を求めます。

---

## アーキテクチャ

```
LocalAIAgent/
├── App/                    # アプリケーション層
│   ├── LocalAIAgentApp.swift
│   ├── AppState.swift      # 状態管理
│   └── ThemeManager.swift
├── Agent/                  # AIエージェント
│   ├── AgentOrchestrator.swift
│   ├── ConversationManager.swift
│   └── ToolParser.swift
├── LLM/                    # 推論エンジン
│   ├── LlamaInference.swift
│   ├── CoreMLInference.swift
│   ├── ModelLoader.swift
│   ├── WhisperManager.swift
│   └── Tokenizer.swift
├── MCP/                    # MCPプロトコル
│   ├── MCPClient.swift
│   ├── MCPProtocol.swift
│   └── Servers/           # MCPサーバー実装
├── Models/                 # データモデル
├── Views/                  # SwiftUI画面
└── Resources/              # アセット・ローカライズ
```

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

## 謝辞

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF推論エンジン
- [Model Context Protocol](https://modelcontextprotocol.io/) - AI連携プロトコル
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - オンデバイス音声認識

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
