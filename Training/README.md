# Elio Japanese Thinking Model Training

Qwen3 1.7BをLoRA学習して、日本語で思考を出力するオリジナルモデルを作成します。

## 必要な環境

- Python 3.10+
- CUDA対応GPU (推奨: 16GB+ VRAM) または Apple Silicon Mac
- 20GB以上のディスク空き容量

## セットアップ

```bash
# 仮想環境作成
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# 依存関係インストール
pip install torch transformers peft datasets accelerate bitsandbytes

# llama.cpp (GGUF変換用)
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp && make
```

## トレーニング手順

### Step 1: トレーニングデータ準備

`training_data.json` に日本語思考の例が含まれています。
必要に応じてデータを追加してください。

### Step 2: LoRAトレーニング

```bash
# GPU使用 (推奨)
python train_lora.py --output_dir ./elio-qwen3-jp-lora

# Apple Silicon Mac
python train_lora.py --output_dir ./elio-qwen3-jp-lora --use_cpu

# パラメータ調整例
python train_lora.py \
  --epochs 5 \
  --lora_r 32 \
  --lora_alpha 64 \
  --learning_rate 1e-4 \
  --output_dir ./elio-qwen3-jp-lora
```

### Step 3: マージ & GGUF変換

```bash
python merge_and_convert.py \
  --lora_path ./elio-qwen3-jp-lora \
  --output_dir ./elio-qwen3-jp-merged \
  --gguf_output ./elio-qwen3-jp-q4_k_m.gguf \
  --quantize q4_k_m \
  --llama_cpp_path ./llama.cpp
```

## 量子化オプション

| 形式 | サイズ目安 | 品質 | 用途 |
|------|-----------|------|------|
| f16 | 3.4GB | 最高 | 開発・テスト |
| q8_0 | 1.7GB | 高 | 高性能デバイス |
| q4_k_m | 1.0GB | 良 | 一般的なiPhone (推奨) |
| q4_k_s | 0.9GB | 良 | メモリ制限時 |
| q3_k_m | 0.7GB | 中 | 古いデバイス |

## Elioアプリへの組み込み

1. 生成された `.gguf` ファイルをHugging Faceにアップロード
2. `ModelLoader.swift` の `availableModels` に追加:

```swift
ModelInfo(
    id: "elio-qwen3-jp-q4_k_m",
    name: "Elio Qwen3 JP",
    size: "1.0GB",
    description: "日本語思考対応モデル",
    url: URL(string: "https://huggingface.co/your-repo/elio-qwen3-jp-q4_k_m.gguf")!,
    minTier: .medium,
    supportsVision: false
)
```

## トレーニングデータ形式

```json
{
  "conversations": [
    {"role": "user", "content": "質問"},
    {"role": "assistant", "content": "<think>\n日本語での思考プロセス\n</think>\n\n回答"}
  ]
}
```

## 期待される出力

トレーニング後、モデルは以下のように応答します：

```
ユーザー: 1+1は？

アシスタント: <think>
簡単な足し算。1と1を足すと2になる。
</think>

1 + 1 = 2 です。
```

## トラブルシューティング

### メモリ不足

```bash
# バッチサイズを下げる
python train_lora.py --batch_size 1

# 勾配蓄積を増やす (train_lora.py内で調整)
gradient_accumulation_steps=8
```

### CUDA out of memory

4bit量子化でトレーニング（デフォルトで有効）を使用するか、
より少ないRAMのモデルを選択してください。

## ライセンス

ベースモデル（Qwen3）のライセンスに従います。
商用利用の可否はQwenのライセンスを確認してください。
