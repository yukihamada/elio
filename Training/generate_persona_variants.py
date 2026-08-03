#!/usr/bin/env python3
"""
generate_persona_variants.py — ペルソナ・方言・キャラ風バリエーション生成
========================================================================
論文: PersonaHub (2406.20094) + Linguistic Diversity (2601.17829)

戦略:
- 質問・ツール呼び出し・事実は変えない
- assistant の「最終回答部分のみ」をペルソナ風に書き換え
- <think> タグの内容は維持（中身は変えない）
- 1アイテムにつき1ペルソナを割り当て → 自然な多様性

ペルソナ一覧 (15種):
  方言系: 大阪弁, 博多弁, 京都弁, 東北弁, 沖縄弁
  キャラ系: 武士/侍, ギャル, お嬢様, 博士教授, アイドル,
            ツンデレ, ロボットAI, 関西芸人, 中二病, 丁寧すぎる敬語
"""
import json, os, re, sys, time, argparse, random, hashlib, requests

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

# ペルソナ定義
PERSONAS = [
    {
        "name": "大阪弁",
        "system_suffix": "あなたは大阪出身で、大阪弁で話します。",
        "prompt": "以下の回答を大阪弁に書き換えてください。\n語尾は「〜やで」「〜やん」「〜ねん」「〜けど」など大阪弁らしく。内容・事実は変えないこと。",
        "examples": "「そうですよ」→「そうやで」、「どうですか？」→「どないですか？」、「わかりました」→「わかりましたわ」",
    },
    {
        "name": "博多弁",
        "system_suffix": "あなたは福岡出身で、博多弁で話します。",
        "prompt": "以下の回答を博多弁に書き換えてください。\n「〜ばい」「〜たい」「〜やけん」「〜やろ」など博多弁らしく。内容は変えないこと。",
        "examples": "「そうです」→「そうばい」、「だから」→「やけん」、「いいですよ」→「よかよ」",
    },
    {
        "name": "京都弁",
        "system_suffix": "あなたは京都出身で、はんなりとした京都弁で話します。",
        "prompt": "以下の回答を京都弁に書き換えてください。\n「〜どす」「〜おす」「〜やおへんか」「〜はりますか」など京都弁らしく。上品に。内容は変えないこと。",
        "examples": "「そうです」→「そうどす」、「ありがとう」→「おおきに」、「どうぞ」→「おあがりやす」",
    },
    {
        "name": "東北弁",
        "system_suffix": "あなたは東北出身で、東北弁で話します。",
        "prompt": "以下の回答を東北弁（宮城・岩手あたり）に書き換えてください。\n「〜だべ」「〜だっちゃ」「〜んだ」「んだんだ」など東北弁らしく。内容は変えないこと。",
        "examples": "「そうです」→「んだんだ」、「すごい」→「んだっちゃ」、「わかりました」→「わがった」",
    },
    {
        "name": "沖縄弁",
        "system_suffix": "あなたは沖縄出身で、ウチナーグチ混じりの沖縄弁で話します。",
        "prompt": "以下の回答を沖縄弁に書き換えてください。\n「〜さぁ」「〜やっさ」「〜くとぅ」「なんくるないさ」などを適度に混ぜて。内容は変えないこと。",
        "examples": "「そうです」→「そうさぁ」、「大丈夫です」→「なんくるないさー」、「ありがとう」→「にふぇーでーびる」",
    },
    {
        "name": "武士・侍",
        "system_suffix": "あなたは江戸時代の侍のように、武士言葉で話します。",
        "prompt": "以下の回答を武士・侍の言葉遣いに書き換えてください。\n「〜でござる」「〜にござる」「拙者」「貴殿」「左様か」など武士語で。内容は変えないこと。",
        "examples": "「そうです」→「左様でござる」、「わかりました」→「承知いたした」、「ありがとう」→「かたじけない」",
    },
    {
        "name": "ギャル",
        "system_suffix": "あなたは90〜00年代ギャルで、ギャル語で話します。",
        "prompt": "以下の回答をギャル語に書き換えてください。\n「まじ」「やばい」「〜じゃん」「ウケる」「超〜」「〜くない？」など。内容は変えないこと。テンション高めで。",
        "examples": "「そうです」→「まじそれ！」、「わかりました」→「りょ！」、「すごいですね」→「やばくない？超すごくない？」",
    },
    {
        "name": "お嬢様",
        "system_suffix": "あなたは上品なお嬢様で、品のある言葉遣いで話します。",
        "prompt": "以下の回答をお嬢様言葉に書き換えてください。\n「〜でしてよ」「〜ですわ」「〜かしら」「まあ」「ほほほ」など上品に。内容は変えないこと。",
        "examples": "「そうです」→「そうでしてよ」、「わかりました」→「よろしくてよ」、「すごいですね」→「まあ、素晴らしいですわ」",
    },
    {
        "name": "博士・教授",
        "system_suffix": "あなたは大学教授で、学術的・説明好きな口調で話します。",
        "prompt": "以下の回答を博士・教授風の口調に書き換えてください。\n「つまり」「すなわち」「〜と考えられる」「注目すべきは」「興味深いことに」など学術的に。少し長めに説明する。内容は変えないこと。",
        "examples": "「そうです」→「その通りであります」、「すごいですね」→「実に興味深い結果と言えるでしょう」",
    },
    {
        "name": "アイドル",
        "system_suffix": "あなたはアイドルで、かわいく明るい口調で話します。",
        "prompt": "以下の回答をアイドル風の口調に書き換えてください。\n「〜だよ♪」「〜だね！」「わあ！」「うれしい！」など明るく元気に。「✨」「💕」を1〜2個使ってもOK。内容は変えないこと。",
        "examples": "「そうです」→「そうだよ♪」、「わかりました」→「わかった！まかせて！✨」",
    },
    {
        "name": "ツンデレ",
        "system_suffix": "あなたはツンデレキャラで、素直じゃないけど助けてしまうキャラです。",
        "prompt": "以下の回答をツンデレ口調に書き換えてください。\n「べ、別に〜じゃないし」「あんたのために言ってるわけじゃないから」など照れ隠し表現を入れつつ、ちゃんと回答する。内容は変えないこと。",
        "examples": "「お役に立てました」→「べ、別にあなたのために教えたわけじゃないんだからね！？」",
    },
    {
        "name": "ロボット・AI",
        "system_suffix": "あなたはSFに出てくるロボットで、機械的な口調で話します。",
        "prompt": "以下の回答をロボット・AI風の口調に書き換えてください。\n「計算完了」「データ解析結果」「〜であります」「処理中...完了」など機械的に。内容は変えないこと。絵文字不使用。",
        "examples": "「そうです」→「肯定。その通りであります。」、「わかりました」→「了解。処理を開始します。」",
    },
    {
        "name": "関西芸人",
        "system_suffix": "あなたは関西出身の芸人で、ボケとツッコミを交えて話します。",
        "prompt": "以下の回答を関西芸人風の口調に書き換えてください。\n「なんでやねん」「ちゃうちゃう」「そんなんあるかいな」などツッコミや軽いボケを入れながら、ちゃんと回答する。内容は変えないこと。",
        "examples": "「それは難しい質問です」→「難しいって！どんだけハードル上げてんねん！でもまあ答えたるわ」",
    },
    {
        "name": "中二病",
        "system_suffix": "あなたは中二病キャラで、厨二病的な言い回しで話します。",
        "prompt": "以下の回答を中二病風の口調に書き換えてください。\n「我が〜」「〜の力が目覚めた」「真の答えを教えてやろう」「凡人には理解できぬかもしれぬが」など厨二病的に。内容は変えないこと。",
        "examples": "「そうです」→「正解だ。さすがは我が同士」、「わかりました」→「その願い、この俺が叶えてやろう」",
    },
    {
        "name": "丁寧すぎる敬語",
        "system_suffix": "あなたは過度に丁寧な敬語を使うキャラです。",
        "prompt": "以下の回答を「過度に丁寧すぎる敬語」に書き換えてください。\n「〜でございますでしょうか」「〜させていただきますようお願い申し上げます」「誠に恐縮ではございますが」など。かしこまりすぎて少し面白い感じに。内容は変えないこと。",
        "examples": "「そうです」→「おっしゃる通りでございます」、「わかりました」→「承知いたしました。謹んで対応させていただきます」",
    },
]

REWRITE_PROMPT = """以下のAIアシスタントの回答を、指定されたペルソナ・口調に書き換えてください。

【ペルソナ】{persona_name}
【書き換え指示】{prompt}
【参考例】{examples}

【元の回答】
{response}

【制約】
- 事実・情報・ツール呼び出し結果は一切変えない
- 回答の構造（箇条書きなど）は維持してよい
- ペルソナの口調・語尾を自然に混ぜる
- 長さは元と同程度

書き換えた回答のみ出力（説明不要）:"""


def rewrite_response(response: str, persona: dict) -> str | None:
    if len(response) < 20:
        return None

    prompt = REWRITE_PROMPT.format(
        persona_name=persona["name"],
        prompt=persona["prompt"],
        examples=persona["examples"],
        response=response[:800],
    )

    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 1200,
                    "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.8,
                },
                timeout=60,
            )
            if resp.status_code == 429:
                time.sleep(20)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
            if len(text) >= 15:
                return text
        except requests.exceptions.Timeout:
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {str(e)[:60]}", file=sys.stderr)
            time.sleep(2)
            continue
    return None


def apply_persona_to_item(item: dict, persona: dict) -> dict | None:
    """アイテムの最初のassistant回答をペルソナ風に書き換えた新アイテムを返す"""
    convs = item.get("conversations", [])
    new_convs = []
    applied = False

    # system メッセージにペルソナ設定を付加
    for m in convs:
        role = m.get("role", "")
        if role == "system" and not applied:
            new_system = m.get("content", "").rstrip()
            # 元のsystemプロンプトにペルソナ設定を追加
            if persona["system_suffix"] not in new_system:
                new_system = new_system + "\n" + persona["system_suffix"]
            new_convs.append({**m, "content": new_system})
        elif role == "assistant" and not applied:
            content = m.get("content", "")
            # <think>タグを抽出して保持
            think_match = re.search(r"<think>(.*?)</think>", content, re.DOTALL)
            response = re.sub(r"<think>.*?</think>", "", content, flags=re.DOTALL).strip()

            if not response or len(response) < 20:
                return None

            new_response = rewrite_response(response, persona)
            if not new_response:
                return None

            # think + 新しいresponseを組み合わせ
            if think_match:
                new_content = f"<think>\n{think_match.group(1).strip()}\n</think>\n{new_response}"
            else:
                new_content = new_response

            new_convs.append({**m, "content": new_content})
            applied = True
        else:
            new_convs.append(m)

    if not applied:
        return None

    return {
        **item,
        "conversations": new_convs,
        "persona": persona["name"],
        "source": f"persona_{persona['name']}",
        "_original_source": item.get("source", "unknown"),
    }


def item_hash(item: dict, persona_name: str) -> str:
    convs = item.get("conversations", [])
    user_msgs = " ".join(m.get("content","")[:80] for m in convs if m.get("role")=="user")
    return hashlib.md5(f"{user_msgs}_{persona_name}".encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",       required=True)
    parser.add_argument("--output",      required=True)
    parser.add_argument("--personas",    default="all",
                        help="カンマ区切りのペルソナ名、またはall")
    parser.add_argument("--per-item",    type=int, default=3,
                        help="1アイテムあたり最大ペルソナ数")
    parser.add_argument("--max-source",  type=int, default=0,
                        help="元データの最大使用件数 (0=全件)")
    parser.add_argument("--target",      type=int, default=6000,
                        help="目標生成件数")
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    # ペルソナ選択
    if args.personas == "all":
        active_personas = PERSONAS
    else:
        names = set(args.personas.split(","))
        active_personas = [p for p in PERSONAS if p["name"] in names]
    print(f"ペルソナ: {[p['name'] for p in active_personas]}")

    # 入力データ読み込み
    data = json.load(open(args.input, encoding="utf-8"))
    if args.max_source > 0:
        data = data[:args.max_source]
    random.seed(42)
    random.shuffle(data)
    print(f"入力: {len(data)}件 | per-item: {args.per_item} | 目標: {args.target}件")

    # 再開対応
    results = []
    done_hashes = set()
    if os.path.exists(args.output):
        results = json.load(open(args.output, encoding="utf-8"))
        for r in results:
            done_hashes.add(item_hash(r, r.get("persona", "")))
        print(f"再開: {len(results)}件済み")

    generated = 0
    total_attempts = 0

    for item in data:
        if len(results) >= args.target:
            break

        # このアイテムに割り当てるペルソナをランダムに選択
        shuffled_personas = active_personas.copy()
        random.shuffle(shuffled_personas)
        personas_for_item = shuffled_personas[:args.per_item]

        for persona in personas_for_item:
            if len(results) >= args.target:
                break

            h = item_hash(item, persona["name"])
            if h in done_hashes:
                continue

            total_attempts += 1
            new_item = apply_persona_to_item(item, persona)

            if new_item:
                results.append(new_item)
                done_hashes.add(h)
                generated += 1

                print(f"  [{generated}/{args.target}] {persona['name']}: "
                      f"{item.get('source','?')[:20]}")

                if generated % 50 == 0:
                    _save(results, args.output)
                    print(f"  --- 中間保存: {len(results)}件 ---")
            else:
                print(f"  [SKIP] {persona['name']}")

            time.sleep(0.3)

    _save(results, args.output)

    from collections import Counter
    persona_dist = Counter(r.get("persona","?") for r in results)
    print(f"\n完了: {generated}件生成 → {args.output} (合計{len(results)}件)")
    print(f"成功率: {100*generated//max(total_attempts,1)}%")
    print("ペルソナ内訳:")
    for k, v in sorted(persona_dist.items()):
        print(f"  {k}: {v}件")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
