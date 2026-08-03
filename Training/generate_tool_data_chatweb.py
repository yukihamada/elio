#!/usr/bin/env python3
"""
ChatWeb.ai Tool Calling Training Data Generator
=================================================

Generates ~2,000 training examples for 15 chatweb.ai tools.
Each example includes Japanese thinking + tool_call + tool_result + response.

Usage:
    python generate_tool_data_chatweb.py --output tool_data.json
    python generate_tool_data_chatweb.py --output tool_data.json --examples_per_tool 200
"""

import argparse
import json
import random
import os

# ─── Tool Definitions (15 base tools from chatweb.ai) ───

TOOLS = {
    "web_search": {
        "description": "Web検索を実行する",
        "parameters": {"query": "str"},
        "examples": [
            ("最新のiPhone情報を調べて", {"query": "iPhone 最新 2026"}, '{"results": [{"title": "iPhone 18発表", "snippet": "Apple が iPhone 18 を発表しました。A20チップ搭載で..."}]}', "最新のiPhone 18が発表されています。A20チップを搭載し、パフォーマンスが大幅に向上しています。"),
            ("Pythonの最新バージョンは？", {"query": "Python 最新バージョン 2026"}, '{"results": [{"title": "Python 3.14 Released", "snippet": "Python 3.14.0 が正式リリースされました"}]}', "Pythonの最新バージョンは **3.14** です。"),
            ("東京オリンピック2024の結果", {"query": "東京オリンピック 2024 結果"}, '{"results": [{"title": "2024パリオリンピック結果", "snippet": "2024年はパリオリンピックでした。日本は金メダル20個..."}]}', "2024年のオリンピックはパリで開催され、日本は金メダル20個を獲得しました。"),
            ("Rustの学習リソース", {"query": "Rust プログラミング 学習 おすすめ"}, '{"results": [{"title": "Rust入門ガイド", "snippet": "The Rust Programming Language（通称The Book）が公式リソースです"}]}', "Rustの学習には公式の「The Rust Programming Language」（通称The Book）がおすすめです。無料でオンラインで読めます。"),
            ("ChatGPTとClaudeの比較", {"query": "ChatGPT Claude 比較 2026"}, '{"results": [{"title": "AIアシスタント比較", "snippet": "ChatGPTとClaudeはどちらも高性能なAIアシスタントです..."}]}', "ChatGPTとClaudeはどちらも高性能なAIアシスタントです。ChatGPTは汎用性が高く、Claudeは長文理解と安全性に強みがあります。"),
        ],
    },
    "read_webpage": {
        "description": "Webページの内容を読み取る",
        "parameters": {"url": "str"},
        "examples": [
            ("https://example.com の内容を読んで", {"url": "https://example.com"}, '{"title": "Example Domain", "content": "This domain is for use in illustrative examples..."}', "example.com は説明用のドメインで、ドキュメントやチュートリアルで使用するために予約されています。"),
            ("このページの内容を要約して: https://news.example.com/article1", {"url": "https://news.example.com/article1"}, '{"title": "AI最新動向", "content": "2026年のAI業界は大きな変革期を迎えています。オンデバイスAIの普及が加速し..."}', "この記事は2026年のAI業界の変革について述べています。特にオンデバイスAIの普及が加速しているとのことです。"),
            ("https://docs.python.org/3/tutorial/ を確認して", {"url": "https://docs.python.org/3/tutorial/"}, '{"title": "The Python Tutorial", "content": "Python is an easy to learn, powerful programming language..."}', "Python公式チュートリアルは、Pythonが学びやすく強力なプログラミング言語であることを紹介し、基本文法からデータ構造まで体系的に解説しています。"),
        ],
    },
    "calculator": {
        "description": "数学計算を実行する",
        "parameters": {"expression": "str"},
        "examples": [
            ("123 × 456 は？", {"expression": "123 * 456"}, '{"result": 56088}', "123 × 456 = **56,088** です。"),
            ("消費税込みで980円の商品、税抜き価格は？", {"expression": "980 / 1.10"}, '{"result": 890.909090909}', "税抜き価格は約 **891円** です（消費税10%の場合）。"),
            ("円周率 × 5の2乗", {"expression": "3.14159265 * 5 ** 2"}, '{"result": 78.5398163}', "π × 5² = 約 **78.54** です。これは半径5の円の面積に相当します。"),
            ("2の32乗は？", {"expression": "2 ** 32"}, '{"result": 4294967296}', "2の32乗は **4,294,967,296**（約43億）です。"),
            ("√144", {"expression": "144 ** 0.5"}, '{"result": 12.0}', "√144 = **12** です。"),
        ],
    },
    "weather": {
        "description": "天気情報を取得する",
        "parameters": {"location": "str"},
        "examples": [
            ("東京の天気は？", {"location": "東京"}, '{"location": "東京", "temperature": 18, "condition": "晴れ", "humidity": 45}', "東京の現在の天気は**晴れ**で、気温は18℃、湿度は45%です。"),
            ("大阪の今日の天気を教えて", {"location": "大阪"}, '{"location": "大阪", "temperature": 20, "condition": "曇り", "humidity": 60}', "大阪の天気は**曇り**で、気温は20℃、湿度は60%です。"),
            ("札幌は雪降ってる？", {"location": "札幌"}, '{"location": "札幌", "temperature": -2, "condition": "雪", "humidity": 75}', "札幌は現在**雪**が降っています。気温は-2℃です。暖かくしてお過ごしください。"),
            ("沖縄の気温は？", {"location": "沖縄"}, '{"location": "沖縄", "temperature": 25, "condition": "晴れ", "humidity": 70}', "沖縄の気温は**25℃**で、晴れています。"),
            ("New Yorkの天気", {"location": "New York"}, '{"location": "New York", "temperature": 10, "condition": "Rain", "humidity": 80}', "ニューヨークの天気は**雨**で、気温は10℃です。傘をお持ちください。"),
        ],
    },
    "translate": {
        "description": "テキストを翻訳する",
        "parameters": {"text": "str", "target_lang": "str"},
        "examples": [
            ("Hello, how are you? を日本語に", {"text": "Hello, how are you?", "target_lang": "ja"}, '{"translated": "こんにちは、お元気ですか？"}', "「Hello, how are you?」の日本語訳は「**こんにちは、お元気ですか？**」です。"),
            ("ありがとうございますを英語で", {"text": "ありがとうございます", "target_lang": "en"}, '{"translated": "Thank you very much."}', "「ありがとうございます」は英語で「**Thank you very much.**」です。"),
            ("おはようを中国語で", {"text": "おはよう", "target_lang": "zh"}, '{"translated": "早上好"}', "「おはよう」は中国語で「**早上好**」（ザオシャンハオ）です。"),
            ("Je t'aime の意味は？", {"text": "Je t'aime", "target_lang": "ja"}, '{"translated": "愛しています"}', "「Je t'aime」はフランス語で「**愛しています**」という意味です。"),
        ],
    },
    "wikipedia": {
        "description": "Wikipediaで情報を検索する",
        "parameters": {"query": "str"},
        "examples": [
            ("アインシュタインについて教えて", {"query": "アルベルト・アインシュタイン"}, '{"title": "アルベルト・アインシュタイン", "summary": "アルベルト・アインシュタイン（1879-1955）はドイツ生まれの理論物理学者。相対性理論の提唱者として知られる。"}', "アルベルト・アインシュタイン（1879-1955）はドイツ生まれの理論物理学者です。特殊相対性理論と一般相対性理論を提唱し、1921年にノーベル物理学賞を受賞しました。"),
            ("源氏物語って何？", {"query": "源氏物語"}, '{"title": "源氏物語", "summary": "源氏物語は平安時代中期に紫式部によって書かれた長編物語。世界最古の長編小説とも言われる。"}', "源氏物語は平安時代中期に**紫式部**によって書かれた長編物語です。世界最古の長編小説とも言われ、光源氏の生涯を中心に描いています。"),
            ("ブロックチェーンの仕組み", {"query": "ブロックチェーン"}, '{"title": "ブロックチェーン", "summary": "ブロックチェーンは分散型台帳技術。取引データをブロックとしてチェーン状につなげて管理する。"}', "ブロックチェーンは**分散型台帳技術**です。取引データをブロックとしてチェーン状につなげ、ネットワーク参加者全員で共有・検証することで、改ざんが極めて困難な仕組みを実現しています。"),
        ],
    },
    "datetime": {
        "description": "日付・時刻の計算を行う",
        "parameters": {"operation": "str", "value": "str"},
        "examples": [
            ("今日から100日後は何月何日？", {"operation": "add_days", "value": "100"}, '{"result": "2026-06-12", "day_of_week": "金曜日"}', "今日から100日後は **2026年6月12日（金曜日）** です。"),
            ("2026年のクリスマスは何曜日？", {"operation": "day_of_week", "value": "2026-12-25"}, '{"result": "金曜日"}', "2026年のクリスマス（12月25日）は**金曜日**です。"),
            ("今年は閏年？", {"operation": "is_leap_year", "value": "2026"}, '{"result": false}', "2026年は閏年**ではありません**。次の閏年は2028年です。"),
        ],
    },
    "create_qr": {
        "description": "QRコードを生成する",
        "parameters": {"content": "str"},
        "examples": [
            ("https://example.com のQRコードを作って", {"content": "https://example.com"}, '{"qr_url": "https://api.chatweb.ai/qr/abc123.png"}', "QRコードを生成しました！こちらからアクセスできます。スマートフォンのカメラで読み取ってください。"),
            ("WiFiのQRコードを作って。SSID: MyWiFi, パスワード: pass1234", {"content": "WIFI:T:WPA;S:MyWiFi;P:pass1234;;"}, '{"qr_url": "https://api.chatweb.ai/qr/wifi456.png"}', "WiFi接続用のQRコードを生成しました。スマートフォンのカメラで読み取ると、自動的にWiFiに接続できます。"),
            ("名刺のQRコードを作って。田中太郎、example@mail.com", {"content": "BEGIN:VCARD\nFN:田中太郎\nEMAIL:example@mail.com\nEND:VCARD"}, '{"qr_url": "https://api.chatweb.ai/qr/vcard789.png"}', "名刺用のQRコードを生成しました。読み取ると連絡先情報が自動的に登録されます。"),
        ],
    },
    "news_search": {
        "description": "最新ニュースを検索する",
        "parameters": {"query": "str", "category": "str"},
        "examples": [
            ("今日のテクノロジーニュース", {"query": "テクノロジー", "category": "technology"}, '{"articles": [{"title": "AI半導体の需要が急増", "source": "日経", "summary": "2026年、AI向け半導体の需要は前年比50%増..."}]}', "テクノロジー関連の最新ニュースです。AI半導体の需要が前年比50%増と急増しています。"),
            ("スポーツの最新ニュース", {"query": "スポーツ", "category": "sports"}, '{"articles": [{"title": "大谷翔平、50本塁打達成", "source": "スポーツ報知", "summary": "ドジャースの大谷翔平選手が今季50本目のホームランを達成..."}]}', "スポーツの最新ニュースです。ドジャースの大谷翔平選手が今季50本目のホームランを達成しました。"),
        ],
    },
    "code_execute": {
        "description": "コードを実行する",
        "parameters": {"language": "str", "code": "str"},
        "examples": [
            ("1から100までの素数を列挙して", {"language": "python", "code": "primes = [n for n in range(2, 101) if all(n % i != 0 for i in range(2, int(n**0.5)+1))]\nprint(primes)"}, '{"output": "[2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]", "exit_code": 0}', "1から100までの素数は以下の25個です：\n2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97"),
            ("フィボナッチ数列の最初の10個", {"language": "python", "code": "fib = [0, 1]\nfor _ in range(8): fib.append(fib[-1] + fib[-2])\nprint(fib)"}, '{"output": "[0, 1, 1, 2, 3, 5, 8, 13, 21, 34]", "exit_code": 0}', "フィボナッチ数列の最初の10個は：\n0, 1, 1, 2, 3, 5, 8, 13, 21, 34"),
            ("Hello Worldをシェルで", {"language": "shell", "code": "echo 'Hello, World!'"}, '{"output": "Hello, World!", "exit_code": 0}', "シェルコマンドを実行しました。出力：`Hello, World!`"),
        ],
    },
    "file_read": {
        "description": "サンドボックス内のファイルを読む",
        "parameters": {"path": "str"},
        "examples": [
            ("data.csvの中身を見せて", {"path": "/tmp/sandbox/data.csv"}, '{"content": "name,age,city\\n田中,25,東京\\n鈴木,30,大阪\\n佐藤,28,名古屋"}', "data.csvの内容です：\n\n| name | age | city |\n|------|-----|------|\n| 田中 | 25 | 東京 |\n| 鈴木 | 30 | 大阪 |\n| 佐藤 | 28 | 名古屋 |"),
            ("config.jsonを読んで", {"path": "/tmp/sandbox/config.json"}, '{"content": "{\\n  \\"api_key\\": \\"***\\",\\n  \\"debug\\": true\\n}"}', "config.jsonの内容です：デバッグモードが有効になっています。"),
        ],
    },
    "file_write": {
        "description": "サンドボックスにファイルを書き込む",
        "parameters": {"path": "str", "content": "str"},
        "examples": [
            ("メモを保存して。内容：買い物リスト - 牛乳、卵、パン", {"path": "/tmp/sandbox/memo.txt", "content": "買い物リスト\n- 牛乳\n- 卵\n- パン"}, '{"success": true, "path": "/tmp/sandbox/memo.txt"}', "メモを保存しました。ファイル名: memo.txt"),
            ("HTMLファイルを作って", {"path": "/tmp/sandbox/index.html", "content": "<!DOCTYPE html>\n<html>\n<head><title>Hello</title></head>\n<body><h1>Hello World</h1></body>\n</html>"}, '{"success": true, "path": "/tmp/sandbox/index.html"}', "HTMLファイルを作成しました。基本的なHello Worldページです。"),
        ],
    },
    "file_list": {
        "description": "ディレクトリの内容を一覧表示する",
        "parameters": {"path": "str"},
        "examples": [
            ("サンドボックスにどんなファイルがある？", {"path": "/tmp/sandbox/"}, '{"files": ["data.csv", "memo.txt", "config.json"], "directories": ["output"]}', "サンドボックスには以下のファイルがあります：\n- data.csv\n- memo.txt\n- config.json\n- output/ (フォルダ)"),
        ],
    },
    "image_generate": {
        "description": "画像を生成する",
        "parameters": {"prompt": "str", "style": "str"},
        "examples": [
            ("富士山の水彩画を描いて", {"prompt": "Mount Fuji watercolor painting, traditional Japanese style", "style": "watercolor"}, '{"image_url": "https://image.pollinations.ai/prompt/mount-fuji-watercolor"}', "富士山の水彩画を生成しました。伝統的な日本画の雰囲気を取り入れています。"),
            ("かわいい猫のイラスト", {"prompt": "cute kawaii cat illustration, anime style", "style": "anime"}, '{"image_url": "https://image.pollinations.ai/prompt/cute-kawaii-cat"}', "かわいい猫のイラストを生成しました。"),
            ("宇宙の壁紙を作って", {"prompt": "deep space nebula, stars, cosmic wallpaper, 4K", "style": "photorealistic"}, '{"image_url": "https://image.pollinations.ai/prompt/deep-space-nebula"}', "宇宙をテーマにした壁紙を生成しました。星雲と星々の美しいイメージです。"),
        ],
    },
    "image_analyze": {
        "description": "画像を分析する",
        "parameters": {"image_url": "str", "question": "str"},
        "examples": [
            ("この画像に何が写ってる？", {"image_url": "https://example.com/photo.jpg", "question": "この画像に何が写っていますか？"}, '{"description": "公園で遊ぶ子供たちの写真です。ブランコや滑り台が見えます。背景には桜の木があり、春の季節と思われます。"}', "この画像には**公園で遊ぶ子供たち**が写っています。ブランコや滑り台が見え、背景の桜の木から春の季節のようです。"),
            ("この料理は何？", {"image_url": "https://example.com/food.jpg", "question": "この料理は何ですか？"}, '{"description": "これは日本のラーメンです。豚骨ベースのスープに細麺、チャーシュー、煮卵、海苔がトッピングされています。"}', "これは**豚骨ラーメン**です。チャーシュー、煮卵、海苔がトッピングされた本格的な一杯ですね。"),
        ],
    },
}

# ─── Thinking templates for tool selection ───

THINKING_TEMPLATES = {
    "web_search": [
        "ウェブ検索で最新の情報を調べよう。",
        "この質問には最新情報が必要だ。web_searchツールを使おう。",
        "検索して確認しよう。",
    ],
    "read_webpage": [
        "指定されたURLのページ内容を読み取ろう。",
        "Webページの内容を確認する必要がある。read_webpageを使おう。",
    ],
    "calculator": [
        "計算が必要だ。calculatorツールで正確に計算しよう。",
        "数学的な計算はcalculatorツールに任せよう。",
        "正確な計算結果を出すためにcalculatorを使う。",
    ],
    "weather": [
        "天気情報が必要だ。weatherツールで確認しよう。",
        "天気を聞かれている。weatherツールを使おう。",
    ],
    "translate": [
        "翻訳が必要だ。translateツールを使おう。",
        "他の言語への翻訳にはtranslateツールが適切。",
    ],
    "wikipedia": [
        "この件についてWikipediaで確認しよう。",
        "百科事典的な情報はwikipediaツールで調べよう。",
    ],
    "datetime": [
        "日付の計算が必要。datetimeツールを使おう。",
        "カレンダー関連の質問だ。datetimeツールで確認しよう。",
    ],
    "create_qr": [
        "QRコードの生成が必要。create_qrツールを使おう。",
        "QRコードを作成するためにcreate_qrを使う。",
    ],
    "news_search": [
        "最新ニュースを検索しよう。news_searchツールを使う。",
        "ニュースの検索にはnews_searchツールが適切。",
    ],
    "code_execute": [
        "コードを実行して確認しよう。code_executeツールを使う。",
        "プログラムを書いて実行すれば正確な結果が得られる。",
    ],
    "file_read": [
        "ファイルの内容を読み取ろう。file_readツールを使う。",
        "指定されたファイルを読む必要がある。",
    ],
    "file_write": [
        "ファイルに書き込もう。file_writeツールを使う。",
        "データをファイルに保存する必要がある。",
    ],
    "file_list": [
        "ディレクトリの内容を確認しよう。file_listツールを使う。",
    ],
    "image_generate": [
        "画像生成が必要だ。image_generateツールを使おう。",
        "イラストや画像を作成するにはimage_generateツールを使う。",
    ],
    "image_analyze": [
        "画像を分析する必要がある。image_analyzeツールを使おう。",
        "画像の内容を確認するためにimage_analyzeを使う。",
    ],
}

# ─── Additional query variations for augmentation ───

QUERY_VARIATIONS = {
    "web_search": [
        ("日本の出生率の最新データ", {"query": "日本 出生率 最新 2026"}, '{"results": [{"title": "出生率1.15に低下", "snippet": "厚生労働省の発表によると..."}]}', "日本の出生率は最新のデータで**1.15**と発表されています。"),
        ("Flutterの最新バージョンは", {"query": "Flutter latest version 2026"}, '{"results": [{"title": "Flutter 4.0 Release", "snippet": "Flutter 4.0 brings major performance improvements..."}]}', "Flutterの最新バージョンは**4.0**です。大幅なパフォーマンス改善が含まれています。"),
        ("OpenAIの最新ニュース", {"query": "OpenAI 最新ニュース 2026"}, '{"results": [{"title": "OpenAI GPT-5発表", "snippet": "OpenAIがGPT-5を正式発表しました"}]}', "OpenAIがGPT-5を正式に発表しました。"),
        ("量子コンピュータの進展", {"query": "量子コンピュータ 最新 進展"}, '{"results": [{"title": "Googleが量子超越性を実証", "snippet": "1000量子ビットの達成により..."}]}', "量子コンピュータの分野では、Googleが1000量子ビットを達成し、量子超越性を実証しました。"),
        ("ビットコインの現在価格", {"query": "ビットコイン 価格 現在"}, '{"results": [{"title": "BTC価格情報", "snippet": "ビットコインは現在約15万ドルで推移..."}]}', "ビットコインは現在約**15万ドル**で推移しています。仮想通貨市場は変動が大きいのでご注意ください。"),
    ],
    "calculator": [
        ("35%引きで7,800円の商品の価格は？", {"expression": "7800 * (1 - 0.35)"}, '{"result": 5070.0}', "35%引きで **5,070円** です。"),
        ("BMIを計算して。身長170cm、体重65kg", {"expression": "65 / (1.70 ** 2)"}, '{"result": 22.49}', "BMIは約 **22.5** です。標準範囲（18.5〜25.0）内で健康的です。"),
        ("1マイルは何キロ？3マイルをキロに変換して", {"expression": "3 * 1.60934"}, '{"result": 4.82802}', "3マイルは約 **4.83キロメートル** です。"),
        ("月利0.5%で100万円を1年間預けたら？", {"expression": "1000000 * (1 + 0.005) ** 12"}, '{"result": 1061677.81}', "月利0.5%で100万円を1年間預けると、約 **1,061,678円** になります（複利計算）。"),
    ],
    "weather": [
        ("京都の天気を教えて", {"location": "京都"}, '{"location": "京都", "temperature": 22, "condition": "晴れ", "humidity": 50}', "京都の天気は**晴れ**で、気温は22℃です。お出かけ日和ですね。"),
        ("明日名古屋は雨？", {"location": "名古屋"}, '{"location": "名古屋", "temperature": 16, "condition": "雨", "humidity": 85}', "名古屋は**雨**の予報です。気温は16℃で、湿度が高くなっています。傘をお忘れなく。"),
        ("ロンドンの気温", {"location": "London"}, '{"location": "London", "temperature": 12, "condition": "Cloudy", "humidity": 70}', "ロンドンの気温は**12℃**で、曇りです。"),
    ],
    "translate": [
        ("美しい花を韓国語で", {"text": "美しい花", "target_lang": "ko"}, '{"translated": "아름다운 꽃"}', "「美しい花」は韓国語で「**아름다운 꽃**」（アルムダウン コッ）です。"),
        ("I love sushiを日本語に", {"text": "I love sushi", "target_lang": "ja"}, '{"translated": "私はお寿司が大好きです"}', "「I love sushi」は日本語で「**私はお寿司が大好きです**」です。"),
    ],
    "code_execute": [
        ("現在の日時をPythonで表示して", {"language": "python", "code": "from datetime import datetime\nprint(datetime.now().strftime('%Y-%m-%d %H:%M:%S'))"}, '{"output": "2026-03-04 15:30:00", "exit_code": 0}', "現在の日時は `2026-03-04 15:30:00` です。"),
        ("ランダムなパスワードを生成して", {"language": "python", "code": "import random, string\npw = ''.join(random.choices(string.ascii_letters + string.digits + '!@#$%', k=16))\nprint(pw)"}, '{"output": "Kx7#mPq2Ld9%RfWn", "exit_code": 0}', "ランダムなパスワードを生成しました：`Kx7#mPq2Ld9%RfWn`（16文字、英数字+記号）"),
    ],
    "image_generate": [
        ("日本庭園のイラスト", {"prompt": "beautiful Japanese garden, zen garden, koi pond, sakura trees", "style": "illustration"}, '{"image_url": "https://image.pollinations.ai/prompt/japanese-garden"}', "日本庭園のイラストを生成しました。池と桜の木がある禅の庭園です。"),
        ("サイバーパンクな東京の夜景", {"prompt": "cyberpunk Tokyo nightscape, neon lights, futuristic city", "style": "digital art"}, '{"image_url": "https://image.pollinations.ai/prompt/cyberpunk-tokyo"}', "サイバーパンク風の東京夜景を生成しました。ネオンライトが輝く未来都市のイメージです。"),
    ],
}

# ─── No-tool examples (model should NOT call tools) ───

NO_TOOL_EXAMPLES = [
    ("こんにちは！", "挨拶されている。ツールは不要。フレンドリーに返答しよう。", "こんにちは！何かお手伝いできることはありますか？"),
    ("ありがとう", "感謝されている。ツールは不要。", "どういたしまして！また何かあればお気軽にどうぞ。"),
    ("1+1は？", "簡単な計算なので、ツールを使わずに直接答えられる。", "1+1 = **2** です。"),
    ("プログラミングって楽しい？", "意見を求められている。ツールは不要。", "プログラミングは楽しいですよ！自分のアイデアを形にできるのが醍醐味です。最初は難しく感じるかもしれませんが、少しずつできることが増えていく喜びがあります。"),
    ("おやすみなさい", "お休みの挨拶。ツールは不要。", "おやすみなさい！ゆっくり休んでくださいね。"),
    ("元気？", "体調を聞かれている。ツールは不要。", "はい、元気です！何かお手伝いできることはありますか？"),
    ("AIについてどう思う？", "意見を求められている。ツールは不要。自分の見解を述べる。", "AIは人間の生活をより便利にする素晴らしい技術だと思います。ただし、倫理的な配慮やプライバシーの保護も大切です。人間とAIが協力してより良い未来を作っていけるといいですね。"),
]


def create_tool_example(tool_name: str, query: str, args: dict, result: str, response: str) -> dict:
    """Create a single tool calling training example."""
    thinking = random.choice(THINKING_TEMPLATES[tool_name])

    tool_call_json = json.dumps({"name": tool_name, "arguments": args}, ensure_ascii=False)

    return {
        "conversations": [
            {"role": "user", "content": query},
            {
                "role": "assistant",
                "content": f"<think>\n{thinking}\n</think>\n\n<tool_call>\n{tool_call_json}\n</tool_call>",
            },
            {"role": "tool", "name": tool_name, "content": result},
            {"role": "assistant", "content": response},
        ]
    }


def create_no_tool_example(query: str, thinking: str, response: str) -> dict:
    """Create a no-tool example (model should respond directly)."""
    return {
        "conversations": [
            {"role": "user", "content": query},
            {"role": "assistant", "content": f"<think>\n{thinking}\n</think>\n\n{response}"},
        ]
    }


def generate_all_data(examples_per_tool: int = 133) -> list:
    """Generate training data for all tools."""
    all_data = []

    for tool_name, tool_info in TOOLS.items():
        base_examples = tool_info["examples"]
        extra_examples = QUERY_VARIATIONS.get(tool_name, [])
        all_examples = base_examples + extra_examples

        # Generate requested number of examples per tool (cycling through templates)
        for i in range(examples_per_tool):
            idx = i % len(all_examples)
            query, args, result, response = all_examples[idx]

            # Add slight variations for duplicate indices
            if i >= len(all_examples):
                query = random.choice([
                    query,
                    query + "？",
                    query.replace("は", "って"),
                    "ねえ、" + query,
                    query + "を教えて",
                ])

            example = create_tool_example(tool_name, query, args, result, response)
            all_data.append(example)

    # Add no-tool examples (10% of total)
    no_tool_count = len(all_data) // 10
    for i in range(no_tool_count):
        idx = i % len(NO_TOOL_EXAMPLES)
        query, thinking, response = NO_TOOL_EXAMPLES[idx]
        example = create_no_tool_example(query, thinking, response)
        all_data.append(example)

    random.shuffle(all_data)
    return all_data


def main():
    parser = argparse.ArgumentParser(description="Generate tool calling training data for chatweb.ai")
    parser.add_argument("--output", type=str, default="tool_data.json", help="Output file path")
    parser.add_argument("--examples_per_tool", type=int, default=133, help="Examples per tool (~2000 total for 15 tools)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    random.seed(args.seed)

    print(f"Generating tool calling data ({args.examples_per_tool} examples × 15 tools)...")
    data = generate_all_data(args.examples_per_tool)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, args.output)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    tool_counts = {}
    no_tool_count = 0
    for item in data:
        has_tool = any(m.get("role") == "tool" for m in item["conversations"])
        if has_tool:
            tool_name = next(m["name"] for m in item["conversations"] if m.get("role") == "tool")
            tool_counts[tool_name] = tool_counts.get(tool_name, 0) + 1
        else:
            no_tool_count += 1

    print(f"\nGenerated {len(data)} examples total:")
    for tool, count in sorted(tool_counts.items()):
        print(f"  {tool}: {count}")
    print(f"  (no tool): {no_tool_count}")
    print(f"\nSaved to: {output_path}")


if __name__ == "__main__":
    main()
