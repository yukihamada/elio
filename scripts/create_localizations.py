#!/usr/bin/env python3
"""
Create iOS Localizable.strings files for 57 languages
Each translation maintains proper iOS .strings format
"""

import os
from pathlib import Path

# Base directory
BASE_DIR = Path("/Users/yuki/workspace/ai/elio/LocalAIAgent/Resources")

# Languages to create (excluding already existing en, ja, zh-Hans, zh-Hant, ko, pt-BR, es, fr, de, it, ar, hi)
# And excluding pt-PT and ru which were just created
LANGUAGES_TODO = [
    ("tr", "Turkish"),
    ("pl", "Polish"),
    ("nl", "Dutch"),
    ("sv", "Swedish"),
    ("da", "Danish"),
    ("nb", "Norwegian"),
    ("fi", "Finnish"),
    ("el", "Greek"),
    ("cs", "Czech"),
    ("hu", "Hungarian"),
    ("ro", "Romanian"),
    ("uk", "Ukrainian"),
    ("vi", "Vietnamese"),
    ("th", "Thai"),
    ("id", "Indonesian"),
    ("ms", "Malay"),
    ("fil", "Filipino"),
    ("he", "Hebrew"),
    ("fa", "Persian"),
    ("ur", "Urdu"),
    ("bn", "Bengali"),
    ("ta", "Tamil"),
    ("te", "Telugu"),
    ("mr", "Marathi"),
    ("gu", "Gujarati"),
    ("kn", "Kannada"),
    ("ml", "Malayalam"),
    ("pa", "Punjabi"),
    ("si", "Sinhala"),
    ("my", "Burmese"),
    ("km", "Khmer"),
    ("lo", "Lao"),
    ("ne", "Nepali"),
    ("am", "Amharic"),
    ("sw", "Swahili"),
    ("zu", "Zulu"),
    ("af", "Afrikaans"),
    ("ha", "Hausa"),
    ("yo", "Yoruba"),
    ("ig", "Igbo"),
    ("so", "Somali"),
    ("sr", "Serbian"),
    ("hr", "Croatian"),
    ("bs", "Bosnian"),
    ("sk", "Slovak"),
    ("sl", "Slovenian"),
    ("bg", "Bulgarian"),
    ("mk", "Macedonian"),
    ("sq", "Albanian"),
    ("lt", "Lithuanian"),
    ("lv", "Latvian"),
    ("et", "Estonian"),
    ("is", "Icelandic"),
    ("ca", "Catalan"),
    ("eu", "Basque"),
]

print(f"Languages to create: {len(LANGUAGES_TODO)}")
print("This script creates placeholder files.")
print("Run with Claude to generate actual translations.")
print()

for lang_code, lang_name in LANGUAGES_TODO:
    target_dir = BASE_DIR / f"{lang_code}.lproj"
    target_file = target_dir / "Localizable.strings"

    # Skip if exists and non-empty
    if target_file.exists() and target_file.stat().st_size > 100:
        print(f"✓ {lang_code} ({lang_name}) - already exists")
        continue

    # Create directory
    target_dir.mkdir(exist_ok=True)

    # Create placeholder
    with open(target_file, 'w', encoding='utf-8') as f:
        f.write(f'/*\n  Localizable.strings ({lang_name})\n  Elio\n*/\n\n')
        f.write(f'// MARK: - App General\n')
        f.write(f'"app.name" = "Elio";\n')
        f.write(f'"app.tagline" = "Your secret-keeping second brain.";\n\n')
        f.write(f'// TODO: Complete translation for {lang_name}\n')
        f.write(f'// Run: claude translate en.lproj/Localizable.strings to {lang_code}\n')

    print(f"Created placeholder: {lang_code} ({lang_name})")

print("\nDone! Use Claude to complete translations.")
