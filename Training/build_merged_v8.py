#!/usr/bin/env python3
"""
build_merged_v8.py — 全データ統合 (persona_variants + recovery を追加)
"""
import json, os, re, random, hashlib, argparse
from collections import Counter

random.seed(42)
TRAINING_DIR = os.path.dirname(os.path.abspath(__file__))

TEMPLATE_THINKS = [
    "ニュース記事が取得できた",
    "情報を整理して",
    "ユーザーの質問に答える",
    "適切な回答をする",
    "考えてみる",
]

SOURCES = [
    # (ファイル名, タグ, 優先度, 最大件数)
    ("distilled_full.json",          "distilled",      1, 2500),
    ("clean_rewritten.json",         "clean_rewrit",   2, 1000),
    ("highquality_data.json",        "highquality",    2,  234),
    ("new_categories_data.json",     "new_cats",       2,  304),
    ("chatweb_enabler_data.json",    "chatweb_enabl",  3,   40),
    ("elio_tools_rewritten.json",    "elio_tools",     3,  150),
    ("tool_coverage_rewritten.json", "tool_coverage",  3,  181),
    ("multiturn_rewritten.json",     "multiturn",      3,   87),
    ("persona_variants.json",        "persona",        3, 6500),
    ("recovery_multiturn_rewritten.json", "recovery",   2,  400),
    ("onboarding_data.json",         "onboarding",     1,  500),  # 挨拶・自己紹介・課金誘導・ツール説明
]

def get_think_len(item):
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
            if t: return len(t.group(1))
    return 0

def get_response_len(item):
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            c = m.get("content","")
            return len(re.sub(r"<think>.*?</think>","",c,flags=re.DOTALL).strip())
    return 0

def is_template(item):
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
            if t:
                think = t.group(1).strip()
                for p in TEMPLATE_THINKS:
                    if think.startswith(p) and len(think) < 100:
                        return True
    return False

def dapo_filter(item):
    tl = get_think_len(item)
    rl = get_response_len(item)
    if tl < 80: return False, f"think<80({tl}字)"
    if tl > 2500: return False, f"think>2500({tl}字)"
    if rl < 30: return False, f"response<30({rl}字)"
    if is_template(item): return False, "template"
    return True, "OK"

def item_hash(item, tag=""):
    user_msgs = " ".join(m.get("content","")[:120] for m in item.get("conversations",[]) if m.get("role")=="user")
    # persona variants: 同じ質問でも回答スタイルが異なる → システムプロンプト or 回答冒頭も含める
    if tag == "persona":
        asst_msgs = " ".join(m.get("content","")[:60] for m in item.get("conversations",[]) if m.get("role")=="assistant")
        sys_msgs  = " ".join(m.get("content","")[:60] for m in item.get("conversations",[]) if m.get("role")=="system")
        key = user_msgs + "|" + asst_msgs + "|" + sys_msgs
    else:
        key = user_msgs
    return hashlib.md5(key.encode()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",      default="merged_v8.json")
    parser.add_argument("--eval-output", default="eval_v8.json")
    parser.add_argument("--eval-ratio",  type=float, default=0.05)
    args = parser.parse_args()

    all_items = []
    seen = set()
    src_counts = Counter()
    filter_counts = Counter()

    print("=== merged_v8 ビルド ===\n")

    for filename, tag, priority, max_items in SOURCES:
        path = os.path.join(TRAINING_DIR, filename)
        if not os.path.exists(path):
            print(f"  [SKIP] {filename}")
            continue
        data = json.load(open(path, encoding="utf-8"))
        data.sort(key=get_think_len, reverse=True)
        data = data[:max_items]

        added = dup = dapo = 0
        for item in data:
            h = item_hash(item, tag)
            if h in seen:
                dup += 1; filter_counts["dup"] += 1; continue
            ok, reason = dapo_filter(item)
            if not ok:
                dapo += 1; filter_counts[reason] += 1; continue
            item["_src"] = tag
            item["_pri"] = priority
            all_items.append(item)
            seen.add(h)
            src_counts[tag] += 1
            added += 1

        added_items = [i for i in all_items if i.get("_src")==tag]
        tl = sorted([get_think_len(i) for i in added_items])
        med = tl[len(tl)//2] if tl else 0
        print(f"  {filename:<40}: {len(data)}→{added}件 (dup:{dup} dapo:{dapo}) think中央値:{med}字")

    print(f"\nDAPO除外内訳:")
    for r, c in sorted(filter_counts.items(), key=lambda x:-x[1])[:8]:
        print(f"  {r}: {c}件")

    all_items.sort(key=lambda x: (x["_pri"], random.random()))
    random.shuffle(all_items)
    eval_n = max(150, int(len(all_items) * args.eval_ratio))
    eval_items  = all_items[:eval_n]
    train_items = all_items[eval_n:]

    def clean(items):
        return [{k:v for k,v in i.items() if not k.startswith("_")} for i in items]

    train_path = os.path.join(TRAINING_DIR, args.output)
    eval_path  = os.path.join(TRAINING_DIR, args.eval_output)

    with open(train_path, "w", encoding="utf-8") as f:
        json.dump(clean(train_items), f, ensure_ascii=False)
    with open(eval_path, "w", encoding="utf-8") as f:
        json.dump(clean(eval_items), f, ensure_ascii=False)

    all_tl = sorted([get_think_len(i) for i in all_items])
    med = all_tl[len(all_tl)//2] if all_tl else 0
    pct400 = 100 * sum(1 for x in all_tl if x>=400) // max(len(all_tl),1)

    print(f"\n=== 完了 ===")
    print(f"合計: {len(all_items)}件 (train:{len(train_items)} eval:{len(eval_items)})")
    print(f"think中央値: {med}字 | 400+字: {pct400}%")
    print(f"\nソース内訳:")
    for t, c in sorted(src_counts.items(), key=lambda x:-x[1]):
        print(f"  {t}: {c}件")
    print(f"\n→ {train_path}")
    print(f"→ {eval_path}")

if __name__ == "__main__":
    main()
