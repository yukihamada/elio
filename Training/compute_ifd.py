#!/usr/bin/env python3
"""
compute_ifd.py — Instruction-Following Difficulty (IFD) スコア計算
===================================================================
論文: "From Quantity to Quality" (arXiv 2308.12032)

IFD = loss(response | instruction) / loss(response)
  高IFD = 指示があって初めて意味を持つ回答 = 価値が高い
  低IFD = 指示なしでも生成できる回答 = 汎用的すぎ/無意味

実装: transformers + ベースモデルの推論
- conditional_loss: プロンプト付きで回答部分のloss
- unconditional_loss: 回答単体のloss
- IFD = conditional / unconditional

注: GPUなしの場合はCPUで実行（遅いが動く）
"""
import json, os, re, sys, argparse, math
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

CHAT_TEMPLATE_SYSTEM = "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。"


def get_loss(model, tokenizer, text: str, context: str = "") -> float:
    """text の平均 cross-entropy loss を計算する。
    context が与えられた場合は context を prefix として loss は text 部分のみ計算。
    """
    if context:
        full_text = context + text
        full_ids = tokenizer.encode(full_text, return_tensors="pt")
        ctx_ids  = tokenizer.encode(context, return_tensors="pt")
        ctx_len  = ctx_ids.shape[1]
    else:
        full_ids = tokenizer.encode(text, return_tensors="pt")
        ctx_len  = 0

    full_ids = full_ids.to(model.device)

    with torch.no_grad():
        outputs = model(full_ids, labels=full_ids)

    # labels の ctx_len 以前を -100 にして text 部分のみの loss を再計算
    labels = full_ids.clone()
    labels[0, :ctx_len] = -100

    with torch.no_grad():
        outputs2 = model(full_ids, labels=labels)

    return outputs2.loss.item()


def build_prompt(item: dict, tokenizer) -> tuple[str, str]:
    """(context_for_conditional, response_text) を返す"""
    convs = item.get("conversations", [])

    messages = []
    response_text = ""

    for m in convs:
        role = m.get("role", "")
        content = m.get("content", "")

        if role == "system":
            messages.append({"role": "system", "content": content})
        elif role == "user":
            messages.append({"role": "user", "content": content})
        elif role == "assistant" and not response_text:
            # <think>を除いた回答部分
            response_text = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()
            # ツール呼び出しも除く
            response_text = re.sub(r"<tool_call>.*?</tool_call>", "", response_text, flags=re.DOTALL).strip()
            if len(response_text) < 20:
                return None, None
            # assistant の前のメッセージまでを context に
            break
        elif role == "tool":
            messages.append({"role": "user", "content": f"[tool result] {content}"})

    if not messages or not response_text:
        return None, None

    # chat template を使って context を構築
    try:
        context = tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=True,
        )
    except Exception:
        context = "\n".join(f"{m['role']}: {m['content']}" for m in messages) + "\nassistant: "

    return context, response_text[:500]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",      required=True)
    parser.add_argument("--output",     required=True)
    parser.add_argument("--model",      default="Qwen/Qwen3.5-2B",
                        help="ベースモデルのパス or HuggingFace ID")
    parser.add_argument("--min-ifd",    type=float, default=0.0,
                        help="このIFD未満は除外 (0=除外しない)")
    parser.add_argument("--top-ratio",  type=float, default=0.7,
                        help="上位X割を保持 (1.0=全件)")
    parser.add_argument("--max-items",  type=int, default=0)
    args = parser.parse_args()

    print(f"モデル読み込み中: {args.model}")
    try:
        tokenizer = AutoTokenizer.from_pretrained(args.model, trust_remote_code=True)
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            torch_dtype=torch.float16 if torch.cuda.is_available() else torch.float32,
            device_map="auto" if torch.cuda.is_available() else "cpu",
            trust_remote_code=True,
        )
        model.eval()
    except Exception as e:
        print(f"[ERROR] モデル読み込み失敗: {e}", file=sys.stderr)
        sys.exit(1)

    data = json.load(open(args.input, encoding="utf-8"))
    if args.max_items > 0:
        data = data[:args.max_items]

    scored = []
    skip = 0

    for i, item in enumerate(data):
        context, response = build_prompt(item, tokenizer)
        if context is None:
            skip += 1
            continue

        try:
            cond_loss   = get_loss(model, tokenizer, response, context=context)
            uncond_loss = get_loss(model, tokenizer, response, context="")
            ifd = cond_loss / max(uncond_loss, 1e-6)
        except Exception as e:
            print(f"  [{i}] LOSS ERROR: {e}", file=sys.stderr)
            skip += 1
            continue

        scored.append({**item, "_ifd": round(ifd, 4)})

        if (i + 1) % 50 == 0:
            print(f"  [{i+1}/{len(data)}] IFD中央値: "
                  f"{sorted([s['_ifd'] for s in scored])[len(scored)//2]:.3f}")

    # IFD でソートして上位を保持
    scored.sort(key=lambda x: x["_ifd"], reverse=True)

    if args.min_ifd > 0:
        scored = [s for s in scored if s["_ifd"] >= args.min_ifd]

    if args.top_ratio < 1.0:
        keep_n = int(len(scored) * args.top_ratio)
        scored = scored[:keep_n]

    # _ifd を保持してソースに記録
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(scored, f, ensure_ascii=False)

    ifd_vals = [s["_ifd"] for s in scored]
    ifd_vals.sort()
    med = ifd_vals[len(ifd_vals)//2] if ifd_vals else 0
    print(f"\n完了: {len(scored)}件保持 (skip:{skip}) IFD中央値:{med:.3f} → {args.output}")
    print(f"IFD分布: min={min(ifd_vals, default=0):.3f} max={max(ifd_vals, default=0):.3f}")


if __name__ == "__main__":
    main()
