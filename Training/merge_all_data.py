#!/usr/bin/env python3
"""
Data Merge Script — Merge All Training Data Sources
=====================================================

Merges training_data.json + tool_data.json + distillation_data.json
into a single unified dataset with deduplication and validation.

Usage:
    python merge_all_data.py --output merged_data.json
    python merge_all_data.py --output merged_data.json --eval_split 0.1
"""

import argparse
import json
import os
import hashlib
import random


def load_json(path: str) -> list:
    """Load JSON file, return empty list if not found."""
    if not os.path.exists(path):
        print(f"  Warning: {path} not found, skipping")
        return []
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    print(f"  Loaded {len(data)} examples from {os.path.basename(path)}")
    return data


def validate_example(example: dict) -> bool:
    """Validate a training example has proper structure."""
    if "conversations" not in example:
        return False
    convs = example["conversations"]
    if len(convs) < 2:
        return False
    # Must have at least one user and one assistant message
    roles = [c.get("role") for c in convs]
    return "user" in roles and "assistant" in roles


def deduplicate(data: list) -> list:
    """Remove duplicate examples based on full conversation hash."""
    seen = set()
    unique = []
    for item in data:
        # Hash the full conversation content (not just the first user message)
        # This allows same question with different tools/responses to both remain
        all_content = "||".join(
            f"{c['role']}:{c['content']}"
            for c in item["conversations"]
            if c.get("content")
        )
        key = hashlib.md5(all_content.encode()).hexdigest()
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return unique


def normalize_example(example: dict) -> dict:
    """Normalize example format (remove extra fields, ensure consistency)."""
    normalized = {
        "conversations": []
    }
    for msg in example["conversations"]:
        norm_msg = {"role": msg["role"], "content": msg["content"]}
        if msg.get("name"):
            norm_msg["name"] = msg["name"]
        normalized["conversations"].append(norm_msg)
    return normalized


def main():
    parser = argparse.ArgumentParser(description="Merge all training data sources")
    parser.add_argument("--output", type=str, default="merged_data.json")
    parser.add_argument("--eval_output", type=str, default="eval_data.json")
    parser.add_argument("--eval_split", type=float, default=0.1, help="Fraction for eval split (0 to disable)")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--data_dir", type=str, default=None, help="Directory containing data files")
    args = parser.parse_args()

    random.seed(args.seed)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = args.data_dir or script_dir

    print("=" * 60)
    print("Merging Training Data")
    print("=" * 60)

    # Load all data sources
    print("\nLoading data sources...")
    sources = {
        "base": load_json(os.path.join(data_dir, "training_data.json")),
        "tool": load_json(os.path.join(data_dir, "tool_data.json")),
        "tool_llm": load_json(os.path.join(data_dir, "tool_data_llm.json")),
        "distillation": load_json(os.path.join(data_dir, "distillation_data.json")),
    }

    # Validate
    print("\nValidating...")
    all_data = []
    for source_name, data in sources.items():
        valid = [d for d in data if validate_example(d)]
        invalid = len(data) - len(valid)
        if invalid > 0:
            print(f"  {source_name}: {invalid} invalid examples removed")
        all_data.extend(valid)

    print(f"Total before dedup: {len(all_data)}")

    # Deduplicate
    all_data = deduplicate(all_data)
    print(f"Total after dedup: {len(all_data)}")

    # Normalize
    all_data = [normalize_example(d) for d in all_data]

    # Shuffle
    random.shuffle(all_data)

    # Split eval
    if args.eval_split > 0:
        eval_count = int(len(all_data) * args.eval_split)
        eval_data = all_data[:eval_count]
        train_data = all_data[eval_count:]
    else:
        train_data = all_data
        eval_data = []

    # Save train
    train_path = os.path.join(data_dir, args.output)
    with open(train_path, "w", encoding="utf-8") as f:
        json.dump(train_data, f, ensure_ascii=False, indent=2)
    print(f"\nTrain data: {len(train_data)} examples → {train_path}")

    # Save eval
    if eval_data:
        eval_path = os.path.join(data_dir, args.eval_output)
        with open(eval_path, "w", encoding="utf-8") as f:
            json.dump(eval_data, f, ensure_ascii=False, indent=2)
        print(f"Eval data: {len(eval_data)} examples → {eval_path}")

    # Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    for source_name, data in sources.items():
        print(f"  {source_name}: {len(data)} examples")
    print(f"  Total (deduplicated): {len(all_data)}")
    print(f"  Train: {len(train_data)}")
    print(f"  Eval: {len(eval_data)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
