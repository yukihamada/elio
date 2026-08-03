#!/usr/bin/env python3
"""
build_merged_v7.py — 全データマージ + DAPO Dynamic Sampling
============================================================
論文: DAPO (arxiv 2503.14476) — Dynamic Sampling
  「全問正解 or 全問不正解になるプロンプトを除外して学習効率を上げる」
  SFT では: think が空/テンプレ/極端に短いもの = "trivially wrong"
           think が長くて多様なもの = "learnable"

マージ戦略:
  Priority 1 (think 900+字): distilled_full    ← 最高品質
  Priority 2 (think 500+字): clean_rewritten, highquality_data, new_categories
  Priority 3 (think 300+字): chatweb_enabler, elio_tools_rewritten, tool_coverage_rewritten
  Priority 4 (think 200+字): multiturn_rewritten (+ long_multiturn_v2の残り)

DAPO フィルタ:
  - think < 80字 → 除外 (trivially wrong)
  - think > 2000字 → 除外 (overlong penalty)
  - 回答が50字未満 → 除外
  - テンプレ思考パターン → 除外
"""
import json, os, re, random, hashlib, argparse
from collections import Counter

random.seed(42)

TRAINING_DIR = os.path.dirname(os.path.abspath(__file__))

# テンプレ思考パターン (DAPO: trivially wrong examples)
TEMPLATE_THINKS = [
    "ニュース記事が取得できた",
    "情報を整理して",
    "ユーザーの質問に答える",
    "適切な回答をする",
    "考えてみる",
]

# データソース定義 (優先度順)
SOURCES = [
    # (ファイル名, カテゴリタグ, 優先度, 最大件数)
    ("distilled_full.json",          "distilled",      1, 2000),
    ("clean_rewritten.json",         "clean_rewrit",   2, 1000),
    ("highquality_data.json",        "highquality",    2,  234),
    ("new_categories_data.json",     "new_cats",       2,  304),
    ("chatweb_enabler_data.json",    "chatweb_enabl",  3,   40),
    ("elio_tools_rewritten.json",    "elio_tools",     3,  150),
    ("tool_coverage_rewritten.json", "tool_coverage",  3,  181),
    ("multiturn_rewritten.json",     "multiturn",      4,   87),
]


def get_think_len(item: dict) -> int:
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
            if t:
                return len(t.group(1))
    return 0


def get_response_len(item: dict) -> int:
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            content = m.get("content", "")
            return len(re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip())
    return 0


def is_template_think(item: dict) -> bool:
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
            if t:
                think = t.group(1).strip()
                for pattern in TEMPLATE_THINKS:
                    if think.startswith(pattern) and len(think) < 100:
                        return True
    return False


def dapo_filter(item: dict) -> tuple[bool, str]:
    """DAPO Dynamic Sampling フィルタ。(通過, 理由) を返す"""
    think_len = get_think_len(item)
    response_len = get_response_len(item)

    if think_len < 80:
        return False, f"think短すぎ({think_len}字)"
    if think_len > 2500:
        return False, f"think長すぎ({think_len}字)"
    if response_len < 30:
        return False, f"回答短すぎ({response_len}字)"
    if is_template_think(item):
        return False, "テンプレthink"

    return True, "OK"


def item_hash(item: dict) -> str:
    convs = item.get("conversations", [])
    user_msgs = " ".join(
        m.get("content","")[:120]
        for m in convs if m.get("role") == "user"
    )
    return hashlib.md5(user_msgs.encode()).hexdigest()


def load_source(filename: str, max_items: int) -> list:
    path = os.path.join(TRAINING_DIR, filename)
    if not os.path.exists(path):
        print(f"  [SKIP] {filename} — ファイルなし")
        return []
    data = json.load(open(path, encoding="utf-8"))
    # think 長い順にソート
    data.sort(key=get_think_len, reverse=True)
    return data[:max_items]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="merged_v7.json")
    parser.add_argument("--eval-output", default="eval_v7.json")
    parser.add_argument("--eval-ratio", type=float, default=0.05)
    parser.add_argument("--target", type=int, default=4000,
                        help="目標件数 (0=制限なし)")
    args = parser.parse_args()

    all_items = []
    seen_hashes = set()
    source_counts = Counter()
    filter_counts = Counter()

    print("=== merged_v7 ビルド ===")
    print(f"DAPO Dynamic Sampling: think<80字, >2500字, 回答<30字, テンプレ → 除外\n")

    for filename, tag, priority, max_items in SOURCES:
        items = load_source(filename, max_items)
        added = skipped_dup = skipped_dapo = 0

        for item in items:
            h = item_hash(item)
            if h in seen_hashes:
                skipped_dup += 1
                filter_counts["duplicate"] += 1
                continue

            ok, reason = dapo_filter(item)
            if not ok:
                skipped_dapo += 1
                filter_counts[reason] += 1
                continue

            # ソース情報付与
            item["_source"] = tag
            item["_priority"] = priority
            all_items.append(item)
            seen_hashes.add(h)
            source_counts[tag] += 1
            added += 1

        tl = [get_think_len(item) for item in all_items if item.get("_source") == tag]
        med = sorted(tl)[len(tl)//2] if tl else 0
        print(f"  {filename}: {len(items)}件入力 → {added}件採用 "
              f"(重複{skipped_dup} DAPO除外{skipped_dapo}) think中央値:{med}字")

    print(f"\nDAPO除外理由内訳:")
    for reason, count in sorted(filter_counts.items(), key=lambda x: -x[1]):
        print(f"  {reason}: {count}件")

    # 優先度でシャッフル (同一優先度内はランダム)
    all_items.sort(key=lambda x: (x["_priority"], random.random()))

    if args.target > 0:
        all_items = all_items[:args.target]

    # eval/train 分割
    random.shuffle(all_items)
    eval_n = max(100, int(len(all_items) * args.eval_ratio))
    eval_items  = all_items[:eval_n]
    train_items = all_items[eval_n:]

    # _source/_priority を除いてクリーンに保存
    def clean(items):
        result = []
        for item in items:
            c = {k: v for k, v in item.items() if not k.startswith("_")}
            result.append(c)
        return result

    train_path = os.path.join(TRAINING_DIR, args.output)
    eval_path  = os.path.join(TRAINING_DIR, args.eval_output)

    with open(train_path, "w", encoding="utf-8") as f:
        json.dump(clean(train_items), f, ensure_ascii=False)
    with open(eval_path, "w", encoding="utf-8") as f:
        json.dump(clean(eval_items), f, ensure_ascii=False)

    # 最終統計
    all_think_lens = sorted([get_think_len(i) for i in all_items])
    med = all_think_lens[len(all_think_lens)//2] if all_think_lens else 0
    pct400 = 100 * sum(1 for x in all_think_lens if x >= 400) // max(len(all_think_lens), 1)

    print(f"\n=== 完了 ===")
    print(f"合計: {len(all_items)}件 (train:{len(train_items)} eval:{len(eval_items)})")
    print(f"think中央値: {med}字 | 400+字: {pct400}%")
    print(f"\nソース内訳:")
    for tag, count in sorted(source_counts.items(), key=lambda x: -x[1]):
        print(f"  {tag}: {count}件")
    print(f"\n→ {train_path}")
    print(f"→ {eval_path}")


if __name__ == "__main__":
    main()
