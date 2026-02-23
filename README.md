<p align="center">
  <img src="LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" height="120" alt="ElioChat">
</p>

<h1 align="center">ElioChat</h1>

<p align="center">
  <strong>あなたの秘密を守る、第2の脳。</strong><br>
  完全無料・広告なし・オフライン対応のプライベートAIチャット
</p>

<p align="center">
  <a href="https://apps.apple.com/app/elio-chat/id6757635481">
    <img src="https://img.shields.io/badge/App_Store-無料ダウンロード-0D96F6?style=for-the-badge&logo=apple&logoColor=white" alt="App Store">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-000000?style=flat-square&logo=apple" alt="iOS 17+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/Models-30%2B-blue?style=flat-square" alt="30+ Models">
  <img src="https://img.shields.io/badge/MCP-13_servers-purple?style=flat-square" alt="MCP">
</p>

<p align="center">
  <strong>日本語</strong> | <a href="README.en.md">English</a>
</p>

---

## アプリの様子

<p align="center">
  <img src="fastlane/screenshots_final/ja/iPhone 16 Pro Max-01_WelcomeScreen.png" width="19%" alt="ウェルカム">
  <img src="fastlane/screenshots_final/ja/iPhone 16 Pro Max-02_ChatSchedule.png" width="19%" alt="予定管理">
  <img src="fastlane/screenshots_final/ja/iPhone 16 Pro Max-03_ChatCode.png" width="19%" alt="コード支援">
  <img src="fastlane/screenshots_final/ja/iPhone 16 Pro Max-05_ChatPrivacy.png" width="19%" alt="プライバシー">
  <img src="fastlane/screenshots_final/ja/iPhone 16 Pro Max-08_Settings.png" width="19%" alt="モデル選択">
</p>

---

## ElioChatでできること

### 1. 機内モードでもAIと会話

```
あなた: 今日の会議の議事録をまとめて

ElioChat: 承知しました。以下の形式でまとめます：
  日時: 2月23日 14:00-15:00
  参加者: 田中、佐藤、山田
  議題: Q1売上報告...
```

インターネット不要。飛行機の中でも、地下鉄でも、山の中でも動きます。
すべての処理がiPhone上で完結するため、データが外部に漏れることはありません。

### 2. カレンダー・リマインダーをAIで操作

```
あなた: 今日の予定を教えて

ElioChat: カレンダーを確認しました。本日の予定：
  10:00 - チーム定例
  12:00 - 佐藤さんとランチ
  14:00 - プロジェクトレビュー
  16:00 - クライアント電話
```

```
あなた: 明日10時にゴミ出しのリマインダー作って

ElioChat: リマインダーを作成しました：
  ゴミ出し - 明日 10:00
```

iOS標準のカレンダー・リマインダー・連絡先・写真と直接連携。
[MCP（Model Context Protocol）](https://modelcontextprotocol.io/) 対応の世界初iOSアプリです。

### 3. 30以上のAIモデルから選べる

| おすすめ | 日本語特化 | 画像認識 |
|:--------:|:----------:|:--------:|
| Qwen3 (0.6B-8B) | TinySwallow 1.5B | Qwen3-VL (2B-8B) |
| Gemma 3 (1B-4B) | ELYZA Llama 3 8B | SmolVLM 2B |
| Phi-4 Mini | Swallow 8B | |

デバイスに合わせて最適なモデルを自動推奨。GGUF形式対応で高速推論。

### 4. 写真をAIに見せて質問

```
あなた: [写真を添付] これは何の花？

ElioChat: これはソメイヨシノ（桜）です。
  開花時期は3月下旬〜4月上旬で...
```

カメラで撮影した写真やライブラリの画像をその場で分析。
Qwen3-VL / SmolVLM による画像認識AIを搭載。

### 5. 音声で入力

WhisperKit によるオンデバイス音声認識。
日本語・英語対応。音声データも外部送信なし。

### 6. Macの推論パワーを借りる（P2P推論）

```
┌──────────┐     WiFi / LAN      ┌──────────┐
│  iPhone  │ ◄──────────────────► │   Mac    │
│ 小型モデル │   Bonjour自動検出    │ 大型モデル │
│  で下書き  │   暗号化P2P接続     │  で検証   │
└──────────┘                     └──────────┘
```

- 同一ネットワーク上のMacを自動発見
- 4桁コードでセキュアにペアリング
- 次回以降は自動接続
- 投機的デコードで高速化（ローカル下書き + Mac検証）

---

## ChatGPTとの比較

|  | ElioChat | ChatGPT |
|:---|:---:|:---:|
| オフライン動作 | 機内モードOK | ネット必須 |
| データ送信 | ゼロ | クラウドに送信 |
| AI学習に使用 | されない | される可能性あり |
| 企業利用 | ChatGPT禁止企業でもOK | 規定による |
| 会話の保存先 | 端末内のみ | サーバーに保存 |
| MCP連携 | 13種類 | 非対応 |
| P2P推論 | Mac連携可能 | 非対応 |
| 料金 | 完全無料 | 月額$20 |

---

## こんな人におすすめ

- **会社の機密情報を扱う人** - ChatGPT禁止の企業でも安心
- **飛行機・地下鉄でAIを使いたい人** - 圏外でも動作
- **プライバシーを重視する人** - データ送信ゼロ
- **日本語でAIを使いたい人** - 日本語特化モデル搭載
- **AIとカレンダーを連携させたい人** - MCP対応

---

## 動作環境

| デバイス | 推奨モデル |
|----------|-----------|
| iPhone 12 以降 | Qwen3 0.6B - 1.7B |
| iPhone 14 Pro 以降 | Qwen3 4B, Gemma 3 4B |
| iPhone 15 Pro Max | Qwen3 8B, ELYZA 8B |
| iPad (M1以降) | 全モデル対応 |

---

## 開発者向け

### ビルド

```bash
git clone https://github.com/yukihamada/elio.git
cd elio
open ElioChat.xcodeproj
```

1. Xcode で Signing & Capabilities を設定
2. 実機を接続して Cmd+R

### テスト

```bash
# 135件のユニットテスト
xcodebuild test -project ElioChat.xcodeproj -scheme ElioChat \
  -testPlan UnitTests -destination 'platform=iOS Simulator,name=iPhone 16'
```

### アーキテクチャ

```
LocalAIAgent/
├── App/            アプリケーション層（AppState, Siri Shortcuts）
├── Agent/          AIエージェント（Orchestrator, ToolParser）
├── LLM/            推論エンジン（llama.cpp, WhisperKit）
├── ChatModes/      マルチバックエンド（Local, Cloud, P2P, Speculative）
│   ├── Backends/   各バックエンド実装
│   └── P2PServer/  プライベートサーバー・メッシュ
├── Discovery/      デバイス検出（Bonjour / QR）
├── MCP/            Model Context Protocol（13サーバー）
├── Security/       デバイスID・キーチェーン
├── TokenEconomy/   サブスクリプション・トークン
├── Views/          SwiftUI画面
└── Resources/      アセット・ローカライズ
```

### チャットモード

| モード | 説明 |
|--------|------|
| Local | 端末上のみで推論（完全オフライン） |
| Cloud | ChatWeb API / Groq |
| Private P2P | Macの推論パワーを活用 |
| P2P Mesh | 複数デバイスで協調推論 |
| Speculative | ローカル下書き + リモート検証 |

---

## リンク

|  |  |
|:--|:--|
| 公式サイト | [elio.love](https://elio.love) |
| App Store | [ダウンロード](https://apps.apple.com/app/elio-chat/id6757635481) |
| プライバシーポリシー | [elio.love/privacy](https://elio.love/privacy) |
| 利用規約 | [elio.love/terms](https://elio.love/terms) |

## 謝辞

- [llama.cpp](https://github.com/ggerganov/llama.cpp) - GGUF推論エンジン
- [Model Context Protocol](https://modelcontextprotocol.io/) - AI連携プロトコル
- [WhisperKit](https://github.com/argmaxinc/WhisperKit) - オンデバイス音声認識

## ライセンス

MIT License - [LICENSE](LICENSE)

---

<p align="center">
  Made with love by <a href="https://github.com/yukihamada">yukihamada</a>
</p>
