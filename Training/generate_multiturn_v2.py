#!/usr/bin/env python3
"""
generate_multiturn_v2.py — 改善版マルチターン会話生成
=====================================================
修正点:
- シナリオごとに多様な開始質問を使う (15種類)
- done_starts の dedup ロジックを会話ハッシュベースに変更
- json_repair でパースエラーを自動修正
- 検証条件を緩和 (2ターン以上, think×1以上)
"""
import json, os, re, sys, time, argparse, random, hashlib, requests
random.seed(42)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SCENARIOS = [
    {
        "title": "旅行計画",
        "tools": ["weather", "wikipedia", "calculator"],
        "starts": [
            "来月京都に旅行したいのですが、おすすめの時期はいつですか？",
            "初めて海外旅行でタイに行きたいのですが、何を準備すればいいですか？",
            "沖縄旅行を計画しています。3泊4日でどんなプランが良いですか？",
            "北海道に家族旅行を考えています。子連れにおすすめのスポットは？",
            "ヨーロッパ周遊旅行を考えているのですが、費用はどのくらいかかりますか？",
            "温泉旅行を計画しています。箱根と草津、どちらがおすすめですか？",
            "東京から日帰りでいける観光地を教えてください",
            "九州旅行を5日間で計画しています。どんな順路が効率的ですか？",
        ],
    },
    {
        "title": "プログラミング学習",
        "tools": ["wikipedia", "code_execute"],
        "starts": [
            "Pythonの辞書型について教えてください",
            "JavaScriptの非同期処理が理解できません。async/awaitを解説してください",
            "Rustを始めたいのですが、メモリ管理の概念を教えてください",
            "SQLのJOINの種類と使い方を教えてください",
            "Gitのブランチ戦略について教えてください",
            "機械学習でよく使われるPythonライブラリを教えてください",
            "Dockerとは何ですか？使い方を教えてください",
            "APIとは何か、REST APIの仕組みを教えてください",
        ],
    },
    {
        "title": "料理レシピ研究",
        "tools": ["wikipedia", "calculator"],
        "starts": [
            "ラタトゥイユを作りたいのですが、材料を教えてください",
            "チャーハンをパラパラに作るコツを教えてください",
            "パスタカルボナーラを本格的に作りたいです",
            "だしの取り方を一から教えてください",
            "ヘルシーな鶏胸肉料理のレシピを教えてください",
            "手作りパンを初めて作りたいのですが",
            "韓国料理のビビンバを家で作れますか？",
            "フランス料理のラムの赤ワイン煮込みを作りたい",
        ],
    },
    {
        "title": "健康・運動計画",
        "tools": ["calculator", "wikipedia"],
        "starts": [
            "最近運動不足で体重も増えてきました。何から始めればいいですか？",
            "筋トレを始めたいのですが、初心者向けのメニューを教えてください",
            "ランニングを始めて3ヶ月で5km走れるようになりたいです",
            "糖質制限ダイエットについて教えてください",
            "腰痛改善に効果的なストレッチを教えてください",
            "睡眠の質を上げる方法を教えてください",
            "ヨガと筋トレどちらを優先すべきか迷っています",
            "プロテインはいつ飲むのが効果的ですか？",
        ],
    },
    {
        "title": "歴史探求",
        "tools": ["wikipedia"],
        "starts": [
            "江戸時代の経済システムについて教えてください",
            "第二次世界大戦がなぜ起きたのか教えてください",
            "ローマ帝国はなぜ滅んだのですか？",
            "日本の明治維新について詳しく教えてください",
            "シルクロードの歴史的意義を教えてください",
            "フランス革命の原因と結果を教えてください",
            "中国の春秋戦国時代について教えてください",
            "アメリカ独立革命について教えてください",
        ],
    },
    {
        "title": "語学学習",
        "tools": ["translate", "wikipedia"],
        "starts": [
            "英語の仮定法過去について理解できないんですが...",
            "TOEIC 700点を目指しています。効率的な勉強法は？",
            "英語の冠詞（a/an/the）の使い方が混乱します",
            "英会話が上達しない理由と改善方法を教えてください",
            "フランス語を独学で始めたいのですが",
            "英語のイディオムを効率よく覚える方法は？",
            "日本語を外国人に教えるコツを教えてください",
            "英語のビジネスメールの書き方を教えてください",
        ],
    },
    {
        "title": "投資・財務計算",
        "tools": ["calculator", "wikipedia", "web_search"],
        "starts": [
            "NISAを始めたいのですが、何から始めればいいですか？",
            "iDeCoとNISAの違いを教えてください",
            "株式投資の基本を教えてください。リスクも含めて",
            "毎月5万円を20年間投資したらいくらになりますか？",
            "インデックス投資とアクティブ投資の違いは？",
            "不動産投資を考えているのですが、メリットデメリットは？",
            "老後2000万円問題について教えてください",
            "仮想通貨投資のリスクについて教えてください",
        ],
    },
    {
        "title": "ニュース深掘り",
        "tools": ["news_search", "wikipedia"],
        "starts": [
            "最近の円安について教えてください",
            "AI技術の最新動向を教えてください",
            "地球温暖化の現状と対策を教えてください",
            "少子化問題の原因と解決策を教えてください",
            "電気自動車の普及が遅い理由を教えてください",
            "半導体不足が経済に与える影響を教えてください",
            "食料安全保障について教えてください",
            "宇宙開発の最新状況を教えてください",
        ],
    },
]

SYSTEM_PROMPTS = [
    "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。",
    "あなたは附田（futa）です。日本語を中心に、ユーザーの質問に誠実かつ正確に答えます。必要に応じてツールを使い、<think>タグで思考過程を示してください。",
    "あなたは附田（futa）という名前のAIアシスタントです。深い思考力と幅広い知識を持ち、<think>タグで論理的に考えてから回答します。",
]

GEN_PROMPT = """「附田(futa)」と日本語ユーザーの会話を生成してください。

テーマ: {title}
使用ツール: {tools}
最初のユーザーの質問: {start}

生成条件:
- 4〜7ターン（userメッセージ4〜7個）
- ツールを2〜3回使用する
- assistant は毎回必ず <think>\\n...200字以上の思考...\\n</think> を含める
- ユーザーは前の回答を踏まえて自然に質問を深める

ツール呼び出し形式:
<tool_call>
{{"name": "ツール名", "arguments": {{"key": "value"}}}}
</tool_call>

ツール結果形式: {{"role": "tool", "name": "ツール名", "content": "{{結果JSON}}"}}

JSONリストのみ出力（説明文不要）:
[{{"role":"user","content":"..."}}, {{"role":"assistant","content":"<think>\\n思考\\n</think>\\n回答"}}, ...]"""


def _hash_conv(convs: list) -> str:
    user_msgs = " ".join(m.get("content", "")[:80] for m in convs if m.get("role") == "user")
    return hashlib.md5(user_msgs.encode()).hexdigest()


def generate_one(scenario: dict, start: str) -> list | None:
    prompt = GEN_PROMPT.format(
        title  = scenario["title"],
        tools  = ", ".join(scenario["tools"]),
        start  = start,
    )
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 4000,
                    "messages": [{"role": "user", "content": prompt}],
                },
                timeout=90,
            )
            if resp.status_code == 429:
                print("  [RATE] 30秒待機...", file=sys.stderr)
                time.sleep(30)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
        except requests.exceptions.Timeout:
            print(f"  [TIMEOUT] attempt {attempt+1}/3", file=sys.stderr)
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {str(e)[:60]}", file=sys.stderr)
            time.sleep(3)
            continue

        # JSON抽出
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

        user_count = sum(1 for m in convs if m.get("role") == "user")
        ass_count  = sum(1 for m in convs if m.get("role") == "assistant")
        thinks     = sum(1 for m in convs if m.get("role") == "assistant" and "<think>" in m.get("content", ""))

        if user_count >= 2 and ass_count >= 2 and thinks >= 1:
            return convs

    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",       default="long_multiturn_v2.json")
    parser.add_argument("--per-scenario", type=int, default=15)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path   = os.path.join(script_dir, args.output)

    results: list  = []
    done_hashes: set = set()
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            done_hashes.add(_hash_conv(r.get("conversations", [])))
        print(f"再開: {len(results)}件済み")

    total_target = len(SCENARIOS) * args.per_scenario
    print(f"目標: {total_target}件 ({len(SCENARIOS)}シナリオ × {args.per_scenario}件)")

    for scenario in SCENARIOS:
        already = sum(1 for r in results if r.get("scenario") == scenario["title"])
        need    = args.per_scenario - already
        if need <= 0:
            print(f"[{scenario['title']}] スキップ ({already}/{args.per_scenario})")
            continue

        print(f"\n[{scenario['title']}] {need}件生成...")

        # starts をシャッフルして多様性を確保
        starts   = scenario["starts"] * (args.per_scenario // len(scenario["starts"]) + 1)
        random.shuffle(starts)
        starts   = starts[:args.per_scenario + 5]  # 少し多めに用意

        generated = 0
        start_idx = 0
        fail      = 0

        while generated < need and fail < 20 and start_idx < len(starts):
            start = starts[start_idx]
            start_idx += 1

            convs = generate_one(scenario, start)
            if not convs:
                fail += 1
                time.sleep(1)
                continue

            h = _hash_conv(convs)
            if h in done_hashes:
                fail += 1
                continue

            sys_prompt = SYSTEM_PROMPTS[generated % len(SYSTEM_PROMPTS)]
            item = {
                "conversations": [{"role": "system", "content": sys_prompt}] + convs,
                "scenario":      scenario["title"],
                "category":      "long_multiturn",
            }
            results.append(item)
            done_hashes.add(h)
            generated += 1
            fail = 0

            user_turns  = sum(1 for m in convs if m["role"] == "user")
            think_count = sum(1 for m in convs if m["role"] == "assistant" and "<think>" in m.get("content", ""))
            think_lens  = [
                len(re.search(r"<think>(.*?)</think>", m.get("content", ""), re.DOTALL).group(1))
                for m in convs
                if m.get("role") == "assistant" and re.search(r"<think>(.*?)</think>", m.get("content", ""), re.DOTALL)
            ]
            avg_think = sum(think_lens) // max(len(think_lens), 1)
            print(f"  [{scenario['title']}] {generated}/{need}: {user_turns}ターン, think×{think_count}, avg {avg_think}字")

            if len(results) % 10 == 0:
                _save(results, out_path)

            time.sleep(0.5)

        print(f"  [{scenario['title']}] 完了: {generated}件")
        _save(results, out_path)

    _save(results, out_path)

    from collections import Counter
    sc_dist = Counter(r.get("scenario", "?") for r in results)
    print(f"\n完了: {len(results)}件 → {out_path}")
    for k, v in sorted(sc_dist.items()):
        print(f"  {k}: {v}件")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
