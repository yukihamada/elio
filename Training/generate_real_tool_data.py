#!/usr/bin/env python3
"""
generate_real_tool_data.py — 実ツール結果を使った学習データ生成
=================================================================
Wikipedia / Jina / 計算機 / 日時 / OpenWeatherMap の実 API を叩いて
リアルなツール結果を含む会話データを生成する。

Gemini 2.0 Flash でクエリ生成 + アシスタント応答生成。
pip install requests openai
"""

import json
import math
import os
import re
import sys
import time
import urllib.parse
import argparse
import datetime
import random

import requests as req
import openai

# ── Gemini client ───────────────────────────────────────────────
def make_client():
    key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
    if not key:
        print("ERROR: GOOGLE_API_KEY が必要です", file=sys.stderr)
        sys.exit(1)
    return openai.OpenAI(
        api_key=key,
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
    ), "gemini-2.0-flash"


# ── 実ツール実行 ──────────────────────────────────────────────────
def tool_wikipedia(query: str) -> dict:
    """日本語 Wikipedia 検索API → サマリー取得の2段階"""
    try:
        # 1. 検索で正しい記事タイトルを取得
        r = req.get(
            "https://ja.wikipedia.org/w/api.php",
            params={
                "action": "query", "list": "search",
                "srsearch": query, "srlimit": 1,
                "format": "json", "utf8": 1,
            },
            headers={"User-Agent": "futa-training/1.0"},
            timeout=10,
        )
        results = r.json().get("query", {}).get("search", [])
        if not results:
            return {"error": f"no results for: {query}"}

        title = results[0]["title"]
        encoded = urllib.parse.quote(title)

        # 2. サマリー取得
        r2 = req.get(
            f"https://ja.wikipedia.org/api/rest_v1/page/summary/{encoded}",
            headers={"User-Agent": "futa-training/1.0"},
            timeout=10,
        )
        data = r2.json()
        extract = data.get("extract", "")
        if not extract:
            return {"error": "empty extract"}
        return {
            "title":   data.get("title", title),
            "summary": extract[:800],
            "url":     data.get("content_urls", {}).get("desktop", {}).get("page", ""),
        }
    except Exception as e:
        return {"error": str(e)}


def tool_weather_jina(location: str) -> dict:
    """wttr.in をJina経由でフェッチ（ローカルSSL問題を回避）"""
    try:
        encoded = urllib.parse.quote(f"{location}?format=j1&lang=ja")
        r = req.get(
            f"https://r.jina.ai/https://wttr.in/{encoded}",
            headers={"Accept": "text/plain", "User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        # JSON部分を抽出
        text = r.text
        start = text.find('{')
        end   = text.rfind('}')
        if start >= 0 and end > start:
            data = json.loads(text[start:end+1])
            cur = data["current_condition"][0]
            desc_list = cur.get("lang_ja", []) or cur.get("weatherDesc", [])
            desc = desc_list[0].get("value", "") if desc_list else ""
            return {
                "location":      location,
                "temperature_c": int(cur["temp_C"]),
                "feels_like_c":  int(cur["FeelsLikeC"]),
                "humidity_pct":  int(cur["humidity"]),
                "description":   desc,
                "wind_kmph":     int(cur["windspeedKmph"]),
            }
        return {"error": "parse failed"}
    except Exception as e:
        return {"error": str(e)}


def tool_calculator(expression: str) -> dict:
    """ローカル安全eval"""
    try:
        safe = {k: getattr(math, k) for k in dir(math) if not k.startswith("_")}
        safe["__builtins__"] = {}
        expr = expression.replace("^", "**").replace("×", "*").replace("÷", "/")
        result = eval(expr, safe)
        if isinstance(result, float) and result.is_integer():
            result = int(result)
        return {"result": result, "expression": expression}
    except Exception as e:
        return {"error": str(e)}


def tool_datetime(operation: str = "now", **kwargs) -> dict:
    """ローカル日時"""
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9)))
    weekdays = ["月曜日","火曜日","水曜日","木曜日","金曜日","土曜日","日曜日"]
    if operation == "now":
        return {
            "datetime": now.strftime("%Y-%m-%d %H:%M:%S"),
            "date":     now.strftime("%Y-%m-%d"),
            "time":     now.strftime("%H:%M"),
            "weekday":  weekdays[now.weekday()],
            "timezone": "Asia/Tokyo (JST, UTC+9)",
        }
    elif operation == "add_days":
        days = int(kwargs.get("days", 1))
        future = now + datetime.timedelta(days=days)
        return {
            "result_date": future.strftime("%Y-%m-%d"),
            "weekday":     weekdays[future.weekday()],
            "days_added":  days,
        }
    elif operation == "diff":
        d1 = datetime.datetime.strptime(kwargs.get("date1", now.strftime("%Y-%m-%d")), "%Y-%m-%d")
        d2 = datetime.datetime.strptime(kwargs.get("date2", now.strftime("%Y-%m-%d")), "%Y-%m-%d")
        return {"days_diff": abs((d2-d1).days), "date1": str(d1.date()), "date2": str(d2.date())}
    return {"datetime": now.strftime("%Y-%m-%d %H:%M:%S")}


def tool_web_fetch(url: str) -> dict:
    """Jina Reader"""
    try:
        r = req.get(
            f"https://r.jina.ai/{url}",
            headers={"Accept": "text/plain", "User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        return {"url": url, "content": r.text[:1500]}
    except Exception as e:
        return {"error": str(e)}


def tool_news_search(query: str = "", category: str = "") -> dict:
    """NHKニュースをJina経由でフェッチ"""
    try:
        search = query or category or "ニュース"
        encoded = urllib.parse.quote(search)
        r = req.get(
            f"https://r.jina.ai/https://news.google.com/rss/search?q={encoded}&hl=ja&gl=JP&ceid=JP:ja",
            headers={"Accept": "text/plain", "User-Agent": "Mozilla/5.0"},
            timeout=15,
        )
        # タイトルを抽出
        titles = re.findall(r'\*\*\*?\s*(.+?)\s*\n', r.text)[:5]
        if not titles:
            titles = re.findall(r'#+\s*(.+)', r.text)[:5]
        return {"query": search, "articles": [{"title": t} for t in titles], "count": len(titles)}
    except Exception as e:
        return {"error": str(e)}


REAL_TOOLS = {
    "wikipedia":   tool_wikipedia,
    "weather":     tool_weather_jina,
    "calculator":  tool_calculator,
    "datetime":    tool_datetime,
    "web_fetch":   tool_web_fetch,
    "news_search": tool_news_search,
}

# ── クエリテンプレート ────────────────────────────────────────────
QUERY_PROMPTS = {
    "wikipedia": [
        "日本の歴史上の人物、科学者、地名、文化・芸術のトピックについてWikipediaで調べたい質問を10個書いてください。具体的な人名・地名・作品名を使ってください。",
        "世界の国々、歴史的事件、科学技術の発明・発見についてWikipediaで調べたい質問を10個書いてください。",
        "日本の伝統文化、食文化、スポーツ選手についてWikipediaで調べたい質問を10個書いてください。",
    ],
    "weather": [
        "旅行・出張・イベントなど具体的なシナリオで天気を確認したい日本語の質問を10個書いてください。都市名を含めてください。",
    ],
    "calculator": [
        "税込み価格、割引後の金額、面積、速度・時間・距離、利率など実用的な計算が必要な日本語の質問を10個書いてください。具体的な数字を使ってください。",
        "複利計算、BMI、カロリー換算、為替換算など生活で使う計算の質問を10個書いてください。",
    ],
    "datetime": [
        "今日の日付・曜日・時刻、N日後/前の日付、誕生日までの日数、イベントまであと何日かを聞く日本語の質問を10個書いてください。",
    ],
    "web_fetch": [
        "特定のWebページのURL（NHKニュース、公式サイト等）を指定してその内容を教えてほしい、という日本語の質問を8個書いてください。URLも含めて書いてください。例: 「https://www3.nhk.or.jp/news/ の最新ニュースを教えて」",
    ],
    "news_search": [
        "最新ニュース、スポーツ結果、経済・政治・技術動向について知りたい日本語の質問を10個書いてください。具体的なキーワードを使ってください。",
    ],
}

# URLs for web_fetch
WEB_FETCH_URLS = [
    "https://www3.nhk.or.jp/news/",
    "https://www.asahi.com/",
    "https://xtech.nikkei.com/",
    "https://zenn.dev/trending",
]


# ── LLM呼び出しヘルパー ──────────────────────────────────────────
def call_gemini(client, model, prompt: str, max_tokens: int = 600, temp: float = 0.7) -> str | None:
    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
            temperature=temp,
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"  [WARN] LLMエラー: {e}", file=sys.stderr)
        time.sleep(2)
        return None


def generate_queries(client, model, tool: str) -> list[str]:
    prompt_list = QUERY_PROMPTS.get(tool, [])
    if not prompt_list:
        return []
    prompt = random.choice(prompt_list) + "\n\n各質問を1行ずつ、番号なしで出力してください。"
    text = call_gemini(client, model, prompt, max_tokens=800, temp=0.9)
    if not text:
        return []
    lines = text.split("\n")
    cleaned = []
    for l in lines:
        l = l.strip()
        # マークダウンリスト記号・番号を除去
        l = re.sub(r'^[\*\-\•・\d+\.\）\)]+\s*', '', l).strip()
        l = re.sub(r'^\*+\s*', '', l).strip()
        if len(l) > 8:
            cleaned.append(l)
    return cleaned[:10]


def generate_tool_call_args(client, model, tool: str, query: str) -> dict | None:
    if tool == "calculator":
        # 数式をクエリから直接抽出
        prompt = f"質問「{query}」に答えるための数式をPython eval()で計算できる形式で返してください。数式のみ（例: 1980*1.1 や sqrt(144)）。"
        text = call_gemini(client, model, prompt, max_tokens=50, temp=0.1)
        if text:
            expr = text.strip().strip('`').split('\n')[0]
            return {"name": "calculator", "arguments": {"expression": expr}}
    elif tool == "datetime":
        opts = [
            {"operation": "now"},
            {"operation": "add_days", "days": str(random.randint(1, 100))},
        ]
        return {"name": "datetime", "arguments": random.choice(opts)}
    elif tool == "wikipedia":
        # クエリからキーワード抽出
        prompt = f"質問「{query}」をWikipediaで検索するための最適なキーワードを1〜4語で返してください（語のみ）。"
        text = call_gemini(client, model, prompt, max_tokens=30, temp=0.2)
        if text:
            return {"name": "wikipedia", "arguments": {"query": text.strip().strip('「」')}}
    elif tool == "weather":
        prompt = f"質問「{query}」に含まれる都市名・地名を1つだけ返してください（地名のみ）。"
        text = call_gemini(client, model, prompt, max_tokens=20, temp=0.1)
        if text:
            return {"name": "weather", "arguments": {"location": text.strip()}}
    elif tool == "web_fetch":
        url = random.choice(WEB_FETCH_URLS)
        return {"name": "web_fetch", "arguments": {"url": url}}
    elif tool == "news_search":
        prompt = f"質問「{query}」に対するnews_search検索キーワードを3〜5語で返してください（語のみ）。"
        text = call_gemini(client, model, prompt, max_tokens=30, temp=0.2)
        if text:
            return {"name": "news_search", "arguments": {"query": text.strip()}}
    return None


def generate_conversation(client, model, query: str, tool_name: str,
                           tool_args: dict, tool_result: dict) -> dict | None:
    result_str = json.dumps(tool_result, ensure_ascii=False)[:600]
    prompt = f"""以下の会話に続くアシスタントの思考と応答を生成してください。

[USER]: {query}
[Tool ({tool_name})の実行結果]: {result_str}

以下の形式で出力してください:

CALL_THINK:
（{tool_name}ツールを呼び出す理由の思考。50〜150字）

FINAL_THINK:
（ツール結果を分析し回答する思考。100〜300字。結果の具体的な情報を言及すること）

RESPONSE:
（ユーザーへの自然な日本語回答。ツール結果の具体的な値を使って150〜300字）"""

    text = call_gemini(client, model, prompt, max_tokens=900, temp=0.75)
    if not text:
        return None

    call_think_m  = re.search(r'CALL_THINK:\s*(.*?)(?=FINAL_THINK:|$)', text, re.DOTALL)
    final_think_m = re.search(r'FINAL_THINK:\s*(.*?)(?=RESPONSE:|$)', text, re.DOTALL)
    response_m    = re.search(r'RESPONSE:\s*(.*?)$', text, re.DOTALL)

    if not (call_think_m and final_think_m and response_m):
        return None

    call_think  = re.sub(r'</?think>', '', call_think_m.group(1).strip()).strip()
    final_think = re.sub(r'</?think>', '', final_think_m.group(1).strip()).strip()
    response    = response_m.group(1).strip()

    if len(call_think) < 20 or len(final_think) < 50 or len(response) < 30:
        return None

    tool_call_json = json.dumps(
        {"name": tool_name, "arguments": tool_args},
        ensure_ascii=False,
    )
    assistant_call  = f"<think>\n{call_think}\n</think>\n\n<tool_call>\n{tool_call_json}\n</tool_call>"
    assistant_final = f"<think>\n{final_think}\n</think>\n\n{response}"

    return {
        "conversations": [
            {"role": "user",      "content": query},
            {"role": "assistant", "content": assistant_call},
            {"role": "tool",      "content": json.dumps(tool_result, ensure_ascii=False), "name": tool_name},
            {"role": "assistant", "content": assistant_final},
        ],
        "category": f"real_{tool_name}",
    }


def execute_tool(tool_name: str, arguments: dict) -> dict:
    fn = REAL_TOOLS.get(tool_name)
    if not fn:
        return {"error": f"unknown tool: {tool_name}"}
    try:
        return fn(**{k: v for k, v in arguments.items()})
    except TypeError:
        try:
            return fn(*list(arguments.values())[:1])
        except Exception as e:
            return {"error": str(e)}
    except Exception as e:
        return {"error": str(e)}


# ── メイン ───────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output",   default="real_tool_data.json")
    parser.add_argument("--per-tool", type=int, default=80)
    parser.add_argument("--tools",    nargs="+",
        default=["wikipedia", "calculator", "datetime", "web_fetch", "weather", "news_search"])
    args = parser.parse_args()

    client, model = make_client()
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)

    results = []
    done_queries: set[str] = set()
    if os.path.exists(output_path):
        with open(output_path, encoding="utf-8") as f:
            results = json.load(f)
        for item in results:
            done_queries.add(item["conversations"][0]["content"])
        print(f"再開: {len(results)}件 処理済み")

    for tool_name in args.tools:
        already = sum(1 for r in results if r.get("category") == f"real_{tool_name}")
        need    = args.per_tool - already
        if need <= 0:
            print(f"[{tool_name}] スキップ ({already}/{args.per_tool})")
            continue

        print(f"\n[{tool_name}] {need}件生成開始...")
        generated = 0
        fail_streak = 0

        while generated < need and fail_streak < 20:
            queries = generate_queries(client, model, tool_name)
            if not queries:
                fail_streak += 1
                time.sleep(2)
                continue

            for query in queries:
                if generated >= need:
                    break
                if query in done_queries:
                    continue

                # ツール引数生成
                tc = generate_tool_call_args(client, model, tool_name, query)
                if not tc:
                    fail_streak += 1
                    continue

                # 実ツール実行
                tool_result = execute_tool(tool_name, tc.get("arguments", {}))
                if "error" in tool_result:
                    print(f"  [SKIP] {tool_name} error: {tool_result['error'][:60]}")
                    fail_streak += 1
                    continue

                # 会話生成
                conv = generate_conversation(
                    client, model, query, tool_name,
                    tc.get("arguments", {}), tool_result,
                )
                if not conv:
                    fail_streak += 1
                    continue

                results.append(conv)
                done_queries.add(query)
                generated += 1
                fail_streak = 0
                print(f"  [{tool_name}] {generated}/{need}: {query[:55]}")

                if len(results) % 20 == 0:
                    _save(results, output_path)

                time.sleep(0.4)

        print(f"  [{tool_name}] 完了: {generated}件生成")
        _save(results, output_path)

    _save(results, output_path)
    print(f"\n完了: {len(results)}件 → {output_path}")
    _show_stats(results)


def _save(data: list, path: str):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def _show_stats(data: list):
    from collections import Counter
    cats = Counter(d.get("category", "unknown") for d in data)
    for c, n in sorted(cats.items()):
        print(f"  {c}: {n}件")


if __name__ == "__main__":
    main()
