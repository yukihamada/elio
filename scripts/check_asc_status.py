#!/usr/bin/env python3
"""App Store Connect ステータスチェッカー — 毎朝10時実行用"""

import jwt, time, requests, subprocess, os
from pathlib import Path
from datetime import datetime

KEY_ID = "5KT46G9Y29"
ISSUER_ID = "e0d22675-afb3-45f0-a821-06b477f44da0"
key = Path.home().joinpath(".appstoreconnect/private_keys/AuthKey_5KT46G9Y29.p8").read_text()
token = jwt.encode(
    {"iss": ISSUER_ID, "iat": int(time.time()), "exp": int(time.time())+1200, "aud": "appstoreconnect-v1"},
    key, algorithm="ES256", headers={"kid": KEY_ID}
)
h = {"Authorization": f"Bearer {token}"}

APPS = [
    ("Elio Chat",    "6757635481"),
    ("Soluna Rx",    "6759962263"),
    ("Soluna Rx Mac","6759965876"),
    ("JiuFlow",      "6757831498"),
    ("JitsuFlow",    "6748526039"),
    ("GroqGo",       "6758568768"),
    ("BANTO",        "6757735526"),
]

STATES_JA = {
    "PREPARE_FOR_SUBMISSION": "提出準備中",
    "WAITING_FOR_REVIEW":     "審査待ち",
    "IN_REVIEW":              "審査中",
    "PENDING_DEVELOPER_RELEASE": "承認済み（リリース待ち）✅",
    "READY_FOR_SALE":         "販売中",
    "REJECTED":               "却下 ❌",
    "DEVELOPER_REJECTED":     "開発者取下げ",
    "INVALID_BINARY":         "無効バイナリ ❌",
    "METADATA_REJECTED":      "メタデータ却下 ❌",
}

lines = [f"【App Store ステータス】{datetime.now().strftime('%Y-%m-%d %H:%M')}", ""]
alerts = []

for name, app_id in APPS:
    r = requests.get(
        f"https://api.appstoreconnect.apple.com/v1/apps/{app_id}/appStoreVersions"
        f"?filter[appStoreState]=PREPARE_FOR_SUBMISSION,WAITING_FOR_REVIEW,IN_REVIEW,"
        f"PENDING_DEVELOPER_RELEASE,REJECTED,DEVELOPER_REJECTED,INVALID_BINARY,METADATA_REJECTED"
        f"&limit=5",
        headers=h, timeout=15
    )
    if not r.ok:
        lines.append(f"[{name}] API Error {r.status_code}")
        continue
    versions = r.json().get("data", [])
    if not versions:
        lines.append(f"[{name}] アクティブなバージョンなし")
        continue
    for v in versions:
        a = v["attributes"]
        state = a["appStoreState"]
        state_ja = STATES_JA.get(state, state)
        plat = "iOS" if a["platform"] == "IOS" else "macOS"
        line = f"[{name}] {plat} v{a['versionString']} → {state_ja}"
        lines.append(line)
        if state in ("PENDING_DEVELOPER_RELEASE", "REJECTED", "INVALID_BINARY", "METADATA_REJECTED", "IN_REVIEW"):
            alerts.append(line)

lines.append("")
lines.append(f"合計 {len(APPS)} アプリ確認完了")

report = "\n".join(lines)

# ログ保存
log_path = Path.home() / "Desktop/asc_status.txt"
log_path.write_text(report)

# macOS通知
if alerts:
    title = f"App Store 要確認 ({len(alerts)}件)"
    body = "\n".join(alerts[:3])
else:
    # 承認待ちがあれば通知
    approved = [l for l in lines if "承認済み" in l]
    if approved:
        title = "App Store 承認されました！🎉"
        body = "\n".join(approved)
    else:
        title = "App Store ステータス確認完了"
        body = "変化なし — ~/Desktop/asc_status.txt を確認"

subprocess.run([
    "osascript", "-e",
    f'display notification "{body}" with title "{title}" sound name "Glass"'
])

print(report)
