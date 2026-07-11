#!/usr/bin/env python3
"""
generate_recovery_multiturn.py — ツール失敗・ユーザー訂正「回復」シナリオ生成
============================================================================
論文: "LLMs Get Lost In Multi-Turn Conversation" (arXiv 2505.06120)
     マルチターンで39%性能低下 → 「失敗からの回復」を明示的に学習させる

回復シナリオ 4種:
  1. tool_fail_retry   : ツール失敗 → 別引数でリトライ or 別ツール使用
  2. user_correction   : ユーザーが「違う」と訂正 → 正しく対応
  3. ambiguous_clarify : 曖昧な質問 → 確認 → 本来の回答
  4. partial_wrong     : 部分的に間違い → ユーザー指摘 → 修正
"""
import json, os, re, sys, time, argparse, random, hashlib, requests

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPT = "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。"

RECOVERY_SCENARIOS = {
    "tool_fail_retry": {
        "desc": "ツール呼び出しが失敗し、別の方法で対応する",
        "template": """以下のシナリオのマルチターン会話を生成してください。

テーマ: {topic}
ツール: {tools}

シナリオ: ユーザーが質問 → AIがツールを呼ぶ → ツールがエラーを返す → AIが別引数または別ツールで再試行 → 成功して回答

生成条件:
- 3〜5ターン
- ツール失敗時のエラーメッセージは現実的に（タイムアウト・入力不正・データなし等）
- AI は冷静にエラーを認識し、<think>内で対処法を考える
- 最終的にユーザーの質問に答える

ツール呼び出し形式: <tool_call>{{"name": "ツール名", "arguments": {{"key": "value"}}}}</tool_call>
ツール結果形式: {{"role": "tool", "name": "ツール名", "content": "{{結果 or エラー}}"}}

JSONリストのみ出力:
[{{"role":"system","content":"{system}"}},{{"role":"user","content":"..."}},...]""",
    },
    "user_correction": {
        "desc": "ユーザーが最初の回答に異議・訂正をする",
        "template": """以下のシナリオのマルチターン会話を生成してください。

テーマ: {topic}

シナリオ: ユーザーが質問 → AIが回答 → ユーザーが「それは違う」「もっと具体的に」と訂正・追加要求 → AIが<think>内で誤りを認識して修正 → 改善された回答

生成条件:
- 4〜6ターン
- ユーザーの訂正は自然な日本語で（「え、でもそれって〜じゃないの？」「もっと〜な感じで教えて」）
- AIは<think>内で自分の誤りを認め、修正方針を考える
- 回答を謙虚に修正・改善する

JSONリストのみ出力:
[{{"role":"system","content":"{system}"}},{{"role":"user","content":"..."}},...]""",
    },
    "ambiguous_clarify": {
        "desc": "曖昧な質問に対して確認を取ってから回答する",
        "template": """以下のシナリオのマルチターン会話を生成してください。

テーマ: {topic}

シナリオ: ユーザーが曖昧/不完全な質問 → AIが<think>内で複数解釈を考慮し確認質問 → ユーザーが意図を明確化 → AIが適切に回答

生成条件:
- 4〜5ターン
- 最初の質問は意図が2通り以上に取れるもの（例:「これ調べて」「おすすめを教えて」）
- AIの確認質問は1つに絞る（質問攻めしない）
- <think>内で「Aと解釈すると〜、Bと解釈すると〜」と考える

JSONリストのみ出力:
[{{"role":"system","content":"{system}"}},{{"role":"user","content":"..."}},...]""",
    },
    "partial_wrong": {
        "desc": "部分的な誤りをユーザーが指摘し修正する",
        "template": """以下のシナリオのマルチターン会話を生成してください。

テーマ: {topic}
ツール: {tools}

シナリオ: ユーザーが質問 → AIがツール使用して回答（一部に軽微な誤り混入） → ユーザーが「〇〇は違う気がする」と指摘 → AIが<think>内で再確認し誤りを認める → 正確な情報で修正

生成条件:
- 4〜6ターン
- 誤りは深刻ではなく軽微なもの（日付ずれ・単位ミス・別スポットの情報等）
- AIは誤りを素直に認め、「ご指摘ありがとうございます」と訂正
- <think>内で「確かに〜の点が誤りでした」と自己批評

JSONリストのみ出力:
[{{"role":"system","content":"{system}"}},{{"role":"user","content":"..."}},...]""",
    },
}

TOPICS = [
    ("旅行計画", ["weather", "web_search", "calculator"]),
    ("料理レシピ", ["calculator", "wikipedia"]),
    ("プログラミング", ["code_execute", "web_search"]),
    ("健康・運動", ["calculator", "wikipedia"]),
    ("買い物・価格調査", ["web_search", "calculator"]),
    ("ニュース・時事", ["news_search", "web_search"]),
    ("語学学習", ["translate", "wikipedia"]),
    ("カレンダー管理", ["list_events", "create_event"]),
    ("天気確認", ["get_current_weather", "get_forecast"]),
    ("メモ作成", ["create_note", "search_notes"]),
    ("投資・財務", ["calculator", "web_search"]),
    ("スポーツ・柔術", ["web_search", "wikipedia"]),
    ("音楽情報", ["web_search", "wikipedia"]),
    ("観光スポット", ["web_search", "get_current_location"]),
    ("歴史調査", ["wikipedia", "web_search"]),
]


def generate_one(scenario_type: str, topic: str, tools: list) -> list | None:
    scenario = RECOVERY_SCENARIOS[scenario_type]
    prompt = scenario["template"].format(
        topic=topic,
        tools=", ".join(tools),
        system=SYSTEM_PROMPT,
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
                time.sleep(30)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
        except requests.exceptions.Timeout:
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {e}", file=sys.stderr)
            time.sleep(3)
            continue

        text = re.sub(r"```(?:json)?\s*", "", text)
        text = re.sub(r"```\s*", "", text).strip()
        s, e = text.find("["), text.rfind("]")
        if s < 0 or e <= s:
            continue
        raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", text[s:e+1])

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
        thinks = sum(1 for m in convs if m.get("role") == "assistant"
                     and "<think>" in m.get("content", ""))

        if user_count >= 2 and thinks >= 1:
            return convs

    return None


def _hash(convs):
    user_msgs = " ".join(m.get("content","")[:80] for m in convs if m.get("role")=="user")
    return hashlib.md5(user_msgs.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",    default="recovery_multiturn.json")
    parser.add_argument("--per-type",  type=int, default=30,
                        help="シナリオタイプ×トピックあたりの件数")
    parser.add_argument("--target",    type=int, default=400)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)

    results = []
    done_hashes = set()
    if os.path.exists(out_path):
        results = json.load(open(out_path, encoding="utf-8"))
        for r in results:
            done_hashes.add(_hash(r.get("conversations", [])))
        print(f"再開: {len(results)}件済み")

    scenario_types = list(RECOVERY_SCENARIOS.keys())
    random.seed(77)

    generated = 0
    print(f"目標: {args.target}件 | シナリオ: {scenario_types}")

    while generated < args.target - len(results):
        s_type = random.choice(scenario_types)
        topic, tools = random.choice(TOPICS)

        convs = generate_one(s_type, topic, tools)
        if not convs:
            time.sleep(1)
            continue

        h = _hash(convs)
        if h in done_hashes:
            continue

        think_lens = [
            len(t.group(1))
            for m in convs if m.get("role") == "assistant"
            for t in [re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)] if t
        ]
        avg_think = sum(think_lens) // max(len(think_lens), 1)

        item = {
            "conversations": convs,
            "scenario_type": s_type,
            "topic": topic,
            "category": "recovery_multiturn",
            "source": "recovery_v1",
        }
        results.append(item)
        done_hashes.add(h)
        generated += 1

        user_turns = sum(1 for m in convs if m.get("role") == "user")
        print(f"  [{len(results)}/{args.target}] {s_type} / {topic}: "
              f"{user_turns}ターン, think avg {avg_think}字")

        if len(results) % 20 == 0:
            with open(out_path, "w", encoding="utf-8") as f:
                json.dump(results, f, ensure_ascii=False)

        time.sleep(0.5)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False)

    from collections import Counter
    type_dist = Counter(r.get("scenario_type","?") for r in results)
    print(f"\n完了: {len(results)}件 → {out_path}")
    for k, v in sorted(type_dist.items()):
        print(f"  {k}: {v}件")


if __name__ == "__main__":
    main()
