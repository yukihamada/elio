#!/usr/bin/env python3
"""
rewrite_thinks.py — 既存データの浅いthinkを深いthinkに書き換える
================================================================
- think < 200字 のアイテムを対象に、Geminiで深い思考を生成
- 元の回答はそのまま、thinkだけ置き換え
"""
import json, os, re, sys, time, argparse, requests

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

REWRITE_PROMPT = """以下は日本語AIアシスタントの会話です。
assistantの<think>タグ内の思考が浅すぎます（{current_len}字）。

ユーザーの質問: {user_question}
現在の思考: {current_think}
assistantの回答: {assistant_response}

この思考を【300〜600字】の深い思考に書き直してください。
要件:
- なぜこの回答が正しいのかの論理的根拠
- 他の可能性や落とし穴の検討
- ユーザーが本当に求めていることの分析
- 注意すべき点の洗い出し

思考テキストのみ出力（タグなし、説明文なし）:"""


def rewrite_think(user_q: str, current_think: str, response: str) -> str | None:
    prompt = REWRITE_PROMPT.format(
        current_len=len(current_think),
        user_question=user_q[:200],
        current_think=current_think[:300],
        assistant_response=response[:300],
    )
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 800,
                    "messages": [{"role": "user", "content": prompt}],
                },
                timeout=60,
            )
            if resp.status_code == 429:
                time.sleep(30)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            if len(text) >= 200:
                return text
        except requests.exceptions.Timeout:
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {str(e)[:60]}", file=sys.stderr)
            time.sleep(3)
            continue
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",  required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--min-think", type=int, default=200, help="この字数未満のthinkを書き換え")
    parser.add_argument("--max-items", type=int, default=500)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    data = json.load(open(args.input, encoding="utf-8"))

    # 既存出力をロード
    if os.path.exists(args.output):
        out_data = json.load(open(args.output, encoding="utf-8"))
        done_indices = set(range(len(out_data)))
        print(f"再開: {len(out_data)}件済み")
    else:
        out_data = []
        done_indices = set()

    targets = []
    for i, item in enumerate(data):
        if i in done_indices:
            continue
        convs = item.get("conversations", [])
        for m in convs:
            if m.get("role") == "assistant":
                t = re.search(r"<think>(.*?)</think>", m.get("content", ""), re.DOTALL)
                if t and len(t.group(1)) < args.min_think:
                    targets.append(i)
                    break

    print(f"書き換え対象: {len(targets)}件 (うち最大{args.max_items}件処理)")
    targets = targets[:args.max_items]

    rewritten = 0
    for idx_in_targets, data_idx in enumerate(targets):
        item = data[data_idx]
        convs = item.get("conversations", [])

        # Find user question and assistant think
        user_q = ""
        for m in convs:
            if m.get("role") == "user":
                user_q = m.get("content", "")
                break

        # Find and rewrite first short think
        new_convs = []
        did_rewrite = False
        for m in convs:
            if m.get("role") == "assistant" and not did_rewrite:
                content = m.get("content", "")
                t = re.search(r"<think>(.*?)</think>", content, re.DOTALL)
                if t and len(t.group(1)) < args.min_think:
                    response = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()
                    new_think = rewrite_think(user_q, t.group(1), response)
                    if new_think:
                        new_content = f"<think>\n{new_think}\n</think>\n{response}"
                        new_convs.append({**m, "content": new_content})
                        did_rewrite = True
                        rewritten += 1
                        continue
            new_convs.append(m)

        new_item = {**item, "conversations": new_convs}
        out_data.append(new_item)

        if rewritten % 10 == 0 and rewritten > 0:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(out_data, f, ensure_ascii=False)

        avg_new_think = 0
        if did_rewrite:
            for m in new_convs:
                if m.get("role") == "assistant":
                    t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
                    if t:
                        avg_new_think = len(t.group(1))
                        break

        print(f"  [{idx_in_targets+1}/{len(targets)}] {'✓ 書換済' if did_rewrite else '- スキップ'} think→{avg_new_think}字")
        time.sleep(0.3)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(out_data, f, ensure_ascii=False)

    print(f"\n完了: {rewritten}件書き換え → {args.output} ({len(out_data)}件)")


if __name__ == "__main__":
    main()
