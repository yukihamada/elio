#!/usr/bin/env python3
"""
generate_diverse_data.py — 多様カテゴリのデータ追加生成
=========================================================
不足しているカテゴリを補完して5,000件超を目指す。
Gemini Flash 2.0 で生成。
"""
import json, os, re, sys, time, argparse, random, requests
random.seed(42)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPTS = [
    "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。",
    "あなたは附田（futa）です。日本語を中心に、ユーザーの質問に誠実かつ正確に答えます。必要に応じてツールを使い、<think>タグで思考過程を示してください。",
    "あなたは附田（futa）という名前のAIアシスタントです。深い思考力と幅広い知識を持ち、<think>タグで論理的に考えてから回答します。",
]

CATEGORIES = [
    {
        "name": "business_japanese",
        "description": "ビジネス日本語・敬語・ビジネスマナー",
        "questions": [
            "ビジネスメールで「お世話になっております」以外の書き出しを教えてください",
            "上司へのメールで謝罪する際の適切な表現は？",
            "プレゼンテーションの冒頭で聴衆を引きつける表現を教えてください",
            "会議で反対意見を穏やかに伝える日本語表現は？",
            "取引先への断りメールの書き方を教えてください",
            "電話対応で「担当者が不在」を伝える丁寧な表現は？",
            "部下を褒める際の効果的な言い方を教えてください",
            "「ご検討ください」よりも丁寧な依頼表現はありますか？",
            "社内報告書の書き方の基本を教えてください",
            "商談で価格交渉をする際の表現を教えてください",
        ],
        "tool": None,
    },
    {
        "name": "science_explanation",
        "description": "科学・技術の分かりやすい解説",
        "questions": [
            "量子コンピュータが普通のコンピュータと違う点を分かりやすく教えてください",
            "ブラックホールとはどういうものですか？",
            "DNAの二重らせん構造はどんな役割を持っていますか？",
            "相対性理論を中学生に分かるように説明してください",
            "光合成のしくみをわかりやすく教えてください",
            "人工知能のディープラーニングの仕組みを教えてください",
            "気候変動のメカニズムを教えてください",
            "核融合発電はなぜ難しいのですか？",
            "宇宙の年齢はどうやって計算するのですか？",
            "ウイルスと細菌の違いを教えてください",
        ],
        "tool": "wikipedia",
    },
    {
        "name": "life_advice",
        "description": "日常生活の悩み・アドバイス",
        "questions": [
            "職場の人間関係でストレスを感じています。うまく対処する方法は？",
            "先延ばし癖を直す効果的な方法を教えてください",
            "副業を始めたいのですが、どんな種類がありますか？",
            "断捨離を効果的に進める方法を教えてください",
            "読書習慣をつけるコツを教えてください",
            "家計管理が苦手です。節約の基本を教えてください",
            "子供のスマホ依存を防ぐ方法を教えてください",
            "一人暮らしを始める際の注意点を教えてください",
            "集中力を高める方法を教えてください",
            "人前で話すことへの緊張を克服する方法は？",
        ],
        "tool": None,
    },
    {
        "name": "tech_support",
        "description": "技術サポート・IT問題解決",
        "questions": [
            "Windowsのパソコンが急に遅くなりました。原因と対策を教えてください",
            "Excelでデータの重複を削除する方法を教えてください",
            "Wi-Fiの速度が遅い原因と改善方法を教えてください",
            "Gmailの迷惑メールが多くて困っています。フィルタの設定方法は？",
            "スマートフォンのバッテリーが急に減るようになりました",
            "GoogleドライブとOneDriveの違いを教えてください",
            "Zoomのビデオ会議で背景をぼかす方法を教えてください",
            "パソコンのウイルス対策ソフトは必要ですか？",
            "MacからWindowsに乗り換えた際の注意点を教えてください",
            "スマホの写真をパソコンに簡単に転送する方法を教えてください",
        ],
        "tool": None,
    },
    {
        "name": "creative_writing",
        "description": "創作・文章作成",
        "questions": [
            "短編小説の冒頭部分を魅力的に書くコツを教えてください",
            "SNSのキャプションを効果的に書く方法は？",
            "プレスリリースの書き方を教えてください",
            "日記を続けやすくする書き方のコツを教えてください",
            "プレゼン資料のコピーを短く印象的に書くには？",
            "読者を惹きつけるブログの書き出しの例を教えてください",
            "感謝の手紙を書く際のポイントを教えてください",
            "詩を書いたことがないのですが、始め方を教えてください",
            "商品説明文を魅力的に書くテクニックを教えてください",
            "インタビュー記事の構成と書き方を教えてください",
        ],
        "tool": None,
    },
    {
        "name": "current_events_qa",
        "description": "時事・社会問題の解説",
        "questions": [
            "インフレが生活に与える影響を教えてください",
            "メタバースとはどういうものですか？実用化はいつですか？",
            "カーボンニュートラルとはどういう意味ですか？",
            "デジタル円（CBDC）について教えてください",
            "働き方改革で変わったことを教えてください",
            "生成AIが社会に与える影響を教えてください",
            "空き家問題の現状と対策を教えてください",
            "フードロス削減の取り組みを教えてください",
        ],
        "tool": "wikipedia",
    },
    {
        "name": "tool_web_search",
        "description": "web_searchを使う複雑な質問",
        "questions": [
            "最新のiPhoneの価格と特徴を調べてください",
            "東京の今週末の天気と気温を教えてください",
            "Python 3.12の新機能を調べてください",
            "日本の最低賃金の最新情報を教えてください",
            "来年の確定申告の締め切りはいつですか？",
            "最近話題のAIツールを調べてください",
            "東京オリンピックの総費用はいくらでしたか？",
            "日本で人気のサブスクサービスを調べてください",
        ],
        "tool": "web_search",
    },
    {
        "name": "tool_code_execute",
        "description": "コード実行を伴う技術的な質問",
        "questions": [
            "Pythonでフィボナッチ数列を生成するコードを書いて実行してください",
            "PythonでCSVファイルを読み込んで統計情報を表示するコードを書いてください",
            "シェルスクリプトでディレクトリのファイル一覧を表示する方法を教えてください",
            "Pythonで簡単な暗号化（Caesar cipher）を実装してください",
            "Pythonで1から100の素数をリストアップしてください",
            "Bashで特定の文字列を含むファイルを検索するコマンドを教えてください",
            "Pythonで日付の計算（2つの日付の差分）をするコードを書いてください",
            "シェルで複数のファイルを一括リネームする方法を教えてください",
        ],
        "tool": "code_execute",
    },
]

PROMPT_TEMPLATE = """以下の質問に「附田(futa)」が答える会話を生成してください。

カテゴリ: {category}
ユーザーの質問: {question}
{tool_instruction}

出力要件:
1. assistant の返答は必ず <think> タグ（300〜600字の深い日本語思考）で始める
2. {tool_usage}
3. 最終回答は具体的で役立つ内容（200字以上）
4. 日本語で自然な会話

JSONのみ出力（system ロールは含めない）:
[
  {{"role": "user", "content": "{question}"}},
  {{"role": "assistant", "content": "<think>\\n...深い思考300字以上...\\n</think>\\n\\n{response_hint}"}}{tool_example}
]"""

TOOL_INSTRUCTION_MAP = {
    "wikipedia": "使用ツール: wikipedia（情報検索）",
    "web_search": "使用ツール: web_search（Web検索）",
    "code_execute": "使用ツール: code_execute（コード実行）",
    None: "ツールは使わず直接回答する",
}

TOOL_USAGE_MAP = {
    "wikipedia": "tool_call タグで wikipedia を呼び出し、結果を使って回答する",
    "web_search": "tool_call タグで web_search を呼び出し、結果を使って回答する",
    "code_execute": "tool_call タグで code_execute を呼び出してコードを実行し、結果を示す",
    None: "tool_call は使わず、知識から直接回答する",
}

TOOL_EXAMPLE_MAP = {
    "wikipedia": """,
  {{"role": "assistant", "content": "<think>\\n調査方針...\\n</think>\\n<tool_call>\\n{{\"name\": \"wikipedia\", \"arguments\": {{\"query\": \"検索クエリ\"}}}}\\n</tool_call>"}},
  {{"role": "tool", "name": "wikipedia", "content": "{{\\\"title\\\": \\\"記事タイトル\\\", \\\"summary\\\": \\\"要約...\\\"}}"}},
  {{"role": "assistant", "content": "<think>\\n結果の分析...\\n</think>\\n\\n最終回答..."}}""",
    "web_search": """,
  {{"role": "assistant", "content": "<think>\\n検索戦略...\\n</think>\\n<tool_call>\\n{{\"name\": \"web_search\", \"arguments\": {{\"query\": \"検索クエリ\"}}}}\\n</tool_call>"}},
  {{"role": "tool", "name": "web_search", "content": "{{\\\"results\\\": [{{\\\"title\\\": \\\"...\\\", \\\"snippet\\\": \\\"...\\\"}}]}}"}},
  {{"role": "assistant", "content": "<think>\\n結果の分析...\\n</think>\\n\\n最終回答..."}}""",
    "code_execute": """,
  {{"role": "assistant", "content": "<think>\\nコード設計...\\n</think>\\n<tool_call>\\n{{\"name\": \"code_execute\", \"arguments\": {{\"language\": \"python\", \"code\": \"print('hello')\"}}}}\\n</tool_call>"}},
  {{"role": "tool", "name": "code_execute", "content": "{{\\\"output\\\": \\\"hello\\\", \\\"exit_code\\\": 0}}"}},
  {{"role": "assistant", "content": "<think>\\n実行結果の確認...\\n</think>\\n\\n最終回答..."}}""",
    None: "",
}


def generate_item(category: dict, question: str) -> dict | None:
    tool = category["tool"]
    prompt = PROMPT_TEMPLATE.format(
        category        = category["description"],
        question        = question,
        tool_instruction= TOOL_INSTRUCTION_MAP[tool],
        tool_usage      = TOOL_USAGE_MAP[tool],
        response_hint   = "回答...",
        tool_example    = TOOL_EXAMPLE_MAP[tool],
    )

    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 2500,
                    "messages": [{"role": "user", "content": prompt}],
                },
                timeout=60,
            )
            if resp.status_code == 429:
                time.sleep(30)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
        except requests.exceptions.Timeout:
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {str(e)[:60]}", file=sys.stderr)
            time.sleep(3)
            continue

        text = re.sub(r"```(?:json)?\s*", "", text)
        text = re.sub(r"```\s*", "", text).strip()
        s = text.find("[")
        e = text.rfind("]")
        if s < 0 or e <= s:
            continue

        raw = text[s:e+1]
        raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", raw)

        try:
            convs = json.loads(raw)
        except json.JSONDecodeError:
            try:
                import json_repair
                convs = json_repair.repair_json(raw, return_objects=True)
            except Exception:
                continue

        if not isinstance(convs, list):
            continue
        convs = [m for m in convs if isinstance(m, dict) and "role" in m]

        # 検証
        ass_msgs = [m for m in convs if m.get("role") == "assistant"]
        if not ass_msgs:
            continue
        thinks = sum(1 for m in ass_msgs if "<think>" in m.get("content", ""))
        if thinks == 0:
            continue

        # システムプロンプト追加
        sys_prompt = random.choice(SYSTEM_PROMPTS)
        full_convs = [{"role": "system", "content": sys_prompt}] + convs

        return {
            "conversations": full_convs,
            "category":      category["name"],
        }

    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",    default="diverse_data.json")
    parser.add_argument("--per-category", type=int, default=60)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path   = os.path.join(script_dir, args.output)

    results: list = []
    done_cats: dict = {}
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        from collections import Counter
        done_cats = dict(Counter(r.get("category", "?") for r in results))
        print(f"再開: {len(results)}件済み")

    total = len(CATEGORIES) * args.per_category
    print(f"目標: {total}件 ({len(CATEGORIES)}カテゴリ × {args.per_category}件)")

    for cat in CATEGORIES:
        already = done_cats.get(cat["name"], 0)
        need    = args.per_category - already
        if need <= 0:
            print(f"[{cat['name']}] スキップ ({already}/{args.per_category})")
            continue

        print(f"\n[{cat['name']}] {need}件生成...")
        questions = (cat["questions"] * (args.per_category // len(cat["questions"]) + 2))
        random.shuffle(questions)

        generated = 0
        fail      = 0
        q_idx     = 0

        while generated < need and fail < 15 and q_idx < len(questions):
            q = questions[q_idx]
            q_idx += 1

            item = generate_item(cat, q)
            if item is None:
                fail += 1
                continue

            results.append(item)
            generated += 1
            fail = 0

            think_lens = [
                len(re.search(r"<think>(.*?)</think>", m["content"], re.DOTALL).group(1))
                for m in item["conversations"]
                if m["role"] == "assistant" and re.search(r"<think>(.*?)</think>", m["content"], re.DOTALL)
            ]
            avg_t = sum(think_lens) // max(len(think_lens), 1)
            print(f"  [{cat['name']}] {generated}/{need}: think avg {avg_t}字, q={q[:30]}")

            if len(results) % 20 == 0:
                _save(results, out_path)

            time.sleep(0.3)

        print(f"  [{cat['name']}] 完了: {generated}件")
        _save(results, out_path)

    _save(results, out_path)
    print(f"\n完了: {len(results)}件 → {out_path}")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
