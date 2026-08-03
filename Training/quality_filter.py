#!/usr/bin/env python3
"""
quality_filter.py — CHIMERA式 5軸品質スコアリング & フィルタリング
====================================================================
論文: CHIMERA (arxiv 2603.00889) + 日本語金融ドメイン (arxiv 2603.01353)

5軸評価:
  1. think_logic    : 思考の論理性・深さ (1-5)
  2. answer_quality : 回答の正確性・有用性 (1-5)
  3. jp_natural     : 日本語の自然さ・流暢さ (1-5)
  4. tool_use       : ツール使用の適切さ (1-5, ツールなしは3固定)
  5. instruction    : 指示への遵守度 (1-5)

合計 >= 18/25 のみ保持 (平均 3.6/5)
"""
import json, os, re, sys, time, argparse, requests, random

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SCORE_PROMPT = """以下のAIアシスタントの会話を5つの軸で評価してください。

ユーザーの質問: {user_q}
AIの思考(<think>): {think_text}
AIの回答: {response_text}
ツール呼び出し: {has_tool}

各軸を1〜5の整数で評価（5が最高）:

1. think_logic: 思考の論理性・深さ
   5=多角的で深い推論、4=十分な推論、3=基本的な推論、2=浅い/部分的、1=思考なし/不適切

2. answer_quality: 回答の正確性・有用性
   5=正確で非常に有用、4=ほぼ正確で有用、3=概ね正しい、2=不正確な点あり、1=不正確/有害

3. jp_natural: 日本語の自然さ・流暢さ
   5=完全に自然、4=ほぼ自然、3=若干ぎこちない、2=かなり不自然、1=機械翻訳的

4. tool_use: ツール使用の適切さ（ツールなしは3固定）
   5=完璧なツール選択・引数、4=ほぼ適切、3=普通/なし、2=不適切なツール選択、1=誤った使い方

5. instruction: 質問への的確な回答
   5=完璧に応答、4=ほぼ応答、3=部分的に応答、2=ずれた回答、1=無関係

JSON形式のみで出力（説明不要）:
{{"think_logic":X,"answer_quality":X,"jp_natural":X,"tool_use":X,"instruction":X,"total":XX}}"""


def score_item(item: dict) -> dict | None:
    convs = item.get("conversations", [])
    user_q = next((m.get("content","")[:200] for m in convs if m.get("role")=="user"), "")

    think_text = ""
    response_text = ""
    has_tool = "なし"

    for m in convs:
        if m.get("role") == "assistant":
            content = m.get("content", "")
            t = re.search(r"<think>(.*?)</think>", content, re.DOTALL)
            if t:
                think_text = t.group(1).strip()[:400]
            response_text = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()[:300]
            if "<tool_call>" in content:
                tc = re.search(r'<tool_call>\s*\{[^}]*"name"\s*:\s*"([^"]+)"', content)
                has_tool = f"あり ({tc.group(1) if tc else '不明'})"
            break

    if not user_q or not response_text:
        return None

    prompt = SCORE_PROMPT.format(
        user_q=user_q,
        think_text=think_text[:300] if think_text else "（思考なし）",
        response_text=response_text[:300],
        has_tool=has_tool,
    )

    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 100,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.1,
                },
                timeout=30,
            )
            if resp.status_code == 429:
                time.sleep(20)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            text = re.sub(r"```(?:json)?\s*", "", text)
            text = re.sub(r"```\s*", "", text).strip()
            s, e = text.find("{"), text.rfind("}")
            if s < 0 or e <= s:
                continue
            scores = json.loads(text[s:e+1])
            for k in ["think_logic","answer_quality","jp_natural","tool_use","instruction"]:
                if k not in scores or not isinstance(scores[k], int):
                    raise ValueError(f"Missing key: {k}")
            scores["total"] = sum(scores[k] for k in ["think_logic","answer_quality","jp_natural","tool_use","instruction"])
            return scores
        except requests.exceptions.Timeout:
            time.sleep(3)
            continue
        except Exception:
            time.sleep(2)
            continue
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",     required=True)
    parser.add_argument("--output",    required=True)
    parser.add_argument("--min-score", type=int, default=18, help="合計スコアの閾値 (max25)")
    parser.add_argument("--max-items", type=int, default=0)
    parser.add_argument("--sample",    type=int, default=0)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    data = json.load(open(args.input, encoding="utf-8"))
    if args.sample > 0:
        random.seed(42)
        data = random.sample(data, min(args.sample, len(data)))
    if args.max_items > 0:
        data = data[:args.max_items]

    # 再開対応: scored済みitemをindexでトラック
    scored_map = {}
    if os.path.exists(args.output):
        existing = json.load(open(args.output, encoding="utf-8"))
        for item in existing:
            idx = item.get("_original_idx", -1)
            if idx >= 0:
                scored_map[idx] = item
        print(f"再開: {len(scored_map)}件済み")

    passed = [v for v in scored_map.values() if v.get("_score_total", 0) >= args.min_score]
    print(f"入力: {len(data)}件 | 閾値: {args.min_score}/25 | 済み: {len(scored_map)}件")

    for i, item in enumerate(data):
        if i in scored_map:
            continue

        scores = score_item(item)
        if scores is None:
            scored_map[i] = {**item, "_original_idx": i, "_score_total": 0}
            continue

        total = scores["total"]
        new_item = {**item, "_original_idx": i, "_score_total": total, "_scores": scores}
        scored_map[i] = new_item

        status = "✓" if total >= args.min_score else "✗"
        if total >= args.min_score:
            passed.append(new_item)

        print(f"  [{i+1}/{len(data)}] {status} {total}/25 "
              f"logic:{scores['think_logic']} ans:{scores['answer_quality']} "
              f"jp:{scores['jp_natural']} tool:{scores['tool_use']} inst:{scores['instruction']}")

        if (i + 1) % 50 == 0:
            _save(passed, args.output)

        time.sleep(0.15)

    _save(passed, args.output)

    all_totals = [v.get("_score_total", 0) for v in scored_map.values() if v.get("_score_total", 0) > 0]
    all_totals.sort()
    med = all_totals[len(all_totals)//2] if all_totals else 0
    print(f"\n完了: {len(scored_map)}件評価 → {len(passed)}件合格 "
          f"({100*len(passed)//max(len(scored_map),1)}%) スコア中央値:{med}/25 → {args.output}")


def _save(data, path):
    clean = []
    for item in data:
        c = {k: v for k, v in item.items() if k not in ("_original_idx", "_scores")}
        clean.append(c)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(clean, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
