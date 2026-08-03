#!/bin/bash
# wait_and_launch.sh — データ生成完了を待ってmerged_v8を作りLambdaで訓練開始

set -e
TRAINING_DIR="/Users/yuki/workspace/ai/elio/Training"
QWEN_DIR="/Users/yuki/workspace/ai/qwen-jp"

echo "=== データ生成完了待ち ==="

wait_for_file() {
    local file="$1"
    local min_count="$2"
    echo -n "待機中: $file (目標${min_count}件以上)"
    while true; do
        if [ -f "$TRAINING_DIR/$file" ]; then
            count=$(python3 -c "import json; print(len(json.load(open('$TRAINING_DIR/$file'))))" 2>/dev/null || echo 0)
            echo -n " [$count]"
            if [ "$count" -ge "$min_count" ]; then
                echo " ✓"
                return 0
            fi
        fi
        echo -n "."
        sleep 60
    done
}

# バックグラウンドプロセスが完了するまで待機
wait_for_file "persona_variants.json" 3000
wait_for_file "recovery_multiturn.json" 200
wait_for_file "quality_filtered_v7.json" 1500

echo ""
echo "=== merged_v8 ビルド ==="
cd "$TRAINING_DIR"
python3 build_merged_v8.py

echo ""
echo "=== Lambda Labs 訓練開始 ==="
cd "$QWEN_DIR"
GKEY=$(aws lambda get-function-configuration \
    --function-name nanobot-prod \
    --region ap-northeast-1 \
    --query 'Environment.Variables.GEMINI_API_KEY' \
    --output text)

GEMINI_API_KEY="$GKEY" python3 launch_training.py --auto

echo "完了！"
