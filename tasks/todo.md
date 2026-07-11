# Pure Swift + Metal LLM Inference Engine

## 概要
llama.cpp (C/C++) への依存を排除し、純粋な Swift + Metal で Qwen3-0.6B (Q4_K GGUF) の推論エンジンを実装する。
既存の `LlamaInference.swift` と同じインターフェースを持つ `SwiftInference.swift` として実装し、段階的に置換する。

## 調査結果

### 関連ファイル
- `LocalAIAgent/LLM/LlamaInference.swift` — 現行推論エンジン (llama.cpp wrapper, 800行)
- `LocalAIAgent/LLM/MLXInference.swift` — MLX Swift wrapper (200行, 参考インターフェース)
- `LocalAIAgent/LLM/CoreMLInference.swift` — 統合マネージャ (GGUF/MLX/CoreML を切り替え)
- `LocalAIAgent/LLM/Tokenizer.swift` — 既存トークナイザー (簡易BPE, 本番では llama.cpp 側を使用)
- `LocalAIAgent/LLM/StreamingDecoder.swift` — UTF-8 ストリーミングデコーダー (再利用可能)
- `LocalAIAgent/Models/ModelSettings.swift` — 生成パラメータ (temperature, topP, topK 等)
- `LocalAIAgent/Models/Message.swift` — メッセージモデル (role, content)
- `Frameworks/llama.xcframework` — 現行の C/C++ バイナリ依存 (削除対象)

### 対象モデル: Qwen3-0.6B Q4_K
- Layers: 28, Embedding: 1024, Heads: 16, KV Heads: 8 (GQA)
- FFN: 3072 (SwiGLU → intermediate = 3072, gate + up = 3072 each)
- RoPE theta: 1000000, RMSNorm eps: 1e-6
- Vocab: 151936 (BPE), EOS: 151645, BOS: 151643
- Q4_K quantization: 4-bit with per-block scales (block size 32)
- Model size: ~400MB GGUF

### 既存パターン
- `@MainActor final class` + `ObservableObject` パターン
- `isLoaded` / `isGenerating` / `loadingProgress` の Published プロパティ
- `generate()` は `onToken: @escaping @MainActor (String) -> Void` コールバック
- 推論ループは `DispatchQueue` バックグラウンドで実行、UI dispatch は4トークンごとバッチ
- `formatChatPrompt()` で ChatML テンプレート構築

### 技術的注意点
- Metal shader は `.metal` ファイルとして追加し、Xcode ビルドで自動コンパイル
- Q4_K dequantization は Metal compute shader で実装 (CPU fallback も用意)
- GGUF パーサーは仕様が公開済み (https://github.com/ggml-org/ggml/blob/master/docs/gguf.md)
- BPE トークナイザーは GGUF 内の vocab + merges から構築
- iPhone のメモリ制約: 0.6B Q4_K ≈ 400MB → 4GB デバイスでも動作可能

---

## 実装ステップ

### Phase 1: 基盤 — GGUF Parser + Tokenizer (推定: 中)

- [ ] **Step 1.1**: `LocalAIAgent/LLM/SwiftLLM/GGUFParser.swift` — GGUF バイナリパーサー
  - マジックナンバー検証 (`GGUF` = 0x46475547)
  - ヘッダー読み取り (version, tensor_count, metadata_kv_count)
  - メタデータ KV パース (string, uint32, float32, array 等)
  - テンソルインフォ読み取り (name, n_dims, dims, type, offset)
  - mmap によるテンソルデータアクセス (ゼロコピー)
  - Q4_K / Q8_0 / F16 / F32 の型定義

- [ ] **Step 1.2**: `LocalAIAgent/LLM/SwiftLLM/BPETokenizer.swift` — BPE トークナイザー
  - GGUF メタデータから vocab (token -> id) と merges をロード
  - `tokenizer.ggml.tokens`, `tokenizer.ggml.scores`, `tokenizer.ggml.merges` キーから構築
  - Pre-tokenization: UTF-8 bytes → base tokens
  - BPE merge ループ (priority queue ベース)
  - Special token handling (`<|im_start|>`, `<|im_end|>`, `<|endoftext|>`)
  - `encode(String) -> [Int32]` / `decode([Int32]) -> String`

- [ ] **Step 1.3**: テスト — `LocalAIAgentTests/SwiftLLMTests/GGUFParserTests.swift`
  - 小さなテスト用 GGUF ヘッダーのバイナリ手動構築 → パース検証
  - メタデータ型の全パターンテスト
  - BPE encode/decode ラウンドトリップテスト

### Phase 2: Transformer — CPU 実装 (推定: 大)

- [ ] **Step 2.1**: `LocalAIAgent/LLM/SwiftLLM/Tensor.swift` — テンソル型
  - `Tensor` struct: shape, strides, data (UnsafeBufferPointer<Float>)
  - 基本操作: reshape, transpose, contiguous
  - Accelerate.framework 連携 (vDSP, BLAS)

- [ ] **Step 2.2**: `LocalAIAgent/LLM/SwiftLLM/Dequantize.swift` — 量子化解除
  - Q4_K block 構造体 (d: Float16, dmin: Float16, scales: [12]UInt8, qs: [128]UInt8)
  - Q4_K → Float32 dequantize (Accelerate 使用)
  - Q8_0 → Float32 dequantize
  - F16 → Float32 変換

- [ ] **Step 2.3**: `LocalAIAgent/LLM/SwiftLLM/Transformer.swift` — Transformer 推論
  - `QwenConfig` struct (GGUF メタデータから構築)
  - `TransformerWeights` struct (GGUF テンソルマッピング)
  - `RMSNorm(x, weight, eps)` — vDSP で高速化
  - `RoPE(q, k, positions, theta)` — 回転位置エンコーディング
  - `Attention(q, k, v, mask)` — GQA (16 heads, 8 KV heads)
  - `SwiGLU(gate, up)` — gate * silu(up)
  - `TransformerBlock.forward(x, pos, kvCache)` — 1レイヤー分
  - `Transformer.forward(tokens, pos) -> logits` — 全28レイヤー
  - KV Cache 管理 (per-layer, growing buffer)

- [ ] **Step 2.4**: テスト — `LocalAIAgentTests/SwiftLLMTests/TransformerTests.swift`
  - RMSNorm の数値検証 (既知入力 → 期待出力)
  - RoPE の回転角度検証
  - Attention の mask 適用検証
  - SwiGLU の活性化検証
  - 単一レイヤー forward の shape 検証

### Phase 3: Metal GPU アクセラレーション (推定: 大)

- [ ] **Step 3.1**: `LocalAIAgent/LLM/SwiftLLM/MetalShaders.metal` — Metal compute shaders
  - `dequantize_q4_k` — Q4_K → Float threadgroup 単位
  - `matmul_f32` — 汎用行列乗算 (tilegroup shared memory)
  - `matmul_q4k_f32` — 量子化行列 x Float ベクトル (fused dequant + matmul)
  - `rms_norm` — RMSNorm kernel
  - `rope_rotary` — RoPE kernel
  - `attention_scores` — QK^T / sqrt(d) + mask
  - `attention_softmax` — 行ごと softmax
  - `attention_output` — softmax(scores) @ V
  - `silu_elementwise` — SiLU 活性化
  - `elementwise_mul` — gate * up

- [ ] **Step 3.2**: `LocalAIAgent/LLM/SwiftLLM/MetalEngine.swift` — Metal 計算エンジン
  - `MTLDevice` / `MTLCommandQueue` 管理
  - Pipeline State キャッシュ (shader 名 → MTLComputePipelineState)
  - Metal Buffer プール (再利用で alloc 削減)
  - `metalMatmul(A, B, M, N, K)` — GPU matmul dispatch
  - `metalDequantize(quantized, output, type, count)` — GPU dequant dispatch
  - テンソルの CPU ↔ GPU 転送最小化 (weights は GPU 常駐)

- [ ] **Step 3.3**: `LocalAIAgent/LLM/SwiftLLM/Transformer.swift` 更新 — Metal パス統合
  - CPU / GPU 自動切替 (Metal 利用可能時は GPU パス)
  - Weights を MTLBuffer として mmap → GPU に常駐
  - KV Cache を MTLBuffer で管理
  - Forward pass 全体を Metal command buffer で実行

- [ ] **Step 3.4**: テスト — CPU vs Metal 出力一致検証
  - 同一入力で CPU / Metal forward → logits 比較 (tolerance 1e-3)
  - matmul 精度テスト (小行列で exact 検証)
  - dequantize 精度テスト (Q4_K block 手動計算と比較)

### Phase 4: Sampling + 統合 (推定: 中)

- [ ] **Step 4.1**: `LocalAIAgent/LLM/SwiftLLM/Sampler.swift` — サンプリング
  - Temperature scaling
  - Top-K filtering
  - Top-P (nucleus) sampling
  - Min-P filtering
  - Repetition penalty
  - Greedy (temperature ≈ 0)
  - `sample(logits: [Float], settings: ModelSettings) -> Int32`

- [ ] **Step 4.2**: `LocalAIAgent/LLM/SwiftInference.swift` — 統合推論クラス
  - `@MainActor final class SwiftInference: ObservableObject`
  - `LlamaInference` と同一の Published プロパティ
  - `loadModel(from: URL)` — GGUF parse → weights load → Metal setup
  - `generate(prompt:settings:stopSequences:onToken:)` — 既存インターフェース準拠
  - `formatChatPrompt(messages:systemPrompt:enableThinking:)` — ChatML
  - `unload()` — Metal buffer 解放 + メモリクリア
  - `CoreMLInference.swift` に SwiftInference バックエンド追加

- [ ] **Step 4.3**: テスト — End-to-End 推論テスト
  - Qwen3-0.6B GGUF ロード → "Hello" プロンプト → トークン生成確認
  - ストリーミング出力の UTF-8 整合性
  - EOS トークン検出による停止
  - Stop sequence による停止
  - メモリリーク検証 (Instruments)

### Phase 5: 精度検証 + パフォーマンス最適化 (推定: 中)

- [ ] **Step 5.1**: 精度検証
  - llama.cpp 出力との比較 (同一プロンプト、temperature=0 で deterministic)
  - 最初の 100 トークンの完全一致検証
  - Perplexity 測定 (WikiText-2 サブセット)
  - 日本語出力品質の定性評価

- [ ] **Step 5.2**: パフォーマンス最適化
  - **Prompt processing (prefill)**: バッチ matmul でトークン並列処理
  - **Token generation (decode)**: 1トークンずつだが matmul を Metal で高速化
  - **KV Cache**: Q8_0 量子化 KV Cache (メモリ帯域削減)
  - **Weight loading**: mmap + MTLBuffer.makeBuffer(bytesNoCopy:) でゼロコピー GPU 転送
  - **Flash Attention**: Metal shader で fused attention (メモリ帯域最適)
  - **Speculative decoding**: 将来的な拡張ポイント (2モデル必要なので後回し)

- [ ] **Step 5.3**: ベンチマーク
  - Prefill speed: tokens/sec (prompt 処理)
  - Decode speed: tokens/sec (生成)
  - Memory footprint: peak RSS
  - Time to first token (TTFT)
  - llama.cpp Metal vs SwiftInference Metal の比較表作成
  - デバイス別ベンチマーク (iPhone 15 Pro / iPhone 16 / Mac)

---

## ファイル配置

```
LocalAIAgent/LLM/
├── SwiftLLM/                          # 新規ディレクトリ
│   ├── GGUFParser.swift               # GGUF バイナリパーサー
│   ├── BPETokenizer.swift             # BPE トークナイザー
│   ├── Tensor.swift                   # テンソル型 + Accelerate ops
│   ├── Dequantize.swift               # Q4_K/Q8_0 dequantization
│   ├── Transformer.swift              # Qwen3 Transformer 実装
│   ├── MetalEngine.swift              # Metal compute 管理
│   ├── MetalShaders.metal             # GPU compute shaders
│   └── Sampler.swift                  # Token sampling
├── SwiftInference.swift               # 統合推論クラス (既存と同一 IF)
├── LlamaInference.swift               # 既存 (Phase 5 完了後に deprecate)
├── MLXInference.swift                 # 既存
├── CoreMLInference.swift              # 既存 (SwiftInference 追加)
├── Tokenizer.swift                    # 既存 (SwiftLLM 版に段階的移行)
└── StreamingDecoder.swift             # 既存 (再利用)

LocalAIAgentTests/
├── SwiftLLMTests/                     # 新規テストディレクトリ
│   ├── GGUFParserTests.swift
│   ├── BPETokenizerTests.swift
│   ├── TransformerTests.swift
│   ├── MetalEngineTests.swift
│   ├── SamplerTests.swift
│   └── SwiftInferenceTests.swift      # E2E テスト
└── ...既存テスト
```

---

## テスト方針

### ユニットテスト (各Phase完了時)
1. **GGUFParser**: ヘッダーパース、メタデータ型網羅、テンソル情報抽出
2. **BPETokenizer**: encode/decode ラウンドトリップ、special tokens、日本語、空文字列
3. **Transformer ops**: RMSNorm/RoPE/Attention/SwiGLU の数値検証 (tolerance 1e-5)
4. **Metal shaders**: CPU 実装との出力比較 (tolerance 1e-3, float16 精度考慮)
5. **Sampler**: temperature=0 で greedy 一致、top-k/top-p の分布検証
6. **E2E**: GGUF ロード → 推論 → 期待テキスト生成

### 統合テスト
- `CoreMLInference` 経由での SwiftInference バックエンド切替
- ChatML フォーマット → 推論 → ストリーミング出力
- メモリ上限テスト (iOS メモリ警告時の graceful degradation)

### パフォーマンステスト
- `XCTMetric` による tokens/sec 測定
- Instruments でメモリプロファイリング
- llama.cpp とのA/Bベンチマーク

---

## リスク

1. **精度劣化**: Q4_K dequantization の実装ミスで推論品質が低下する可能性
   - 対策: llama.cpp の Q4_K 実装をリファレンスとして逐次検証
2. **Metal shader のデバイス互換性**: A15/A16/A17/A18 で挙動差がある可能性
   - 対策: threadgroup サイズを保守的に設定、デバイス別テスト
3. **パフォーマンス**: llama.cpp は10年以上の最適化があり、初期実装で同等速度は困難
   - 対策: まず正確性を確保し、段階的に Metal 最適化を積む
4. **GGUF 仕様変更**: ggml が GGUF v4 等をリリースした場合の追従
   - 対策: v3 に固定し、必要時のみアップグレード
5. **メモリ**: mmap + Metal buffer の二重確保で OOM リスク
   - 対策: Metal の `makeBuffer(bytesNoCopy:)` でゼロコピー、mmap は read-only

---

## 完了条件

- [ ] Qwen3-0.6B Q4_K GGUF を純 Swift + Metal でロードし推論できる
- [ ] llama.cpp と同一プロンプト (temperature=0) で最初の50トークンが一致
- [ ] Decode speed が llama.cpp Metal の 70% 以上 (iPhone 15 Pro 基準)
- [ ] Prefill speed が llama.cpp Metal の 50% 以上
- [ ] メモリ使用量が llama.cpp の 1.2 倍以内
- [ ] 全ユニットテストが pass
- [ ] `CoreMLInference` から SwiftInference バックエンドとして利用可能
- [ ] `Frameworks/llama.xcframework` を削除してもビルドが通る (最終目標)
