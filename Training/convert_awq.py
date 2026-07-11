#!/usr/bin/env python3
"""
AWQ Quantization for vLLM Deployment
======================================

Converts the merged model to AWQ format for efficient vLLM serving.

Requirements:
    pip install autoawq transformers

Usage:
    python convert_awq.py --model_path ./futa-2b-v1-merged --output ./futa-2b-v1-awq
"""

import argparse
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Convert model to AWQ quantization")
    parser.add_argument("--model_path", type=str, required=True, help="Path to merged HF model")
    parser.add_argument("--output", type=str, default="./futa-2b-v1-awq", help="Output directory")
    parser.add_argument("--quant_bits", type=int, default=4, choices=[4, 8], help="Quantization bits")
    parser.add_argument("--group_size", type=int, default=128, help="Quantization group size")
    parser.add_argument("--calib_data", type=str, default=None, help="Calibration data (JSON)")
    parser.add_argument("--calib_samples", type=int, default=128, help="Number of calibration samples")
    parser.add_argument("--calib_seq_len", type=int, default=512, help="Calibration sequence length")
    args = parser.parse_args()

    print("=" * 60)
    print("AWQ Quantization")
    print("=" * 60)
    print(f"Model: {args.model_path}")
    print(f"Output: {args.output}")
    print(f"Bits: {args.quant_bits}, Group size: {args.group_size}")
    print("=" * 60)

    try:
        from awq import AutoAWQForCausalLM
        from transformers import AutoTokenizer
    except ImportError:
        print("Error: autoawq not installed. Install with:")
        print("  pip install autoawq")
        sys.exit(1)

    # Load tokenizer
    print("\nLoading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(args.model_path, trust_remote_code=True)

    # Load model
    print("Loading model for quantization...")
    model = AutoAWQForCausalLM.from_pretrained(
        args.model_path,
        trust_remote_code=True,
        safetensors=True,
    )

    # Prepare calibration data
    calib_data = None
    if args.calib_data and os.path.exists(args.calib_data):
        print(f"Loading calibration data from: {args.calib_data}")
        with open(args.calib_data, "r", encoding="utf-8") as f:
            raw_data = json.load(f)

        calib_data = []
        for item in raw_data[:args.calib_samples]:
            text = ""
            for msg in item.get("conversations", []):
                role = msg["role"]
                content = msg["content"]
                text += f"<|im_start|>{role}\n{content}<|im_end|>\n"
            calib_data.append(text)
    else:
        print("Using default calibration data (wikitext)")

    # Quantize
    quant_config = {
        "zero_point": True,
        "q_group_size": args.group_size,
        "w_bit": args.quant_bits,
        "version": "GEMM",
    }

    print(f"\nQuantizing with config: {quant_config}")
    model.quantize(
        tokenizer,
        quant_config=quant_config,
        calib_data=calib_data,
        n_samples=args.calib_samples,
        seqlen=args.calib_seq_len,
    )

    # Save
    print(f"\nSaving AWQ model to: {args.output}")
    os.makedirs(args.output, exist_ok=True)
    model.save_quantized(args.output, safetensors=True)
    tokenizer.save_pretrained(args.output)

    # Save model info
    info = {
        "name": "futa-2b-v1-awq",
        "base_model": args.model_path,
        "quantization": "awq",
        "bits": args.quant_bits,
        "group_size": args.group_size,
        "format": "safetensors",
        "description": "Futa-2B AWQ quantized for vLLM deployment",
    }
    with open(os.path.join(args.output, "model_info.json"), "w") as f:
        json.dump(info, f, indent=2, ensure_ascii=False)

    # File size
    total_size = sum(
        os.path.getsize(os.path.join(args.output, f))
        for f in os.listdir(args.output)
        if f.endswith((".safetensors", ".bin"))
    )
    print(f"\nAWQ model size: {total_size / (1024**2):.1f} MB")
    print("=" * 60)
    print("AWQ quantization complete!")
    print(f"Deploy with vLLM: vllm serve {args.output} --quantization awq")
    print("=" * 60)


if __name__ == "__main__":
    main()
