#!/bin/bash
# Phase 3以降の自動実行スクリプト
# distilled.json と long_multiturn.json が完成したら実行

cd "$(dirname "$0")"

echo "=== Phase 3: 品質フィルタ + マージ ==="
python3 quality_filter.py \
  --inputs distilled.json long_multiturn.json multitool_data.json real_tool_data.json \
  --output merged_v4.json \
  --eval eval_v4.json \
  --min-score 0.6 \
  --eval-ratio 0.1

echo ""
echo "=== 完了 ==="
ls -lh merged_v4.json eval_v4.json 2>/dev/null
