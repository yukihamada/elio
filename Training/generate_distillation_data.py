#!/usr/bin/env python3
"""
Knowledge Distillation Data Generator
======================================

Generates ~1,500 training examples by distilling from Claude/GPT-4o.
Uses the teacher model's Japanese thinking + high-quality responses.

Requirements:
    pip install openai anthropic

Usage:
    # Using Claude (default)
    ANTHROPIC_API_KEY=sk-... python generate_distillation_data.py --output distillation_data.json

    # Using OpenAI
    OPENAI_API_KEY=sk-... python generate_distillation_data.py --provider openai --output distillation_data.json

    # Using OpenRouter (any model)
    OPENROUTER_API_KEY=sk-... python generate_distillation_data.py --provider openrouter --output distillation_data.json
"""

import argparse
import json
import os
import sys
import time
import random

# ─── Prompt Categories ───

CATEGORIES = {
    "general_knowledge": {
        "system": "あなたは日本語で考え、丁寧に回答するAIアシスタントです。必ず<think>タグ内で日本語の思考過程を示してから回答してください。",
        "prompts": [
            "量子コンピュータとは何ですか？初心者にも分かるように説明してください。",
            "なぜ日本は地震が多いのですか？",
            "mRNAワクチンの仕組みを説明してください。",
            "ブラックホールに吸い込まれるとどうなりますか？",
            "なぜ人間は夢を見るのですか？",
            "インフレーションとは何ですか？",
            "DNAとRNAの違いは？",
            "なぜ海は青く見えるのですか？",
            "相対性理論を簡単に説明して",
            "免疫システムはどのように機能しますか？",
            "宇宙はどのように始まったのですか？",
            "なぜ季節があるのですか？",
            "原子力発電の仕組みは？",
            "進化論とは何ですか？",
            "温暖化が進むとどうなりますか？",
            "暗号化の仕組みを教えて",
            "5Gと4Gの違いは？",
            "半導体はなぜ重要なのですか？",
            "バッテリー技術の最新動向は？",
            "自動運転のレベル分けを教えて",
        ],
    },
    "coding": {
        "system": "あなたはプログラミングに精通したAIアシスタントです。必ず<think>タグ内で日本語の思考過程を示し、コードと説明を提供してください。",
        "prompts": [
            "Pythonでバブルソートを実装して",
            "Swiftでシングルトンパターンの実装方法",
            "Rustの所有権システムを説明して",
            "JavaScriptのPromiseとasync/awaitの違い",
            "SQLでJOINの種類と使い方",
            "Gitのrebaseとmergeの使い分け",
            "DockerとKubernetesの違い",
            "RESTとGraphQLの比較",
            "TypeScriptのジェネリクスの使い方",
            "Pythonでデコレータを作る方法",
            "再帰関数とは？具体例を示して",
            "ハッシュマップの仕組みを説明して",
            "二分探索を実装して",
            "HTMLとCSSでレスポンシブデザインを作る基本",
            "WebSocketとHTTPの違い",
            "Pythonのリスト内包表記の使い方",
            "Goのgoroutineとチャネルの使い方",
            "テスト駆動開発（TDD）とは？",
            "CIとCDの違いを説明して",
            "マイクロサービスアーキテクチャとは？",
        ],
    },
    "math": {
        "system": "あなたは数学に強いAIアシスタントです。必ず<think>タグ内で日本語の思考過程を示し、ステップバイステップで解説してください。",
        "prompts": [
            "x² + 5x + 6 = 0 を解いて",
            "1から1000までの3の倍数の合計は？",
            "確率：サイコロを2つ振って合計が7になる確率",
            "微分：f(x) = 3x³ + 2x² - 5x + 1 を微分して",
            "積分：∫(2x + 3)dx を計算して",
            "行列の掛け算の方法を説明して",
            "統計：平均、中央値、最頻値の違い",
            "三角関数のsin, cos, tanの関係",
            "対数とは何ですか？",
            "順列と組み合わせの違い",
            "ピタゴラスの定理を証明して",
            "等差数列の和の公式を導出して",
            "ベクトルの内積と外積の違い",
            "標準偏差の計算方法",
            "フーリエ変換とは何ですか？",
        ],
    },
    "japanese_culture": {
        "system": "あなたは日本文化に詳しいAIアシスタントです。必ず<think>タグ内で日本語の思考過程を示してから回答してください。",
        "prompts": [
            "茶道の基本的な作法を教えて",
            "俳句のルールと名句を紹介して",
            "日本の四季の行事を教えて",
            "武士道の精神とは？",
            "日本の伝統的な建築様式について",
            "和食がユネスコ無形文化遺産に登録された理由",
            "歌舞伎と能の違い",
            "日本の祭りの種類と特徴",
            "書道の基本を教えて",
            "着物の種類と着こなし",
            "日本庭園の設計思想",
            "禅の考え方を説明して",
            "日本の年中行事について教えて",
            "落語とは何ですか？",
            "日本の方言の特徴を教えて",
        ],
    },
    "daily_life": {
        "system": "あなたは生活に役立つアドバイスをする日本語AIアシスタントです。必ず<think>タグ内で日本語の思考過程を示してから回答してください。",
        "prompts": [
            "効率的な勉強法を教えて",
            "一人暮らしの節約術",
            "健康的な食生活のコツ",
            "睡眠の質を上げる方法",
            "ストレス解消法を教えて",
            "時間管理のコツ",
            "引っ越しの手順を教えて",
            "確定申告の基本的な流れ",
            "面接で好印象を与えるコツ",
            "プレゼンテーションのコツ",
            "メールの書き方のマナー",
            "冠婚葬祭のマナー",
            "旅行の計画の立て方",
            "自己啓発におすすめの方法",
            "副業を始めるためのアドバイス",
        ],
    },
    "creative": {
        "system": "あなたは創造性豊かなAIアシスタントです。必ず<think>タグ内で日本語の思考過程を示してから、クリエイティブな回答をしてください。",
        "prompts": [
            "春をテーマに短い詩を書いて",
            "猫が主人公の短いお話を作って",
            "SF風の短編ストーリーのあらすじ",
            "面白いなぞなぞを3つ作って",
            "未来の東京についての描写",
            "ファンタジー世界の設定を考えて",
            "桜をテーマにした俳句を3つ",
            "ミステリー小説のあらすじを考えて",
            "AIと人間の友情をテーマにした話",
            "日本の昔話風の新しいお話",
        ],
    },
}


def call_anthropic(system: str, prompt: str, api_key: str) -> str | None:
    """Call Claude API."""
    try:
        import anthropic

        client = anthropic.Anthropic(api_key=api_key)
        response = client.messages.create(
            model="claude-sonnet-4-5-20250929",
            max_tokens=2048,
            system=system,
            messages=[{"role": "user", "content": prompt}],
        )
        return response.content[0].text
    except Exception as e:
        print(f"  Error: {e}")
        return None


def call_openai(system: str, prompt: str, api_key: str, base_url: str | None = None, model: str = "gpt-4o") -> str | None:
    """Call OpenAI-compatible API."""
    try:
        from openai import OpenAI

        client = OpenAI(api_key=api_key, base_url=base_url)
        response = client.chat.completions.create(
            model=model,
            max_tokens=2048,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
        )
        return response.choices[0].message.content
    except Exception as e:
        print(f"  Error: {e}")
        return None


def ensure_think_tags(text: str) -> str:
    """Ensure the response has proper <think> tags."""
    if "<think>" not in text:
        # Wrap the first paragraph as thinking
        lines = text.split("\n\n", 1)
        if len(lines) == 2:
            return f"<think>\n{lines[0]}\n</think>\n\n{lines[1]}"
        return f"<think>\nこの質問について考える。\n</think>\n\n{text}"
    return text


def generate_data(args):
    """Generate distillation data from teacher model."""
    all_data = []
    total_prompts = sum(len(cat["prompts"]) for cat in CATEGORIES.values())
    repeats = max(1, args.target_count // total_prompts)

    print(f"Total prompts: {total_prompts}, repeats: {repeats}")
    print(f"Provider: {args.provider}")

    call_fn = None
    if args.provider == "anthropic":
        api_key = args.api_key or os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            print("Error: ANTHROPIC_API_KEY not set")
            sys.exit(1)
        call_fn = lambda sys, prompt: call_anthropic(sys, prompt, api_key)
    elif args.provider == "openai":
        api_key = args.api_key or os.environ.get("OPENAI_API_KEY")
        if not api_key:
            print("Error: OPENAI_API_KEY not set")
            sys.exit(1)
        call_fn = lambda sys, prompt: call_openai(sys, prompt, api_key)
    elif args.provider == "openrouter":
        api_key = args.api_key or os.environ.get("OPENROUTER_API_KEY")
        if not api_key:
            print("Error: OPENROUTER_API_KEY not set")
            sys.exit(1)
        call_fn = lambda sys, prompt: call_openai(
            sys, prompt, api_key,
            base_url="https://openrouter.ai/api/v1",
            model=args.model or "anthropic/claude-sonnet-4-5-20250929",
        )

    idx = 0
    for repeat in range(repeats):
        for cat_name, cat_info in CATEGORIES.items():
            for prompt in cat_info["prompts"]:
                idx += 1
                print(f"[{idx}/{total_prompts * repeats}] {cat_name}: {prompt[:40]}...")

                # Add variation for repeated prompts
                actual_prompt = prompt
                if repeat > 0:
                    variations = [
                        f"{prompt}（簡潔に）",
                        f"{prompt}（詳しく）",
                        f"{prompt}（例を交えて）",
                        f"初心者向けに説明してください：{prompt}",
                    ]
                    actual_prompt = variations[repeat % len(variations)]

                response = call_fn(cat_info["system"], actual_prompt)
                if response:
                    response = ensure_think_tags(response)
                    all_data.append({
                        "conversations": [
                            {"role": "user", "content": actual_prompt},
                            {"role": "assistant", "content": response},
                        ],
                        "category": cat_name,
                    })

                # Rate limiting
                time.sleep(args.delay)

                if len(all_data) >= args.target_count:
                    break
            if len(all_data) >= args.target_count:
                break
        if len(all_data) >= args.target_count:
            break

    return all_data


def generate_offline_data() -> list:
    """Generate offline data without API calls (template-based)."""
    all_data = []

    # Use the existing training_data.json format as reference
    template_responses = {
        "general_knowledge": [
            ("量子コンピュータとは何ですか？初心者にも分かるように説明してください。",
             "<think>\n量子コンピュータについて初心者向けに説明する必要がある。従来のコンピュータとの違いを中心に、量子ビット、重ね合わせ、量子もつれの概念を分かりやすく伝えよう。\n</think>\n\n**量子コンピュータ**は、量子力学の原理を使った次世代のコンピュータです。\n\n**従来のコンピュータとの違い**\n- 従来：0か1の「ビット」で計算\n- 量子：0と1を同時に持てる「量子ビット（キュービット）」で計算\n\n**分かりやすい例え**\n迷路を解くとき：\n- 従来のPC → 1つずつ道を試す\n- 量子PC → 全ての道を同時に試す\n\n**得意なこと**\n- 暗号解読\n- 新薬開発のシミュレーション\n- 最適化問題\n\nまだ発展途上ですが、将来的に社会を大きく変える可能性のある技術です。"),
            ("なぜ日本は地震が多いのですか？",
             "<think>\n日本で地震が多い理由を説明する。プレートテクトニクス、太平洋プレート、フィリピン海プレート、ユーラシアプレート、北米プレートの4つが関わっている。環太平洋火山帯に位置していることも重要。\n</think>\n\n日本で地震が多いのは、**4つのプレートが交わる位置**にあるからです。\n\n**4つのプレート**\n1. 太平洋プレート\n2. フィリピン海プレート\n3. ユーラシアプレート\n4. 北米プレート\n\n**仕組み**\n- プレート同士がぶつかり、沈み込む\n- 蓄積されたエネルギーが一気に解放 → 地震\n\n日本は「環太平洋火山帯（リング・オブ・ファイア）」上にあり、世界の地震の約10%が日本周辺で発生しています。"),
        ],
        "coding": [
            ("Pythonでバブルソートを実装して",
             "<think>\nバブルソートの実装を求められている。隣り合う要素を比較して交換する最も基本的なソートアルゴリズム。時間計算量はO(n²)。最適化として、交換が発生しなかったら早期終了するフラグを追加する。\n</think>\n\nバブルソートの実装です：\n\n```python\ndef bubble_sort(arr):\n    n = len(arr)\n    for i in range(n):\n        swapped = False\n        for j in range(0, n - i - 1):\n            if arr[j] > arr[j + 1]:\n                arr[j], arr[j + 1] = arr[j + 1], arr[j]\n                swapped = True\n        if not swapped:\n            break  # 交換なし = ソート完了\n    return arr\n\n# 使用例\ndata = [64, 34, 25, 12, 22, 11, 90]\nprint(bubble_sort(data))  # [11, 12, 22, 25, 34, 64, 90]\n```\n\n**特徴**\n- 時間計算量: O(n²)\n- 空間計算量: O(1)\n- 安定ソート\n- 小さなデータに適している"),
        ],
        "math": [
            ("x² + 5x + 6 = 0 を解いて",
             "<think>\n二次方程式 x² + 5x + 6 = 0 を解く。因数分解を試みる。6 = 2×3 で、2+3=5 なので (x+2)(x+3)=0 と因数分解できる。\n</think>\n\n**x² + 5x + 6 = 0** を因数分解で解きます。\n\n**解法**\n1. 掛けて6、足して5になる2つの数を探す\n2. 2 × 3 = 6, 2 + 3 = 5 → 見つかった！\n3. (x + 2)(x + 3) = 0\n4. x + 2 = 0 または x + 3 = 0\n\n**答え: x = -2, x = -3**"),
        ],
    }

    for cat_name, examples in template_responses.items():
        for prompt, response in examples:
            all_data.append({
                "conversations": [
                    {"role": "user", "content": prompt},
                    {"role": "assistant", "content": response},
                ],
                "category": cat_name,
            })

    return all_data


def main():
    parser = argparse.ArgumentParser(description="Generate distillation training data")
    parser.add_argument("--output", type=str, default="distillation_data.json")
    parser.add_argument("--provider", type=str, default="anthropic", choices=["anthropic", "openai", "openrouter", "offline"])
    parser.add_argument("--api_key", type=str, default=None)
    parser.add_argument("--model", type=str, default=None, help="Model name (for OpenRouter)")
    parser.add_argument("--target_count", type=int, default=1500, help="Target number of examples")
    parser.add_argument("--delay", type=float, default=0.5, help="Delay between API calls (seconds)")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    random.seed(args.seed)

    if args.provider == "offline":
        print("Generating offline template data...")
        data = generate_offline_data()
    else:
        data = generate_data(args)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    # Stats
    cat_counts = {}
    for item in data:
        cat = item.get("category", "unknown")
        cat_counts[cat] = cat_counts.get(cat, 0) + 1

    print(f"\nGenerated {len(data)} examples:")
    for cat, count in sorted(cat_counts.items()):
        print(f"  {cat}: {count}")
    print(f"\nSaved to: {output_path}")


if __name__ == "__main__":
    main()
