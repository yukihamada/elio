#!/usr/bin/env python3
"""学習データを見やすいHTMLビューアーに変換"""
import json, re, random, os
from collections import Counter

random.seed(42)

def load_data():
    d = json.load(open("merged_v8.json", encoding="utf-8"))
    try:
        e = json.load(open("eval_v8.json", encoding="utf-8"))
    except:
        e = []
    return d, e

def think_len(item):
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            t = re.search(r"<think>(.*?)</think>", m.get("content",""), re.DOTALL)
            if t: return len(t.group(1))
    return 0

def get_tools(item):
    tools = []
    for m in item.get("conversations", []):
        if m.get("role") == "assistant":
            tools += re.findall(r'"name":\s*"([^"]+)"', m.get("content",""))
    return list(dict.fromkeys(tools))  # unique, order preserved

def get_persona(item):
    for m in item.get("conversations", []):
        if m.get("role") == "system":
            c = m.get("content","")
            # detect persona suffix
            patterns = ["大阪弁","博多弁","京都弁","東北弁","沖縄弁","武士","侍","ギャル","お嬢様","博士","教授","アイドル","ツンデレ","ロボット","芸人","中二病","敬語"]
            for p in patterns:
                if p in c: return p
    return None

def extract_item(item, idx, split="train"):
    convs = item.get("conversations", [])
    sys_msg = next((m["content"] for m in convs if m["role"] == "system"), "")
    user_msgs = [m["content"] for m in convs if m["role"] == "user"]
    asst_msgs = [m["content"] for m in convs if m["role"] == "assistant"]

    tl = think_len(item)
    tools = get_tools(item)
    persona = get_persona(item)
    turns = len(user_msgs)

    think_text = ""
    response_text = ""
    if asst_msgs:
        c = asst_msgs[0]
        t = re.search(r"<think>(.*?)</think>", c, re.DOTALL)
        if t:
            think_text = t.group(1).strip()
        response_text = re.sub(r"<think>.*?</think>", "", c, flags=re.DOTALL).strip()

    return {
        "idx": idx,
        "split": split,
        "turns": turns,
        "system": sys_msg[:150],
        "user": user_msgs[0][:300] if user_msgs else "",
        "think_len": tl,
        "think": think_text[:600],
        "tools": tools,
        "persona": persona,
        "response": response_text[:400],
        "has_multi": turns > 1,
    }

def build_stats(all_d):
    tls = sorted(think_len(i) for i in all_d)
    n = len(tls)
    tool_counter = Counter()
    persona_counter = Counter()

    for item in all_d:
        for t in get_tools(item):
            tool_counter[t] += 1
        p = get_persona(item)
        if p: persona_counter[p] += 1

    buckets = [0]*6  # <80, 80-199, 200-399, 400-799, 800-1499, 1500+
    for tl in tls:
        if tl < 80: buckets[0] += 1
        elif tl < 200: buckets[1] += 1
        elif tl < 400: buckets[2] += 1
        elif tl < 800: buckets[3] += 1
        elif tl < 1500: buckets[4] += 1
        else: buckets[5] += 1

    multi_turn = sum(1 for i in all_d if sum(1 for m in i.get("conversations",[]) if m["role"]=="user") > 1)
    has_tool = sum(1 for i in all_d if get_tools(i))
    has_persona = sum(1 for i in all_d if get_persona(i))

    return {
        "total": n,
        "median_think": tls[n//2] if n else 0,
        "avg_think": int(sum(tls)/n) if n else 0,
        "pct_400": int(100 * sum(1 for x in tls if x >= 400) / n) if n else 0,
        "tool_items": has_tool,
        "multi_turn_items": multi_turn,
        "persona_items": has_persona,
        "top_tools": tool_counter.most_common(15),
        "top_personas": persona_counter.most_common(15),
        "think_buckets": buckets,
    }

def main():
    print("データ読み込み中...")
    train_d, eval_d = load_data()
    all_d = train_d + eval_d

    print("統計計算中...")
    stats = build_stats(all_d)

    print("サンプル抽出中...")
    # 全件をサンプリング（最大300件表示用）
    sample_train = random.sample(train_d, min(250, len(train_d)))
    sample_eval  = random.sample(eval_d,  min(50,  len(eval_d)))

    items_json = json.dumps(
        [extract_item(i, idx, "train") for idx, i in enumerate(sample_train)] +
        [extract_item(i, idx+len(sample_train), "eval") for idx, i in enumerate(sample_eval)],
        ensure_ascii=False
    )
    stats_json = json.dumps(stats, ensure_ascii=False)

    html = f"""<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>futa-2b 学習データビューアー</title>
<style>
*{{box-sizing:border-box;margin:0;padding:0}}
body{{font-family:'Hiragino Kaku Gothic ProN','Meiryo',sans-serif;background:#0f1117;color:#e2e8f0;min-height:100vh}}
header{{background:linear-gradient(135deg,#1e3a5f,#2d1b69);padding:24px 32px;border-bottom:1px solid #2d3748}}
header h1{{font-size:1.6rem;font-weight:700;color:#63b3ed;letter-spacing:.03em}}
header p{{color:#94a3b8;font-size:.85rem;margin-top:4px}}
.container{{max-width:1400px;margin:0 auto;padding:24px 16px}}

/* Stats grid */
.stats-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:28px}}
.stat-card{{background:#1a1f2e;border:1px solid #2d3748;border-radius:10px;padding:16px;text-align:center}}
.stat-card .num{{font-size:1.8rem;font-weight:800;color:#63b3ed}}
.stat-card .lbl{{font-size:.75rem;color:#718096;margin-top:4px}}
.stat-card.green .num{{color:#68d391}}
.stat-card.yellow .num{{color:#f6e05e}}
.stat-card.purple .num{{color:#b794f4}}
.stat-card.pink .num{{color:#fc8181}}

/* Charts row */
.charts{{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:28px}}
@media(max-width:800px){{.charts{{grid-template-columns:1fr}}}}
.chart-card{{background:#1a1f2e;border:1px solid #2d3748;border-radius:10px;padding:20px}}
.chart-card h3{{font-size:.9rem;color:#a0aec0;margin-bottom:14px;font-weight:600;text-transform:uppercase;letter-spacing:.05em}}
.bar-row{{display:flex;align-items:center;margin-bottom:8px;gap:8px}}
.bar-label{{width:90px;font-size:.75rem;color:#718096;text-align:right;flex-shrink:0}}
.bar-track{{flex:1;background:#2d3748;border-radius:4px;height:18px;overflow:hidden}}
.bar-fill{{height:100%;border-radius:4px;transition:width .5s ease;display:flex;align-items:center;justify-content:flex-end;padding-right:6px}}
.bar-fill span{{font-size:.65rem;color:#fff;font-weight:600;opacity:.9}}
.bar-count{{width:50px;font-size:.72rem;color:#4a5568;text-align:left}}

/* Filters */
.filters{{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:20px;align-items:center}}
.filters select,.filters input{{background:#1a1f2e;border:1px solid #2d3748;color:#e2e8f0;border-radius:6px;padding:6px 12px;font-size:.82rem}}
.filters select:focus,.filters input:focus{{outline:none;border-color:#63b3ed}}
.filter-btn{{background:#2d3748;border:none;color:#e2e8f0;border-radius:6px;padding:6px 14px;font-size:.82rem;cursor:pointer;transition:background .2s}}
.filter-btn:hover{{background:#3d4a5c}}
.filter-btn.active{{background:#2b6cb0;color:#fff}}
.count-badge{{background:#2b6cb0;color:#fff;border-radius:12px;padding:2px 10px;font-size:.75rem;font-weight:700}}

/* Items */
.items-grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(380px,1fr));gap:14px}}
@media(max-width:600px){{.items-grid{{grid-template-columns:1fr}}}}
.item-card{{background:#1a1f2e;border:1px solid #2d3748;border-radius:10px;overflow:hidden;transition:border-color .2s,transform .2s;cursor:pointer}}
.item-card:hover{{border-color:#4a90d9;transform:translateY(-1px)}}
.item-card.expanded{{border-color:#63b3ed}}
.card-header{{padding:12px 16px;background:#151a27;border-bottom:1px solid #2d3748;display:flex;align-items:center;gap:8px;flex-wrap:wrap}}
.badge{{font-size:.65rem;padding:2px 8px;border-radius:10px;font-weight:600;white-space:nowrap}}
.badge.train{{background:#1c3a5f;color:#63b3ed}}
.badge.eval{{background:#2d1b69;color:#b794f4}}
.badge.tool{{background:#1a3a2a;color:#68d391}}
.badge.multi{{background:#3a2a1a;color:#f6ad55}}
.badge.persona{{background:#3a1a2a;color:#fc8181}}
.think-meter{{width:60px;height:6px;background:#2d3748;border-radius:3px;overflow:hidden;flex-shrink:0}}
.think-meter-fill{{height:100%;background:linear-gradient(90deg,#4299e1,#9f7aea);border-radius:3px}}
.think-num{{font-size:.65rem;color:#718096}}
.card-body{{padding:14px 16px}}
.user-msg{{font-size:.82rem;color:#e2e8f0;line-height:1.55;margin-bottom:10px}}
.user-msg strong{{color:#63b3ed;font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;display:block;margin-bottom:3px}}
.tools-row{{display:flex;flex-wrap:wrap;gap:5px;margin-bottom:10px}}
.tool-chip{{font-size:.65rem;padding:2px 8px;border-radius:10px;background:#1a2a3a;color:#4fd1c5;border:1px solid #2d4a5a}}
.expand-section{{display:none;border-top:1px solid #2d3748;padding-top:12px;margin-top:4px}}
.item-card.expanded .expand-section{{display:block}}
.think-box{{background:#0d1117;border-left:3px solid #4299e1;padding:10px 14px;border-radius:0 6px 6px 0;font-size:.78rem;color:#94a3b8;line-height:1.7;margin-bottom:10px;max-height:220px;overflow-y:auto;white-space:pre-wrap}}
.response-box{{background:#0d1117;border-left:3px solid #68d391;padding:10px 14px;border-radius:0 6px 6px 0;font-size:.78rem;color:#a0e0c0;line-height:1.7;max-height:200px;overflow-y:auto;white-space:pre-wrap}}
.section-label{{font-size:.7rem;color:#718096;text-transform:uppercase;letter-spacing:.05em;margin-bottom:6px;font-weight:600}}
.system-box{{font-size:.72rem;color:#6b7280;background:#111520;border-radius:4px;padding:6px 10px;margin-bottom:10px;line-height:1.5}}

/* Pagination */
.pagination{{display:flex;align-items:center;gap:8px;justify-content:center;margin-top:24px;flex-wrap:wrap}}
.pagination button{{background:#1a1f2e;border:1px solid #2d3748;color:#e2e8f0;border-radius:6px;padding:6px 14px;cursor:pointer;font-size:.82rem}}
.pagination button:hover{{background:#2d3748}}
.pagination button.active{{background:#2b6cb0;border-color:#2b6cb0;color:#fff}}
.pagination .page-info{{color:#718096;font-size:.8rem}}

.no-results{{text-align:center;padding:40px;color:#4a5568;font-size:.9rem}}
</style>
</head>
<body>
<header>
  <h1>futa-2b 学習データビューアー</h1>
  <p>merged_v8.json &nbsp;|&nbsp; 表示: ランダムサンプル300件 / 全{len(all_d)}件</p>
</header>
<div class="container">

<!-- Stats -->
<div class="stats-grid" id="statsGrid"></div>

<!-- Charts -->
<div class="charts">
  <div class="chart-card">
    <h3>思考長 (think) 分布</h3>
    <div id="thinkChart"></div>
  </div>
  <div class="chart-card">
    <h3>ツール使用 Top15</h3>
    <div id="toolChart"></div>
  </div>
</div>

<!-- Filters -->
<div class="filters">
  <input id="searchBox" type="text" placeholder="🔍 キーワード検索..." style="width:220px">
  <select id="splitFilter">
    <option value="">全データ</option>
    <option value="train">Train のみ</option>
    <option value="eval">Eval のみ</option>
  </select>
  <select id="thinkFilter">
    <option value="">think長さ</option>
    <option value="0-199">〜199字</option>
    <option value="200-399">200〜399字</option>
    <option value="400-799">400〜799字</option>
    <option value="800-">800字〜</option>
  </select>
  <select id="toolFilter">
    <option value="">ツール</option>
    <option value="any">ツールあり</option>
    <option value="none">ツールなし</option>
    <option value="calculator">calculator</option>
    <option value="wikipedia">wikipedia</option>
    <option value="web_search">web_search</option>
    <option value="weather">weather</option>
    <option value="translate">translate</option>
    <option value="code_execute">code_execute</option>
    <option value="image_generate">image_generate</option>
    <option value="create_qr">create_qr</option>
  </select>
  <button class="filter-btn" id="multiBtn" onclick="toggleFilter('multi')">マルチターン</button>
  <button class="filter-btn" id="personaBtn" onclick="toggleFilter('persona')">ペルソナあり</button>
  <span class="count-badge" id="countBadge">0件</span>
</div>

<!-- Items -->
<div class="items-grid" id="itemsGrid"></div>
<div class="no-results" id="noResults" style="display:none">条件に一致するデータがありません</div>

<!-- Pagination -->
<div class="pagination" id="pagination"></div>

</div>

<script>
const STATS = {stats_json};
const ITEMS = {items_json};
const PAGE_SIZE = 30;
let curPage = 1;
let filtered = [];
let activeFilters = {{}};

// === Stats ===
function renderStats() {{
  const s = STATS;
  const cards = [
    {{num: s.total.toLocaleString(), lbl: '合計件数', cls:''}},
    {{num: '{len(train_d)}', lbl: 'Train', cls:''}},
    {{num: '{len(eval_d)}', lbl: 'Eval', cls:'purple'}},
    {{num: s.median_think.toLocaleString()+'字', lbl: 'think 中央値', cls:'green'}},
    {{num: s.pct_400+'%', lbl: '400字以上', cls:'green'}},
    {{num: s.tool_items.toLocaleString(), lbl: 'ツール使用', cls:'yellow'}},
    {{num: s.multi_turn_items.toLocaleString(), lbl: 'マルチターン', cls:'yellow'}},
    {{num: s.persona_items.toLocaleString(), lbl: 'ペルソナ', cls:'pink'}},
  ];
  document.getElementById('statsGrid').innerHTML = cards.map(c =>
    `<div class="stat-card ${{c.cls}}"><div class="num">${{c.num}}</div><div class="lbl">${{c.lbl}}</div></div>`
  ).join('');
}}

// === Charts ===
function renderCharts() {{
  const s = STATS;
  const bucketLabels = ['<80字','80-199字','200-399字','400-799字','800-1499字','1500+字'];
  const bucketColors = ['#e53e3e','#ed8936','#ecc94b','#68d391','#4299e1','#9f7aea'];
  const maxBucket = Math.max(...s.think_buckets);

  document.getElementById('thinkChart').innerHTML = s.think_buckets.map((v,i) => `
    <div class="bar-row">
      <div class="bar-label">${{bucketLabels[i]}}</div>
      <div class="bar-track">
        <div class="bar-fill" style="width:${{Math.round(v/maxBucket*100)}}%;background:${{bucketColors[i]}}">
          <span>${{v>20?v:''}}</span>
        </div>
      </div>
      <div class="bar-count">${{v}}件</div>
    </div>
  `).join('');

  const maxTool = s.top_tools[0][1];
  document.getElementById('toolChart').innerHTML = s.top_tools.map(([name,cnt]) => `
    <div class="bar-row">
      <div class="bar-label">${{name}}</div>
      <div class="bar-track">
        <div class="bar-fill" style="width:${{Math.round(cnt/maxTool*100)}}%;background:#4299e1">
          <span>${{cnt>50?cnt:''}}</span>
        </div>
      </div>
      <div class="bar-count">${{cnt}}件</div>
    </div>
  `).join('');
}}

// === Filter ===
function getFiltered() {{
  const q = document.getElementById('searchBox').value.toLowerCase();
  const split = document.getElementById('splitFilter').value;
  const thinkF = document.getElementById('thinkFilter').value;
  const toolF = document.getElementById('toolFilter').value;

  return ITEMS.filter(item => {{
    if (split && item.split !== split) return false;
    if (thinkF) {{
      const [lo,hi] = thinkF.split('-').map(Number);
      if (hi !== undefined && (item.think_len < lo || item.think_len >= (hi||Infinity))) return false;
      if (isNaN(hi) && item.think_len < lo) return false;
    }}
    if (toolF === 'any' && item.tools.length === 0) return false;
    if (toolF === 'none' && item.tools.length > 0) return false;
    if (toolF && toolF !== 'any' && toolF !== 'none' && !item.tools.includes(toolF)) return false;
    if (activeFilters.multi && !item.has_multi) return false;
    if (activeFilters.persona && !item.persona) return false;
    if (q && !item.user.toLowerCase().includes(q) && !item.think.toLowerCase().includes(q) && !item.response.toLowerCase().includes(q)) return false;
    return true;
  }});
}}

function toggleFilter(key) {{
  activeFilters[key] = !activeFilters[key];
  document.getElementById(key+'Btn').classList.toggle('active', !!activeFilters[key]);
  applyFilters();
}}

function applyFilters() {{
  filtered = getFiltered();
  curPage = 1;
  document.getElementById('countBadge').textContent = filtered.length+'件';
  renderPage();
}}

// === Render ===
function renderPage() {{
  const start = (curPage-1)*PAGE_SIZE;
  const page = filtered.slice(start, start+PAGE_SIZE);

  if (filtered.length === 0) {{
    document.getElementById('itemsGrid').innerHTML = '';
    document.getElementById('noResults').style.display = 'block';
  }} else {{
    document.getElementById('noResults').style.display = 'none';
    document.getElementById('itemsGrid').innerHTML = page.map(item => renderCard(item)).join('');
  }}
  renderPagination();
}}

function renderCard(item) {{
  const thinkPct = Math.min(100, Math.round(item.think_len/2000*100));
  const tools = item.tools.map(t => `<span class="tool-chip">${{t}}</span>`).join('');
  const badges = [
    `<span class="badge ${{item.split}}">${{item.split}}</span>`,
    item.tools.length ? `<span class="badge tool">ツール ${{item.tools.length}}</span>` : '',
    item.has_multi ? `<span class="badge multi">${{item.turns}}ターン</span>` : '',
    item.persona ? `<span class="badge persona">${{item.persona}}</span>` : '',
  ].filter(Boolean).join('');

  const thinkPreview = item.think ? item.think.replace(/</g,'&lt;').replace(/>/g,'&gt;') : '';
  const responsePreview = item.response ? item.response.replace(/</g,'&lt;').replace(/>/g,'&gt;') : '';
  const systemPreview = item.system ? item.system.replace(/</g,'&lt;').replace(/>/g,'&gt;') : '';

  return `
  <div class="item-card" id="card_${{item.idx}}" onclick="toggleCard(${{item.idx}})">
    <div class="card-header">
      ${{badges}}
      <div style="margin-left:auto;display:flex;align-items:center;gap:6px">
        <div class="think-meter"><div class="think-meter-fill" style="width:${{thinkPct}}%"></div></div>
        <span class="think-num">${{item.think_len}}字</span>
      </div>
    </div>
    <div class="card-body">
      <div class="user-msg"><strong>User</strong>${{item.user.replace(/</g,'&lt;').replace(/>/g,'&gt;')}}</div>
      ${{tools ? `<div class="tools-row">${{tools}}</div>` : ''}}
      <div class="expand-section" id="exp_${{item.idx}}">
        ${{item.system ? `<div class="system-box">${{systemPreview}}</div>` : ''}}
        ${{thinkPreview ? `<div class="section-label">Think (${{item.think_len}}字)</div><div class="think-box">${{thinkPreview}}</div>` : ''}}
        <div class="section-label">Response</div>
        <div class="response-box">${{responsePreview}}</div>
      </div>
    </div>
  </div>`;
}}

function toggleCard(idx) {{
  const card = document.getElementById('card_'+idx);
  card.classList.toggle('expanded');
}}

function renderPagination() {{
  const totalPages = Math.ceil(filtered.length/PAGE_SIZE);
  if (totalPages <= 1) {{ document.getElementById('pagination').innerHTML=''; return; }}

  let pages = [];
  for (let i=1;i<=totalPages;i++) {{
    if (i===1||i===totalPages||Math.abs(i-curPage)<=2) pages.push(i);
    else if (Math.abs(i-curPage)===3) pages.push('...');
  }}
  pages = [...new Set(pages)];

  document.getElementById('pagination').innerHTML = `
    <button onclick="goPage(${{curPage-1}})" ${{curPage===1?'disabled':''}}>← 前</button>
    ${{pages.map(p=>p==='...'?`<span style="color:#4a5568">…</span>`:`<button class="${{p===curPage?'active':''}}" onclick="goPage(${{p}})">${{p}}</button>`).join('')}}
    <button onclick="goPage(${{curPage+1}})" ${{curPage===totalPages?'disabled':''}}>次 →</button>
    <span class="page-info">${{curPage}}/${{totalPages}}ページ (${{filtered.length}}件)</span>
  `;
}}

function goPage(p) {{
  const total = Math.ceil(filtered.length/PAGE_SIZE);
  if (p<1||p>total) return;
  curPage = p;
  renderPage();
  window.scrollTo({{top:0,behavior:'smooth'}});
}}

// Event listeners
['searchBox','splitFilter','thinkFilter','toolFilter'].forEach(id => {{
  document.getElementById(id).addEventListener('input', applyFilters);
  document.getElementById(id).addEventListener('change', applyFilters);
}});

// Init
renderStats();
renderCharts();
applyFilters();
</script>
</body>
</html>"""

    out_path = "data_viewer.html"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"✅ 生成完了: {out_path}")
    print(f"   件数: {len(all_d)} (train:{len(train_d)} eval:{len(eval_d)})")
    print(f"   think中央値: {stats['median_think']}字 | 400+字: {stats['pct_400']}%")
    print(f"   ツール使用: {stats['tool_items']}件 | ペルソナ: {stats['persona_items']}件")
    return out_path

if __name__ == "__main__":
    import os
    os.chdir("/Users/yuki/workspace/ai/elio/Training")
    main()
