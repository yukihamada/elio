#!/usr/bin/env python3
"""
distill_with_claude.py — Gemini Flash 2.0 による高品質 Think 蒸留
================================================================
DeepSeek-R1 蒸留アプローチ: 教師 (Gemini Flash 2.0) → 生徒 (futa-2B)
400〜800字の深い推論チェーンを生成し学習データの質を根本から改善。

選択基準（優先順）:
1. マルチツール会話
2. ツール呼び出しのある会話
3. think が 200 字未満の会話
"""
import json, os, re, sys, time, argparse, hashlib, random, requests
random.seed(42)

# Gemini OpenAI互換エンドポイント
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

DISTILL_SYSTEM = """あなたは「附田(futa)」というAIアシスタントの内部思考プロセスを設計する専門家です。

与えられた会話状況で附田が持つべき深い内部思考を生成してください。

【品質基準】
- 400〜800字の日本語
- 具体的な推論ステップを複数含める
- ツール呼び出し時: なぜそのツールか・引数の選択根拠・期待される結果・リスク
- ツール結果解釈時: 情報の信頼性・重要ポイント抽出・回答構成方針・補足の必要性
- 複数のアプローチを比較検討するプロセスを含める
- 「〜かもしれない」「一方で〜」「しかし〜」などの批判的思考表現を使う

【禁止事項】
- 「〜ツールを使おう」で終わる1文の思考
- 100字以下の短い思考
- <think>タグ自体は出力しない（内部テキストのみ）"""


def distill_think(client, situation: str, think_type: str) -> str | None:
    try:
        resp = requests.post(
            f"{GEMINI_BASE}/chat/completions",
            headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
            json={
                "model": "gemini-2.0-flash",
                "max_tokens": 1200,
                "messages": [
                    {"role": "system", "content": DISTILL_SYSTEM},
                    {"role": "user",   "content": situation},
                ],
            },
            timeout=120,
        )
        if resp.status_code == 429:
            print("  [RATE] 30秒待機...", file=sys.stderr)
            time.sleep(30)
            return None
        resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        text = re.sub(r'</?think>', '', text).strip()
        return text if len(text) >= 200 else None
    except requests.exceptions.Timeout:
        print("  [TIMEOUT] リトライ...", file=sys.stderr)
        time.sleep(5)
        return None
    except Exception as e:
        print(f"  [WARN] {str(e)[:80]}", file=sys.stderr)
        time.sleep(3)
        return None


def build_situation_call(user_q: str, context: str, tool_name: str, tool_args: dict) -> str:
    return f"""会話状況:
ユーザーの質問: {user_q}
直前の会話:
{context}

附田がこれから「{tool_name}」ツールを呼び出します（引数: {json.dumps(tool_args, ensure_ascii=False)[:200]}）。
このツールを呼び出す前の深い内部思考（400〜800字）を生成してください。"""


def build_situation_final(user_q: str, context: str, tool_name: str, tool_result: str, response_hint: str) -> str:
    return f"""会話状況:
ユーザーの質問: {user_q}
直前の会話:
{context}

「{tool_name}」ツールの結果が返ってきました:
{tool_result[:500]}

附田はこれから最終回答を生成します（回答の方向性: {response_hint[:150]}）。
ツール結果を分析し最終回答を考える前の深い内部思考（400〜800字）を生成してください。"""


def inject_think(content: str, think_text: str) -> str:
    m = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
    block = f"<think>\n{think_text}\n</think>\n\n"
    if m:
        return content[:m.start()] + block + content[m.end():].lstrip()
    return block + content


def build_context(convs: list, up_to: int) -> str:
    lines = []
    for msg in convs[max(0, up_to-4):up_to]:
        role = msg["role"]
        name = msg.get("name", "")
        text = msg["content"][:250]
        if role == "tool":
            lines.append(f"[Tool({name})]: {text}")
        else:
            lines.append(f"[{role.upper()}]: {text}")
    return "\n".join(lines)


def priority_score(item: dict) -> int:
    convs = item["conversations"]
    score = 0
    tool_count = sum(1 for m in convs if m["role"] == "tool")
    score += tool_count * 10
    user_count = sum(1 for m in convs if m["role"] == "user")
    score += user_count * 3
    for msg in convs:
        if msg["role"] == "assistant":
            m = re.search(r'<think>(.*?)</think>', msg["content"], re.DOTALL)
            think_len = len(m.group(1).strip()) if m else 0
            if think_len < 200:
                score += (200 - think_len) // 5
    return score


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",   default="merged_v3.json")
    parser.add_argument("--output",  default="distilled.json")
    parser.add_argument("--n",       type=int, default=2000, help="蒸留対象件数")
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
    client = None  # not used with Gemini HTTP client
    script_dir = os.path.dirname(os.path.abspath(__file__))
    in_path    = os.path.join(script_dir, args.input)
    out_path   = os.path.join(script_dir, args.output)

    with open(in_path, encoding="utf-8") as f:
        data = json.load(f)
    print(f"入力: {len(data)}件")

    # 再開
    done: set[str] = set()
    result: list   = []
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            result = json.load(f)
        for item in result:
            done.add(_hash(item))
        print(f"再開: {len(result)}件済み")

    remaining = [item for item in data if _hash(item) not in done]
    by_priority = sorted(remaining, key=priority_score, reverse=True)
    to_distill  = by_priority[:args.n]
    to_passthru = by_priority[args.n:]

    print(f"蒸留対象: {len(to_distill)}件 | そのまま通過: {len(to_passthru)}件")

    distilled = 0
    think_before, think_after = [], []

    for idx, item in enumerate(to_distill):
        if _hash(item) in done:
            continue

        convs = item["conversations"]
        new_convs = list(convs)
        user_q = next((m["content"] for m in convs if m["role"] == "user"), "")
        changed = False

        for i, msg in enumerate(convs):
            if msg["role"] != "assistant":
                continue

            content    = msg["content"]
            m          = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
            think_text = m.group(1).strip() if m else ""
            think_before.append(len(think_text))

            # 既に充分なら skip
            if len(think_text) >= 400:
                think_after.append(len(think_text))
                continue

            context = build_context(convs, i)

            if "<tool_call>" in content:
                tc_m = re.search(r'<tool_call>\s*(\{.*?\})\s*</tool_call>', content, re.DOTALL)
                tool_name, tool_args = "", {}
                if tc_m:
                    try:
                        tc = json.loads(tc_m.group(1))
                        tool_name = tc.get("name", "")
                        tool_args = tc.get("arguments", {})
                    except Exception:
                        pass
                situation = build_situation_call(user_q, context, tool_name, tool_args)

            elif i > 0 and convs[i-1]["role"] == "tool":
                tool_msg    = convs[i-1]
                response_hint = re.sub(r'<think>.*?</think>', '', content, flags=re.DOTALL).strip()[:150]
                situation = build_situation_final(
                    user_q, context, tool_msg.get("name","tool"),
                    tool_msg.get("content",""), response_hint
                )
            else:
                think_after.append(len(think_text))
                continue

            new_think = distill_think(client, situation, "call")
            if new_think:
                new_msg           = dict(msg)
                new_msg["content"] = inject_think(content, new_think)
                new_convs[i]      = new_msg
                changed           = True
                think_after.append(len(new_think))
            else:
                think_after.append(len(think_text))

            time.sleep(0.3)

        new_item                  = dict(item)
        new_item["conversations"] = new_convs
        result.append(new_item)
        done.add(_hash(item))
        if changed:
            distilled += 1

        if (idx + 1) % 20 == 0:
            ab = sum(think_before) // max(len(think_before), 1)
            aa = sum(think_after)  // max(len(think_after), 1)
            print(f"[{idx+1}/{len(to_distill)}] 蒸留: {distilled}件 | think avg {ab}→{aa}字")
            _save(result, out_path)

    # パス通過分を追加
    for item in to_passthru:
        if _hash(item) not in done:
            result.append(item)
            done.add(_hash(item))

    _save(result, out_path)

    ab = sum(think_before) // max(len(think_before), 1)
    aa = sum(think_after)  // max(len(think_after), 1)
    print(f"\n完了: 蒸留 {distilled}件 | think avg {ab} → {aa}字")
    print(f"総件数: {len(result)} → {out_path}")


def _hash(item: dict) -> str:
    convs = item["conversations"]
    return hashlib.md5(
        "|".join(m["content"][:100] for m in convs if m["role"] == "user").encode()
    ).hexdigest()


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
