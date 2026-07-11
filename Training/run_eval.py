#!/usr/bin/env python3
"""
run_eval.py — futa-2b vs Qwen3.5-2B-Instruct 比較評価
=======================================================
使い方:
  # モデルA（ベース）とモデルB（futa）の比較
  python run_eval.py --model-a Qwen/Qwen3.5-2B-Instruct \
                     --model-b ./futa-2b-v1-merged \
                     --judge-api-key $GEMINI_API_KEY

  # 生成済み回答を再評価のみ
  python run_eval.py --score-only --results results_futa_vs_qwen.json
"""
import json, os, re, sys, time, argparse, requests
from pathlib import Path

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPT = "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。"

# ========== Judge Prompt ==========

JUDGE_PROMPT = """あなたは厳格なAI評価者です。2つのAIアシスタントの回答を比較評価してください。

【質問】
{question}

【期待される振る舞い】
{expected}

【モデルA（ベース: Qwen3.5-2B）の回答】
{response_a}

【モデルB（futa-2b: ファインチューニング済み）の回答】
{response_b}

以下の5軸で各モデルを1〜5で評価してください（5が最高）:

1. 正確性: 事実・計算が正確か
2. 有用性: ユーザーの質問に本当に役立つか
3. 日本語: 自然で流暢な日本語か
4. 思考深度: <think>タグ内の推論が深いか（なければ3）
5. 指示遵守: 質問の意図に的確に答えているか

また総合的にどちらが優れているかを判定してください。

JSON形式のみで出力:
{{
  "model_a": {{"accuracy":X,"helpfulness":X,"japanese":X,"thinking":X,"instruction":X,"total":X}},
  "model_b": {{"accuracy":X,"helpfulness":X,"japanese":X,"thinking":X,"instruction":X,"total":X}},
  "winner": "A" or "B" or "tie",
  "reason": "一言でその理由"
}}"""


def judge_responses(question: str, expected: str,
                    response_a: str, response_b: str) -> dict | None:
    prompt = JUDGE_PROMPT.format(
        question=question[:300],
        expected=expected,
        response_a=response_a[:600],
        response_b=response_b[:600],
    )
    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={"model": "gemini-2.0-flash", "max_tokens": 400,
                      "messages": [{"role": "user", "content": prompt}],
                      "temperature": 0.1},
                timeout=30,
            )
            if resp.status_code == 429:
                time.sleep(20); continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            text = re.sub(r"```(?:json)?\s*", "", text)
            text = re.sub(r"```\s*", "", text).strip()
            s, e = text.find("{"), text.rfind("}")
            if s < 0 or e <= s: continue
            return json.loads(text[s:e+1])
        except Exception:
            time.sleep(2)
    return None


def call_model_api(base_url: str, model_name: str,
                   messages: list, api_key: str = "") -> str:
    """vLLM / OpenAI互換APIを呼び出す"""
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    payload = {
        "model": model_name,
        "messages": messages,
        "max_tokens": 1024,
        "temperature": 0.7,
    }
    try:
        resp = requests.post(f"{base_url}/v1/chat/completions",
                             headers=headers, json=payload, timeout=60)
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:
        return f"[ERROR] {e}"


def run_local_model(model_path: str, messages: list) -> str:
    """ローカルモデルをtransformersで実行"""
    try:
        import torch
        from transformers import AutoTokenizer, AutoModelForCausalLM

        if not hasattr(run_local_model, "_cache"):
            run_local_model._cache = {}

        if model_path not in run_local_model._cache:
            print(f"  モデル読み込み中: {model_path}")
            tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
            model = AutoModelForCausalLM.from_pretrained(
                model_path,
                torch_dtype=torch.bfloat16,
                device_map="auto",
                trust_remote_code=True,
            )
            model.eval()
            run_local_model._cache[model_path] = (model, tokenizer)

        model, tokenizer = run_local_model._cache[model_path]

        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
        inputs = tokenizer(text, return_tensors="pt").to(model.device)

        with torch.no_grad():
            outputs = model.generate(
                **inputs,
                max_new_tokens=512,
                temperature=0.7,
                do_sample=True,
                pad_token_id=tokenizer.eos_token_id,
            )

        new_tokens = outputs[0][inputs["input_ids"].shape[1]:]
        return tokenizer.decode(new_tokens, skip_special_tokens=True).strip()
    except Exception as e:
        return f"[ERROR] {e}"


def get_response(model_spec: str, messages: list) -> str:
    """model_spec: 'local:path', 'api:base_url:model_name', 'gemini:model'"""
    if model_spec.startswith("local:"):
        path = model_spec[6:]
        return run_local_model(path, messages)
    elif model_spec.startswith("api:"):
        parts = model_spec.split(":", 2)
        base_url, model_name = parts[1], parts[2]
        return call_model_api(base_url, model_name, messages)
    elif model_spec.startswith("gemini:"):
        model_name = model_spec[7:]
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={"model": model_name, "max_tokens": 1024,
                      "messages": messages, "temperature": 0.7},
                timeout=60,
            )
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"].strip()
        except Exception as e:
            return f"[ERROR] {e}"
    return "[ERROR] unknown model spec"


def build_messages(item: dict) -> list:
    """eval_suite のアイテムからメッセージリストを構築"""
    msgs = [{"role": "system", "content": SYSTEM_PROMPT}]
    if "turns" in item:
        for turn in item["turns"]:
            msgs.append(turn)
    else:
        msgs.append({"role": "user", "content": item["input"]})
    return msgs


def think_stats(response: str) -> dict:
    t = re.search(r"<think>(.*?)</think>", response, re.DOTALL)
    return {
        "has_think": bool(t),
        "think_len": len(t.group(1)) if t else 0,
        "has_tool_call": "<tool_call>" in response,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-a",  default="gemini:gemini-2.0-flash",
                        help="モデルA仕様: local:PATH or api:BASE_URL:MODEL or gemini:MODEL")
    parser.add_argument("--model-b",  default="gemini:gemini-2.0-flash",
                        help="モデルB仕様")
    parser.add_argument("--model-a-name", default="Qwen3.5-2B-base")
    parser.add_argument("--model-b-name", default="futa-2b-v1")
    parser.add_argument("--eval-suite", default="eval_suite.json")
    parser.add_argument("--output",   default="eval_results.json")
    parser.add_argument("--categories", default="all",
                        help="カンマ区切りのカテゴリ名、またはall")
    parser.add_argument("--score-only", action="store_true")
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    suite = json.load(open(args.eval_suite, encoding="utf-8"))

    # カテゴリフィルタ
    if args.categories != "all":
        cats = set(args.categories.split(","))
        suite = [item for item in suite if item.get("category","") in cats]
    print(f"評価項目: {len(suite)}件 ({args.model_a_name} vs {args.model_b_name})")

    # 既存結果のロード
    results = []
    done_ids = set()
    if os.path.exists(args.output):
        results = json.load(open(args.output, encoding="utf-8"))
        done_ids = {r["id"] for r in results}
        print(f"再開: {len(done_ids)}件済み")

    if not args.score_only:
        for item in suite:
            if item["id"] in done_ids:
                continue

            messages = build_messages(item)
            question = item.get("input", str(item.get("turns",["?"])[0]))

            print(f"\n[{item['id']}] {question[:50]}...")

            resp_a = get_response(args.model_a, messages)
            time.sleep(0.5)
            resp_b = get_response(args.model_b, messages)
            time.sleep(0.5)

            print(f"  A ({args.model_a_name}): {resp_a[:80].replace(chr(10),' ')}...")
            print(f"  B ({args.model_b_name}): {resp_b[:80].replace(chr(10),' ')}...")

            result = {
                "id": item["id"],
                "category": item.get("category",""),
                "question": question,
                "expected": item.get("expected_behavior",""),
                "response_a": resp_a,
                "response_b": resp_b,
                "stats_a": think_stats(resp_a),
                "stats_b": think_stats(resp_b),
            }
            results.append(result)

            if len(results) % 5 == 0:
                json.dump(results, open(args.output,"w",encoding="utf-8"), ensure_ascii=False)

        json.dump(results, open(args.output,"w",encoding="utf-8"), ensure_ascii=False)

    # Judge採点
    print("\n=== Judge採点開始 ===")
    scored = 0
    for r in results:
        if "judge" in r:
            continue
        judge = judge_responses(
            r["question"], r["expected"],
            r["response_a"], r["response_b"]
        )
        if judge:
            r["judge"] = judge
            scored += 1
            winner = judge.get("winner","?")
            ta = judge.get("model_a",{}).get("total",0)
            tb = judge.get("model_b",{}).get("total",0)
            print(f"  [{r['id']}] A:{ta} B:{tb} → winner:{winner} ({judge.get('reason','')})")
        time.sleep(0.2)

    json.dump(results, open(args.output,"w",encoding="utf-8"), ensure_ascii=False)

    # サマリー
    print_summary(results, args.model_a_name, args.model_b_name)


def print_summary(results, name_a, name_b):
    from collections import Counter, defaultdict

    judged = [r for r in results if "judge" in r]
    if not judged:
        print("採点済みデータなし")
        return

    winners = Counter(r["judge"].get("winner","?") for r in judged)
    a_scores = [r["judge"].get("model_a",{}).get("total",0) for r in judged]
    b_scores = [r["judge"].get("model_b",{}).get("total",0) for r in judged]

    print(f"\n{'='*50}")
    print(f"  {name_a} vs {name_b}")
    print(f"{'='*50}")
    print(f"  評価数: {len(judged)}件")
    print(f"  {name_a} 勝利: {winners.get('A',0)}件")
    print(f"  {name_b} 勝利: {winners.get('B',0)}件")
    print(f"  引き分け: {winners.get('tie',0)}件")
    print(f"  平均スコア: {name_a}={sum(a_scores)/len(a_scores):.2f} {name_b}={sum(b_scores)/len(b_scores):.2f}")

    # カテゴリ別
    cat_results = defaultdict(lambda: {"A":0,"B":0,"tie":0,"a_scores":[],"b_scores":[]})
    for r in judged:
        cat = r.get("category","?")
        winner = r["judge"].get("winner","?")
        cat_results[cat][winner] += 1
        cat_results[cat]["a_scores"].append(r["judge"].get("model_a",{}).get("total",0))
        cat_results[cat]["b_scores"].append(r["judge"].get("model_b",{}).get("total",0))

    print(f"\n  カテゴリ別 (A勝/B勝/引分 | Aavg vs Bavg):")
    for cat, cr in sorted(cat_results.items()):
        a_avg = sum(cr["a_scores"])/len(cr["a_scores"])
        b_avg = sum(cr["b_scores"])/len(cr["b_scores"])
        print(f"    {cat:<25}: {cr['A']}/{cr['B']}/{cr['tie']} | {a_avg:.1f} vs {b_avg:.1f}")

    # think stats
    a_think = [r["stats_a"]["think_len"] for r in judged if r["stats_a"]["has_think"]]
    b_think = [r["stats_b"]["think_len"] for r in judged if r["stats_b"]["has_think"]]
    if a_think:
        print(f"\n  <think>中央値: {name_a}={sorted(a_think)[len(a_think)//2]}字, {name_b}={sorted(b_think)[len(b_think)//2] if b_think else 0}字")


if __name__ == "__main__":
    main()
