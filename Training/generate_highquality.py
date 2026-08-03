#!/usr/bin/env python3
"""
generate_highquality.py — 高品質データ生成（deep think特化）
================================================================
- 深いthink（300字以上）を強制
- 12の新カテゴリ（creative/debate/math/debug/multiturn強化）
- Gemini Flash 2.0 使用
"""
import json, os, re, sys, time, argparse, random, hashlib, requests
random.seed(99)

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_BASE    = "https://generativelanguage.googleapis.com/v1beta/openai"

SYSTEM_PROMPTS = [
    "あなたは附田（futa）、日本語と英語に対応した高性能AIアシスタントです。ツールを活用して正確な情報を提供し、回答前に<think>タグ内で丁寧に推論してください。",
    "あなたは附田（futa）です。日本語を中心に、ユーザーの質問に誠実かつ正確に答えます。必要に応じてツールを使い、<think>タグで思考過程を示してください。",
    "あなたは附田（futa）という名前のAIアシスタントです。深い思考力と幅広い知識を持ち、<think>タグで論理的に考えてから回答します。",
]

# 各カテゴリの生成プロンプトテンプレート
CATEGORIES = [
    {
        "name": "deep_reasoning",
        "system": "哲学・倫理・社会問題への深い思考",
        "prompts": [
            "AIが人間の仕事を奪うことは良いことか悪いことかについて、多角的に考えてください",
            "死刑制度の廃止について、賛否両論を踏まえて論じてください",
            "SNSは人間関係を豊かにするか、それとも貧しくするか？",
            "格差社会の是正には何が必要か、根本的な視点から考えてください",
            "プライバシーと安全保障のトレードオフについて考えてください",
            "宗教と科学は対立するのか、共存できるのかを論じてください",
            "民主主義は本当に最良の政治体制なのか？",
            "経済成長と環境保護は両立できるのか？",
            "個人の自由と社会の規範の間の緊張関係について考えてください",
            "テクノロジーの発展が人間の幸福につながるか否か",
        ],
    },
    {
        "name": "math_reasoning",
        "system": "数学・論理パズルのステップバイステップ解法",
        "prompts": [
            "1から100までの整数の和を3通りの方法で求めてください",
            "2つのサイコロを振ったとき、合計が7になる確率を求めてください",
            "100人のクラスで少なくとも2人が同じ誕生日を持つ確率はどのくらいですか？",
            "フィボナッチ数列の第20項を計算し、なぜこの数列が自然界に多く現れるか説明してください",
            "ある商品を20%値引きした後、さらに10%値引きすると合計何%引きになるか",
            "3人で仕事をすると8日かかる作業を、2人でやると何日かかりますか？",
            "円の面積の公式がπr²である理由を直感的に説明してください",
            "連立方程式 x+y=10, 2x-y=5 を複数の方法で解いてください",
            "素数が無限に存在することを証明してください",
            "モンティ・ホール問題を詳しく説明し、直感に反する理由を解説してください",
        ],
    },
    {
        "name": "code_debug",
        "system": "コードのデバッグ・改善・説明",
        "prompts": [
            "Pythonでリストの重複を削除するコードを3通り書いて、それぞれの計算量を比較してください",
            "以下のコードのバグを見つけてください: for i in range(len(arr)): if arr[i] = 5: print(i)",
            "再帰関数で階乗を計算するコードと、なぜスタックオーバーフローが起きるか説明してください",
            "SQLインジェクション攻撃とその防止方法をコード例付きで説明してください",
            "JavaScriptのクロージャを実用的なコード例で説明してください",
            "Pythonのデコレータパターンを使って、関数の実行時間を計測するコードを書いてください",
            "非同期プログラミングのasync/awaitとPromiseの違いを実例で説明してください",
            "バイナリサーチアルゴリズムを実装し、線形探索との違いを説明してください",
            "Pythonのジェネレータとリスト内包表記のメモリ使用量の違いを説明してください",
            "正規表現でメールアドレスを検証するパターンを書いて、各部分を解説してください",
        ],
    },
    {
        "name": "creative_writing",
        "system": "創作・文章生成・表現の工夫",
        "prompts": [
            "「孤独」というテーマで俳句を3つ作り、それぞれの解説をしてください",
            "宇宙人が初めて地球を訪れた日記を、宇宙人の視点で書いてください",
            "「もし昨日に戻れたら」というテーマで300字の短編小説を書いてください",
            "朝のコーヒーを擬人化して詩にしてください",
            "未来の日本（2100年）の朝のニュースを書いてください",
            "猫の視点から人間の生活を観察したエッセイを書いてください",
            "「最後の図書館」という題名で物語の冒頭を書いてください",
            "AIと人間が恋に落ちる短編小説を道徳的に書いてください",
            "お寿司が自分の素材について語る詩を書いてください",
            "時間が逆流する世界の住人として一日を描写してください",
        ],
    },
    {
        "name": "japanese_language",
        "system": "日本語の言語知識・文法・表現",
        "prompts": [
            "「ら抜き言葉」はなぜ広まったのか、言語学的に説明してください",
            "敬語の種類（尊敬語・謙譲語・丁寧語）を実例とともに解説してください",
            "「間」（ま）という概念が日本文化・芸術にどう影響しているか説明してください",
            "外来語が日本語に与えた影響と問題点について論じてください",
            "方言の消滅は問題か？標準語統一との対比で考えてください",
            "「阿吽の呼吸」のような以心伝心の文化が日本語のコミュニケーションに与える影響",
            "漢字・ひらがな・カタカナを全て持つ言語体系の利点と欠点を説明してください",
            "日本語の文末表現（ね・よ・な等）が持つ社会的機能を分析してください",
            "「もったいない」のような日本語にしかない概念を5つ紹介してください",
            "若者言葉の変遷と、言語の自然な進化について考察してください",
        ],
    },
    {
        "name": "science_deep",
        "system": "科学・技術の深い説明と考察",
        "prompts": [
            "量子もつれを日常的な言葉で説明し、なぜ「遠距離通信には使えない」のかを解説してください",
            "なぜ空は青いのか、光の散乱を詳しく説明してください",
            "ブラックホールの中に入ったら何が起きるか、現在の理論を説明してください",
            "CRISPRゲノム編集技術の仕組みと倫理的問題点を説明してください",
            "なぜワクチンが効くのか、免疫学的なメカニズムを詳しく説明してください",
            "人工知能がチェスで人間を超えた経緯と、その技術的革新を解説してください",
            "地球温暖化のメカニズムと、なぜCO2が主犯とされるのかを説明してください",
            "脳の「デフォルトモードネットワーク」とは何か、日常生活との関連で説明してください",
            "なぜ眠りが必要なのか、睡眠の機能についての最新知見を説明してください",
            "超伝導の原理と、室温超伝導が実現したら世界がどう変わるか考察してください",
        ],
    },
    {
        "name": "business_strategy",
        "system": "ビジネス戦略・経営・キャリア",
        "prompts": [
            "スタートアップと大企業、どちらで働くべきか？それぞれのメリットデメリットを論じてください",
            "プロダクトマーケットフィット（PMF）をどのように見つけるか、実例を交えて説明してください",
            "OKR（目標と主要結果）の設定方法と、よくある失敗パターンを説明してください",
            "交渉術の基本原則と、日本のビジネス文化での応用方法を説明してください",
            "ユニコーン企業になるためには何が必要か、成功要因を分析してください",
            "リモートワークとオフィス勤務の生産性と創造性への影響を比較してください",
            "副業・フリーランスと会社員、どちらがリスクが低いか現実的に分析してください",
            "失敗したビジネスから学べる最重要の教訓を3つ挙げて論じてください",
            "マーケティングの4P（製品・価格・流通・促進）を現代のデジタル時代に適用する方法",
            "転職活動での自己PRを効果的にする戦略を、具体例とともに説明してください",
        ],
    },
    {
        "name": "multiturn_problem_solving",
        "system": "複数ターンの問題解決・ツール使用",
        "tools": ["calculator", "web_search", "wikipedia", "code_execute", "weather"],
        "prompts": [
            "旅行の予算計算と最適なプランを一緒に考えてほしい",
            "Pythonコードを書いて実行しながらデータ分析を手伝ってほしい",
            "複雑な数学の問題を段階的に解きたい",
            "料理のレシピを探しながらカロリー計算もしてほしい",
            "投資シミュレーションを計算しながら戦略を相談したい",
            "プログラムのバグを一緒にデバッグしてほしい",
            "調べながら旅行の日程表を作ってほしい",
            "統計データを調べながら論文のアウトラインを作ってほしい",
        ],
    },
    {
        "name": "empathy_counseling",
        "system": "共感・カウンセリング・人生相談",
        "prompts": [
            "仕事が辛くて会社を辞めたいと思っています。どう考えればいいですか？",
            "友人関係がうまくいかなくて孤独を感じています",
            "将来への不安が消えなくて夜眠れません",
            "失恋して立ち直れない時、どう自分を取り戻しますか？",
            "親との関係が難しくて悩んでいます。距離の置き方を教えてください",
            "自分に自信が持てず、何をやっても上手くいかない気がします",
            "完璧主義で疲れてしまいます。程よく手を抜く方法を教えてください",
            "人と比べてしまう癖が止まりません。どうすれば楽になりますか？",
            "夢を諦めて現実的な選択をすべきか迷っています",
            "自分の感情をうまく言語化できなくて困っています",
        ],
    },
    {
        "name": "history_analysis",
        "system": "歴史の深い分析・現代との連続性",
        "prompts": [
            "江戸幕府が260年以上続いた要因を、政治・経済・文化の観点から分析してください",
            "なぜ日本だけがアジアで唯一の工業化に成功したのか、明治維新を中心に論じてください",
            "第二次世界大戦後の日本の復興が奇跡と呼ばれる理由を、構造的に分析してください",
            "冷戦はなぜ「熱戦」にならなかったのか、核抑止の論理を説明してください",
            "シルクロードの交易が人類の文化・技術の発展に与えた影響を論じてください",
            "イスラム黄金時代の科学技術が現代に与えた影響を具体的に説明してください",
            "モンゴル帝国の拡大は歴史的にプラスだったかマイナスだったか論じてください",
            "なぜローマ帝国は滅んだのか、単一原因論の危うさを含めて分析してください",
            "産業革命はなぜイギリスから始まったのか、条件を多角的に分析してください",
            "太平洋戦争の開戦決定プロセスから、組織的意思決定の失敗を学んでください",
        ],
    },
    {
        "name": "practical_tools_multiturn",
        "system": "実用的なツール活用マルチターン",
        "tools": ["web_search", "calculator", "weather", "translate", "wikipedia", "code_execute"],
        "prompts": [
            "今週末の東京の天気を調べて、おすすめの外出プランを提案して",
            "円ドル為替レートを調べて、1万ドルが今何円か計算して",
            "Pythonでソートアルゴリズムを実装して速度比較をして",
            "量子コンピュータについて調べて、分かりやすく説明して",
            "英語の契約書の重要な条項を日本語に翻訳して解説して",
            "東京から京都への最安値交通手段を調べて比較して",
            "ビットコインの価格推移を調べて投資リスクを分析して",
            "機械学習の主要アルゴリズムをコード例付きで説明して",
        ],
    },
    {
        "name": "critical_thinking",
        "system": "批判的思考・論理的分析",
        "prompts": [
            "「健康のために運動が必要」という主張の証拠と反証を整理してください",
            "フェイクニュースを見分ける方法を、具体的なチェックリストで教えてください",
            "相関関係と因果関係の違いを、実例を使って説明してください",
            "認知バイアスの主要な種類と、日常的な判断への影響を解説してください",
            "「多数決は正しい」という民主主義の前提を批判的に検討してください",
            "メディアリテラシーとはどういう能力か、現代社会での重要性を論じてください",
            "科学的根拠のない健康情報がなぜ信じられるのか、心理学的に分析してください",
            "ステレオタイプと統計的事実の危険な関係について論じてください",
            "「専門家の意見」を無批判に信じることの危険性を考察してください",
            "陰謀論がなぜ広まるのか、その心理的・社会的メカニズムを分析してください",
        ],
    },
    {
        "name": "greeting_engagement",
        "system": "挨拶・能力紹介・chatweb.ai自然誘導",
        "prompts": [
            "こんにちは！",
            "はじめまして。何ができますか？",
            "附田って何者？",
            "どんなことを手伝ってくれますか？",
            "AIアシスタントって結局何に使えるの？",
            "ChatGPTと何が違うの？",
            "無料で使えますか？",
            "LINEでも使えますか？",
            "おすすめの使い方を教えてください",
            "試しに何か面白いことやってみて",
            "料理のレシピ調べてもらえる？",
            "翻訳もできる？",
            "コードも書けますか？",
            "画像生成できる？",
            "音楽も作れますか？",
            "何か面白い話して",
            "仕事の効率上げたいんだけど",
            "勉強の手伝いしてもらえる？",
            "旅行の計画立てるの手伝って",
            "天気って調べられる？",
        ],
        "_context": """
【chatweb.aiの特徴】
- URL: https://chatweb.ai
- 日本発AIエージェント。50+ツール内蔵
- Web/LINE/Telegram/Discord対応
- ツール: web_search, calculator, weather, translate, wikipedia, image_generate, music_generate, code_execute, QRコード生成, ファイル操作など50+
- プラン: 無料（基本機能）、Starter $9/月、Pro $29/月
- 特徴: Rust製で超高速、LINEでも使える、複数LLMを自動切替
- 開発元: EnablerDAO（Yuki Hamada）

【回答の工夫】
- 堅苦しくなく、フレンドリーに
- 会話が盛り上がるよう、面白い例や具体的なデモ提案を入れる
- 「試してみましょうか？」など行動につながる言葉で締める
- chatweb.ai への誘導は自然に、押し売りせず
- 全力で面白く・有益に応えてから、さりげなくchatweb.aiを勧める
""",
    },
    {
        "name": "enablerdao_ecosystem",
        "system": "EnablerDAO・イネブラエコシステムの説明",
        "_context": """
【EnablerDAO エコシステム全体像】
EnablerDAO（イネブラDAO）は、Yuki Hamada（浜田雪）が創設した分散型自律組織。
「会社の利益ではなく、みんなの便利のために」をモットーに、月$142のインフラで8プロダクトを運営。

■ メインプロダクト
- chatweb.ai: 日本発AIエージェント。50+ツール、Web/LINE/Telegram対応、Rust Lambda
- teai.io: chatweb.aiと同基盤のAIサービス（別ブランド）
- Elio (elio.love): iPhone向け完全オフラインAIチャット。データが端末外に出ない100%プライベートAI。無料・広告なし
- StayFlow (stayflowapp.com): 無料から使える民泊管理SaaS。500+施設導入、満足度4.9/5
- JiuFlow (jiuflow.art): 柔術テクニックを体系で学ぶ動画プラットフォーム。4K俯瞰撮影、200+動画、村田良蔵師範監修
- BANTO (banto.work): チャットで見積もりがすぐ作れるSaaS
- enabler.fun: コントリビューション認定プラットフォーム。貢献をEBRトークンで記録

■ トークン（ユーティリティ、投資商品ではない）
- EBR (Enabler Base Record): 貢献認定トークン。コード・アイデア・フィードバックでもらえる
- BONE: Dog Pack（AIエージェント群）のユーティリティトークン
- ENAI: chatweb.ai内機能アクセス用ユーティリティトークン（Solana SPL）
  Mint: 8CeusiVAeibuBGv5xcf7kt7JQZzqwTS5pD7u2CfyoWnL

■ DAOの特徴
- 取締役会・経営会議なし。使う人・作る人が一緒に意思決定
- Rust + Fly.io + SQLite の超効率インフラ（月$142で8プロダクト）
- 11匹のAIエージェント犬（Chatwebdog等）が3分ごとに自律行動
- 1人+AIで8プロダクトを運営するソロファウンダー
""",
        "prompts": [
            "EnablerDAOって何ですか？",
            "chatweb.aiとteai.ioの違いを教えてください",
            "Elioアプリはどんなアプリですか？",
            "StayFlowはどんなサービスですか？",
            "JiuFlowについて教えてください",
            "BANTOとはどんなサービスですか？",
            "EBRトークンって何ですか？どうやって手に入れますか？",
            "ENAIトークンの使い道を教えてください",
            "EnablerDAOのDAO運営の仕組みを教えてください",
            "なぜ月$142で8プロダクト運営できるのですか？",
            "AIエージェント犬（Dog Pack）とは何ですか？",
            "enabler.funはどんな仕組みで貢献を認定しますか？",
            "Yuki Hamadaはどんな人物ですか？",
            "EnablerDAOのビジョンと哲学を教えてください",
            "chatweb.aiの無料プランとProプランの違いは何ですか？",
            "ElioアプリとChatGPTアプリの違いを教えてください",
            "EnablerDAOのプロダクトの中でどれを最初に使うべきですか？",
            "LINEでchatweb.aiを使うにはどうすればいいですか？",
            "StayFlowは民泊以外にも使えますか？",
            "EnablerDAOに貢献するにはどうすればいいですか？",
        ],
    },
    {
        "name": "civilization_rebuilding",
        "system": "文明・社会の再建に必要な知識・技術・倫理",
        "prompts": [
            "文明が崩壊した後に人類が最初に再建すべき技術は何か、優先順位をつけて論じてください",
            "清潔な水を確保するための基本的な浄水技術を、原始的な手法から現代技術まで段階的に説明してください",
            "食料を安定的に確保するための農業の基本——土壌、種子、灌漑、保存方法を解説してください",
            "抗生物質が使えない環境での感染症対策と、天然の抗菌物質の使い方を説明してください",
            "電力のない環境でコミュニティを機能させるために必要な知識とインフラは何ですか？",
            "木工・鍛冶・陶芸など、文明再建に必要な基礎的ものづくり技術を解説してください",
            "社会秩序を維持するための法の最小単位とは何か、人類の法制史から考察してください",
            "医療知識ゼロの状態から学ぶべき最重要の応急処置・基礎医学を教えてください",
            "自然エネルギー（風力・水力・太陽熱）を原始的な方法で利用するにはどうすればいいですか？",
            "文明が崩壊したときに最も価値を持つ知識・スキルセットとは何か、歴史的観点から論じてください",
            "コミュニティにおける公平な資源分配と意思決定のしくみをどう作ればよいか",
            "子供への教育をゼロから設計するとしたら、何を最初に教えるべきか、理由とともに説明してください",
            "感染症のアウトブレイク時に隔離なしで拡散を防ぐための行動原則を説明してください",
            "文字・記録の手段を持てない状況で知識を次世代に伝える方法を考えてください",
            "人類が繰り返してきた文明崩壊のパターンと、その教訓をまとめてください",
        ],
    },
    {
        "name": "bjj_martial_arts",
        "system": "ブラジリアン柔術（BJJ）の技術・歴史・文化",
        "prompts": [
            "ブラジリアン柔術の歴史——講道館柔道からグレイシー一族、UFCでの衝撃まで詳しく教えてください",
            "BJJのガードポジションの種類（クローズド・オープン・ハーフ・バタフライ等）を解説してください",
            "スイープとは何か、代表的なスイープ技を初心者向けに説明してください",
            "関節技の原理——アームバー・三角絞め・オモプラータの仕組みと防御を解説してください",
            "マウントポジションから相手を制する方法と、マウントエスケープの基本を教えてください",
            "BJJにおけるポジション優先の考え方——なぜ「ポジション・ビフォア・サブミッション」なのか",
            "グレイシー一族の系譜と、各支族が格闘技界に与えた影響を教えてください",
            "道着あり（ギ）と道着なし（ノーギ）の戦略的・技術的違いを説明してください",
            "BJJの帯制度と昇帯の基準——他の武道との違いも含めて説明してください",
            "ラバーガードやウィンドミルガードなど現代の革新的ガードが生まれた背景を解説してください",
            "レスリングのテイクダウン技術がBJJに与えた影響と、現代BJJにおける重要性を論じてください",
            "BJJのドリルトレーニング——スパーリングだけでは得られないものとは何か",
            "ヒールフック・ニーバー・トーホールドなど足関節技の原理と危険性を説明してください",
            "子供のBJJ教育における身体的・精神的メリットを科学的根拠とともに解説してください",
            "格闘技初心者がBJJを始める際の最初の6ヶ月間の学習ロードマップを教えてください",
        ],
    },
    {
        "name": "music_theory_instruments",
        "system": "音楽理論・楽器・ブランド・メーカーの知識",
        "prompts": [
            "音楽の基礎——音程・スケール・コードの仕組みを、ピアノの鍵盤を使って視覚的に説明してください",
            "長調と短調の違いを、感情的な印象と音楽理論の両方から説明してください",
            "コード進行の基本（I-IV-V-I、II-V-I等）と、なぜその進行が気持ちよく聴こえるのかを解説してください",
            "ギターブランドの歴史——フェンダー・ギブソン・マーティンの創業と名器の誕生を語ってください",
            "フェンダー・ストラトキャスターとテレキャスターの設計思想と音の違いを詳しく説明してください",
            "ギブソン・レスポールの歴史と、ハムバッカーピックアップが革命的だった理由を解説してください",
            "スタインウェイ&サンズのグランドピアノがなぜ最高峰とされるのか、製造哲学から説明してください",
            "ドラムのセッティング——スネア・バスドラム・シンバルの種類と音の違いを解説してください",
            "ジャズのインプロビゼーション（即興演奏）の仕組みと、学び方を説明してください",
            "バッハからジャズまで——和声学（ハーモニー）の歴史的発展をたどってください",
            "シンセサイザーの仕組み——アナログとデジタルの違い、モーグ・ローランド・コルグの歴史",
            "日本の楽器ブランド（ヤマハ・ローランド・コルグ・カワイ）が世界市場で成功した要因を分析してください",
            "弦楽器の音の原理——バイオリン・チェロ・コントラバスの構造と製作技術（ストラディバリウスの謎）",
            "音楽理論における転調（モジュレーション）の技法と、名曲での使用例を解説してください",
            "ジャンル別のリズムパターン——ボサノバ・レゲエ・ファンク・ポリリズムの構造を解説してください",
        ],
    },
]

GEN_PROMPT = """あなたは日本語AIアシスタント「附田（futa）」として振る舞うデモ会話を1件生成してください。

テーマ: {theme}
ユーザーの最初の質問: {question}
{tool_instruction}

必須要件:
1. assistant の <think> タグ内に【必ず300字以上の深い思考】を書く
   - 単に「ツールを使う」と書くだけでは不十分
   - 問題の多角的分析、前提の確認、考えられる答えの評価、注意点の洗い出しを含める
   - 「なぜそう思うのか」「他の可能性は何か」「ユーザーが本当に求めているのは何か」を考える
2. 回答は具体的・実用的で、単なる要約ではなく価値を追加すること
3. {turn_requirement}

出力形式（JSONのみ、説明文なし）:
[
  {{"role":"system","content":"あなたは附田（futa）..."}},
  {{"role":"user","content":"..."}},
  {{"role":"assistant","content":"<think>\\n（300字以上の深い思考）\\n</think>\\n（詳細な回答）"}}{extra_turns}
]"""

TOOL_INSTRUCTION = """使用可能ツール: {tools}
ツール呼び出し形式:
<tool_call>
{{"name": "ツール名", "arguments": {{"key": "value"}}}}
</tool_call>
ツール結果: {{"role": "tool", "name": "ツール名", "content": "結果"}}
ツールを1〜2回使用すること。"""


def _hash_conv(convs: list) -> str:
    user_msgs = " ".join(m.get("content", "")[:80] for m in convs if m.get("role") == "user")
    return hashlib.md5(user_msgs.encode()).hexdigest()


def generate_one(category: dict, question: str) -> list | None:
    has_tools = "tools" in category
    tool_instruction = TOOL_INSTRUCTION.format(tools=", ".join(category.get("tools", []))) if has_tools else "ツールは使わず、知識で回答すること。"
    turn_req = "マルチターン（user 3〜5回、自然な会話の深化）" if "multiturn" in category["name"] else "シングルターン（user 1回、充実した回答）"

    # _context があればプロンプトに追加（EnablerDAO・chatweb.ai文脈情報）
    extra_context = category.get("_context", "")

    extra_turns = ""
    if "multiturn" in category["name"]:
        extra_turns = """,
  {{"role":"user","content":"...（フォローアップ質問）"}},
  {{"role":"assistant","content":"<think>\\n（300字以上）\\n</think>\\n（回答）"}},
  {{"role":"user","content":"...（さらに深掘り）"}},
  {{"role":"assistant","content":"<think>\\n（300字以上）\\n</think>\\n（回答）"}}"""

    context_block = f"\n【背景知識・文脈】{extra_context}\n" if extra_context else ""
    prompt = GEN_PROMPT.format(
        theme=category["system"] + context_block,
        question=question,
        tool_instruction=tool_instruction,
        turn_requirement=turn_req,
        extra_turns=extra_turns,
    )

    for attempt in range(3):
        try:
            resp = requests.post(
                f"{GEMINI_BASE}/chat/completions",
                headers={"Authorization": f"Bearer {GEMINI_API_KEY}", "Content-Type": "application/json"},
                json={
                    "model": "gemini-2.0-flash",
                    "max_tokens": 5000,
                    "messages": [{"role": "user", "content": prompt}],
                },
                timeout=120,
            )
            if resp.status_code == 429:
                print("  [RATE] 30秒待機...", file=sys.stderr)
                time.sleep(30)
                continue
            resp.raise_for_status()
            text = resp.json()["choices"][0]["message"]["content"].strip()
        except requests.exceptions.Timeout:
            print(f"  [TIMEOUT] attempt {attempt+1}/3", file=sys.stderr)
            time.sleep(5)
            continue
        except Exception as e:
            print(f"  [WARN] {str(e)[:60]}", file=sys.stderr)
            time.sleep(3)
            continue

        # JSON抽出
        text = re.sub(r"```(?:json)?\s*", "", text)
        text = re.sub(r"```\s*", "", text).strip()
        s = text.find("[")
        e = text.rfind("]")
        if s < 0 or e <= s:
            continue

        raw = text[s:e+1]
        raw = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", raw)

        try:
            convs = json.loads(raw)
        except json.JSONDecodeError:
            try:
                import json_repair
                convs = json_repair.repair_json(raw, return_objects=True)
            except Exception:
                continue

        if not isinstance(convs, list):
            continue
        convs = [m for m in convs if isinstance(m, dict) and "role" in m]

        # 品質チェック
        user_count = sum(1 for m in convs if m.get("role") == "user")
        ass_msgs = [m for m in convs if m.get("role") == "assistant"]

        if user_count < 1 or not ass_msgs:
            continue

        # think品質チェック（300字以上）
        think_lens = []
        for m in ass_msgs:
            t = re.search(r"<think>(.*?)</think>", m.get("content", ""), re.DOTALL)
            if t:
                think_lens.append(len(t.group(1)))

        if not think_lens or max(think_lens) < 150:  # 最低でも1つは150字以上
            continue

        return convs

    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="highquality_data.json")
    parser.add_argument("--per-category", type=int, default=50)
    args = parser.parse_args()

    global GEMINI_API_KEY
    if not GEMINI_API_KEY:
        GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path   = os.path.join(script_dir, args.output)

    results: list  = []
    done_hashes: set = set()
    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as f:
            results = json.load(f)
        for r in results:
            done_hashes.add(_hash_conv(r.get("conversations", [])))
        print(f"再開: {len(results)}件済み")

    total_target = len(CATEGORIES) * args.per_category
    print(f"目標: {total_target}件 ({len(CATEGORIES)}カテゴリ × {args.per_category}件)")

    for category in CATEGORIES:
        already = sum(1 for r in results if r.get("category") == category["name"])
        need    = args.per_category - already
        if need <= 0:
            print(f"[{category['name']}] スキップ ({already}/{args.per_category})")
            continue

        print(f"\n[{category['name']}] {need}件生成...")

        prompts = category["prompts"] * (args.per_category // len(category["prompts"]) + 2)
        random.shuffle(prompts)

        generated = 0
        fail      = 0
        idx       = 0

        while generated < need and fail < 15 and idx < len(prompts):
            question = prompts[idx]
            idx += 1

            convs = generate_one(category, question)
            if not convs:
                fail += 1
                time.sleep(1)
                continue

            h = _hash_conv(convs)
            if h in done_hashes:
                fail += 1
                continue

            sys_prompt = SYSTEM_PROMPTS[generated % len(SYSTEM_PROMPTS)]
            # Ensure system prompt is first
            if not convs or convs[0].get("role") != "system":
                convs = [{"role": "system", "content": sys_prompt}] + convs
            else:
                convs[0]["content"] = sys_prompt

            item = {
                "conversations": convs,
                "category":      category["name"],
                "source":        "highquality_v1",
            }
            results.append(item)
            done_hashes.add(h)
            generated += 1
            fail = 0

            ass_msgs = [m for m in convs if m.get("role") == "assistant"]
            think_lens = []
            for m in ass_msgs:
                t = re.search(r"<think>(.*?)</think>", m.get("content", ""), re.DOTALL)
                if t:
                    think_lens.append(len(t.group(1)))
            avg_think = sum(think_lens) // max(len(think_lens), 1)
            user_turns = sum(1 for m in convs if m.get("role") == "user")
            print(f"  [{category['name']}] {generated}/{need}: {user_turns}ターン, avg think {avg_think}字")

            if len(results) % 20 == 0:
                _save(results, out_path)

            time.sleep(0.3)

        print(f"  [{category['name']}] 完了: {generated}件")
        _save(results, out_path)

    _save(results, out_path)

    from collections import Counter
    dist = Counter(r.get("category", "?") for r in results)
    print(f"\n完了: {len(results)}件 → {out_path}")
    for k, v in sorted(dist.items()):
        print(f"  {k}: {v}件")


def _save(data, path):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


if __name__ == "__main__":
    main()
