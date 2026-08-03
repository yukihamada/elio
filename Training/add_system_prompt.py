#!/usr/bin/env python3
"""
add_system_prompt.py — 全データにシステムプロンプトを追加
"""
import json, os, sys, argparse

SYSTEM_PROMPTS = [
    "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。",
    "あなたは附田（futa）です。日本語を中心に、ユーザーの質問に誠実かつ正確に答えます。必要に応じてツールを使い、<think>タグで思考過程を示してください。",
    "あなたはfuta、日本語特化の知的AIアシスタントです。複雑な質問には<think>タグで推論を行い、ツールを適切に活用して最善の回答を提供してください。",
    "You are futa, a highly capable AI assistant specializing in Japanese. Use <think> tags to reason through problems and leverage available tools to provide accurate, helpful responses.",
    "あなたは附田（futa）、chatweb.aiが開発した日本語AIアシスタントです。ユーザーの意図を深く理解し、<think>タグで思考し、必要なツールを使って最高の回答をしてください。",
]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",  required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--vary",   action="store_true", help="システムプロンプトを会話ごとにランダム変化")
    args = parser.parse_args()

    import random
    random.seed(42)

    with open(args.input, encoding="utf-8") as f:
        data = json.load(f)

    result = []
    for i, item in enumerate(data):
        convs = item["conversations"]
        # すでにsystemメッセージがあればスキップ
        if convs and convs[0]["role"] == "system":
            result.append(item)
            continue

        if args.vary:
            sys_prompt = SYSTEM_PROMPTS[i % len(SYSTEM_PROMPTS)]
        else:
            sys_prompt = SYSTEM_PROMPTS[0]

        new_item = dict(item)
        new_item["conversations"] = [
            {"role": "system", "content": sys_prompt}
        ] + convs
        result.append(new_item)

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"完了: {len(result)}件 → {out}")
    print(f"サンプル: {result[0]['conversations'][0]['content'][:80]}")

if __name__ == "__main__":
    main()
