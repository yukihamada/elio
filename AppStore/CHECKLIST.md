# App Store 提出チェックリスト

## コード側（完了済み ✅）
- [x] ビルド成功
- [x] テスト53件パス
- [x] Info.plist - ローカルネットワーク説明
- [x] Info.plist - Bonjourサービス
- [x] Entitlements - In-App Purchase
- [x] プライバシーポリシー（アプリ内）
- [x] 利用規約（アプリ内）
- [x] StoreKit設定ファイル

---

## App Store Connect（手動作業）

### 1. サブスクリプション作成
場所: App Store Connect > アプリ > サブスクリプション

```
グループ名: ElioChat Premium

Basic:
- Product ID: love.elio.subscription.basic
- 価格: ¥500/月
- 説明: 1,000トークン/月

Pro:
- Product ID: love.elio.subscription.pro
- 価格: ¥1,500/月
- 説明: 5,000トークン/月
```

### 2. アプリ情報入力
場所: App Store Connect > アプリ > App Store > アプリ情報

- [ ] サブタイトル: `Subtitle.txt` からコピー
- [ ] プライバシーポリシーURL: `https://elio.love/privacy`

### 3. バージョン情報入力
場所: App Store Connect > アプリ > App Store > バージョン

- [ ] スクリーンショット（6.7インチ、6.5インチ、5.5インチ）
- [ ] 説明文: `Description_ja.txt` からコピー
- [ ] キーワード: `Keywords.txt` からコピー
- [ ] 新機能: `WhatsNew.txt` からコピー

### 4. 審査情報
場所: App Store Connect > アプリ > App Store > バージョン > 審査に関する情報

- [ ] 審査メモ: `ReviewNotes.txt` からコピー
- [ ] 連絡先: support@elio.love

### 5. プライバシーポリシー公開
- [ ] `privacy.html` をWebサーバーにアップロード
- [ ] `terms.html` をWebサーバーにアップロード
- [ ] URLをApp Store Connectに設定

---

## ファイル一覧

```
AppStore/
├── CHECKLIST.md          # このファイル
├── Description_ja.txt    # 説明文（日本語）
├── Description_en.txt    # 説明文（英語）
├── Keywords.txt          # キーワード
├── WhatsNew.txt          # 新機能
├── Subtitle.txt          # サブタイトル
├── ReviewNotes.txt       # 審査メモ
├── SubscriptionInfo.txt  # サブスク設定
├── privacy.html          # プライバシーポリシー（Web用）
└── terms.html            # 利用規約（Web用）
```

---

## 提出コマンド

```bash
# アーカイブ作成
xcodebuild archive -scheme ElioChat -archivePath build/ElioChat.xcarchive

# App Store用エクスポート
xcodebuild -exportArchive -archivePath build/ElioChat.xcarchive -exportPath build/AppStore -exportOptionsPlist ExportOptions.plist

# または Xcode > Product > Archive から提出
```
