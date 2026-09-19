#!/usr/bin/env python3
"""Prepare pinned MarkdownView with its missing Catalyst dependency condition."""
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
package = root / "Packages/MarkdownView"
revision = "8b746c5146b7842e9547b4d60adb2f1712cebb33"
if not package.exists():
    subprocess.run(["git", "clone", "--depth", "1", "--branch", "1.7.0",
                    "https://github.com/LiYanan2004/MarkdownView.git", str(package)], check=True)
actual = subprocess.check_output(["git", "-C", str(package), "rev-parse", "HEAD"], text=True).strip()
assert actual == revision, "Unexpected MarkdownView source revision"
manifest = package / "Package.swift"
text = manifest.read_text()
old = "condition: .when(platforms: [.iOS, .macOS])"
new = "condition: .when(platforms: [.iOS, .macOS, .macCatalyst])"
assert old in text or new in text, "Upstream condition changed"
manifest.write_text(text.replace(old, new))
print("MarkdownView 1.7.0: Highlightr enabled for Mac Catalyst")
