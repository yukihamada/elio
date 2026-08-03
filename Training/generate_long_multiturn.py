#!/usr/bin/env python3
"""
generate_long_multiturn.py — 6〜10ターンの自然なマルチターン会話生成
=====================================================================
研究で判明したベストプラクティス:
- 全ターンに loss をかける (all-round loss)
- 自然なコンテキスト継続（前の回答を踏まえた追加質問）
- ツール使用を含む複雑なシナリオ
- 5+ ターンが単一ターンより大幅にモデル性能を向上

Claude Sonnet 4.5 で生成（高品質な思考チェーン込み）。
"""
import json, os, re, sys, time, argparse, random, requests
random.seed(42)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SCENARIOS = [
    {
        "title": "旅行計画",
        "description": "ユーザーが旅行先を相談し、天気・観光・費用計算まで深める",
        "tools": ["weather", "wikipedia", "calculator"],
        "example_start": "来月京都に旅行したいのですが、おすすめの時期はいつですか？",
        "turns": 7,
    },
    {
        "title": "プログラミング学習",
        "description": "Pythonを学ぶユーザーが概念→実装→デバッグと深める",
        "tools": ["wikipedia", "code_execute"],
        "example_start": "Pythonの辞書型について教えてください",
        "turns": 8,
    },
    {
        "title": "料理レシピ研究",
        "description": "料理を作りたいユーザーが食材・作り方・栄養まで掘り下げる",
        "tools": ["wikipedia", "calculator"],
        "example_start": "ラタトゥイユを作りたいのですが、材料を教えてください",
        "turns": 6,
    },
    {
        "title": "健康・運動計画",
        "description": "健康改善を目指すユーザーがBMI計算・運動計画・栄養まで相談",
        "tools": ["calculator", "wikipedia"],
        "example_start": "最近運動不足で体重も増えてきました。何から始めればいいですか？",
        "turns": 7,
    },
    {
        "title": "歴史探求",
        "description": "歴史的なテーマをWikipediaで調べながら深掘りする",
        "tools": ["wikipedia"],
        "example_start": "江戸時代の経済システムについて教えてください",
        "turns": 8,
    },
    {
        "title": "語学学習",
        "description": "英語学習者が文法・単語・翻訳を通じて学ぶ",
        "tools": ["translate", "wikipedia"],
        "example_start": "英語の仮定法過去について理解できないんですが...",
        "turns": 7,
    },
    {
        "title": "投資・財務計算",
        "description": "投資初心者が基礎知識から具体的な計算まで相談",
        "tools": ["calculator", "wikipedia", "web_search"],
        "example_start": "NISAを始めたいのですが、何から始めればいいですか？",
        "turns": 8,
    },
    {
        "title": "ニュース深堀り",
        "description": "最新ニュースの背景をWikipediaで深く理解する",
        "tools": ["news_search", "wikipedia"],
        "example_start": "最近の円安について教えてください",
        "turns": 6,
    },
]

SYSTEM_PROMPTS = [
    "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。",
    "あなたは附田（futa）です。日本語を中心に、ユーザーの質問に誠実かつ正確に答えます。必要に応じてツールを使い、<think>タグで思考過程を示してください。",
]

GEN_PROMPT_TEMPLATE = """「附田(futa)」と日本語ユーザーの会話を生成してください。

テーマ: {title} ({description})
ツール: {tools}
最初の質問: {example_start}

条件:
- {turns}ターン（userメッセージ{turns}個）
- ツールを2回以上使う
- assistant は毎回 <think> タグ（200字以上）で考える
- ツール形式: <tool_call>\\n{{"name":"ツール名","arguments":{{...}}}}\\n</tool_call>
- ツール結果ロール: {{"role":"tool","content":"{{結果JSON}}","name":"ツール名"}}

JSONリストのみ出力:
[{{"role":"user","content":"質問"}},{{"role":"assistant","content":"<think>\\n思考\\n</think>\\n回答か<tool_call>..."}},...] """


def generate_multiturn(client, scenario: dict) -> list | None:
    prompt = GEN_PROMPT_TEMPLATE.format(
        turns        = scenario["turns"],
        title        = scenario["title"],
        description  = scenario["description"],
        tools        = ", ".join(scenario["tools"]),
        example_start= scenario["example_start"],
    )

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
            return None
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()

        # JSONを抽出・修復
        text = re.sub(r'```(?:json)?\s*', '', text)
        text = re.sub(r'```\s*', '', text).strip()
        start = text.find('[')
        end   = text.rfind(']')
        if start < 0 or end <= start:
            return None

        raw = text[start:end+1]
        # 制御文字除去 (タブ/改行以外)
        raw = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', raw)

        try:
            convs = json.loads(raw)
        except json.JSONDecodeError:
            try:
                import json_repair
                convs = json_repair.repair_json(raw, return_objects=True)
            except Exception as e:
                raise json.JSONDecodeError(str(e), raw, 0)

        # 必ずdictのリストになるよう正規化
        if not isinstance(convs, list) or len(convs) < 4:
            return None
        convs = [m for m in convs if isinstance(m, dict)]
        if len(convs) < 4:
            return None

        # 検証: user・assistant の交互確認
        user_count = sum(1 for m in convs if m.get("role") == "user")
        ass_count  = sum(1 for m in convs if m.get("role") == "assistant")
        if user_count < 2 or ass_count < 2:
            return None

        # think タグ確認 (最低1つ)
        thinks = sum(1 for m in convs
                     if m.get("role") == "assistant" and "<think>" in m.get("content",""))
        if thinks < 1:
            return None

        return convs

    except (json.JSONDecodeError, Exception) as e:
        print(f"  [WARN] パースエラー: {str(e)[:60]}", file=sys.stderr)
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",  default="long_multiturn.json")
    parser.add_argument("--per-scenario", type=int, default=15,
                        help="シナリオあたりの生成件数")
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
    client = None  # HTTP client used directly
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path   = os.path.join(script_dir, args.output)

    results: list   = []
    done_starts: set = set()
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            convs = r.get("conversations", [])
            if convs:
                first_user = next((m["content"] for m in convs if m["role"] == "user"), "")
                done_starts.add(first_user[:50])
        print(f"再開: {len(results)}件済み")

    total = len(SCENARIOS) * args.per_scenario
    print(f"目標: {total}件 ({len(SCENARIOS)}シナリオ × {args.per_scenario}件)")

    for scenario in SCENARIOS:
        already = sum(1 for r in results if r.get("scenario") == scenario["title"])
        need    = args.per_scenario - already
        if need <= 0:
            print(f"[{scenario['title']}] スキップ ({already}/{args.per_scenario})")
            continue

        print(f"\n[{scenario['title']}] {need}件生成...")
        generated = 0
        fail      = 0

        while generated < need and fail < 15:
            convs = generate_multiturn(client, scenario)
            if not convs:
                fail += 1
                time.sleep(1)
                continue

            first_user = next((m["content"] for m in convs if m["role"] == "user"), "")
            if first_user[:50] in done_starts:
                fail += 1
                continue

            sys_prompt = SYSTEM_PROMPTS[generated % len(SYSTEM_PROMPTS)]
            item = {
                "conversations": [{"role": "system", "content": sys_prompt}] + convs,
                "scenario":      scenario["title"],
                "category":      "long_multiturn",
            }
            results.append(item)
            done_starts.add(first_user[:50])
            generated += 1
            fail = 0

            # 統計
            user_turns = sum(1 for m in convs if m["role"] == "user")
            think_count = sum(1 for m in convs if m["role"] == "assistant" and "<think>" in m.get("content",""))
            think_lens  = [len(re.search(r'<think>(.*?)</think>', m["content"], re.DOTALL).group(1))
                           for m in convs if m["role"] == "assistant"
                           and re.search(r'<think>(.*?)</think>', m["content"], re.DOTALL)]
            avg_think = sum(think_lens) // max(len(think_lens), 1)
            print(f"  [{scenario['title']}] {generated}/{need}: {user_turns}ターン, think×{think_count}, avg {avg_think}字")

            if len(results) % 10 == 0:
                _save(results, out_path)

            time.sleep(1.0)

        print(f"  [{scenario['title']}] 完了: {generated}件")
        _save(results, out_path)

    _save(results, out_path)

    # 統計
    from collections import Counter
    turn_dist = Counter(
        sum(1 for m in r["conversations"] if m["role"] == "user")
        for r in results
    )
    print(f"\n完了: {len(results)}件 → {out_path}")
    print("ターン数分布:")
    for k, v in sorted(turn_dist.items()):
        print(f"  {k}ターン: {v}件")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
