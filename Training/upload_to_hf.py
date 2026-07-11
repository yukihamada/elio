#!/usr/bin/env python3
"""
Upload Model to HuggingFace Hub
=================================

Uploads model files (GGUF, AWQ, or full model) to HuggingFace.

Requirements:
    pip install huggingface_hub

Usage:
    # Upload GGUF
    HF_TOKEN=hf_... python upload_to_hf.py --model_path ./futa-2b-v1-q4_k_m.gguf --repo enablerdao/futa-2b-v1-gguf

    # Upload AWQ model directory
    HF_TOKEN=hf_... python upload_to_hf.py --model_path ./futa-2b-v1-awq --repo enablerdao/futa-2b-v1-awq

    # Upload merged model directory
    HF_TOKEN=hf_... python upload_to_hf.py --model_path ./futa-2b-v1-merged --repo enablerdao/futa-2b-v1
"""

import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Upload model to HuggingFace Hub")
    parser.add_argument("--model_path", type=str, required=True, help="Path to model file or directory")
    parser.add_argument("--repo", type=str, required=True, help="HuggingFace repo ID (e.g. enablerdao/futa-2b-v1)")
    parser.add_argument("--token", type=str, default=None, help="HF token (or use HF_TOKEN env var)")
    parser.add_argument("--private", action="store_true", help="Create private repo")
    parser.add_argument("--commit_message", type=str, default="Upload futa-2b model", help="Commit message")
    args = parser.parse_args()

    token = args.token or os.environ.get("HF_TOKEN")
    if not token:
        print("Error: HF_TOKEN not set. Set via --token or HF_TOKEN env var.")
        sys.exit(1)

    try:
        from huggingface_hub import HfApi, create_repo
    except ImportError:
        print("Error: huggingface_hub not installed. Install with:")
        print("  pip install huggingface_hub")
        sys.exit(1)

    api = HfApi(token=token)

    print("=" * 60)
    print("Upload to HuggingFace Hub")
    print("=" * 60)
    print(f"Model: {args.model_path}")
    print(f"Repo: {args.repo}")
    print("=" * 60)

    # Create repo if it doesn't exist
    try:
        create_repo(
            repo_id=args.repo,
            token=token,
            private=args.private,
            exist_ok=True,
        )
        print(f"Repo '{args.repo}' ready.")
    except Exception as e:
        print(f"Warning: {e}")

    # Upload
    if os.path.isfile(args.model_path):
        # Single file upload (GGUF)
        filename = os.path.basename(args.model_path)
        print(f"\nUploading file: {filename}")
        api.upload_file(
            path_or_fileobj=args.model_path,
            path_in_repo=filename,
            repo_id=args.repo,
            commit_message=args.commit_message,
        )
        size_mb = os.path.getsize(args.model_path) / (1024**2)
        print(f"Uploaded: {filename} ({size_mb:.1f} MB)")

    elif os.path.isdir(args.model_path):
        # Directory upload (AWQ or merged model)
        print(f"\nUploading directory: {args.model_path}")
        api.upload_folder(
            folder_path=args.model_path,
            repo_id=args.repo,
            commit_message=args.commit_message,
            ignore_patterns=["*.pyc", "__pycache__", ".git*", "optimizer*", "scheduler*", "training_args*"],
        )
        total_size = sum(
            os.path.getsize(os.path.join(dp, f))
            for dp, _, fns in os.walk(args.model_path)
            for f in fns
        )
        print(f"Uploaded: {total_size / (1024**2):.1f} MB total")
    else:
        print(f"Error: {args.model_path} not found")
        sys.exit(1)

    print(f"\nModel available at: https://huggingface.co/{args.repo}")
    print("=" * 60)


if __name__ == "__main__":
    main()
