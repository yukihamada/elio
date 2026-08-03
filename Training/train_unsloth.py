#!/usr/bin/env python3
"""
Futa-2B SFT Training Script (Unsloth)
=======================================

Fine-tunes Qwen3.5-2B using Unsloth for 2x faster training.
Reads configuration from config_futa.yaml.

Requirements:
    pip install unsloth transformers datasets peft trl wandb pyyaml

Usage:
    python train_unsloth.py
    python train_unsloth.py --config config_futa.yaml
    python train_unsloth.py --config config_futa.yaml --no-wandb
"""

import argparse
import json
import os
import sys

import yaml


def load_config(config_path: str) -> dict:
    """Load YAML configuration."""
    with open(config_path, "r") as f:
        return yaml.safe_load(f)


def load_data(path: str) -> list:
    """Load training data from JSON."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def format_chatml(example: dict, tokenizer) -> str:
    """Format a conversation into ChatML format."""
    messages = example["conversations"]
    formatted = ""
    for msg in messages:
        role = msg["role"]
        content = msg["content"]
        # Map tool role to user (with context)
        if role == "tool":
            tool_name = msg.get("name", "tool")
            formatted += f"<|im_start|>user\n[Tool Result: {tool_name}]\n{content}<|im_end|>\n"
        else:
            formatted += f"<|im_start|>{role}\n{content}<|im_end|>\n"
    return formatted


def main():
    parser = argparse.ArgumentParser(description="Train Futa-2B with Unsloth SFT")
    parser.add_argument("--config", type=str, default="config_futa.yaml")
    parser.add_argument("--no-wandb", action="store_true", help="Disable WandB logging")
    parser.add_argument("--resume", type=str, default=None, help="Resume from checkpoint")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    config_path = os.path.join(script_dir, args.config)
    cfg = load_config(config_path)

    print("=" * 60)
    print("Futa-2B SFT Training (Unsloth)")
    print("=" * 60)
    print(f"Model: {cfg['model']['name']}")
    print(f"LoRA r={cfg['lora']['r']}, alpha={cfg['lora']['alpha']}")
    print(f"Max seq length: {cfg['model']['max_seq_length']}")
    print("=" * 60)

    # ─── WandB setup ───
    use_wandb = cfg.get("wandb", {}).get("enabled", False) and not args.no_wandb
    if use_wandb:
        import wandb
        wandb.init(
            project=cfg["wandb"]["project"],
            name=cfg["wandb"]["run_name"],
            tags=cfg["wandb"].get("tags", []),
            config=cfg,
        )
        report_to = "wandb"
    else:
        report_to = "none"

    # ─── Load model with Unsloth ───
    try:
        from unsloth import FastLanguageModel
    except ImportError:
        print("Error: unsloth not installed. Install with:")
        print("  pip install unsloth")
        sys.exit(1)

    model, tokenizer = FastLanguageModel.from_pretrained(
        model_name=cfg["model"]["name"],
        max_seq_length=cfg["model"]["max_seq_length"],
        dtype=None,  # auto-detect
        load_in_4bit=cfg["model"].get("load_in_4bit", True),
        trust_remote_code=cfg["model"].get("trust_remote_code", True),
    )

    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # ─── Apply LoRA ───
    model = FastLanguageModel.get_peft_model(
        model,
        r=cfg["lora"]["r"],
        lora_alpha=cfg["lora"]["alpha"],
        lora_dropout=cfg["lora"]["dropout"],
        target_modules=cfg["lora"]["target_modules"],
        bias=cfg["lora"]["bias"],
        use_gradient_checkpointing="unsloth",
        random_state=cfg["training"]["seed"],
    )

    model.print_trainable_parameters()

    # ─── Load data ───
    print("\nLoading training data...")
    train_path = os.path.join(script_dir, cfg["data"]["train_file"])
    train_data = load_data(train_path)
    print(f"Train examples: {len(train_data)}")

    eval_data = None
    eval_path = os.path.join(script_dir, cfg["data"]["eval_file"])
    if os.path.exists(eval_path):
        eval_data = load_data(eval_path)
        print(f"Eval examples: {len(eval_data)}")
    else:
        # Auto-split
        split = cfg["data"].get("eval_split", 0.1)
        if split > 0:
            import random
            random.seed(cfg["training"]["seed"])
            random.shuffle(train_data)
            eval_count = int(len(train_data) * split)
            eval_data = train_data[:eval_count]
            train_data = train_data[eval_count:]
            print(f"Auto-split: train={len(train_data)}, eval={len(eval_data)}")

    # ─── Prepare datasets ───
    from datasets import Dataset

    def tokenize_fn(examples):
        texts = []
        for conv in examples["conversations"]:
            text = format_chatml({"conversations": conv}, tokenizer)
            texts.append(text)

        max_len = cfg["data"].get("max_length", 4096)
        tokenized = tokenizer(
            texts,
            truncation=True,
            max_length=max_len,
            padding="max_length",
            return_tensors="pt",
        )
        tokenized["labels"] = tokenized["input_ids"].clone()
        return tokenized

    train_dataset = Dataset.from_dict({"conversations": [d["conversations"] for d in train_data]})
    train_dataset = train_dataset.map(tokenize_fn, batched=True, remove_columns=["conversations"])

    eval_dataset = None
    if eval_data:
        eval_dataset = Dataset.from_dict({"conversations": [d["conversations"] for d in eval_data]})
        eval_dataset = eval_dataset.map(tokenize_fn, batched=True, remove_columns=["conversations"])

    # ─── Training ───
    from transformers import TrainingArguments, DataCollatorForSeq2Seq
    from trl import SFTTrainer

    tc = cfg["training"]
    training_args = TrainingArguments(
        output_dir=os.path.join(script_dir, tc["output_dir"]),
        num_train_epochs=tc["num_epochs"],
        per_device_train_batch_size=tc["batch_size"],
        gradient_accumulation_steps=tc["gradient_accumulation_steps"],
        learning_rate=tc["learning_rate"],
        lr_scheduler_type=tc.get("lr_scheduler", "cosine"),
        warmup_ratio=tc["warmup_ratio"],
        weight_decay=tc["weight_decay"],
        max_grad_norm=tc.get("max_grad_norm", 1.0),
        bf16=tc.get("bf16", True),
        gradient_checkpointing=tc.get("gradient_checkpointing", True),
        save_strategy=tc.get("save_strategy", "steps"),
        save_steps=tc.get("save_steps", 200),
        save_total_limit=tc.get("save_total_limit", 3),
        logging_steps=tc.get("logging_steps", 10),
        eval_strategy="steps" if eval_dataset else "no",
        eval_steps=tc.get("eval_steps", 200) if eval_dataset else None,
        seed=tc["seed"],
        optim=tc.get("optim", "adamw_8bit"),
        report_to=report_to,
        dataloader_num_workers=0,
    )

    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        padding=True,
        return_tensors="pt",
    )

    trainer = SFTTrainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        eval_dataset=eval_dataset,
        data_collator=data_collator,
    )

    # ─── Train ───
    print("\n" + "=" * 60)
    print("Starting training...")
    print("=" * 60)

    if args.resume:
        trainer.train(resume_from_checkpoint=args.resume)
    else:
        trainer.train()

    # ─── Save ───
    output_dir = os.path.join(script_dir, tc["output_dir"])
    print(f"\nSaving LoRA weights to: {output_dir}")
    model.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)

    # Save training info
    info = {
        "base_model": cfg["model"]["name"],
        "lora_r": cfg["lora"]["r"],
        "lora_alpha": cfg["lora"]["alpha"],
        "epochs": tc["num_epochs"],
        "train_examples": len(train_data),
        "eval_examples": len(eval_data) if eval_data else 0,
        "description": "Futa-2B: Japanese thinking + tool calling fine-tuned model",
    }
    with open(os.path.join(output_dir, "training_info.json"), "w") as f:
        json.dump(info, f, indent=2, ensure_ascii=False)

    # ─── Optional merge ───
    export_cfg = cfg.get("export", {})
    if export_cfg.get("merge_lora", False):
        print("\nMerging LoRA weights with base model...")
        merged_dir = os.path.join(script_dir, export_cfg["output_dir"])
        model.save_pretrained_merged(merged_dir, tokenizer, save_method="merged_16bit")
        print(f"Merged model saved to: {merged_dir}")

    if use_wandb:
        wandb.finish()

    print("\n" + "=" * 60)
    print("Training complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
