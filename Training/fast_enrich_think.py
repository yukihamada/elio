#!/usr/bin/env python3
"""
fast_enrich_think.py — テンプレートベースの高速think充実化
=========================================================
LLM不要。ルールベースで80%+ のケースを処理。
- thin think (< 80字): ツール名・コンテキストから拡充
- tool後のno-think: ツール結果の内容から生成
"""
import json, os, re, sys, argparse, random

random.seed(42)

# ── ツール別 思考テンプレート ────────────────────────────────────
CALL_THINK_TEMPLATES = {
    "wikipedia": [
        "{topic}についての正確な情報を得るには、Wikipediaで調べるのが最適だ。百科事典的な背景知識と歴史的経緯も含めて取得できるため、ユーザーに詳しく説明できるだろう。",
        "この質問に答えるには{topic}の概要・歴史・詳細が必要だ。WikipediaのAPIを使えば信頼性の高い情報を素早く取得できる。",
        "{topic}について聞かれた。まずWikipediaで基本情報を確認し、正確な事実に基づいた回答を組み立てよう。",
    ],
    "calculator": [
        "この計算は手計算だとミスが生じる可能性があるため、calculatorツールで正確に求めよう。式を立てると{expr}になる。",
        "数値計算が必要な質問だ。正確な答えを出すためにcalculatorを使い、計算過程も確認しながら進める。",
        "{expr}を計算する必要がある。calculatorツールに任せることで確実な値が得られる。",
    ],
    "weather": [
        "{location}の現在の天気を確認するためにweatherツールを使う。気温・湿度・天気概況を取得してユーザーに適切なアドバイスを添えて伝えよう。",
        "天気に関する質問だ。{location}のリアルタイム気象データをweatherツールで取得して答える。",
        "{location}の天気情報をweatherツールで取得する。外出や旅行の参考になるよう気温と体感温度も報告しよう。",
    ],
    "translate": [
        "翻訳が必要な場面だ。translateツールを使えば高精度な翻訳が得られる。文脈を保ちながら自然な{target}に変換してもらおう。",
        "翻訳の依頼だ。translateツールで正確かつ自然な訳文を取得し、必要に応じて補足説明を加えよう。",
        "この文章を{target}に翻訳する。translateツールに渡して品質の高い訳文を得る。",
    ],
    "web_search": [
        "最新情報や具体的な事実を確認するためweb_searchツールを使う。検索結果から信頼性の高い情報を選んで回答に活用しよう。",
        "この質問にはリアルタイムの情報が必要だ。web_searchで検索して最新の状況を把握する。",
        "ウェブ検索が必要な質問だ。複数の情報源から確認しながら正確な情報を提供しよう。",
    ],
    "web_fetch": [
        "指定されたURLのコンテンツを取得するためweb_fetchを使う。ページの内容を読み込んでユーザーが求める情報を抽出しよう。",
        "このURLのページ内容を確認する必要がある。web_fetchツールでコンテンツを取得して要約する。",
    ],
    "news_search": [
        "最新ニュースを確認するためnews_searchを使う。信頼できるソースの記事を取得して現状をまとめよう。",
        "この話題の最新動向をnews_searchで調べる。複数の記事から状況を把握して伝えよう。",
    ],
    "datetime": [
        "現在の日時をdatetimeツールで取得する。正確な日付・時刻・曜日を確認してユーザーに伝えよう。",
        "日付や曜日の計算が必要だ。datetimeツールを使って正確な情報を得る。",
    ],
    "image_generate": [
        "画像生成が必要だ。image_generateツールで要求に合った画像を作成しよう。プロンプトを工夫して品質を高める。",
        "ユーザーが画像を求めている。image_generateツールで希望する内容の画像を生成する。",
    ],
    "code_execute": [
        "コードを実行して結果を確認する必要がある。code_executeツールでサンドボックス環境で安全に実行しよう。",
        "実際にコードを動かして答えを出す。code_executeを使ってプログラムの実行結果を確認する。",
    ],
    "create_qr": [
        "QRコード生成が求められている。create_qrツールで指定の内容をQRコードに変換しよう。",
    ],
}

FINAL_THINK_TEMPLATES = {
    "wikipedia": [
        "Wikipediaから「{title}」について情報が得られた。{summary_start}という内容だ。この情報をわかりやすくまとめてユーザーに伝えよう。重要なポイントを整理して補足も加える。",
        "検索結果として「{title}」の情報が返ってきた。ユーザーの質問に直接答える部分を中心に、読みやすい形式で提示しよう。",
        "「{title}」に関するWikipediaの情報を確認した。得られた内容を整理し、ユーザーが知りたいポイントに絞って回答を構成する。",
    ],
    "calculator": [
        "計算結果として{result}が得られた。この数値の意味を解釈し、単位や文脈を添えてユーザーが理解しやすい形で説明しよう。",
        "計算ツールから{result}という答えが返ってきた。計算の流れを簡潔に説明しながら結果を伝える。",
        "{result}という計算結果が出た。ユーザーが何のためにこの計算をしたかを踏まえ、実用的な解釈も加えて回答しよう。",
    ],
    "weather": [
        "天気データが取得できた。気温{temp}℃、{desc}という状況だ。この情報をもとに外出時の注意点や服装のアドバイスも添えて伝えよう。",
        "気象情報が返ってきた。数値をそのまま伝えるだけでなく、体感や生活への影響も含めて分かりやすく説明しよう。",
    ],
    "translate": [
        "翻訳結果が得られた。訳文が自然かどうか確認し、文化的な補足や注意点があれば加えて伝えよう。",
        "翻訳が完了した。ユーザーが求める用途に合った訳文になっているか確認しながら回答を組み立てる。",
    ],
    "web_search": [
        "検索結果が返ってきた。複数の情報から信頼性の高いものを選び、ユーザーの質問に正確に答えよう。",
        "ウェブ検索の結果を確認した。関連性の高い情報をまとめて、ユーザーが求める回答を構成する。",
    ],
    "web_fetch": [
        "ウェブページのコンテンツを取得した。ユーザーが知りたい情報を抽出し、要点をまとめて伝えよう。",
        "ページの内容が取得できた。関係する部分を整理してわかりやすく説明する。",
    ],
    "news_search": [
        "ニュース検索の結果が返ってきた。最新の動向を整理し、ユーザーに分かりやすく現状を説明しよう。",
        "ニュース記事が取得できた。重要なポイントをまとめて最新情報を伝える。",
    ],
    "datetime": [
        "現在の日時情報が取得できた。ユーザーが必要としている情報（日付・曜日・時刻）を整理して伝えよう。",
        "日時データが返ってきた。ユーザーの質問に合わせた形で具体的に答える。",
    ],
    "calculator_err": [
        "計算でエラーが発生した。エラーの原因を分析し、数学的に正しい解説をユーザーに提供しよう。",
    ],
    "default": [
        "ツールから結果が得られた。内容を整理し、ユーザーの質問に的確に答えよう。",
        "実行結果を確認した。この情報をもとにユーザーが理解しやすい回答を組み立てる。",
    ],
}

GENERIC_THINK_TEMPLATES = [
    "この質問には{tool}ツールが最も適している。ユーザーの意図を正確に把握して、ツールに渡す引数を適切に設定しよう。",
    "{tool}ツールを使うことでこの質問に答えられる。必要な情報を正確に取得してユーザーに役立つ回答を提供しよう。",
    "この種の質問には{tool}ツールが有効だ。適切な引数でツールを呼び出し、得られた結果を分かりやすく解説する。",
]


def extract_tool_name(content: str) -> str:
    m = re.search(r'"name"\s*:\s*"([^"]+)"', content)
    return m.group(1) if m else ""


def extract_tool_result_info(tool_content: str, tool_name: str) -> dict:
    """ツール結果から主要情報を抽出"""
    info = {}
    try:
        data = json.loads(tool_content)
        if tool_name == "wikipedia":
            info["title"]         = data.get("title", "")
            summary               = data.get("summary", data.get("extract", ""))
            info["summary_start"] = summary[:50] if summary else ""
        elif tool_name == "calculator":
            info["result"] = str(data.get("result", ""))
            info["expr"]   = data.get("expression", "")
        elif tool_name == "weather":
            info["temp"] = str(data.get("temperature_c", ""))
            info["desc"] = data.get("description", "")
            info["loc"]  = data.get("location", "")
    except Exception:
        pass
    return info


def expand_thin_think(think_text: str, tool_name: str, user_query: str) -> str:
    """50〜80字以下のthinkを拡充"""
    templates = CALL_THINK_TEMPLATES.get(tool_name, GENERIC_THINK_TEMPLATES)
    tpl = random.choice(templates)

    # テンプレート変数を埋める
    topic   = re.sub(r'[？?。、！!]', '', user_query)[:20]
    target  = "英語" if "英語" in user_query else "日本語" if "日本語" in user_query else "対象言語"
    loc     = re.search(r'(東京|大阪|京都|名古屋|福岡|札幌|仙台|横浜|神戸|広島|London|Paris|New York|Seoul|Beijing)', user_query)
    location = loc.group(1) if loc else user_query[:10]

    # calculatorは数式を推測
    num_match = re.search(r'[\d,.]+', user_query)
    expr = num_match.group(0) + "..." if num_match else "数式"

    text = tpl.format(
        topic=topic, target=target, location=location,
        loc=location, expr=expr, tool=tool_name,
    )

    # 元のthinkが短くても意味があれば前置き
    if len(think_text) > 10:
        return f"{think_text}\n{text}"
    return text


def generate_final_think(tool_name: str, tool_result: str, user_query: str) -> str:
    """ツール結果後の思考を生成"""
    info = extract_tool_result_info(tool_result, tool_name)

    # エラーケース
    if '"error"' in tool_result:
        templates = FINAL_THINK_TEMPLATES.get(f"{tool_name}_err",
                    FINAL_THINK_TEMPLATES.get("default"))
        return random.choice(templates)

    templates = FINAL_THINK_TEMPLATES.get(tool_name, FINAL_THINK_TEMPLATES["default"])
    tpl = random.choice(templates)

    text = tpl.format(
        title        = info.get("title", "取得した情報"),
        summary_start= info.get("summary_start", "詳細な情報"),
        result       = info.get("result", "計算結果"),
        expr         = info.get("expr", ""),
        temp         = info.get("temp", ""),
        desc         = info.get("desc", ""),
        loc          = info.get("loc", ""),
    )
    return text


def inject_think(content: str, think_text: str) -> str:
    m = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
    block = f"<think>\n{think_text}\n</think>\n\n"
    if m:
        return content[:m.start()] + block + content[m.end():].lstrip()
    return block + content


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input",  required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))

    with open(os.path.join(script_dir, args.input), encoding="utf-8") as f:
        data = json.load(f)

    result  = []
    modified = 0

    for item in data:
        convs    = item["conversations"]
        new_convs = list(convs)
        changed  = False

        for i, msg in enumerate(convs):
            if msg["role"] != "assistant":
                continue

            content = msg["content"]
            m = re.search(r'<think>(.*?)</think>', content, re.DOTALL)
            think_text = m.group(1).strip() if m else ""

            is_after_tool = i > 0 and convs[i-1]["role"] == "tool"
            tool_name = ""
            if is_after_tool:
                tool_name = convs[i-1].get("name", "")
            else:
                # tool_call がある場合は呼び出し前のassistant
                tool_name = extract_tool_name(content)

            # 修正不要ならスキップ
            if len(think_text) >= 80 and not (not think_text and is_after_tool):
                continue

            user_query = ""
            for prev in reversed(convs[:i]):
                if prev["role"] == "user":
                    user_query = prev["content"]
                    break

            if is_after_tool and not think_text:
                # ツール後・think無し → 生成
                tool_result = convs[i-1].get("content", "")
                new_think = generate_final_think(tool_name, tool_result, user_query)
            elif len(think_text) < 80:
                # thin think → 拡充
                new_think = expand_thin_think(think_text, tool_name, user_query)
            else:
                continue

            new_msg = dict(msg)
            new_msg["content"] = inject_think(content, new_think)
            new_convs[i] = new_msg
            changed = True

        new_item = dict(item)
        new_item["conversations"] = new_convs
        result.append(new_item)
        if changed:
            modified += 1

    out = os.path.join(script_dir, args.output)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False)

    print(f"完了: {len(result)}件 (修正: {modified}件) → {out}")


if __name__ == "__main__":
    main()
