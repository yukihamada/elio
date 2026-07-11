#!/usr/bin/env python3
"""
generate_elio_tools.py — ElioChat iOS MCP ツール専用データ生成
==============================================================
ElioChat の実装ツール（13 MCP サーバー）に特化した
現実的なマルチターン会話データを生成する。

ツール名は ElioChat の実装と完全一致させること。
"""
import json, os, re, sys, time, argparse, random, hashlib, requests
random.seed(88)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPT = "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。"

# ElioChat の実ツール（MCPサーバー実装と完全一致）
ELIO_TOOLS = {
    # === WebSearchServer ===
    "web_search": {
        "server": "websearch",
        "desc": "DuckDuckGo でウェブ検索（プライバシー重視）",
        "args_example": '{"query": "東京 桜 2025 見頃"}',
        "result_example": '{"results": [{"title": "2025年東京の桜開花予想", "url": "https://example.com", "snippet": "東京の桜の見頃は3月下旬〜4月上旬と予想されます..."}, {"title": "上野公園の桜情報", "url": "https://ueno.jp/sakura", "snippet": "上野公園では例年3000本の桜が..."}]}',
        "scenarios": [
            "今日の東京の桜の開花状況を調べてください",
            "最新のAIニュースを検索してください",
            "近くにおすすめのカフェを調べてください",
            "明日の東京マラソンの情報を教えてください",
            "Python 3.13の新機能を検索してください",
        ],
    },

    # === CalendarServer ===
    "list_events": {
        "server": "calendar",
        "desc": "カレンダーのイベント一覧を取得（iCloud/Google/Exchange対応）",
        "args_example": '{"start_date": "2025-03-06", "end_date": "2025-03-13", "calendar_name": null}',
        "result_example": '{"events": [{"id": "evt001", "title": "週次MTG", "start": "2025-03-10T10:00:00+09:00", "end": "2025-03-10T11:00:00+09:00", "calendar": "仕事", "location": "会議室A"}, {"id": "evt002", "title": "歯医者", "start": "2025-03-11T14:00:00+09:00", "end": "2025-03-11T15:00:00+09:00", "calendar": "個人"}]}',
        "scenarios": [
            "今週のスケジュールを教えてください",
            "来週の予定を確認してください",
            "今日の予定は何がありますか？",
            "今月のイベントをリストアップしてください",
            "仕事のカレンダーを見せてください",
        ],
    },
    "create_event": {
        "server": "calendar",
        "desc": "カレンダーに新しいイベントを作成",
        "args_example": '{"title": "チームMTG", "start_date": "2025-03-10", "start_time": "14:00", "end_time": "15:00", "calendar_name": "仕事", "location": "オンライン", "notes": "四半期レビュー"}',
        "result_example": '{"success": true, "event_id": "evt_new_001", "title": "チームMTG", "start": "2025-03-10T14:00:00+09:00", "calendar": "仕事"}',
        "scenarios": [
            "来週の火曜日14時に歯医者の予約を入れてください",
            "明日の朝9時にチームミーティングを設定してください",
            "3月15日に誕生日パーティーをカレンダーに追加してください",
            "毎週月曜日10時にランニングを登録してください",
        ],
    },
    "list_calendars": {
        "server": "calendar",
        "desc": "利用可能なカレンダー一覧を取得",
        "args_example": '{}',
        "result_example": '{"calendars": [{"name": "仕事", "type": "exchange", "color": "blue"}, {"name": "個人", "type": "icloud", "color": "red"}, {"name": "家族", "type": "google", "color": "green"}]}',
        "scenarios": [
            "どんなカレンダーがありますか？",
            "カレンダーの一覧を見せてください",
            "仕事用と個人用のカレンダーは分けていますか？",
        ],
    },

    # === RemindersServer ===
    "list_reminders": {
        "server": "reminders",
        "desc": "リマインダーの一覧を取得（未完了・完了でフィルタ可）",
        "args_example": '{"list_name": null, "completed": false}',
        "result_example": '{"reminders": [{"id": "rem001", "title": "レポート提出", "due_date": "2025-03-08T17:00:00+09:00", "priority": "high", "notes": "部長に送付"}, {"id": "rem002", "title": "薬を飲む", "due_date": "2025-03-06T21:00:00+09:00", "priority": "medium"}]}',
        "scenarios": [
            "今日のリマインダーを教えてください",
            "未完了のタスクを全部見せてください",
            "買い物リストを確認してください",
            "優先度の高いリマインダーはありますか？",
        ],
    },
    "create_reminder": {
        "server": "reminders",
        "desc": "新しいリマインダーを作成",
        "args_example": '{"title": "プレゼン資料作成", "due_date": "2025-03-10", "due_time": "10:00", "priority": "high", "notes": "CEO向け", "list_name": "仕事"}',
        "result_example": '{"success": true, "reminder_id": "rem_new_001", "title": "プレゼン資料作成", "due": "2025-03-10T10:00:00+09:00"}',
        "scenarios": [
            "明日の朝8時に薬を飲むリマインダーを作ってください",
            "来週月曜日までに報告書を提出するリマインダーを高優先で設定して",
            "牛乳を買うことを買い物リストに追加してください",
            "3日後に誕生日プレゼントを送るリマインダーをセットして",
        ],
    },
    "complete_reminder": {
        "server": "reminders",
        "desc": "リマインダーを完了済みにする",
        "args_example": '{"reminder_id": "rem001"}',
        "result_example": '{"success": true, "reminder_id": "rem001", "title": "レポート提出", "completed": true}',
        "scenarios": [
            "レポートを提出したのでリマインダーを完了にしてください",
            "このタスクを完了済みにしてください",
        ],
    },

    # === WeatherServer ===
    "get_current_weather": {
        "server": "weather",
        "desc": "現在地または指定場所の現在の天気を取得（Apple WeatherKit）",
        "args_example": '{"location": "東京"}',
        "result_example": '{"location": "東京都千代田区", "temperature": 15.2, "feels_like": 13.1, "condition": "晴れ", "humidity": 52, "wind_speed": 8.3, "wind_direction": "北西", "uv_index": 3, "visibility": 10.0, "timestamp": "2025-03-06T20:00:00+09:00"}',
        "scenarios": [
            "今の天気を教えてください",
            "大阪の現在の気温は？",
            "外に出るのに適した服装を教えてください。今の天気は？",
            "今日は傘が必要ですか？",
            "札幌の天気はどうですか？",
        ],
    },
    "get_forecast": {
        "server": "weather",
        "desc": "7〜10日間の天気予報を取得",
        "args_example": '{"location": "東京", "days": 7}',
        "result_example": '{"location": "東京", "forecast": [{"date": "2025-03-07", "high": 18, "low": 8, "condition": "晴れのち曇り", "precipitation_chance": 20}, {"date": "2025-03-08", "high": 14, "low": 7, "condition": "雨", "precipitation_chance": 80}, {"date": "2025-03-09", "high": 16, "low": 9, "condition": "曇り", "precipitation_chance": 40}]}',
        "scenarios": [
            "今週末の天気予報を教えてください",
            "来週のお花見に向けて天気を確認したい",
            "3日間の天気を教えてください",
            "週末はバーベキューできますか？天気は？",
        ],
    },

    # === ContactsServer ===
    "search_contacts": {
        "server": "contacts",
        "desc": "連絡先を名前・電話番号・メールで検索",
        "args_example": '{"query": "田中"}',
        "result_example": '{"contacts": [{"id": "con001", "name": "田中 太郎", "phone": ["090-1234-5678"], "email": ["taro@example.com"], "company": "株式会社ABC"}, {"id": "con002", "name": "田中 花子", "phone": ["080-9876-5432"], "email": ["hanako@xyz.co.jp"]}]}',
        "scenarios": [
            "田中さんの電話番号を調べてください",
            "山田さんのメールアドレスを確認してください",
            "スミスさんの連絡先を探してください",
            "会社名でABCの担当者を検索してください",
        ],
    },
    "get_contact": {
        "server": "contacts",
        "desc": "特定の連絡先の詳細情報を取得",
        "args_example": '{"contact_id": "con001"}',
        "result_example": '{"id": "con001", "name": "田中 太郎", "phone": ["090-1234-5678", "03-1234-5678"], "email": ["taro@example.com", "tanaka@company.co.jp"], "company": "株式会社ABC", "title": "営業部長", "address": "東京都渋谷区...", "birthday": "1985-04-15", "notes": "Golf好き"}',
        "scenarios": [
            "田中さんの詳しい連絡先を教えてください",
            "この連絡先の全情報を確認したい",
        ],
    },

    # === LocationServer ===
    "get_current_location": {
        "server": "location",
        "desc": "現在地の緯度・経度・住所を取得（GPS）",
        "args_example": '{}',
        "result_example": '{"latitude": 35.6894, "longitude": 139.6917, "accuracy": 10.0, "address": "東京都渋谷区渋谷2丁目", "city": "渋谷区", "prefecture": "東京都", "country": "日本"}',
        "scenarios": [
            "今どこにいますか？",
            "現在地を教えてください",
            "近くのコンビニを探したい。今の場所は？",
            "今いる場所の住所を教えて",
        ],
    },
    "reverse_geocode": {
        "server": "location",
        "desc": "緯度・経度から住所に変換",
        "args_example": '{"latitude": 35.6586, "longitude": 139.7454}',
        "result_example": '{"address": "東京都港区芝公園4丁目2-8", "landmark": "東京タワー", "city": "港区", "prefecture": "東京都"}',
        "scenarios": [
            "この座標の住所を教えてください",
            "緯度経度から場所名を調べてください",
        ],
    },

    # === NotesServer ===
    "list_notes": {
        "server": "notes",
        "desc": "Apple メモの一覧を取得（フォルダでフィルタ可）",
        "args_example": '{"folder": null, "limit": 10}',
        "result_example": '{"notes": [{"id": "note001", "title": "会議メモ 2025/03/05", "preview": "議題: Q1レビュー、参加者: ...", "created": "2025-03-05T14:30:00+09:00", "modified": "2025-03-05T15:45:00+09:00", "folder": "仕事"}, {"id": "note002", "title": "買い物リスト", "preview": "牛乳、卵、パン...", "folder": "個人"}]}',
        "scenarios": [
            "最近のメモを見せてください",
            "仕事フォルダのメモを確認したい",
            "昨日書いたメモを探してください",
            "会議のメモはどこにありますか？",
        ],
    },
    "create_note": {
        "server": "notes",
        "desc": "新しいメモを作成",
        "args_example": '{"title": "アイデアメモ", "content": "## 新機能のアイデア\\n1. ダークモード追加\\n2. 音声入力対応\\n3. ...", "folder": "仕事"}',
        "result_example": '{"success": true, "note_id": "note_new_001", "title": "アイデアメモ", "folder": "仕事", "created": "2025-03-06T20:00:00+09:00"}',
        "scenarios": [
            "今日のミーティングのメモを作成してください",
            "アイデアをメモに残したい",
            "買い物リストをメモに書いてください",
            "プロジェクトのメモを新規作成してください",
        ],
    },
    "search_notes": {
        "server": "notes",
        "desc": "メモをキーワードで検索",
        "args_example": '{"keyword": "予算"}',
        "result_example": '{"notes": [{"id": "note003", "title": "2025年度予算計画", "preview": "総予算: 1,200万円、内訳...", "folder": "仕事", "modified": "2025-02-28"}]}',
        "scenarios": [
            "予算に関するメモを探してください",
            "プロジェクトXについてのメモはありますか？",
            "レシピのメモを検索してください",
        ],
    },

    # === PhotosServer ===
    "list_photos": {
        "server": "photos",
        "desc": "写真ライブラリの写真一覧を取得（日付・アルバムでフィルタ）",
        "args_example": '{"album": null, "start_date": "2025-03-01", "limit": 10}',
        "result_example": '{"photos": [{"id": "img001", "filename": "IMG_1234.jpg", "date": "2025-03-05T15:30:00+09:00", "location": "東京都渋谷区", "size_mb": 4.2, "width": 4032, "height": 3024, "album": "カメラ"}, {"id": "img002", "filename": "IMG_1235.jpg", "date": "2025-03-05T15:31:00+09:00", "size_mb": 3.8}]}',
        "scenarios": [
            "今月撮った写真を見せてください",
            "京都旅行の写真はありますか？",
            "最近の写真を10枚教えてください",
            "去年の誕生日の写真を探してください",
        ],
    },
    "get_photo_metadata": {
        "server": "photos",
        "desc": "特定の写真のメタデータを取得（位置情報・撮影設定等）",
        "args_example": '{"photo_id": "img001"}',
        "result_example": '{"id": "img001", "filename": "IMG_1234.jpg", "date": "2025-03-05T15:30:22+09:00", "location": {"latitude": 35.6586, "longitude": 139.7454, "address": "東京都港区芝公園"}, "camera": "iPhone 16 Pro", "focal_length": "24mm", "aperture": "f/1.78", "iso": 64, "shutter_speed": "1/500"}',
        "scenarios": [
            "この写真はどこで撮りましたか？",
            "写真の詳細情報を教えてください",
            "写真の撮影場所と日時を確認したい",
        ],
    },

    # === FileSystemServer ===
    "list_files": {
        "server": "filesystem",
        "desc": "アプリのサンドボックス内のファイル一覧を表示",
        "args_example": '{"path": "/", "depth": 2}',
        "result_example": '{"path": "/", "files": [{"name": "Documents", "type": "directory", "size": null}, {"name": "notes.txt", "type": "file", "size_kb": 12.3, "modified": "2025-03-05T10:00:00+09:00"}, {"name": "report.pdf", "type": "file", "size_kb": 245.7}]}',
        "scenarios": [
            "保存されているファイルを見せてください",
            "Documentsフォルダの中身を確認してください",
            "どんなファイルが保存されていますか？",
        ],
    },
    "read_file": {
        "server": "filesystem",
        "desc": "テキストファイルの内容を読む",
        "args_example": '{"path": "/Documents/notes.txt"}',
        "result_example": '{"path": "/Documents/notes.txt", "content": "# 2025年3月のメモ\\n\\n## タスク\\n- レポート作成\\n- 会議準備\\n\\n## アイデア\\n新機能について..."}',
        "scenarios": [
            "保存したメモファイルを読んでください",
            "レポートの内容を確認してください",
            "このテキストファイルを開いてください",
        ],
    },
    "write_file": {
        "server": "filesystem",
        "desc": "テキストファイルを作成・更新",
        "args_example": '{"path": "/Documents/todo.txt", "content": "# TODOリスト\\n- [ ] メール返信\\n- [ ] 報告書作成\\n- [ ] ジム"}',
        "result_example": '{"success": true, "path": "/Documents/todo.txt", "size_kb": 0.8, "created": "2025-03-06T20:00:00+09:00"}',
        "scenarios": [
            "TODOリストをファイルに保存してください",
            "アイデアをテキストファイルに書き出してください",
            "会議メモをファイルとして保存してください",
        ],
    },

    # === NewsServer ===
    "get_news": {
        "server": "news",
        "desc": "最新ニュースを取得（カテゴリ: general/tech/business/sports/science）",
        "args_example": '{"category": "tech", "count": 5}',
        "result_example": '{"articles": [{"title": "OpenAI、GPT-5を発表——推論能力が大幅向上", "source": "TechCrunch", "url": "...", "summary": "OpenAIは本日、GPT-5の発表を行い...", "published_at": "5分前"}, {"title": "Apple、Vision Pro 2を発表", "source": "9to5Mac", "summary": "より軽量で価格も抑えた...", "published_at": "1時間前"}]}',
        "scenarios": [
            "最新のテクノロジーニュースを教えてください",
            "今日のビジネスニュースは？",
            "AI関連の最新ニュースを5件教えてください",
            "スポーツニュースを確認してください",
            "今日起きた主要なニュースをまとめてください",
        ],
    },
    "search_news": {
        "server": "news",
        "desc": "キーワードでニュースを検索",
        "args_example": '{"query": "日銀 利上げ", "count": 5}',
        "result_example": '{"query": "日銀 利上げ", "articles": [{"title": "日銀が利上げを決定、0.5%へ", "source": "日本経済新聞", "summary": "日本銀行は金融政策決定会合で...", "published_at": "2時間前"}]}',
        "scenarios": [
            "日銀の金融政策に関するニュースを検索してください",
            "Tesla の最新ニュースを調べてください",
            "円安に関する最新ニュースを教えてください",
            "オリンピックのニュースを検索してください",
        ],
    },

    # === ShortcutsServer ===
    "list_shortcuts": {
        "server": "shortcuts",
        "desc": "利用可能なiOSショートカットの一覧を取得",
        "args_example": '{}',
        "result_example": '{"shortcuts": [{"name": "おやすみモード", "description": "夜間設定を一括変更"}, {"name": "帰宅通知", "description": "現在地から帰宅中を家族に通知"}, {"name": "ワークアウト開始", "description": "Apple Watchでランニングを開始"}]}',
        "scenarios": [
            "どんなショートカットが使えますか？",
            "設定しているショートカットを一覧で見せてください",
        ],
    },
    "run_shortcut": {
        "server": "shortcuts",
        "desc": "iOSショートカットを実行",
        "args_example": '{"shortcut_name": "おやすみモード"}',
        "result_example": '{"success": true, "shortcut_name": "おやすみモード", "executed_at": "2025-03-06T22:00:00+09:00", "output": "おやすみモードを有効にしました"}',
        "scenarios": [
            "おやすみモードのショートカットを実行してください",
            "帰宅通知を家族に送るショートカットを動かしてください",
            "ワークアウト開始のショートカットを実行してください",
        ],
    },

    # === EmergencyKnowledgeBaseServer ===
    "search_emergency_info": {
        "server": "emergency_kb",
        "desc": "緊急・安全情報（応急処置・防災）を検索",
        "args_example": '{"query": "心肺蘇生 CPR"}',
        "result_example": '{"topic": "心肺蘇生法（CPR）", "steps": ["1. 意識確認: 肩を叩いて「大丈夫ですか？」と声かけ", "2. 119番・AEDを手配", "3. 胸骨圧迫: 胸の中央を30回押す（強く・速く・戻す）", "4. 人工呼吸: 2回（訓練者のみ）", "5. AEDが来たら使用"], "notes": "訓練を受けていない場合は胸骨圧迫のみでOK"}',
        "scenarios": [
            "心肺蘇生の方法を教えてください",
            "地震が起きた時の対応を教えてください",
            "熱中症の応急処置は？",
            "骨折した時はどうすればいいですか？",
            "火事が起きたらどうすればいいですか？",
        ],
    },
    "get_safety_guidelines": {
        "server": "emergency_kb",
        "desc": "安全ガイドライン・防災情報を取得",
        "args_example": '{"category": "earthquake"}',
        "result_example": '{"category": "地震対策", "guidelines": ["非常用バッグに水・食料3日分", "家具の転倒防止", "避難場所の確認", "家族との連絡方法を決める"], "emergency_contacts": {"police": "110", "fire_ambulance": "119", "disaster_info": "0120-974-119"}}',
        "scenarios": [
            "地震への備えを教えてください",
            "防災グッズに何を用意すればいいですか？",
            "台風が来る前にすべきことを教えてください",
        ],
    },
}

GEN_PROMPT = """ElioChat（iPhoneで動くオフラインAIアシスタント「附田/futa」）とユーザーの会話を生成してください。

ツール: {tool_name}（{server_name}サーバー）
ツールの機能: {tool_desc}
ユーザーの状況: {scenario}

必須要件:
1. <think>タグ内に200〜400字の思考（なぜこのツールが適切か、引数の設定理由、注意点）
2. 完全なツール実行フロー:
   - user の自然な質問（iPhoneで話しかけるような口語）
   - assistant: <think>思考</think> + ツール呼び出し
   - tool: 現実的な結果（日本語）
   - assistant: <think>結果を踏まえた考察</think> + 親切な最終回答

特記事項:
- ElioChat はオフラインでも動作するiPhoneアプリ
- 天気・カレンダー・写真等はデバイスのAPIを直接使用
- 回答は自然な日本語で、口語的に

ツール呼び出し形式:
<tool_call>
{{"name": "{tool_name}", "arguments": {arg_example}}}
</tool_call>

ツール結果ロール: {{"role": "tool", "name": "{tool_name}", "content": "..."}}

JSONのみ出力:
[
  {{"role":"system","content":"{system_prompt}"}},
  {{"role":"user","content":"（口語的な質問）"}},
  {{"role":"assistant","content":"<think>\\n（200〜400字の思考）\\n</think>\\n（ツール呼び出し）"}},
  {{"role":"tool","name":"{tool_name}","content":"（現実的なツール結果）"}},
  {{"role":"assistant","content":"<think>\\n（結果を受けた考察）\\n</think>\\n（親切な回答）"}}
]"""


def _hash_conv(convs):
    user_msgs = " ".join(m.get("content","")[:80] for m in convs if m.get("role")=="user")
    return hashlib.md5(user_msgs.encode()).hexdigest()


def generate_one(tool_name, tool_info, scenario):
    prompt = GEN_PROMPT.format(
        tool_name=tool_name,
        server_name=tool_info["server"],
        tool_desc=tool_info["desc"],
        scenario=scenario,
        arg_example=tool_info["args_example"],
        system_prompt=SYSTEM_PROMPT,
    )
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={"model": "gemini-2.0-flash", "max_tokens": 3000,
                      "messages": [{"role": "user", "content": prompt}]},
                timeout=90,
            )
            if resp.status_code == 429:
                time.sleep(30); continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
        except requests.exceptions.Timeout:
            time.sleep(5); continue
        except Exception as e:
            print(f"  [WARN] {e}", file=sys.stderr); time.sleep(3); continue

        text = re.sub(r"```(?:json)?\s*", "", text)
        text = re.sub(r"```\s*", "", text).strip()
        s, e2 = text.find("["), text.rfind("]")
        if s < 0 or e2 <= s: continue
        raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text[s:e2+1])
        try:
            convs = json.loads(raw)
        except json.JSONDecodeError:
            try:
                import json_repair
                convs = json_repair.repair_json(raw, return_objects=True)
            except: continue

        if not isinstance(convs, list): continue
        convs = [m for m in convs if isinstance(m, dict) and "role" in m]

        has_tool_call  = any("<tool_call>" in m.get("content","") for m in convs if m.get("role")=="assistant")
        has_tool_result = any(m.get("role")=="tool" for m in convs)
        has_think      = any("<think>" in m.get("content","") for m in convs if m.get("role")=="assistant")
        think_lens     = [len(t.group(1)) for m in convs if m.get("role")=="assistant"
                          for t in [re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)] if t]

        if has_tool_call and has_tool_result and has_think and max(think_lens, default=0) >= 80:
            return convs
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",   default="elio_tools_data.json")
    parser.add_argument("--per-tool", type=int, default=8)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)
    results, done_hashes = [], set()
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            done_hashes.add(_hash_conv(r.get("conversations", [])))
        print(f"再開: {len(results)}件済み")

    from collections import Counter
    tool_counts = Counter(r.get("tool") for r in results)
    total = len(ELIO_TOOLS) * args.per_tool
    print(f"ElioChat ツール数: {len(ELIO_TOOLS)}, 目標: {total}件")

    for tool_name, tool_info in ELIO_TOOLS.items():
        already = tool_counts.get(tool_name, 0)
        need = args.per_tool - already
        if need <= 0:
            print(f"[{tool_name}] スキップ")
            continue

        print(f"\n[{tool_name}] ({tool_info['server']}) {need}件生成...")
        scenarios = tool_info["scenarios"] * (args.per_tool // max(len(tool_info["scenarios"]),1) + 2)
        random.shuffle(scenarios)

        generated = fail = 0
        for scenario in scenarios:
            if generated >= need or fail >= 8: break
            convs = generate_one(tool_name, tool_info, scenario)
            if not convs:
                fail += 1; time.sleep(1); continue
            h = _hash_conv(convs)
            if h in done_hashes:
                fail += 1; continue

            results.append({
                "conversations": convs,
                "category": f"elio_{tool_info['server']}",
                "tool": tool_name,
                "source": "elio_tools_v1",
            })
            done_hashes.add(h)
            generated += 1; fail = 0

            tl = [len(t.group(1)) for m in convs if m.get("role")=="assistant"
                  for t in [re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)] if t]
            print(f"  {generated}/{need}: think avg {sum(tl)//max(len(tl),1)}字")

            if len(results) % 20 == 0:
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False)
            time.sleep(0.4)

        print(f"  [{tool_name}] 完了: {generated}件")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False)

    from collections import Counter
    dist = Counter(r.get("tool") for r in results)
    print(f"\n完了: {len(results)}件 → {out_path}")
    for k, v in sorted(dist.items()):
        print(f"  {k}: {v}件")


if __name__ == "__main__":
    main()
