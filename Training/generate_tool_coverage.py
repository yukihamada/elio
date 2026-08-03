#!/usr/bin/env python3
"""
generate_tool_coverage.py — 全ツールカバレッジデータ生成
==========================================================
chatweb.ai の全ツールに対して現実的な multi-turn 会話を生成。
ツール呼び出し→ツール結果→最終回答の完全なフローを含む。
"""
import json, os, re, sys, time, argparse, random, hashlib, requests
random.seed(55)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPT = "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。"

# 全ツール定義（名前・説明・引数例・現実的なツール結果例）
ALL_TOOLS = {
    # ─── 既存カバー済み（少量追加） ───
    "web_search": {
        "desc": "Webを検索して最新情報を取得",
        "args": '{"query": "最新のAI技術トレンド 2025"}',
        "result": '{"results": [{"title": "2025年のAI技術動向", "url": "https://example.com/ai2025", "snippet": "生成AIの進化が続き..."}]}',
        "scenarios": [
            "最新のAI技術トレンドを教えてください",
            "円安の原因を調べて説明してください",
            "東京オリンピック2020の成果を検索して教えてください",
        ],
    },
    # ─── 未カバーツール ───
    "browser": {
        "desc": "Webブラウザを操作してページを取得・操作",
        "args": '{"url": "https://example.com", "action": "get_text"}',
        "result": '{"title": "Example Domain", "text": "This domain is for use in illustrative examples...", "links": []}',
        "scenarios": [
            "https://chatweb.ai のトップページの内容を確認して要約してください",
            "このウェブサイトのお問い合わせフォームの内容を取得してください",
            "指定したURLのページタイトルと本文を取得してください",
        ],
    },
    "browser_screenshot": {
        "desc": "Webページのスクリーンショットを取得",
        "args": '{"url": "https://example.com"}',
        "result": '{"screenshot_url": "https://storage.example.com/screenshot_abc123.png", "width": 1280, "height": 800}',
        "scenarios": [
            "このウェブサイトのスクリーンショットを撮ってください",
            "競合他社のサイトのデザインを確認したい",
            "サイトの見た目を確認してレポートを作ってください",
        ],
    },
    "csv_analysis": {
        "desc": "CSVファイルを分析して統計・集計を実行",
        "args": '{"file_path": "/tmp/sandbox/sales.csv", "operation": "summary"}',
        "result": '{"rows": 1250, "columns": ["date","product","amount","region"], "summary": {"amount": {"mean": 45230, "max": 980000, "min": 1200}}}',
        "scenarios": [
            "売上データのCSVを分析して月別集計を出してください",
            "このCSVファイルの統計サマリーを作成してください",
            "データの外れ値を検出してください",
        ],
    },
    "youtube_transcript": {
        "desc": "YouTube動画の字幕・トランスクリプトを取得",
        "args": '{"video_id": "dQw4w9WgXcQ"}',
        "result": '{"title": "Never Gonna Give You Up", "transcript": [{"text": "We\'re no strangers to love...", "start": 0.0, "duration": 3.5}], "language": "en"}',
        "scenarios": [
            "このYouTube動画の内容を要約してください（動画IDを教えます）",
            "英語のYouTube講義を日本語で要約したい",
            "このプレゼン動画のキーポイントを箇条書きにしてください",
        ],
    },
    "arxiv_search": {
        "desc": "arXivで学術論文を検索",
        "args": '{"query": "large language model reasoning", "max_results": 5}',
        "result": '{"papers": [{"id": "2401.12345", "title": "Chain-of-Thought Reasoning in LLMs", "authors": ["John Smith"], "abstract": "We propose a novel...", "published": "2024-01-15"}]}',
        "scenarios": [
            "量子コンピュータの最新研究論文を探してください",
            "深層学習を使った医療診断の論文を5件検索してください",
            "大規模言語モデルの推論能力に関する最新論文を教えてください",
        ],
    },
    "music_generate": {
        "desc": "AIで音楽を生成（Suno API）",
        "args": '{"prompt": "relaxing jazz piano, slow tempo, evening mood", "duration": 30}',
        "result": '{"audio_url": "https://cdn.suno.ai/generated_abc123.mp3", "duration": 30, "style": "jazz"}',
        "scenarios": [
            "リラックスできるジャズ音楽を作ってください",
            "朝の目覚めに合うアップテンポな曲を生成してください",
            "プレゼン用のBGMを作りたい。落ち着いたコーポレート風で",
        ],
    },
    "video_generate": {
        "desc": "AIで短い動画を生成（Kling API）",
        "args": '{"prompt": "桜の花びらが風に舞う春の公園、穏やかな日差し", "duration": 5}',
        "result": '{"video_url": "https://cdn.kling.ai/video_xyz789.mp4", "duration": 5, "resolution": "1080p"}',
        "scenarios": [
            "春の桜のショート動画を生成してください",
            "プロモーション用の商品紹介動画を作ってください",
            "SNS用に夕焼けの海の動画を生成してほしい",
        ],
    },
    "filesystem": {
        "desc": "ファイルシステムの検索・グロブパターンマッチ",
        "args": '{"pattern": "/tmp/sandbox/**/*.txt", "operation": "glob"}',
        "result": '{"matches": ["/tmp/sandbox/notes.txt", "/tmp/sandbox/report.txt"], "count": 2}',
        "scenarios": [
            "サンドボックス内のすべてのPythonファイルを検索してください",
            "特定のパターンに一致するファイルを見つけてください",
            "ディレクトリ構造を再帰的に確認してください",
        ],
    },
    "github_read_file": {
        "desc": "GitHubリポジトリのファイルを読む",
        "args": '{"owner": "yukihamada", "repo": "nanobot", "path": "README.md"}',
        "result": '{"content": "# nanobot\\n\\nA production-grade AI agent platform...", "sha": "abc123", "size": 4096}',
        "scenarios": [
            "GitHubリポジトリのREADMEを確認して概要を教えてください",
            "このリポジトリのソースコードを確認してバグを探してください",
            "OSSプロジェクトのドキュメントを読んで使い方を教えてください",
        ],
    },
    "github_create_pr": {
        "desc": "GitHubにプルリクエストを作成",
        "args": '{"owner": "yukihamada", "repo": "nanobot", "title": "Fix: タイムアウト修正", "body": "...", "head": "fix/timeout", "base": "main"}',
        "result": '{"pr_number": 42, "url": "https://github.com/yukihamada/nanobot/pull/42", "status": "open"}',
        "scenarios": [
            "バグ修正のプルリクエストを作成してください",
            "新機能の追加PRを作りたい",
            "ドキュメント更新のPRを作成してください",
        ],
    },
    "gmail": {
        "desc": "Gmailでメールを送信・検索",
        "args": '{"to": "team@example.com", "subject": "会議のリマインド", "body": "明日10時の会議をお忘れなく"}',
        "result": '{"message_id": "msg_abc123", "status": "sent", "timestamp": "2025-03-06T10:00:00Z"}',
        "scenarios": [
            "チームメンバーに会議のリマインドメールを送ってください",
            "クライアントへの提案書送付メールを作成して送信してください",
            "未読メールから重要なものを検索してください",
        ],
    },
    "google_calendar": {
        "desc": "Googleカレンダーでイベントを管理",
        "args": '{"action": "create", "title": "週次MTG", "start": "2025-03-10T10:00:00", "end": "2025-03-10T11:00:00"}',
        "result": '{"event_id": "evt_abc123", "status": "confirmed", "link": "https://calendar.google.com/event?eid=abc123"}',
        "scenarios": [
            "来週の月曜日に会議を設定してください",
            "今月のスケジュールを確認してください",
            "定期MTGをカレンダーに登録してください",
        ],
    },
    "slack": {
        "desc": "Slackにメッセージを送信・検索",
        "args": '{"channel": "#general", "message": "本日のリリースが完了しました！"}',
        "result": '{"ok": true, "ts": "1741234567.123456", "channel": "C12345"}',
        "scenarios": [
            "開発チームのSlackにリリース完了を通知してください",
            "特定のSlackチャンネルにメッセージを送ってください",
            "昨日のSlack会話を検索して要約してください",
        ],
    },
    "discord": {
        "desc": "Discordにメッセージを送信",
        "args": '{"channel_id": "123456789", "message": "新しいアップデートをリリースしました！"}',
        "result": '{"id": "987654321", "channel_id": "123456789", "content": "新しいアップデートをリリースしました！"}',
        "scenarios": [
            "Discordサーバーにお知らせを投稿してください",
            "コミュニティへの告知メッセージを作成して送信してください",
            "Discordに新機能のリリースノートを投稿してください",
        ],
    },
    "notion": {
        "desc": "Notionのページ・データベースを操作",
        "args": '{"action": "create_page", "title": "プロジェクト計画書", "content": "## 目標\\n..."}',
        "result": '{"page_id": "page_abc123", "url": "https://notion.so/page_abc123", "status": "created"}',
        "scenarios": [
            "プロジェクトのタスクリストをNotionに作成してください",
            "会議のメモをNotionに記録してください",
            "Notionデータベースから今月のタスクを確認してください",
        ],
    },
    "spotify": {
        "desc": "Spotifyで音楽再生・検索を制御",
        "args": '{"action": "search", "query": "relaxing jazz", "type": "playlist"}',
        "result": '{"playlists": [{"name": "Relaxing Jazz Evening", "id": "37i9dQZF1DX", "tracks": 50, "url": "https://open.spotify.com/playlist/37i9dQZF1DX"}]}',
        "scenarios": [
            "集中して作業できるBGMをSpotifyで再生してください",
            "ジャズのプレイリストを検索してください",
            "今再生中の曲を教えてください",
        ],
    },
    "postgres": {
        "desc": "PostgreSQLデータベースにSQLクエリを実行",
        "args": '{"query": "SELECT COUNT(*) as total, AVG(amount) as avg_amount FROM orders WHERE created_at > NOW() - INTERVAL \'30 days\'"}',
        "result": '{"rows": [{"total": 1250, "avg_amount": 45230.5}], "row_count": 1, "execution_time_ms": 12}',
        "scenarios": [
            "先月の売上集計をデータベースから取得してください",
            "ユーザーテーブルから条件に合うデータを検索してください",
            "在庫切れ商品を一覧表示するSQLを実行してください",
        ],
    },
    "webhook_trigger": {
        "desc": "外部サービスのWebhookを呼び出す",
        "args": '{"url": "https://hooks.zapier.com/hooks/catch/123/abc", "method": "POST", "payload": {"event": "order_completed", "order_id": 12345}}',
        "result": '{"status": 200, "response": "Webhook received", "triggered_at": "2025-03-06T10:00:00Z"}',
        "scenarios": [
            "注文完了時にZapierのWebhookを呼び出してください",
            "外部システムに在庫更新を通知するWebhookをトリガーしてください",
            "Slashコマンドのイベントを外部サービスに送信してください",
        ],
    },
    "web_deploy": {
        "desc": "静的サイトをワンクリックでデプロイ",
        "args": '{"files": {"index.html": "<html><body><h1>Hello</h1></body></html>"}, "subdomain": "myapp"}',
        "result": '{"url": "https://myapp.deploy.chatweb.ai", "status": "deployed", "build_time_ms": 1230}',
        "scenarios": [
            "簡単なランディングページを作ってデプロイしてください",
            "ポートフォリオサイトのHTMLを生成してデプロイしてください",
            "プレビュー用のプロトタイプサイトを素早く公開してください",
        ],
    },
    "git_status": {
        "desc": "Gitリポジトリの状態を確認",
        "args": '{"repo_path": "/tmp/sandbox/myproject"}',
        "result": '{"branch": "main", "modified": ["src/app.py", "README.md"], "untracked": ["test.py"], "staged": []}',
        "scenarios": [
            "現在のリポジトリの変更状況を確認してください",
            "どのファイルを変更したか教えてください",
            "コミット前に変更内容を確認してください",
        ],
    },
    "git_commit": {
        "desc": "Gitにコミットを作成",
        "args": '{"repo_path": "/tmp/sandbox/myproject", "message": "feat: ユーザー認証機能を追加", "files": ["src/auth.py"]}',
        "result": '{"commit_hash": "a1b2c3d", "message": "feat: ユーザー認証機能を追加", "files_changed": 1}',
        "scenarios": [
            "変更をコミットしてください",
            "バグ修正をコミットしたい",
            "機能追加をGitにコミットしてください",
        ],
    },
    "run_tests": {
        "desc": "プロジェクトのテストスイートを実行",
        "args": '{"repo_path": "/tmp/sandbox/myproject", "command": "pytest tests/ -v"}',
        "result": '{"passed": 24, "failed": 1, "errors": 0, "duration_s": 3.2, "output": "FAILED tests/test_auth.py::test_login - AssertionError"}',
        "scenarios": [
            "テストを実行して結果を教えてください",
            "どのテストが失敗しているか確認してください",
            "コードを変更したのでテストが通るか確認してください",
        ],
    },
    "memory_log": {
        "desc": "会話の重要情報を長期記憶に保存",
        "args": '{"key": "user_preference", "value": "ユーザーはPythonが得意でAI開発が専門", "tags": ["preference", "skill"]}',
        "result": '{"stored": true, "key": "user_preference", "expires": null}',
        "scenarios": [
            "私の好みを覚えておいてください",
            "このプロジェクトの重要な情報を記憶してください",
            "次回も同じ設定で使えるようにメモしておいてください",
        ],
    },
    "knowledge_graph": {
        "desc": "知識グラフで概念の関係を検索・構築",
        "args": '{"action": "query", "entity": "機械学習", "relation": "関連技術"}',
        "result": '{"entity": "機械学習", "relations": [{"type": "関連技術", "target": "ディープラーニング"}, {"type": "応用分野", "target": "自然言語処理"}]}',
        "scenarios": [
            "機械学習と関連する技術の関係図を作ってください",
            "このトピックの知識構造を整理してください",
            "概念間の関係を知識グラフで可視化してください",
        ],
    },
    "phone_call": {
        "desc": "電話をかける（Amazon Connect連携）",
        "args": '{"phone_number": "+81-3-1234-5678", "message": "ご予約のリマインドです。明日14時にお伺いします。"}',
        "result": '{"call_id": "call_abc123", "status": "initiated", "duration_s": 0}',
        "scenarios": [
            "予約リマインドの電話を入れてください",
            "顧客に確認の電話をかけてください",
            "この番号に自動音声で通知を送ってください",
        ],
    },
    "tavily_search": {
        "desc": "Tavily APIで高精度Web検索（AI最適化）",
        "args": '{"query": "2025年 日本のスタートアップ資金調達 最新", "search_depth": "advanced"}',
        "result": '{"results": [{"title": "2025年Q1スタートアップ調達額", "url": "...", "content": "...", "score": 0.95}], "answer": "2025年のスタートアップ資金調達は前年比20%増..."}',
        "scenarios": [
            "最新のスタートアップ動向を詳しく調べてください",
            "特定テーマの信頼性の高い情報源を検索してください",
            "競合他社の最新動向を精度高く調査してください",
        ],
    },
    "run_linter": {
        "desc": "コードの静的解析・Lintを実行",
        "args": '{"repo_path": "/tmp/sandbox/myproject", "tool": "pylint", "target": "src/"}',
        "result": '{"score": 8.5, "errors": 2, "warnings": 5, "issues": [{"line": 42, "type": "E1101", "message": "Module has no member"}]}',
        "scenarios": [
            "コードの品質チェックをしてください",
            "Lintエラーを確認して修正方法を教えてください",
            "プルリクエスト前にコードをチェックしてください",
        ],
    },
}

GEN_PROMPT = """日本語AIアシスタント「附田（futa）」とユーザーの会話を生成してください。

ツール: {tool_name}
ツールの説明: {tool_desc}
シナリオ: {scenario}

必須要件:
1. <think>タグ内に250〜500字の深い思考（なぜこのツールを使うか、引数をどう設定するか、注意点）
2. 以下の完全なフローを含む:
   - user の質問
   - assistant の思考 + ツール呼び出し
   - tool の結果（現実的な内容）
   - assistant の最終回答（ツール結果を活用した具体的な回答）
3. ツール結果は現実的な値で

ツール呼び出し形式:
<tool_call>
{{"name": "{tool_name}", "arguments": {arg_example}}}
</tool_call>

ツール結果のロール: {{"role": "tool", "name": "{tool_name}", "content": "..."}}

JSONのみ出力（説明なし）:
[
  {{"role":"system","content":"{system_prompt}"}},
  {{"role":"user","content":"（シナリオの質問）"}},
  {{"role":"assistant","content":"<think>\\n（250〜500字の思考）\\n</think>\\n（ツール呼び出し）"}},
  {{"role":"tool","name":"{tool_name}","content":"（現実的なツール結果）"}},
  {{"role":"assistant","content":"<think>\\n（ツール結果を受けての考察100字以上）\\n</think>\\n（ツール結果を活用した具体的回答）"}}
]"""


def _hash_conv(convs):
    user_msgs = " ".join(m.get("content","")[:80] for m in convs if m.get("role")=="user")
    return hashlib.md5(user_msgs.encode()).hexdigest()


def generate_one(tool_name, tool_info, scenario):
    prompt = GEN_PROMPT.format(
        tool_name=tool_name,
        tool_desc=tool_info["desc"],
        scenario=scenario,
        arg_example=tool_info["args"],
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

        # 検証: tool呼び出しがある & think がある
        has_tool_call = any("<tool_call>" in m.get("content","") for m in convs if m.get("role")=="assistant")
        has_tool_result = any(m.get("role")=="tool" for m in convs)
        has_think = any("<think>" in m.get("content","") for m in convs if m.get("role")=="assistant")
        think_lens = [len(t.group(1)) for m in convs if m.get("role")=="assistant"
                      for t in [re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)] if t]

        if has_tool_call and has_tool_result and has_think and max(think_lens, default=0) >= 100:
            return convs
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="tool_coverage_data.json")
    parser.add_argument("--per-tool", type=int, default=5)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, args.output)

    results = []
    done_hashes = set()
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            done_hashes.add(_hash_conv(r.get("conversations", [])))
        print(f"再開: {len(results)}件済み")

    from collections import Counter
    tool_counts = Counter(r.get("tool") for r in results)

    total_tools = len(ALL_TOOLS)
    print(f"ツール数: {total_tools}, 目標: {args.per_tool}件/ツール = {total_tools * args.per_tool}件")

    for tool_name, tool_info in ALL_TOOLS.items():
        already = tool_counts.get(tool_name, 0)
        need = args.per_tool - already
        if need <= 0:
            print(f"[{tool_name}] スキップ ({already}/{args.per_tool})")
            continue

        print(f"\n[{tool_name}] {need}件生成...")
        scenarios = tool_info["scenarios"] * (args.per_tool // len(tool_info["scenarios"]) + 2)
        random.shuffle(scenarios)

        generated = 0
        fail = 0
        for scenario in scenarios:
            if generated >= need or fail >= 8:
                break
            convs = generate_one(tool_name, tool_info, scenario)
            if not convs:
                fail += 1; time.sleep(1); continue

            h = _hash_conv(convs)
            if h in done_hashes:
                fail += 1; continue

            item = {
                "conversations": convs,
                "category": f"tool_{tool_name}",
                "tool": tool_name,
                "source": "tool_coverage_v1",
            }
            results.append(item)
            done_hashes.add(h)
            generated += 1
            fail = 0

            think_lens = [len(t.group(1)) for m in convs if m.get("role")=="assistant"
                          for t in [re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)] if t]
            print(f"  {generated}/{need}: think avg {sum(think_lens)//max(len(think_lens),1)}字")

            if len(results) % 20 == 0:
                with open(out_path, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False)
            time.sleep(0.5)

        print(f"  [{tool_name}] 完了: {generated}件")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(results, f, ensure_ascii=False)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False)

    tool_dist = Counter(r.get("tool") for r in results)
    print(f"\n完了: {len(results)}件 → {out_path}")
    for k, v in sorted(tool_dist.items()):
        print(f"  {k}: {v}件")


if __name__ == "__main__":
    main()
