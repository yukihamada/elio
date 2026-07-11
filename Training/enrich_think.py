#!/usr/bin/env python3
"""
enrich_think.py — <think> タグ充実化スクリプト
=================================================
merged_final.json の全 assistant メッセージを精査し、
- think なし (ツール後の最終回答)  → 100〜300字の思考を追加
- thin think (50字以下)            → 拡充

Gemini 2.0 Flash を使用 (GOOGLE_API_KEY)。
バッチ処理で逐次保存するため中断・再開可能。
"""

import json
import os
import re
import sys
import time
import argparse

import openai

# ── Gemini client ───────────────────────────────────────────────
def make_client():
    key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not key:
        print("ERROR: GOOGLE_API_KEY が必要です", file=sys.stderr)
        sys.exit(1)
    return openai.OpenAI(
        api_key=key,
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
    ), "gemini-2.0-flash"


# ── Think 生成 ──────────────────────────────────────────────────
SYSTEM = """あなたは日本語に特化したAIアシスタントの思考プロセスを生成する専門家です。
与えられた会話コンテキストを見て、アシスタントが返答する前に持つべき自然な内部思考を書いてください。

ルール:
- 100〜300字の日本語で書く
- 具体的な判断・推論を含める（「なぜこのツールを使うか」「情報をどう整理するか」「何に注意すべきか」）
- 「〜しよう」「〜が必要だ」「〜を考えると」等の思考らしい表現
- <think>タグは含めない（生テキストのみ返す）
- ツール結果の解釈が必要な場合はその分析も含める"""


def generate_think(client, model, conversation_context: str, current_response: str) -> str | None:
    prompt = f"""以下の会話を見て、アシスタントが「{current_response[:80]}...」と返答する前の内部思考を100〜300字で書いてください。

会話コンテキスト:
{conversation_context}

アシスタントの返答（参考）:
{current_response[:200]}"""

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM},
                {"role": "user", "content": prompt},
            ],
            max_tokens=400,
            temperature=0.7,
        )
        think = resp.choices[0].message.content.strip()
        # タグが混入した場合は除去
        think = re.sub(r'</?think>', '', think).strip()
        return think if len(think) >= 50 else None
    except Exception as e:
        print(f"  [WARN] think生成エラー: {e}", file=sys.stderr)
        return None


def inject_think(content: str, think_text: str) -> str:
    """assistant メッセージに <think> を注入 / 置換"""
    m = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
    think_block = f"<think>\n{think_text}\n</think>\n\n"
    if m:
        return content[:m.start()] + think_block + content[m.end():].lstrip()
    else:
        return think_block + content


def build_context(conversations: list, up_to_idx: int) -> str:
    """idx までの会話を文字列化"""
    lines = []
    for msg in conversations[:up_to_idx]:
        role = msg["role"]
        content = msg["content"][:300]
        name = msg.get("name", "")
        if role == "tool":
            lines.append(f"[Tool({name})]: {content}")
        else:
            lines.append(f"[{role.upper()}]: {content}")
    return "\n".join(lines)


# ── メイン ───────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",  default="merged_final.json")
    parser.add_argument("--output", default="merged_enriched.json")
    parser.add_argument("--limit",  type=int, default=0, help="処理上限件数 (0=全件)")
    parser.add_argument("--thin-only", action="store_true", help="thin thinkのみ修正")
    args = parser.parse_args()

    client, model = make_client()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    input_path  = os.path.join(script_dir, args.input)
    output_path = os.path.join(script_dir, args.output)

    print(f"読み込み: {input_path}")
    with open(input_path, encoding="utf-8") as f:
        data = json.load(f)

    # 既存出力があれば再開
    processed_hashes = set()
    result = []
    if os.path.exists(output_path):
        with open(output_path, encoding="utf-8") as f:
            result = json.load(f)
        for item in result:
            h = json.dumps(item["conversations"][0]["content"], ensure_ascii=False)
            processed_hashes.add(h)
        print(f"再開: {len(result)}件 処理済み")

    total = len(data)
    modified = 0
    skipped  = 0

    for idx, item in enumerate(data):
        # 再開チェック
        first_q = json.dumps(item["conversations"][0]["content"], ensure_ascii=False)
        if first_q in processed_hashes:
            skipped += 1
            continue

        if args.limit and (idx - skipped) >= args.limit:
            break

        convs = item["conversations"]
        new_convs = list(convs)
        changed = False

        for i, msg in enumerate(convs):
            if msg["role"] != "assistant":
                continue

            content = msg["content"]
            m = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
            think_text = m.group(1).strip() if m else ""

            is_final_after_tool = i > 0 and convs[i - 1]["role"] == "tool"
            needs_enrich = (
                (not think_text and is_final_after_tool) or
                (len(think_text) < 50)
            )

            if args.thin_only and not think_text:
                continue

            if not needs_enrich:
                continue

            # 生成
            context = build_context(convs, i)
            new_think = generate_think(client, model, context, content)

            if new_think:
                new_msg = dict(msg)
                new_msg["content"] = inject_think(content, new_think)
                new_convs[i] = new_msg
                changed = True

        new_item = dict(item)
        new_item["conversations"] = new_convs
        result.append(new_item)

        if changed:
            modified += 1

        # 逐次保存
        if len(result) % 50 == 0:
            with open(output_path, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=None)
            print(f"  [{len(result)}/{total}] 修正: {modified}件", flush=True)

        time.sleep(0.05)  # レート制限対策

    # 最終保存
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=None)

    print(f"\n完了: {len(result)}件 (修正: {modified}件)")
    print(f"出力: {output_path}")


if __name__ == "__main__":
    main()
