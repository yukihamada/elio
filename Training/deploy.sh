#!/bin/bash
# Futa-2B Training Deployment Script
# ====================================
# Syncs training code + config to GPU server and runs training.
#
# Usage:
#   ./deploy.sh <server>              # Deploy and run SFT
#   ./deploy.sh <server> --grpo       # Deploy and run GRPO
#   ./deploy.sh <server> --sync-only  # Sync files only

set -euo pipefail

SERVER="${1:?Usage: ./deploy.sh <user@server> [--grpo|--sync-only]}"
MODE="${2:---sft}"
REMOTE_DIR="~/futa-2b-training"

echo "============================================"
echo "Futa-2B Training Deployment"
echo "============================================"
echo "Server: $SERVER"
echo "Mode: $MODE"
echo "Remote: $REMOTE_DIR"
echo "============================================"

# Files to sync
FILES=(
    train_unsloth.py
    train_grpo.py
    config_futa.yaml
    generate_tool_data_chatweb.py
    generate_distillation_data.py
    merge_all_data.py
    merge_and_convert.py
    convert_awq.py
    upload_to_hf.py
    requirements.txt
    merged_v4.json
    eval_v4.json
    quality_filter.py
    distill_with_claude.py
)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Create remote directory
echo ""
echo "Creating remote directory..."
ssh "$SERVER" "mkdir -p $REMOTE_DIR"

# Sync files
echo "Syncing files..."
for f in "${FILES[@]}"; do
    src="$SCRIPT_DIR/$f"
    if [ -f "$src" ]; then
        rsync -avz "$src" "$SERVER:$REMOTE_DIR/"
        echo "  ✓ $f"
    else
        echo "  - $f (not found, skipping)"
    fi
done

# Sync data files if they exist
for f in tool_data_llm.json distillation_data.json improvements.json; do
    src="$SCRIPT_DIR/$f"
    if [ -f "$src" ]; then
        rsync -avz "$src" "$SERVER:$REMOTE_DIR/"
        echo "  ✓ $f (data)"
    fi
done

if [ "$MODE" = "--sync-only" ]; then
    echo ""
    echo "Sync complete. Files at $SERVER:$REMOTE_DIR/"
    exit 0
fi

# Install dependencies
echo ""
echo "Installing dependencies..."
ssh "$SERVER" "cd $REMOTE_DIR && pip install -q unsloth trl transformers datasets peft accelerate wandb pyyaml autoawq huggingface_hub 2>&1 | tail -1"

if [ "$MODE" = "--grpo" ]; then
    # Run GRPO
    echo ""
    echo "Starting GRPO training..."
    ssh -t "$SERVER" "cd $REMOTE_DIR && python train_grpo.py --config config_futa.yaml"
else
    # Run SFT
    echo ""
    echo "Starting SFT training..."
    ssh -t "$SERVER" "cd $REMOTE_DIR && python train_unsloth.py --config config_futa.yaml"
fi

echo ""
echo "============================================"
echo "Training complete!"
echo "============================================"
echo "Model at: $SERVER:$REMOTE_DIR/futa-2b-v1-lora"
echo ""
echo "Next steps:"
echo "  1. Download: scp -r $SERVER:$REMOTE_DIR/futa-2b-v1-merged ./futa-2b-v1-merged"
echo "  2. GGUF:     python merge_and_convert.py --lora_path ./futa-2b-v1-lora --quantize q4_k_m"
echo "  3. AWQ:      python convert_awq.py --model_path ./futa-2b-v1-merged"
echo "  4. Upload:   python upload_to_hf.py --model_path ./futa-2b-v1-awq --repo enablerdao/futa-2b-v1-awq"
