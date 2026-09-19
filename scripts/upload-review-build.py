#!/usr/bin/env python3
"""Xcode 26 archive/export/upload only; never submits or releases a version."""
import os
import pathlib
import plistlib
import re
import subprocess
import sys

assert os.environ.get("GITHUB_ACTIONS") == "true", "Distribution builds run on GitHub"
platform = sys.argv[1]
assert platform in ("ios", "mac")
number = os.environ["BUILD_NUMBER"]
assert re.fullmatch(r"[1-9][0-9]{0,5}", number), "Invalid build number"
key_id = os.environ["APP_STORE_CONNECT_API_KEY_ID"]
issuer = os.environ["APP_STORE_CONNECT_ISSUER_ID"]
key_content = os.environ["APP_STORE_CONNECT_API_KEY"].replace("\\n", "\n")
assert key_content.startswith("-----BEGIN PRIVATE KEY-----"), "Invalid ASC key format"
key = pathlib.Path(os.environ["RUNNER_TEMP"]) / f"AuthKey_{key_id}.p8"
key.write_text(key_content)
key.chmod(0o600)
archive = pathlib.Path(f"build/{platform}.xcarchive")
export = pathlib.Path(f"build/{platform}-export")
options = pathlib.Path(f"build/{platform}-ExportOptions.plist")
options.parent.mkdir(exist_ok=True)
options.write_bytes(plistlib.dumps({
    "method": "app-store-connect", "destination": "upload", "signingStyle": "automatic",
    "teamID": "5BV85JW8US", "uploadSymbols": True, "manageAppVersionAndBuildNumber": False,
}))
destination = "generic/platform=iOS" if platform == "ios" else "generic/platform=macOS,variant=Mac Catalyst"
try:
    subprocess.run(["xcodebuild", "archive", "-project", "ElioChat.xcodeproj", "-scheme", "ElioChat",
                    "-configuration", "Release", "-destination", destination,
                    "-archivePath", str(archive), "CODE_SIGNING_ALLOWED=NO",
                    "MARKETING_VERSION=1.2.43", f"CURRENT_PROJECT_VERSION={number}",
                    "ARCHS=arm64"], check=True)
    app = archive / "Products/Applications/ElioChat.app"
    subprocess.run(["python3", "scripts/audit-review-app.py", str(app)], check=True)
    info_path = app / ("Info.plist" if platform == "ios" else "Contents/Info.plist")
    info = plistlib.loads(info_path.read_bytes())
    assert info["CFBundleVersion"] == number
    assert info["CFBundleShortVersionString"] == "1.2.43"
    if platform == "mac":
        # An unsigned archive has no signed entitlements for Xcode's export
        # re-signing to preserve. Attach the existing app entitlements before
        # cloud distribution signing, otherwise ASC rejects the missing sandbox.
        subprocess.run(["codesign", "--force", "--sign", "-", "--entitlements",
                        "LocalAIAgent/LocalAIAgent.entitlements", str(app)], check=True)
        signed = subprocess.check_output(["codesign", "--display", "--entitlements", "-", "--xml", str(app)],
                                         stderr=subprocess.DEVNULL)
        assert plistlib.loads(signed).get("com.apple.security.app-sandbox") is True
        print("PASS: Mac archive signature includes app-sandbox=true")
    subprocess.run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                    "-exportPath", str(export), "-exportOptionsPlist", str(options),
                    "-allowProvisioningUpdates", "-authenticationKeyPath", str(key),
                    "-authenticationKeyID", key_id, "-authenticationKeyIssuerID", issuer], check=True)
    print(f"UPLOAD SUCCEEDED: {platform} 1.2.43 ({number}); no review submission requested")
finally:
    key.unlink(missing_ok=True)
