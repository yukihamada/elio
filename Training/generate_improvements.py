#!/usr/bin/env python3
"""
Training Data Quality Improvements
====================================
1. マルチターン会話 (300件)
2. ネガティブ例・ツール不要判断 (150件)
3. エラーハンドリング (150件)
4. 薄い引数の修正

Usage:
    python generate_improvements.py --output improvements.json
"""

import argparse
import json
import os
import random
import re
import time

import openai

# ─── Client setup ───
def make_client():
    key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_GENERATIVE_AI_API_KEY")
    if key:
        return openai.OpenAI(
            api_key=key,
            base_url="https://generativelanguage.googleapis.com/v1beta/openai/"
        ), "gemini-2.0-flash"
    key = os.environ.get("OPENAI_API_KEY")
    if key:
        return openai.OpenAI(api_key=key), "gpt-4.1-mini"
    raise RuntimeError("No API key")

client, MODEL = make_client()
print(f"Using: {MODEL}")


def call_llm(prompt: str, max_tokens: int = 800) -> str:
    for attempt in range(3):
        try:
            resp = client.chat.completions.create(
                model=MODEL,
                max_tokens=max_tokens,
                temperature=0.85,
                messages=[{"role": "user", "content": prompt}],
            )
            return resp.choices[0].message.content.strip()
        except Exception as e:
            if attempt == 2:
                raise
            time.sleep(2)
    return ""


def parse_json_obj(text: str) -> dict | None:
    """Extract first valid JSON object from text."""
    # strip markdown fences
    text = re.sub(r'```(?:json)?\s*', '', text)
    text = re.sub(r'```\s*$', '', text).strip()

    # try outermost { ... } (first { to last })
    start = text.find('{')
    end = text.rfind('}')
    if start >= 0 and end > start:
        try:
            obj = json.loads(text[start:end + 1])
            if isinstance(obj, dict):
                return obj
        except Exception:
            pass

    # bracket-walk fallback
    for m in re.finditer(r'\{', text):
        depth = 0
        for i, ch in enumerate(text[m.start():], m.start()):
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(text[m.start():i + 1])
                        if isinstance(obj, dict):
                            return obj
                    except Exception:
                        break
    return None


# ─── 1. マルチターン ───

MULTI_TURN_SEEDS = [
    # (tool, turn1_query, turn2_query, mock_result1, mock_result2)
    ("weather", "東京の今日の天気を教えて", "じゃあ大阪は？",
     '{"location":"東京","temperature":18,"condition":"晴れ","humidity":50}',
     '{"location":"大阪","temperature":20,"condition":"曇り","humidity":60}'),
    ("weather", "札幌の天気は？", "明日も同じくらいの天気かな",
     '{"location":"札幌","temperature":5,"condition":"雪","humidity":80}',
     '{"location":"札幌","temperature":4,"condition":"小雪","humidity":82}'),
    ("web_search", "東京でおすすめのラーメン屋を教えて", "そのうちつけ麺が有名な店はある？",
     '{"results":[{"title":"東京ラーメンランキング2024","snippet":"一風堂、蔦、中華そば青葉など人気店多数"}]}',
     '{"results":[{"title":"東京つけ麺人気店","snippet":"六厘舎、三田製麺所が有名。行列必至"}]}'),
    ("calculator", "消費税10%で3,800円の商品はいくら？", "5個買ったら合計いくら？",
     '{"result":4180}',
     '{"result":20900}'),
    ("calculator", "月収35万円の手取りは大体いくら？", "年収にすると？",
     '{"result":280000}',
     '{"result":3360000}'),
    ("translate", "「ありがとうございます」を英語に翻訳して", "フランス語でも教えて",
     '{"translated":"Thank you very much"}',
     '{"translated":"Merci beaucoup"}'),
    ("translate", "I love sushi and ramen. を日本語に", "韓国語でも",
     '{"translated":"寿司とラーメンが大好きです。"}',
     '{"translated":"초밥과 라멘을 정말 좋아합니다."}'),
    ("wikipedia", "宮沢賢治について教えて", "代表作の銀河鉄道の夜はどんな内容？",
     '{"title":"宮沢賢治","summary":"1896年-1933年。詩人・童話作家。岩手県生まれ。農業と文学を融合させた独自の世界観"}',
     '{"title":"銀河鉄道の夜","summary":"少年ジョバンニと友人カムパネルラが銀河鉄道に乗り旅をする幻想的な物語。未完の傑作"}'),
    ("news_search", "最新のAI技術ニュースを教えて", "GPT関連のニュースは？",
     '{"articles":[{"title":"Gemini 2.0発表","source":"TechCrunch","summary":"Googleが次世代AIモデルを公開"}]}',
     '{"articles":[{"title":"OpenAI新モデル","source":"日経新聞","summary":"ChatGPTの新バージョンがリリース"}]}'),
    ("code_execute", "1から100の合計をPythonで計算して", "同じことをリスト内包表記でも書いて",
     '{"output":"5050","exit_code":0}',
     '{"output":"5050","exit_code":0}'),
    ("file_write", "/tmp/sandbox/memo.txtに「今日のタスク：報告書作成」と書いて", "書いた内容を確認して",
     '{"success":true,"path":"/tmp/sandbox/memo.txt"}',
     '{"content":"今日のタスク：報告書作成"}'),
    ("datetime", "今日から30日後は何日？", "その日は何曜日？",
     '{"result":"2024-07-15"}',
     '{"result":"月曜日"}'),
    ("create_qr", "https://chatweb.aiのQRコードを作って", "会社名「株式会社テスト」のvCardのQRも作って",
     '{"qr_url":"https://api.chatweb.ai/qr/chatweb.png"}',
     '{"qr_url":"https://api.chatweb.ai/qr/vcard.png"}'),
]


def build_multi_turn_example(seed: tuple) -> dict | None:
    tool, q1, q2, result1, result2 = seed

    prompt = f"""以下のマルチターン会話トレーニングデータを生成してください。

ツール: {tool}
1回目の質問: {q1}
2回目の質問（1回目の続き）: {q2}
1回目のツール結果: {result1}
2回目のツール結果: {result2}

以下のJSON形式で返してください（マークダウン不要、JSONのみ）:
{{
  "conversations": [
    {{"role": "user", "content": "1回目の質問（具体的に）"}},
    {{"role": "assistant", "content": "<think>\\nなぜ{tool}ツールを使うか1-3文で。\\n</think>\\n\\n<tool_call>\\n{{\"name\": \"{tool}\", \"arguments\": {{具体的な引数}}}}\\n</tool_call>"}},
    {{"role": "tool", "name": "{tool}", "content": "{result1}"}},
    {{"role": "assistant", "content": "1回目の自然な回答（結果を説明）"}},
    {{"role": "user", "content": "2回目の質問（1回目を受けた自然な続き）"}},
    {{"role": "assistant", "content": "<think>\\n前の文脈を踏まえた思考。\\n</think>\\n\\n<tool_call>\\n{{\"name\": \"{tool}\", \"arguments\": {{具体的な引数}}}}\\n</tool_call>"}},
    {{"role": "tool", "name": "{tool}", "content": "{result2}"}},
    {{"role": "assistant", "content": "2回目の自然な回答"}}
  ]
}}

重要: tool_callのargumentsには具体的な値を入れること。"""

    try:
        text = call_llm(prompt, max_tokens=1500)
        obj = parse_json_obj(text)
        if obj and "conversations" in obj:
            roles = [m.get("role") for m in obj["conversations"]]
            if roles.count("user") >= 2 and roles.count("tool") >= 2:
                return obj
    except Exception as e:
        print(f"  Error: {e}")
    return None


# ─── 2. ネガティブ例 ───

NEGATIVE_SEEDS = [
    ("日本の首都はどこ？", "簡単な地理知識なので直接答えられる"),
    ("今日は何の日？", "一般的な知識で答えられる（リアルタイム情報不要）"),
    ("元気ですか？", "挨拶・雑談なのでツール不要"),
    ("落ち込んでいます", "感情サポートは直接対話が適切"),
    ("プログラミングを学ぶコツを教えて", "アドバイスは知識で答えられる"),
    ("1+1はいくつ？", "暗算できるのでcalculatorは不要"),
    ("英語でhello はどういう意味？", "基本的な語彙なのでtranslateツール不要"),
    ("おすすめの本を教えて", "意見・推薦は知識で対応可能"),
    ("Pythonのリストとタプルの違いは？", "プログラミング知識で答えられる"),
    ("睡眠の質を上げる方法は？", "健康アドバイスは直接回答可能"),
    ("最近仕事が大変で...", "共感・傾聴が必要、ツール不要"),
    ("2024年は何年前？", "現在年から引くだけ、計算ツール不要"),
    ("俳句を一つ作って", "創作はツール不要"),
    ("相対性理論って何？", "科学知識で説明できる"),
    ("カロリーを抑えたいのですが", "健康・食事アドバイスは直接回答"),
]

NEGATIVE_CONSIDERED = [
    ("東京の人口は？", "web_search", "一般知識として知っているので検索不要"),
    ("円周率を教えて", "calculator", "3.14159...は暗記しているのでツール不要"),
    ("「ありがとう」の英訳は？", "translate", "基本語彙として知っているので翻訳ツール不要"),
    ("最新ニュースを教えて", "news_search", "具体的なトピックがないので検索せず説明を促す"),
    ("100の平方根は？", "calculator", "10と知っているので計算不要"),
]


def build_negative_example(seed: tuple, with_consideration: bool = False) -> dict | None:
    if with_consideration:
        user_q, tool_name, reason = seed
        prompt = f"""AIアシスタントがツール使用を「検討したが不要」と判断する会話例を生成してください。

ユーザーの質問: {user_q}
一度検討するツール: {tool_name}
不要と判断した理由: {reason}

以下のJSON形式で返してください（マークダウン不要）:
{{
  "conversations": [
    {{"role": "user", "content": "{user_q}"}},
    {{"role": "assistant", "content": "<think>\\n{tool_name}ツールを使おうかと思ったが、{reason}。直接答える。\\n</think>\\n\\n（自然な直接回答）"}}
  ]
}}"""
    else:
        user_q, reason = seed
        prompt = f"""AIアシスタントがツールを使わず直接答える会話例を生成してください。

ユーザーの質問: {user_q}
直接答える理由: {reason}

以下のJSON形式で返してください（マークダウン不要）:
{{
  "conversations": [
    {{"role": "user", "content": "{user_q}"}},
    {{"role": "assistant", "content": "<think>\\n{reason}。直接回答する。\\n</think>\\n\\n（丁寧で役立つ回答、100-200文字程度）"}}
  ]
}}"""

    try:
        text = call_llm(prompt, max_tokens=400)
        obj = parse_json_obj(text)
        if obj and "conversations" in obj:
            convs = obj["conversations"]
            has_tool = any(m.get("role") == "tool" for m in convs)
            has_think = any("<think>" in m.get("content", "") for m in convs if m.get("role") == "assistant")
            if not has_tool and has_think:
                return obj
    except Exception as e:
        print(f"  Error: {e}")
    return None


# ─── 3. エラーハンドリング ───

ERROR_SEEDS = [
    ("web_search", "「桜前線2025年最新」を調べて", '{"results":[],"message":"No results found"}',
     "「2025年 桜前線」など別のキーワードで再検索を提案"),
    ("weather", "「ムー大陸」の天気を教えて", '{"error":"Location not found: ムー大陸"}',
     "実在しない場所なので謝罪し、実在の地名を入力するよう案内"),
    ("read_webpage", "https://private.example.com を読んで", '{"error":"403 Forbidden: Access denied"}',
     "アクセス拒否。公開ページか別の情報源を提案"),
    ("calculator", "5÷0を計算して", '{"error":"ZeroDivisionError: division by zero"}',
     "0除算を説明し、正しい計算式を提案"),
    ("code_execute", "print(Hello World)を実行して", '{"output":"","exit_code":1,"error":"SyntaxError: invalid syntax (line 1)"}',
     "構文エラーを指摘して正しいコードを提示"),
    ("translate", "日本語をzz語に翻訳して", '{"error":"Unsupported target language: zz"}',
     "未対応言語。対応言語一覧を案内"),
    ("file_read", "/tmp/sandbox/missing.txt を読んで", '{"error":"FileNotFoundError: /tmp/sandbox/missing.txt"}',
     "ファイルが存在しないことを説明。file_listで確認を提案"),
    ("news_search", "「極秘情報」のニュースを探して", '{"articles":[],"message":"No articles found"}',
     "該当ニュースなし。より一般的なキーワードを提案"),
    ("image_analyze", "https://expired.example.com/img.jpg を分析して", '{"error":"Image not accessible: Connection timeout"}',
     "画像にアクセスできない。別のURLか画像の説明を求める"),
    ("code_execute", "import os; os.system(\"rm -rf /\")", '{"error":"SecurityError: Dangerous command blocked"}',
     "危険なコマンドをブロック。安全なコードのみ実行可能と説明"),
]


def build_error_example(seed: tuple) -> dict | None:
    tool, user_q, error_result, expected_behavior = seed

    prompt = f"""ツール実行でエラーが発生し、AIが適切に対処する会話例を生成してください。

ユーザーの質問: {user_q}
ツール: {tool}
エラーレスポンス: {error_result}
期待する対処: {expected_behavior}

以下のJSON形式で返してください（マークダウン不要）:
{{
  "conversations": [
    {{"role": "user", "content": "{user_q}"}},
    {{"role": "assistant", "content": "<think>\\n{tool}ツールを使う。\\n</think>\\n\\n<tool_call>\\n{{\"name\": \"{tool}\", \"arguments\": {{具体的な引数}}}}\\n</tool_call>"}},
    {{"role": "tool", "name": "{tool}", "content": {json.dumps(error_result)}}},
    {{"role": "assistant", "content": "<think>\\nエラーが発生。{expected_behavior}。\\n</think>\\n\\n（丁寧なエラー説明と代替案の提示）"}}
  ]
}}"""

    try:
        text = call_llm(prompt, max_tokens=500)
        obj = parse_json_obj(text)
        if obj and "conversations" in obj:
            convs = obj["conversations"]
            roles = [m.get("role") for m in convs]
            has_tool = "tool" in roles
            tool_content = next((m.get("content", "") for m in convs if m.get("role") == "tool"), "")
            has_error = "error" in tool_content.lower() or "not found" in tool_content.lower() or "[]" in tool_content
            if has_tool:
                return obj
    except Exception as e:
        print(f"  Error: {e}")
    return None


# ─── 4. 薄い引数修正 ───

def fix_thin_arguments(data: list[dict], max_fixes: int = 150) -> tuple[list[dict], int]:
    thin_patterns = [
        (r'"text":\s*"([^"]{1,25})"', "translate"),
        (r'"code":\s*"([^"]{1,30})"', "code_execute"),
        (r'"content":\s*"([^"]{1,20})"', "file_write"),
    ]

    to_fix = []
    for i, item in enumerate(data):
        for msg in item["conversations"]:
            if msg.get("role") == "assistant":
                content = msg.get("content", "")
                tc_match = re.search(r'<tool_call>\s*(.*?)\s*</tool_call>', content, re.DOTALL)
                if tc_match:
                    tc_text = tc_match.group(1)
                    tool_name = ""
                    try:
                        tc = json.loads(tc_text)
                        tool_name = tc.get("name", "")
                    except:
                        pass
                    for pattern, target_tool in thin_patterns:
                        if (target_tool == tool_name or not target_tool) and re.search(pattern, tc_text):
                            to_fix.append(i)
                            break

    print(f"  薄い引数: {len(to_fix)}件")
    fixed = 0

    for i in to_fix[:max_fixes]:
        item = data[i]
        user_q = next((m.get("content", "") for m in item["conversations"] if m.get("role") == "user"), "")
        ass_msg = next((m for m in item["conversations"] if m.get("role") == "assistant" and "<tool_call>" in m.get("content", "")), None)
        if not ass_msg:
            continue
        tc_match = re.search(r'<tool_call>\s*(.*?)\s*</tool_call>', ass_msg["content"], re.DOTALL)
        if not tc_match:
            continue
        try:
            tc = json.loads(tc_match.group(1))
        except:
            continue

        prompt = f"""ユーザーの質問: {user_q}
現在のtool_call引数: {json.dumps(tc.get("arguments", {}), ensure_ascii=False)}

引数が薄すぎます。ユーザーの質問を元に具体的な値に改善した引数JSONのみ返してください（マークダウン不要）:"""

        try:
            text = call_llm(prompt, max_tokens=200)
            obj = parse_json_obj(text)
            if obj and isinstance(obj, dict):
                tc["arguments"] = obj
                new_tc = json.dumps(tc, ensure_ascii=False)
                ass_msg["content"] = re.sub(
                    r'<tool_call>\s*.*?\s*</tool_call>',
                    f'<tool_call>\n{new_tc}\n</tool_call>',
                    ass_msg["content"], flags=re.DOTALL
                )
                fixed += 1
            time.sleep(0.2)
        except:
            pass

    return data, fixed


# ─── Main ───

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="improvements.json")
    parser.add_argument("--multi_turn", type=int, default=3)   # seed当たり繰り返し数
    parser.add_argument("--tool_data", default="tool_data_llm.json")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)
    all_new = []

    # 1. マルチターン
    print(f"\n{'='*50}\n1. マルチターン会話生成\n{'='*50}")
    multi_ok = 0
    seeds_expanded = MULTI_TURN_SEEDS * args.multi_turn
    random.shuffle(seeds_expanded)
    for j, seed in enumerate(seeds_expanded):
        if j % 5 == 0:
            print(f"  {j}/{len(seeds_expanded)}...")
        ex = build_multi_turn_example(seed)
        if ex:
            all_new.append(ex)
            multi_ok += 1
        time.sleep(0.3)
    print(f"  → {multi_ok}件生成")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_new, f, ensure_ascii=False, indent=2)

    # 2. ネガティブ例
    print(f"\n{'='*50}\n2. ネガティブ例生成\n{'='*50}")
    neg_ok = 0
    for j, seed in enumerate(NEGATIVE_SEEDS * 3):
        ex = build_negative_example(seed, with_consideration=False)
        if ex:
            all_new.append(ex)
            neg_ok += 1
        time.sleep(0.2)
    for seed in NEGATIVE_CONSIDERED * 5:
        ex = build_negative_example(seed, with_consideration=True)
        if ex:
            all_new.append(ex)
            neg_ok += 1
        time.sleep(0.2)
    print(f"  → {neg_ok}件生成")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_new, f, ensure_ascii=False, indent=2)

    # 3. エラーハンドリング
    print(f"\n{'='*50}\n3. エラーハンドリング例生成\n{'='*50}")
    err_ok = 0
    for j, seed in enumerate(ERROR_SEEDS * 5):
        ex = build_error_example(seed)
        if ex:
            all_new.append(ex)
            err_ok += 1
        time.sleep(0.2)
    print(f"  → {err_ok}件生成")

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_new, f, ensure_ascii=False, indent=2)

    # 4. 薄い引数修正
    tool_data_path = os.path.join(script_dir, args.tool_data)
    if os.path.exists(tool_data_path):
        print(f"\n{'='*50}\n4. 薄い引数修正\n{'='*50}")
        with open(tool_data_path, encoding="utf-8") as f:
            tool_data = json.load(f)
        tool_data, fixed = fix_thin_arguments(tool_data, max_fixes=150)
        print(f"  → {fixed}件修正")
        with open(tool_data_path, "w", encoding="utf-8") as f:
            json.dump(tool_data, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*50}")
    print(f"完了: {len(all_new)}件")
    print(f"  multi_turn: {multi_ok}, negative: {neg_ok}, error: {err_ok}")
    print(f"Saved to: {output_path}")


if __name__ == "__main__":
    main()
