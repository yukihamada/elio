#!/usr/bin/env python3
"""
Qwen3 1.7B LoRA Training Script for Japanese Thinking
======================================================

This script fine-tunes Qwen3 1.7B using LoRA to output thinking in Japanese.

Requirements:
    pip install torch transformers peft datasets accelerate bitsandbytes

Usage:
    python train_lora.py --output_dir ./elio-qwen3-1.7b-jp

For GPU training (recommended):
    CUDA_VISIBLE_DEVICES=0 python train_lora.py

For CPU training (slow):
    python train_lora.py --use_cpu
"""

import argparse
import json
import os
from typing import Dict, List

import torch
from datasets import Dataset
from peft import (
    LoraConfig,
    TaskType,
    get_peft_model,
    prepare_model_for_kbit_training,
)
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    DataCollatorForSeq2Seq,
    Trainer,
    TrainingArguments,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Train Qwen3 1.7B with LoRA for Japanese thinking")
    parser.add_argument(
        "--model_name",
        type=str,
        default="Qwen/Qwen2.5-1.5B-Instruct",  # Closest available, or use Qwen3 when released
        help="Base model to fine-tune",
    )
    parser.add_argument(
        "--training_data",
        type=str,
        default="training_data.json",
        help="Path to training data JSON file",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="./elio-qwen3-1.7b-jp-lora",
        help="Directory to save the LoRA weights",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=3,
        help="Number of training epochs",
    )
    parser.add_argument(
        "--batch_size",
        type=int,
        default=4,
        help="Training batch size",
    )
    parser.add_argument(
        "--learning_rate",
        type=float,
        default=2e-4,
        help="Learning rate",
    )
    parser.add_argument(
        "--lora_r",
        type=int,
        default=16,
        help="LoRA rank",
    )
    parser.add_argument(
        "--lora_alpha",
        type=int,
        default=32,
        help="LoRA alpha",
    )
    parser.add_argument(
        "--use_cpu",
        action="store_true",
        help="Force CPU training (slow)",
    )
    parser.add_argument(
        "--use_4bit",
        action="store_true",
        default=True,
        help="Use 4-bit quantization for training",
    )
    parser.add_argument(
        "--max_length",
        type=int,
        default=2048,
        help="Maximum sequence length",
    )
    return parser.parse_args()


def load_training_data(file_path: str) -> List[Dict]:
    """Load training data from JSON file."""
    with open(file_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


def format_conversation(conversation: Dict, tokenizer) -> str:
    """Format a conversation into the model's chat template."""
    messages = conversation["conversations"]

    # Build chat format
    formatted = ""
    for msg in messages:
        role = msg["role"]
        content = msg["content"]

        if role == "user":
            formatted += f"<|im_start|>user\n{content}<|im_end|>\n"
        elif role == "assistant":
            formatted += f"<|im_start|>assistant\n{content}<|im_end|>\n"
        elif role == "system":
            formatted += f"<|im_start|>system\n{content}<|im_end|>\n"

    return formatted


def prepare_dataset(training_data: List[Dict], tokenizer, max_length: int) -> Dataset:
    """Prepare the dataset for training."""

    def tokenize_function(examples):
        texts = []
        for conv in examples["conversations"]:
            text = format_conversation({"conversations": conv}, tokenizer)
            texts.append(text)

        tokenized = tokenizer(
            texts,
            truncation=True,
            max_length=max_length,
            padding="max_length",
            return_tensors="pt",
        )

        # Labels are the same as input_ids for causal LM
        tokenized["labels"] = tokenized["input_ids"].clone()

        return tokenized

    # Create dataset
    dataset_dict = {"conversations": [d["conversations"] for d in training_data]}
    dataset = Dataset.from_dict(dataset_dict)

    # Tokenize
    tokenized_dataset = dataset.map(
        tokenize_function,
        batched=True,
        remove_columns=["conversations"],
    )

    return tokenized_dataset


def main():
    args = parse_args()

    print("=" * 60)
    print("Elio Japanese Thinking LoRA Training")
    print("=" * 60)
    print(f"Model: {args.model_name}")
    print(f"Output: {args.output_dir}")
    print(f"Epochs: {args.epochs}")
    print(f"LoRA rank: {args.lora_r}, alpha: {args.lora_alpha}")
    print("=" * 60)

    # Determine device
    if args.use_cpu:
        device = "cpu"
        print("Using CPU (this will be slow)")
    elif torch.cuda.is_available():
        device = "cuda"
        print(f"Using CUDA: {torch.cuda.get_device_name(0)}")
    elif torch.backends.mps.is_available():
        device = "mps"
        print("Using Apple Metal (MPS)")
    else:
        device = "cpu"
        print("No GPU available, using CPU")

    # Load tokenizer
    print("\nLoading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(
        args.model_name,
        trust_remote_code=True,
        padding_side="right",
    )

    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    # Quantization config for 4-bit training
    bnb_config = None
    if args.use_4bit and device == "cuda":
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_use_double_quant=True,
        )

    # Load model
    print("Loading model...")
    model = AutoModelForCausalLM.from_pretrained(
        args.model_name,
        quantization_config=bnb_config,
        device_map="auto" if device != "cpu" else None,
        trust_remote_code=True,
        torch_dtype=torch.bfloat16 if device != "cpu" else torch.float32,
    )

    if device == "cpu":
        model = model.to(device)

    # Prepare model for training
    if bnb_config:
        model = prepare_model_for_kbit_training(model)

    # LoRA configuration
    print("Applying LoRA...")
    lora_config = LoraConfig(
        r=args.lora_r,
        lora_alpha=args.lora_alpha,
        target_modules=[
            "q_proj",
            "k_proj",
            "v_proj",
            "o_proj",
            "gate_proj",
            "up_proj",
            "down_proj",
        ],
        lora_dropout=0.05,
        bias="none",
        task_type=TaskType.CAUSAL_LM,
    )

    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # Load and prepare training data
    print("\nLoading training data...")
    script_dir = os.path.dirname(os.path.abspath(__file__))
    training_data_path = os.path.join(script_dir, args.training_data)
    training_data = load_training_data(training_data_path)
    print(f"Loaded {len(training_data)} training examples")

    # Prepare dataset
    print("Preparing dataset...")
    dataset = prepare_dataset(training_data, tokenizer, args.max_length)

    # Training arguments
    training_args = TrainingArguments(
        output_dir=args.output_dir,
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=4,
        learning_rate=args.learning_rate,
        weight_decay=0.01,
        warmup_ratio=0.1,
        logging_steps=10,
        save_strategy="epoch",
        save_total_limit=2,
        bf16=device == "cuda",
        fp16=False,
        optim="adamw_torch",
        report_to="none",
        gradient_checkpointing=True,
        dataloader_num_workers=0,
    )

    # Data collator
    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        padding=True,
        return_tensors="pt",
    )

    # Initialize trainer
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=dataset,
        data_collator=data_collator,
    )

    # Train
    print("\n" + "=" * 60)
    print("Starting training...")
    print("=" * 60)

    trainer.train()

    # Save the LoRA weights
    print("\nSaving LoRA weights...")
    model.save_pretrained(args.output_dir)
    tokenizer.save_pretrained(args.output_dir)

    print("\n" + "=" * 60)
    print("Training complete!")
    print(f"LoRA weights saved to: {args.output_dir}")
    print("=" * 60)

    # Save training info
    info = {
        "base_model": args.model_name,
        "lora_r": args.lora_r,
        "lora_alpha": args.lora_alpha,
        "epochs": args.epochs,
        "training_examples": len(training_data),
        "description": "Japanese thinking LoRA for Elio AI Assistant",
    }

    with open(os.path.join(args.output_dir, "training_info.json"), "w") as f:
        json.dump(info, f, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
