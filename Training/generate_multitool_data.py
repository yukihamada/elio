#!/usr/bin/env python3
"""
generate_multitool_data.py — 2〜3ツールを連鎖使用する会話データ生成
===================================================================
例:
  - wikipedia → translate: 調べて英訳
  - calculator → calculator: 複数ステップ計算
  - web_search → calculator: 価格取得→計算
  - datetime → calculator: 日数計算
  - wikipedia → calculator: 数値情報を取得して計算
"""
import json, os, re, sys, time, argparse, random
import openai

def make_client():
    key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not key:
        print("ERROR: GOOGLE_API_KEY が必要です", file=sys.stderr)
        sys.exit(1)
    return openai.OpenAI(
        api_key=key,
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
    ), "gemini-2.0-flash"


# ── ツールコンビネーションと質問テンプレ ─────────────────────────
COMBOS = [
    # (tool1, tool2, ユーザー質問パターン, 想定ツール結果)
    {
        "tools": ["wikipedia", "calculator"],
        "queries": [
            "富士山の標高はエベレストの何%ですか？",
            "東京の人口は大阪の何倍ですか？",
            "日本の面積はアメリカの何%ですか？",
            "光の速度で地球を一周するのに何秒かかりますか？",
            "日本の人口密度（人/km²）を計算してください",
        ],
        "tool1_result": {"title": "富士山", "summary": "富士山の標高は3,776メートル。日本最高峰の火山。"},
        "tool2_result": {"result": 42.3, "expression": "3776/8848*100"},
    },
    {
        "tools": ["datetime", "calculator"],
        "queries": [
            "今年の残り日数と、それが全体の何%かを教えて",
            "今日から100日後は何月何日で、現在からの経過日数は？",
            "今年の元旦から今日まで何週間経ちましたか？",
            "次の大型連休（ゴールデンウィーク）まで何日ありますか？",
        ],
        "tool1_result": {"date": "2026-03-05", "weekday": "木曜日", "datetime": "2026-03-05 18:30:00"},
        "tool2_result": {"result": 301, "expression": "365-64"},
    },
    {
        "tools": ["wikipedia", "translate"],
        "queries": [
            "源氏物語についてwikipediaで調べて英語で要約してください",
            "浮世絵とは何か調べて、英語で説明してください",
            "侘び寂びの概念をWikipediaで調べて英語で説明して",
            "武士道とは何か調べて英語にしてください",
        ],
        "tool1_result": {"title": "源氏物語", "summary": "源氏物語は11世紀初頭に紫式部が著した長編物語。光源氏の恋愛や政治的活動を描く。世界最古の長編小説の一つとされる。"},
        "tool2_result": {"translated": "The Tale of Genji is a long narrative written by Murasaki Shikibu in the early 11th century, depicting the romantic and political activities of Hikaru Genji. It is considered one of the world's oldest novels."},
    },
    {
        "tools": ["calculator", "calculator"],
        "queries": [
            "月収30万円で税率20%の場合、手取りと年収手取りを計算して",
            "1000万円を年利5%で複利運用した場合の5年後と10年後の金額を教えて",
            "体重65kg、身長175cmのBMIと、標準体重との差を計算して",
        ],
        "tool1_result": {"result": 240000, "expression": "300000*(1-0.20)"},
        "tool2_result": {"result": 2880000, "expression": "240000*12"},
    },
    {
        "tools": ["news_search", "wikipedia"],
        "queries": [
            "最近の人工知能ニュースを調べて、AIの歴史もwikipediaで確認してください",
            "気候変動に関する最新ニュースを調べてから、地球温暖化についてwikipediaで詳しく教えて",
        ],
        "tool1_result": {"query": "人工知能", "articles": [{"title": "ChatGPT、新機能を発表"}, {"title": "AI規制法案、国会で審議へ"}], "count": 2},
        "tool2_result": {"title": "人工知能", "summary": "人工知能（AI）は、機械が人間の知的活動（学習・推論・問題解決など）を模倣する技術。1956年のダートマス会議で命名された。"},
    },
]


SYSTEM_TEMPLATE = """あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。"""


def call_gemini(client, model, prompt, max_tokens=1200, temp=0.75):
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temp,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"  [WARN] LLMエラー: {e}", file=sys.stderr)
        time.sleep(2)
        return None


def generate_multitool_conversation(client, model, combo: dict, user_query: str) -> dict | None:
    tools = combo["tools"]
    t1_result = combo["tool1_result"]
    t2_result = combo["tool2_result"]

    prompt = f"""以下の2ステップのツール使用シナリオで、AIアシスタント「附田(futa)」の完全な会話を生成してください。

ユーザーの質問: {user_query}
使用ツール順: {tools[0]} → {tools[1]}
ツール1の結果例: {json.dumps(t1_result, ensure_ascii=False)}
ツール2の結果例: {json.dumps(t2_result, ensure_ascii=False)}

以下のフォーマットで出力してください（実際の数値・内容は自然に調整してOK）:

CALL1_THINK:
（{tools[0]}ツールを使う理由の思考。80〜150字）

TOOL1_ARGS:
{{"name": "{tools[0]}", "arguments": {{...}}}}

TOOL1_RESULT:
{{...実際の結果（できれば正確な数値）...}}

CALL2_THINK:
（ツール1の結果を踏まえて{tools[1]}ツールを使う理由の思考。80〜200字）

TOOL2_ARGS:
{{"name": "{tools[1]}", "arguments": {{...}}}}

TOOL2_RESULT:
{{...実際の結果...}}

FINAL_THINK:
（両ツールの結果を統合して回答する思考。100〜250字）

FINAL_RESPONSE:
（ユーザーへの最終回答。200〜400字。具体的な数値・情報を含む）"""

    text = call_gemini(client, model, prompt, max_tokens=1500, temp=0.75)
    if not text:
        return None

    def extract(label, text):
        m = re.search(rf'{label}:\s*(.*?)(?=\n[A-Z1-9_]+:|$)', text, re.DOTALL)
        return m.group(1).strip() if m else ""

    call1_think   = re.sub(r'</?think>', '', extract("CALL1_THINK", text)).strip()
    tool1_args_s  = extract("TOOL1_ARGS", text)
    tool1_result_s= extract("TOOL1_RESULT", text)
    call2_think   = re.sub(r'</?think>', '', extract("CALL2_THINK", text)).strip()
    tool2_args_s  = extract("TOOL2_ARGS", text)
    tool2_result_s= extract("TOOL2_RESULT", text)
    final_think   = re.sub(r'</?think>', '', extract("FINAL_THINK", text)).strip()
    final_resp    = extract("FINAL_RESPONSE", text)

    # 必須フィールドチェック
    if not all([call1_think, tool1_args_s, call2_think, tool2_args_s, final_think, final_resp]):
        return None

    def parse_json_safe(s):
        s = re.sub(r'```(?:json)?\s*', '', s)
        s = re.sub(r'```\s*', '', s).strip()
        start = s.find('{')
        end   = s.rfind('}')
        if start >= 0 and end > start:
            try:
                return json.loads(s[start:end+1])
            except Exception:
                pass
        return None

    t1_args = parse_json_safe(tool1_args_s)
    t2_args = parse_json_safe(tool2_args_s)
    t1_res  = parse_json_safe(tool1_result_s) or t1_result
    t2_res  = parse_json_safe(tool2_result_s) or t2_result

    if not (t1_args and t2_args):
        return None

    # 会話組み立て
    t1_call_json = json.dumps(t1_args, ensure_ascii=False)
    t2_call_json = json.dumps(t2_args, ensure_ascii=False)

    return {
        "conversations": [
            {"role": "system",    "content": SYSTEM_TEMPLATE},
            {"role": "user",      "content": user_query},
            {"role": "assistant", "content": f"<think>\n{call1_think}\n</think>\n\n<tool_call>\n{t1_call_json}\n</tool_call>"},
            {"role": "tool",      "content": json.dumps(t1_res, ensure_ascii=False), "name": tools[0]},
            {"role": "assistant", "content": f"<think>\n{call2_think}\n</think>\n\n<tool_call>\n{t2_call_json}\n</tool_call>"},
            {"role": "tool",      "content": json.dumps(t2_res, ensure_ascii=False), "name": tools[1]},
            {"role": "assistant", "content": f"<think>\n{final_think}\n</think>\n\n{final_resp}"},
        ],
        "category": f"multitool_{tools[0]}_{tools[1]}",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",    default="multitool_data.json")
    parser.add_argument("--per-combo", type=int, default=60)
    args = parser.parse_args()

    client, model = make_client()
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)

    results = []
    done_queries = set()
    if os.path.exists(output_path):
        with open(output_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            done_queries.add(r["conversations"][1]["content"])  # user query
        print(f"再開: {len(results)}件")

    total_target = len(COMBOS) * args.per_combo
    print(f"目標: {total_target}件 ({len(COMBOS)}コンボ × {args.per_combo}件)")

    for combo in COMBOS:
        label = f"{combo['tools'][0]}+{combo['tools'][1]}"
        already = sum(1 for r in results
                      if r.get("category", "").startswith(f"multitool_{combo['tools'][0]}_{combo['tools'][1]}"))
        need = args.per_combo - already
        if need <= 0:
            print(f"[{label}] スキップ ({already}/{args.per_combo})")
            continue

        print(f"\n[{label}] {need}件生成...")
        generated = 0
        fail = 0

        # 追加クエリを動的生成
        queries = list(combo["queries"])
        while len(queries) < need + 5:
            extra_prompt = f"以下のような質問をさらに10個考えてください（{label}を使うシナリオ）:\n" + \
                           "\n".join(combo["queries"][:3]) + \
                           "\n\n新しい質問を1行ずつ（番号なし）:"
            text = call_gemini(client, model, extra_prompt, max_tokens=400, temp=0.9)
            if text:
                new_qs = [l.strip().lstrip("・-•*1234567890.）) ") for l in text.split("\n") if len(l.strip()) > 8]
                queries.extend(new_qs[:10])
            else:
                break

        for query in queries:
            if generated >= need:
                break
            if query in done_queries:
                continue

            conv = generate_multitool_conversation(client, model, combo, query)
            if not conv:
                fail += 1
                if fail > 10:
                    break
                continue

            results.append(conv)
            done_queries.add(query)
            generated += 1
            fail = 0
            print(f"  [{label}] {generated}/{need}: {query[:55]}")

            if len(results) % 20 == 0:
                with open(output_path, "w", encoding="utf-8") as f:
                    json.dump(results, f, ensure_ascii=False)

            time.sleep(0.5)

        print(f"  [{label}] 完了: {generated}件")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False)

    print(f"\n完了: {len(results)}件 → {output_path}")
    from collections import Counter
    for c, n in sorted(Counter(r.get("category") for r in results).items()):
        print(f"  {c}: {n}件")


if __name__ == "__main__":
    main()
