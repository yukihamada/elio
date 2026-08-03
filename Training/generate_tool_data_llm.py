#!/usr/bin/env python3
"""
LLM-Powered Tool Calling Data Generator
=========================================

Uses Claude to generate diverse Japanese queries for each tool (200/tool = 3,000 total),
then builds full training examples with <think> + <tool_call> + tool result + response.

Usage:
    python generate_tool_data_llm.py --output tool_data_llm.json
    python generate_tool_data_llm.py --output tool_data_llm.json --queries_per_tool 100
"""

import argparse
import json
import os
import random
import re
import sys
import time

import openai
client = openai.OpenAI()
MODEL = "gpt-4.1-mini"

# ─── Tool specs ───

TOOL_SPECS = {
    "web_search": {
        "desc": "最新情報・現在の出来事・価格・商品・ニュースなどを検索するツール",
        "args": {"query": "検索クエリ文字列"},
        "mock_result_template": '{{"results": [{{"title": "{title}", "snippet": "{snippet}"}}]}}',
        "contexts": ["最新ニュース", "商品検索", "人物調査", "技術情報", "スポーツ結果", "映画・音楽", "レシピ・料理", "旅行・観光"],
    },
    "calculator": {
        "desc": "数式を計算するツール（四則演算、べき乗、平方根、パーセント計算など）",
        "args": {"expression": "数式文字列（Pythonの数式形式）"},
        "mock_result_template": '{{"result": {result}}}',
        "contexts": ["日常計算", "ビジネス計算", "数学問題", "単位変換", "割合計算", "複利計算"],
    },
    "weather": {
        "desc": "指定した場所の現在の天気・気温・湿度を取得するツール",
        "args": {"location": "場所名（都市名・地域名）"},
        "mock_result_template": '{{"location": "{location}", "temperature": 20, "condition": "晴れ", "humidity": 55}}',
        "contexts": ["外出前の確認", "旅行計画", "農業・農作業", "スポーツ・アウトドア", "ファッション選択"],
    },
    "translate": {
        "desc": "テキストを別の言語に翻訳するツール",
        "args": {"text": "翻訳するテキスト", "target_lang": "翻訳先言語コード（ja/en/zh/ko等）"},
        "mock_result_template": '{{"translated": "{translated}"}}',
        "contexts": ["ビジネスメール翻訳", "旅行会話", "外国語学習", "SNS投稿", "映画・音楽タイトル", "料理名"],
    },
    "wikipedia": {
        "desc": "Wikipediaで歴史・人物・科学・地理などの知識を検索するツール",
        "args": {"query": "検索キーワード"},
        "mock_result_template": '{{"title": "{title}", "summary": "{summary}"}}',
        "contexts": ["歴史上の人物", "科学・技術", "地理・地名", "文化・芸術", "スポーツ選手", "動植物"],
    },
    "datetime": {
        "desc": "日付計算・曜日確認・閏年チェックなどを行うツール",
        "args": {"operation": "操作種別（add_days/day_of_week/is_leap_year等）", "value": "操作対象の値"},
        "mock_result_template": '{{"result": "{result}"}}',
        "contexts": ["イベント計画", "期限計算", "記念日", "年齢計算", "プロジェクト管理"],
    },
    "create_qr": {
        "desc": "テキスト・URL・WiFi情報などからQRコードを生成するツール",
        "args": {"content": "QRコードに埋め込むテキストまたはURL"},
        "mock_result_template": '{{"qr_url": "https://api.chatweb.ai/qr/sample.png"}}',
        "contexts": ["URL共有", "WiFi設定共有", "名刺・連絡先", "イベント告知", "商品情報"],
    },
    "news_search": {
        "desc": "最新ニュースを検索するツール",
        "args": {"query": "検索キーワード", "category": "カテゴリ（technology/sports/business/politics等）"},
        "mock_result_template": '{{"articles": [{{"title": "{title}", "source": "日経新聞", "summary": "{summary}"}}]}}',
        "contexts": ["テクノロジー", "スポーツ", "ビジネス・経済", "政治", "エンタメ", "健康"],
    },
    "code_execute": {
        "desc": "PythonやShellコードを実行して結果を得るツール",
        "args": {"language": "言語（python/shell）", "code": "実行するコード"},
        "mock_result_template": '{{"output": "{output}", "exit_code": 0}}',
        "contexts": ["数値計算", "データ変換", "ファイル操作", "テキスト処理", "日付処理", "乱数生成"],
    },
    "image_generate": {
        "desc": "テキストプロンプトから画像を生成するツール",
        "args": {"prompt": "英語の画像生成プロンプト", "style": "スタイル（photorealistic/anime/watercolor/digital art等）"},
        "mock_result_template": '{{"image_url": "https://image.pollinations.ai/prompt/sample"}}',
        "contexts": ["イラスト作成", "壁紙・背景", "キャラクター", "風景・自然", "食べ物", "建物・都市"],
    },
    "image_analyze": {
        "desc": "画像の内容を分析・説明するツール",
        "args": {"image_url": "分析する画像のURL", "question": "画像について知りたいこと"},
        "mock_result_template": '{{"description": "画像には{description}が写っています。"}}',
        "contexts": ["写真の内容確認", "料理識別", "植物・動物識別", "テキスト読み取り", "場所特定"],
    },
    "read_webpage": {
        "desc": "指定URLのWebページ内容を取得・要約するツール",
        "args": {"url": "読み取るWebページのURL"},
        "mock_result_template": '{{"title": "{title}", "content": "{content}"}}',
        "contexts": ["記事・ブログ読み取り", "公式サイト確認", "文書・PDF", "ニュース詳細"],
    },
    "file_read": {
        "desc": "サンドボックス内のファイルを読み込むツール",
        "args": {"path": "ファイルパス（/tmp/sandbox/以下）"},
        "mock_result_template": '{{"content": "{content}"}}',
        "contexts": ["データファイル確認", "設定ファイル読み取り", "メモ・ノート確認"],
    },
    "file_write": {
        "desc": "サンドボックスにファイルを書き込むツール",
        "args": {"path": "ファイルパス（/tmp/sandbox/以下）", "content": "書き込む内容"},
        "mock_result_template": '{{"success": true, "path": "{path}"}}',
        "contexts": ["メモ保存", "データ出力", "HTMLファイル作成", "設定保存"],
    },
    "file_list": {
        "desc": "サンドボックスのディレクトリ内のファイル一覧を取得するツール",
        "args": {"path": "ディレクトリパス（/tmp/sandbox/以下）"},
        "mock_result_template": '{{"files": ["data.csv", "memo.txt"], "directories": ["output"]}}',
        "contexts": ["作業ファイル確認", "生成済みファイル一覧"],
    },
}

# ─── Generate diverse queries per tool ───

def generate_queries_for_tool(tool_name: str, spec: dict, n: int) -> list[dict]:
    """Use Claude to generate n diverse Japanese queries for a tool."""
    prompt = f"""あなたはトレーニングデータ生成AIです。

ツール: {tool_name}
ツールの説明: {spec['desc']}
ツールの引数: {json.dumps(spec['args'], ensure_ascii=False)}
想定されるユースケース: {', '.join(spec['contexts'])}

このツールを使いたくなる日本語のユーザー発言を{n}個生成してください。
条件:
- 多様なシチュエーション・言い回しを使うこと（「〜を教えて」「〜は？」「〜してほしい」「〜調べて」など様々なパターン）
- 日常会話〜ビジネス場面まで幅広く
- 具体的な固有名詞を含む質問を多く含めること
- 1行1質問、番号なし

JSON配列で返してください。例: ["質問1", "質問2", ...]"""

    resp = client.chat.completions.create(
        model=MODEL,
        max_tokens=4000,
        messages=[{"role": "user", "content": prompt}],
    )
    text = resp.choices[0].message.content.strip()

    # Extract JSON array
    match = re.search(r'\[.*\]', text, re.DOTALL)
    if match:
        try:
            queries = json.loads(match.group())
            return queries[:n]
        except Exception:
            pass

    # Fallback: parse line by line
    lines = [l.strip().strip('"').strip("'") for l in text.split('\n') if l.strip() and not l.strip().startswith('[')]
    return lines[:n]


def build_tool_example(tool_name: str, spec: dict, query: str) -> dict | None:
    """Use Claude to build a complete training example for a tool query."""
    prompt = f"""以下のユーザー発言に対して、AIアシスタントが {tool_name} ツールを使って回答するトレーニングデータを生成してください。

ユーザー発言: {query}
ツール: {tool_name}
ツール引数形式: {json.dumps(spec['args'], ensure_ascii=False)}

以下のJSON形式で厳密に返してください（マークダウン不要、JSONのみ）:
{{
  "think": "日本語の思考過程（2〜5文、なぜこのツールを使うかの推論）",
  "tool_args": {{{', '.join(f'"{k}": "..."' for k in spec['args'])}}},
  "mock_result": "ツールから返ってきそうなJSONの文字列",
  "response": "ツール結果を踏まえた日本語の最終回答（Markdownで整形）"
}}"""

    try:
        resp = client.chat.completions.create(
            model=MODEL,
            max_tokens=1000,
            messages=[{"role": "user", "content": prompt}],
        )
        text = resp.choices[0].message.content.strip()

        # Extract JSON
        match = re.search(r'\{.*\}', text, re.DOTALL)
        if not match:
            return None
        data = json.loads(match.group())

        tool_call_json = json.dumps(
            {"name": tool_name, "arguments": data["tool_args"]},
            ensure_ascii=False
        )

        return {
            "conversations": [
                {"role": "user", "content": query},
                {
                    "role": "assistant",
                    "content": f"<think>\n{data['think']}\n</think>\n\n<tool_call>\n{tool_call_json}\n</tool_call>",
                },
                {"role": "tool", "name": tool_name, "content": data["mock_result"]},
                {"role": "assistant", "content": data["response"]},
            ]
        }
    except Exception as e:
        return None


# ─── No-tool examples ───

def generate_notool_examples(n: int) -> list[dict]:
    """Use Claude to generate direct-answer (no tool needed) examples."""
    prompt = f"""日本語のAIアシスタントとユーザーの会話トレーニングデータを{n}個生成してください。
条件:
- ツールを使わずに直接答えられる質問（雑談、常識問題、アドバイス、感情サポート等）
- 必ず<think>タグ内に日本語の思考過程を含めること
- 多様なシチュエーション（挨拶、悩み相談、雑学、意見、感想等）

JSON配列で返してください（各要素はconversationsキーを持つオブジェクト）:
[
  {{
    "conversations": [
      {{"role": "user", "content": "ユーザーの発言"}},
      {{"role": "assistant", "content": "<think>\\n思考過程\\n</think>\\n\\n回答"}}
    ]
  }},
  ...
]"""

    try:
        resp = client.chat.completions.create(
            model=MODEL,
            max_tokens=8000,
            messages=[{"role": "user", "content": prompt}],
        )
        text = resp.choices[0].message.content.strip()
        match = re.search(r'\[.*\]', text, re.DOTALL)
        if match:
            return json.loads(match.group())
    except Exception as e:
        print(f"  Error generating no-tool examples: {e}")
    return []


# ─── Main ───

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="tool_data_llm.json")
    parser.add_argument("--queries_per_tool", type=int, default=200,
                        help="Number of diverse queries per tool (default=200, 15 tools = 3,000 total)")
    parser.add_argument("--notool_count", type=int, default=300,
                        help="Number of direct-answer examples (default=300)")
    parser.add_argument("--delay", type=float, default=0.3, help="Delay between API calls")
    parser.add_argument("--resume", type=str, default=None, help="Resume from partial file")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)

    # Resume support
    existing = []
    done_tools = set()
    if args.resume and os.path.exists(args.resume):
        with open(args.resume) as f:
            existing = json.load(f)
        # Detect done tools from existing data
        for item in existing:
            for msg in item.get("conversations", []):
                if msg.get("role") == "tool":
                    done_tools.add(msg.get("name", ""))
        print(f"Resuming from {len(existing)} existing examples. Done tools: {done_tools}")

    all_data = list(existing)

    # Generate per-tool data
    for tool_name, spec in TOOL_SPECS.items():
        if tool_name in done_tools:
            print(f"[SKIP] {tool_name} (already done)")
            continue

        print(f"\n{'='*50}")
        print(f"Tool: {tool_name} ({args.queries_per_tool} queries)")
        print(f"{'='*50}")

        # Step 1: Generate diverse queries
        print(f"  Generating {args.queries_per_tool} diverse queries...")
        queries = []
        batch_size = 50  # Claude can generate ~50 at once
        while len(queries) < args.queries_per_tool:
            remaining = args.queries_per_tool - len(queries)
            n = min(batch_size, remaining)
            batch = generate_queries_for_tool(tool_name, spec, n)
            queries.extend(batch)
            print(f"  Got {len(queries)}/{args.queries_per_tool} queries")
            time.sleep(args.delay)

        queries = queries[:args.queries_per_tool]

        # Step 2: Build training examples for each query
        tool_examples = []
        for i, query in enumerate(queries):
            if i % 20 == 0:
                print(f"  Building examples: {i}/{len(queries)}")
            example = build_tool_example(tool_name, spec, query)
            if example:
                tool_examples.append(example)
            time.sleep(args.delay)

        print(f"  Built {len(tool_examples)}/{len(queries)} valid examples")
        all_data.extend(tool_examples)

        # Save checkpoint after each tool
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(all_data, f, ensure_ascii=False, indent=2)
        print(f"  Saved checkpoint: {len(all_data)} total")

    # Generate no-tool examples
    print(f"\n{'='*50}")
    print(f"Generating {args.notool_count} no-tool examples...")
    batch_size = 30
    notool_all = []
    while len(notool_all) < args.notool_count:
        remaining = args.notool_count - len(notool_all)
        n = min(batch_size, remaining)
        batch = generate_notool_examples(n)
        notool_all.extend(batch)
        print(f"  Got {len(notool_all)}/{args.notool_count}")
        time.sleep(args.delay)

    all_data.extend(notool_all[:args.notool_count])

    # Final save
    random.shuffle(all_data)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_data, f, ensure_ascii=False, indent=2)

    # Stats
    tool_counts = {}
    notool = 0
    for item in all_data:
        t = next((m.get("name") for m in item.get("conversations", []) if m.get("role") == "tool"), None)
        if t:
            tool_counts[t] = tool_counts.get(t, 0) + 1
        else:
            notool += 1

    print(f"\n{'='*50}")
    print(f"DONE: {len(all_data)} total examples")
    for t, c in sorted(tool_counts.items()):
        print(f"  {t}: {c}")
    print(f"  (no tool): {notool}")
    print(f"Saved to: {output_path}")


if __name__ == "__main__":
    main()
