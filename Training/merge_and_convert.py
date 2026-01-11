#!/usr/bin/env python3
"""
Merge LoRA weights and Convert to GGUF
======================================

This script:
1. Merges LoRA weights with the base model
2. Saves the merged model
3. Converts to GGUF format for mobile deployment

Requirements:
    pip install torch transformers peft

    # For GGUF conversion, you need llama.cpp:
    git clone https://github.com/ggerganov/llama.cpp
    cd llama.cpp && make

Usage:
    python merge_and_convert.py \
        --lora_path ./elio-qwen3-1.7b-jp-lora \
        --output_dir ./elio-qwen3-1.7b-jp-merged \
        --quantize q4_k_m
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

import torch
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer


def parse_args():
    parser = argparse.ArgumentParser(description="Merge LoRA and convert to GGUF")
    parser.add_argument(
        "--base_model",
        type=str,
        default="Qwen/Qwen2.5-1.5B-Instruct",
        help="Base model name",
    )
    parser.add_argument(
        "--lora_path",
        type=str,
        required=True,
        help="Path to LoRA weights",
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="./elio-qwen3-1.7b-jp-merged",
        help="Directory to save merged model",
    )
    parser.add_argument(
        "--gguf_output",
        type=str,
        default="./elio-qwen3-1.7b-jp.gguf",
        help="Output GGUF file path",
    )
    parser.add_argument(
        "--quantize",
        type=str,
        default="q4_k_m",
        choices=["f16", "q8_0", "q4_k_m", "q4_k_s", "q3_k_m", "q2_k"],
        help="Quantization type",
    )
    parser.add_argument(
        "--llama_cpp_path",
        type=str,
        default="../llama.cpp",
        help="Path to llama.cpp directory",
    )
    parser.add_argument(
        "--skip_merge",
        action="store_true",
        help="Skip merge step (use existing merged model)",
    )
    parser.add_argument(
        "--skip_convert",
        action="store_true",
        help="Skip GGUF conversion step",
    )
    return parser.parse_args()


def merge_lora(base_model_name: str, lora_path: str, output_dir: str):
    """Merge LoRA weights with base model."""
    print("=" * 60)
    print("Step 1: Merging LoRA weights")
    print("=" * 60)

    print(f"Loading base model: {base_model_name}")
    base_model = AutoModelForCausalLM.from_pretrained(
        base_model_name,
        torch_dtype=torch.float16,
        device_map="auto",
        trust_remote_code=True,
    )

    print(f"Loading LoRA weights from: {lora_path}")
    model = PeftModel.from_pretrained(base_model, lora_path)

    print("Merging weights...")
    merged_model = model.merge_and_unload()

    print(f"Saving merged model to: {output_dir}")
    merged_model.save_pretrained(output_dir, safe_serialization=True)

    # Also save tokenizer
    tokenizer = AutoTokenizer.from_pretrained(lora_path)
    tokenizer.save_pretrained(output_dir)

    print("Merge complete!")
    return output_dir


def convert_to_gguf(
    model_path: str,
    output_path: str,
    llama_cpp_path: str,
    quantize: str,
):
    """Convert merged model to GGUF format."""
    print("\n" + "=" * 60)
    print("Step 2: Converting to GGUF")
    print("=" * 60)

    convert_script = os.path.join(llama_cpp_path, "convert_hf_to_gguf.py")

    if not os.path.exists(convert_script):
        print(f"Error: Could not find {convert_script}")
        print("Please clone llama.cpp and build it:")
        print("  git clone https://github.com/ggerganov/llama.cpp")
        print("  cd llama.cpp && make")
        sys.exit(1)

    # First convert to f16 GGUF
    f16_output = output_path.replace(".gguf", "-f16.gguf")
    print(f"Converting to GGUF (f16): {f16_output}")

    cmd = [
        sys.executable,
        convert_script,
        model_path,
        "--outfile",
        f16_output,
        "--outtype",
        "f16",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error converting to GGUF: {result.stderr}")
        sys.exit(1)

    print("Conversion to f16 GGUF complete!")

    # Quantize if needed
    if quantize != "f16":
        print(f"\nQuantizing to {quantize}...")
        quantize_bin = os.path.join(llama_cpp_path, "llama-quantize")

        if not os.path.exists(quantize_bin):
            print(f"Error: Could not find {quantize_bin}")
            print("Please build llama.cpp: cd llama.cpp && make")
            sys.exit(1)

        cmd = [quantize_bin, f16_output, output_path, quantize]

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error quantizing: {result.stderr}")
            sys.exit(1)

        # Remove f16 intermediate file
        os.remove(f16_output)
        print(f"Quantization complete: {output_path}")
    else:
        shutil.move(f16_output, output_path)

    # Print file size
    size_mb = os.path.getsize(output_path) / (1024 * 1024)
    print(f"Final model size: {size_mb:.1f} MB")

    return output_path


def create_model_info(output_path: str, args):
    """Create model info JSON file."""
    info = {
        "name": "Elio-Qwen3-1.7B-JP",
        "description": "Qwen3 1.7B fine-tuned for Japanese thinking output",
        "base_model": args.base_model,
        "quantization": args.quantize,
        "file": os.path.basename(output_path),
        "size_mb": os.path.getsize(output_path) / (1024 * 1024),
        "features": [
            "Japanese thinking (<think> tags)",
            "Optimized for mobile deployment",
            "GGUF format for llama.cpp",
        ],
        "usage": {
            "context_size": 4096,
            "recommended_temp": 0.7,
            "stop_tokens": ["<|im_end|>", "</think>"],
        },
    }

    info_path = output_path.replace(".gguf", "-info.json")
    with open(info_path, "w", encoding="utf-8") as f:
        json.dump(info, f, indent=2, ensure_ascii=False)

    print(f"Model info saved to: {info_path}")


def main():
    args = parse_args()

    print("=" * 60)
    print("Elio Model Merge & GGUF Conversion")
    print("=" * 60)
    print(f"Base model: {args.base_model}")
    print(f"LoRA path: {args.lora_path}")
    print(f"Output: {args.gguf_output}")
    print(f"Quantization: {args.quantize}")
    print("=" * 60)

    # Step 1: Merge LoRA
    if not args.skip_merge:
        merge_lora(args.base_model, args.lora_path, args.output_dir)
    else:
        print("Skipping merge step (using existing merged model)")

    # Step 2: Convert to GGUF
    if not args.skip_convert:
        convert_to_gguf(
            args.output_dir,
            args.gguf_output,
            args.llama_cpp_path,
            args.quantize,
        )
        create_model_info(args.gguf_output, args)
    else:
        print("Skipping GGUF conversion step")

    print("\n" + "=" * 60)
    print("All done!")
    print("=" * 60)
    print(f"\nTo use this model in Elio:")
    print(f"1. Copy {args.gguf_output} to the app's Models folder")
    print("2. The model will appear in the model selection list")
    print("\nOr host it on Hugging Face for download within the app.")


if __name__ == "__main__":
    main()
