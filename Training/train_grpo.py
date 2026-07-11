#!/usr/bin/env python3
"""
train_grpo.py — Futa-2B GRPO 強化学習
=======================================
RC-GRPO ベストプラクティス (arxiv 2602.03025) に基づく実装。
SFT 後のモデルを対象に、5つの報酬関数でツール呼び出し品質を強化。

報酬関数:
  1. think_depth    — <think> の深さ・長さ (最重要)
  2. tool_format    — tool_call JSON の正確性
  3. tool_selection — 正しいツールを選んだか
  4. args_quality   — 引数の具体性・完全性
  5. response_quality — 最終回答の品質・日本語

Requirements: pip install unsloth trl transformers datasets pyyaml
Usage:
  python train_grpo.py --sft_model ./futa-2b-v1-lora --data merged_v4.json
"""

import argparse, json, os, re, sys
import yaml


# ─── 報酬関数群 ──────────────────────────────────────────────────

VALID_TOOLS = {
    "web_search", "web_fetch", "calculator", "weather", "translate",
    "wikipedia", "datetime", "create_qr", "news_search", "code_execute",
    "file_read", "file_write", "file_list", "image_generate", "image_analyze",
}

def reward_think_depth(completions, **kwargs) -> list[float]:
    """
    Reward 1: <think> の深さ・推論品質
    研究知見: 深い思考チェーンは回答品質と強く相関する
    """
    scores = []
    for text in completions:
        m = re.search(r"<think>(.*?)</think>", text, re.DOTALL)
        if not m:
            scores.append(-1.5)  # think なし = 強ペナルティ
            continue

        think = m.group(1).strip()
        length = len(think)

        # 長さスコア (400〜600字で最高)
        if length < 50:    s = -1.0
        elif length < 100: s = -0.3
        elif length < 200: s =  0.2
        elif length < 400: s =  0.6
        elif length < 800: s =  1.0
        else:              s =  0.8  # 過度に長い場合は少し減点

        # 推論マーカーボーナス
        reasoning = ["なぜなら", "一方で", "しかし", "また", "さらに",
                     "考えられる", "可能性", "必要が", "注意", "ため"]
        bonus = sum(0.05 for r in reasoning if r in think)
        s = min(s + bonus, 1.0)

        # 日本語品質
        jp = len(re.findall(r"[\u3040-\u30ff\u4e00-\u9fff]", think))
        if jp / max(length, 1) < 0.3:
            s -= 0.3  # 日本語少なすぎ

        scores.append(max(s, -1.5))
    return scores


def reward_tool_format(completions, **kwargs) -> list[float]:
    """
    Reward 2: tool_call の JSON フォーマット正確性
    """
    scores = []
    for text in completions:
        m = re.search(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", text, re.DOTALL)
        if not m:
            scores.append(0.0)  # ツールなし = 中立
            continue

        try:
            obj = json.loads(m.group(1))
        except json.JSONDecodeError:
            scores.append(-1.0)  # 無効JSON = 強ペナルティ
            continue

        s = 0.3  # valid JSON

        if "name" in obj:
            s += 0.3
            if obj["name"] in VALID_TOOLS:
                s += 0.2

        if "arguments" in obj and isinstance(obj["arguments"], dict):
            s += 0.2
            if obj["arguments"]:  # 空でない
                s += 0.1
            # 引数に具体的な値がある (長さ 3 以上)
            meaningful = sum(
                1 for v in obj["arguments"].values()
                if isinstance(v, str) and len(v) >= 3
            )
            if meaningful >= 1:
                s += 0.1

        scores.append(min(s, 1.0))
    return scores


def reward_tool_selection(completions, prompts=None, **kwargs) -> list[float]:
    """
    Reward 3: 期待されるツールを正しく選択したか
    kwargs には expected_tool が渡される (事前に設定)
    """
    expected_tools = kwargs.get("expected_tools", [None] * len(completions))
    scores = []

    for text, expected in zip(completions, expected_tools):
        if expected is None:
            scores.append(0.0)
            continue

        m = re.search(r'"name"\s*:\s*"(\w+)"', text)
        if not m:
            scores.append(-0.5)
            continue

        actual = m.group(1)
        if actual == expected:
            scores.append(1.0)
        elif actual in VALID_TOOLS:
            scores.append(0.0)  # 違うが有効なツール = 中立
        else:
            scores.append(-0.5)

    return scores


def reward_args_quality(completions, **kwargs) -> list[float]:
    """
    Reward 4: 引数の具体性・完全性
    """
    scores = []
    for text in completions:
        m = re.search(r'"arguments"\s*:\s*(\{[^}]*\})', text, re.DOTALL)
        if not m:
            scores.append(0.0)
            continue

        try:
            args = json.loads(m.group(1))
        except Exception:
            scores.append(-0.3)
            continue

        if not args:
            scores.append(-0.2)
            continue

        values = list(args.values())
        # 全引数の平均長
        avg_len = sum(len(str(v)) for v in values) / max(len(values), 1)

        if avg_len < 2:   s = -0.5  # ほぼ空
        elif avg_len < 5: s =  0.0
        elif avg_len < 15: s = 0.5
        else:             s = 1.0

        scores.append(s)
    return scores


def reward_response_quality(completions, **kwargs) -> list[float]:
    """
    Reward 5: 最終回答の品質
    """
    scores = []
    for text in completions:
        # tool_call/think 除去後の回答テキスト
        resp = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
        resp = re.sub(r"<tool_call>.*?</tool_call>", "", resp, flags=re.DOTALL)
        resp = resp.strip()

        if not resp:
            scores.append(-1.0)
            continue

        s = 0.0

        # 日本語が含まれる
        jp = len(re.findall(r"[\u3040-\u30ff\u4e00-\u9fff]", resp))
        if jp > 5:
            s += 0.4

        # 長さが適切 (50〜600字)
        rlen = len(resp)
        if rlen < 20:
            s -= 0.5
        elif rlen < 50:
            s += 0.1
        elif rlen <= 600:
            s += 0.4
        else:
            s += 0.2  # 長すぎると少し減点

        # 構造化 (Markdown)
        if "**" in resp or "```" in resp or "\n-" in resp or "\n1." in resp:
            s += 0.2

        # エラーメッセージや生 JSON を含まない
        if '{"error"' in resp or "Traceback" in resp:
            s -= 0.5

        scores.append(min(max(s, -1.0), 1.0))
    return scores


# 全報酬関数のリスト (重み付き)
REWARD_FNS = [
    (reward_think_depth,     0.30),  # 最重要
    (reward_tool_format,     0.25),
    (reward_tool_selection,  0.20),
    (reward_args_quality,    0.15),
    (reward_response_quality,0.10),
]


def combined_reward(completions, **kwargs) -> list[float]:
    n = len(completions)
    total = [0.0] * n
    for fn, weight in REWARD_FNS:
        try:
            part = fn(completions, **kwargs)
            for i in range(n):
                total[i] += part[i] * weight
        except Exception as e:
            print(f"  [WARN] reward fn error: {e}", file=sys.stderr)
    return total


# ─── データ準備 ─────────────────────────────────────────────────

def prepare_grpo_dataset(data_path: str, tokenizer, max_seq: int = 4096) -> "Dataset":
    """GRPO 用データセット準備"""
    from datasets import Dataset

    with open(data_path, encoding="utf-8") as f:
        data = json.load(f)

    rows = []
    for item in data:
        convs = item["conversations"]

        # 最初の user まで (system + user) をプロンプトとして使う
        prompt_convs = []
        first_user_idx = -1
        for i, msg in enumerate(convs):
            if msg["role"] == "user":
                first_user_idx = i
                break
            prompt_convs.append(msg)

        if first_user_idx < 0:
            continue

        prompt_convs.append(convs[first_user_idx])

        # ChatML 形式に変換
        prompt_text = ""
        for msg in prompt_convs:
            role    = msg["role"]
            content = msg["content"]
            if role == "tool":
                prompt_text += f"<|im_start|>user\n[Tool Result: {msg.get('name','tool')}]\n{content}<|im_end|>\n"
            else:
                prompt_text += f"<|im_start|>{role}\n{content}<|im_end|>\n"
        prompt_text += "<|im_start|>assistant\n"

        # 期待ツール
        tool_msg = next((m for m in convs if m.get("role") == "tool"), None)
        expected_tool = tool_msg["name"] if tool_msg else None

        rows.append({
            "prompt":        prompt_text,
            "expected_tool": expected_tool,
        })

    return Dataset.from_list(rows)


# ─── メイン ────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config",     default="config_futa.yaml")
    parser.add_argument("--sft_model",  default=None)
    parser.add_argument("--data",       default="merged_v4.json")
    parser.add_argument("--output_dir", default="./futa-2b-v1-grpo")
    parser.add_argument("--epochs",     type=int, default=1)
    parser.add_argument("--batch_size", type=int, default=2)
    parser.add_argument("--num_gen",    type=int, default=8, help="グループサイズ")
    parser.add_argument("--lr",         type=float, default=5e-7)
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))

    with open(os.path.join(script_dir, args.config)) as f:
        cfg = yaml.safe_load(f)

    print("=" * 60)
    print("Futa-2B GRPO 強化学習")
    print("  報酬関数: think_depth(30%) + tool_format(25%) +")
    print("           tool_selection(20%) + args_quality(15%) +")
    print("           response_quality(10%)")
    print(f"  グループサイズ: {args.num_gen}")
    print("=" * 60)

    try:
        from unsloth import FastLanguageModel
    except ImportError:
        print("ERROR: pip install unsloth")
        sys.exit(1)

    model_path = args.sft_model or os.path.join(script_dir, cfg["training"]["output_dir"])
    print(f"SFT モデル: {model_path}")

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name    = model_path,
        max_seq_length= cfg["model"]["max_seq_length"],
        load_in_4bit  = True,
        trust_remote_code=True,
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # GRPO 用 LoRA (SFT とは別)
    model = FastLanguageModel.get_peft_model(
        model,
        r              = 32,
        lora_alpha     = 64,
        lora_dropout   = 0.05,
        target_modules = ["q_proj","k_proj","v_proj","o_proj"],
        bias           = "none",
        use_gradient_checkpointing="unsloth",
        random_state   = 42,
    )

    data_path = os.path.join(script_dir, args.data)
    dataset   = prepare_grpo_dataset(data_path, tokenizer, cfg["model"]["max_seq_length"])
    print(f"GRPO データ: {len(dataset)}件")

    from trl import GRPOConfig, GRPOTrainer

    # expected_tool を報酬関数に渡すためのラッパー
    def reward_with_metadata(completions, prompts=None, **kwargs) -> list[float]:
        return combined_reward(completions, prompts=prompts, **kwargs)

    grpo_cfg = GRPOConfig(
        output_dir              = os.path.join(script_dir, args.output_dir),
        num_train_epochs        = args.epochs,
        per_device_train_batch_size = args.batch_size,
        num_generations         = args.num_gen,
        max_completion_length   = 1024,
        learning_rate           = args.lr,
        lr_scheduler_type       = "cosine",
        warmup_ratio            = 0.05,
        logging_steps           = 5,
        save_steps              = 100,
        save_total_limit        = 2,
        bf16                    = True,
        seed                    = 42,
        report_to               = "none",
        # RC-GRPO: KL ペナルティで policy collapse 防止
        kl_coef                 = 0.05,
    )

    trainer = GRPOTrainer(
        model            = model,
        config           = grpo_cfg,
        train_dataset    = dataset,
        reward_funcs     = reward_with_metadata,
        processing_class = tokenizer,
    )

    print("\n GRPO 学習開始...")
    trainer.train()

    out = os.path.join(script_dir, args.output_dir)
    model.save_pretrained(out)
    tokenizer.save_pretrained(out)
    print(f"\n完了: {out}")


if __name__ == "__main__":
    main()
