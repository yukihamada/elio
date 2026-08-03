#!/usr/bin/env python3
"""
generate_dpo_pairs.py — DPO preference pair 生成
==================================================
論文: Latent Reasoning Distillation (arxiv 2601.21611)
     SFT + DPO で SFT 単体を一貫して上回る

戦略: 既存の高品質アイテムから、
  chosen  = 元の深い<think> + 良い回答
  rejected = 意図的に浅い/不完全な<think> + 同じ回答

DPO フォーマット (TRL 対応):
{
  "conversations": [...system/user...],
  "chosen":   {"role":"assistant","content":"<think>深い思考</think>\n回答"},
  "rejected": {"role":"assistant","content":"<think>浅い思考</think>\n回答"}
}
"""
import json, os, re, sys, time, argparse, requests, random

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

BAD_THINK_PROMPT = """以下は日本語AIアシスタントの高品質な思考です。
これを意図的に「浅くて不完全な思考」に書き直してください。

元の思考（良い例）:
{good_think}

「浅い思考」の要件:
- 50〜100字程度（元の1/4以下）
- 表面的な理解のみ
- なぜその答えが正しいか説明しない
- 落とし穴や代替案を検討しない
- 「とりあえず答える」感じ

浅い思考テキストのみ出力（タグなし）:"""

HARD_THINK_PROMPT = """以下の会話に対して、さらに深く洗練された思考を生成してください。

ユーザーの質問: {user_q}
現在の思考: {current_think}
回答: {response}

改善した思考の要件:
- 400〜700字
- 複数の視点から考察
- 反例・例外ケースの検討
- ユーザーの真のニーズの分析
- 回答の論拠を明確に

改善した思考テキストのみ出力（タグなし）:"""


def gen_bad_think(good_think: str) -> str | None:
    prompt = BAD_THINK_PROMPT.format(good_think=good_think[:500])
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={"model": "gemini-2.0-flash", "max_tokens": 200,
                      "messages": [{"role": "user", "content": prompt}], "temperature": 0.8},
                timeout=30,
            )
            if resp.status_code == 429:
                time.sleep(20); continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            # 50〜150字の浅い思考であることを確認
            if 30 <= len(text) <= 200:
                return text
        except requests.exceptions.Timeout:
            time.sleep(3); continue
        except Exception:
            time.sleep(2); continue
    return None


def gen_better_think(user_q: str, current_think: str, response: str) -> str | None:
    prompt = HARD_THINK_PROMPT.format(
        user_q=user_q[:200],
        current_think=current_think[:400],
        response=response[:300],
    )
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={"model": "gemini-2.0-flash", "max_tokens": 900,
                      "messages": [{"role": "user", "content": prompt}], "temperature": 0.7},
                timeout=60,
            )
            if resp.status_code == 429:
                time.sleep(20); continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            if len(text) >= 300:
                return text
        except requests.exceptions.Timeout:
            time.sleep(5); continue
        except Exception:
            time.sleep(2); continue
    return None


def make_dpo_pair(item: dict, mode: str = "bad_think") -> dict | None:
    """
    mode:
      "bad_think"   = chosen=元のthink, rejected=生成した浅いthink
      "better_think" = chosen=より深いthink, rejected=元のthink
    """
    convs = item.get("conversations", [])

    # user/system メッセージのみ抽出 (最後のassistantを除く)
    prefix = []
    user_q = ""
    assistant_msg = None

    for m in convs:
        role = m.get("role", "")
        if role in ("system", "user"):
            prefix.append(m)
            if role == "user":
                user_q = m.get("content", "")[:200]
        elif role == "assistant" and assistant_msg is None:
            assistant_msg = m

    if not assistant_msg or not user_q:
        return None

    content = assistant_msg.get("content", "")
    t = re.search(r"<think>(.*?)</think>", content, re.DOTALL)
    if not t:
        return None

    current_think = t.group(1).strip()
    response = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()

    if len(current_think) < 150:
        return None  # 元のthinkが短すぎる → chosen向きでない

    if mode == "bad_think":
        bad_think = gen_bad_think(current_think)
        if not bad_think:
            return None
        chosen_content   = f"<think>\n{current_think}\n</think>\n{response}"
        rejected_content = f"<think>\n{bad_think}\n</think>\n{response}"
    else:  # better_think
        better_think = gen_better_think(user_q, current_think, response)
        if not better_think:
            return None
        chosen_content   = f"<think>\n{better_think}\n</think>\n{response}"
        rejected_content = f"<think>\n{current_think}\n</think>\n{response}"

    return {
        "conversations": prefix,
        "chosen":   {"role": "assistant", "content": chosen_content},
        "rejected": {"role": "assistant", "content": rejected_content},
        "source":   item.get("source", item.get("category", "unknown")),
        "dpo_mode": mode,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",     required=True)
    parser.add_argument("--output",    required=True)
    parser.add_argument("--max-items", type=int, default=500)
    parser.add_argument("--mode",      choices=["bad_think","better_think","both"], default="bad_think")
    parser.add_argument("--min-think", type=int, default=200,
                        help="このthink長さ以上のアイテムのみ対象")
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    data = json.load(open(args.input, encoding="utf-8"))
    random.seed(42)
    random.shuffle(data)

    # think の長いアイテムを優先 (DPO の chosen として質が高い)
    candidates = []
    for item in data:
        for m in item.get("conversations", []):
            if m.get("role") == "assistant":
                t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
                if t and len(t.group(1)) >= args.min_think:
                    candidates.append(item)
                break
    candidates = candidates[:args.max_items]

    print(f"対象: {len(candidates)}件 (think>={args.min_think}字) | mode={args.mode}")

    # 再開対応
    results = []
    done_count = 0
    if os.path.exists(args.output):
        results = json.load(open(args.output, encoding="utf-8"))
        done_count = len(results)
        print(f"再開: {done_count}件済み")

    modes = ["bad_think", "better_think"] if args.mode == "both" else [args.mode]

    generated = 0
    for idx, item in enumerate(candidates[done_count:], start=done_count):
        for mode in modes:
            pair = make_dpo_pair(item, mode=mode)
            if pair:
                results.append(pair)
                generated += 1

                # think 長さを表示
                chosen_t = re.search(r"<think>(.*?)</think>", pair["chosen"]["content"], re.DOTALL)
                rejected_t = re.search(r"<think>(.*?)</think>", pair["rejected"]["content"], re.DOTALL)
                c_len = len(chosen_t.group(1)) if chosen_t else 0
                r_len = len(rejected_t.group(1)) if rejected_t else 0
                print(f"  [{idx+1}/{len(candidates)}] {mode}: chosen={c_len}字 rejected={r_len}字")

            time.sleep(0.3)

        if (idx + 1) % 20 == 0:
            _save(results, args.output)

    _save(results, args.output)
    print(f"\n完了: {generated}件生成 → {args.output} (合計{len(results)}件)")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
