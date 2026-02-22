#!/bin/bash

# Generate iOS Localizations for ElioChat
# This script creates Localizable.strings files for 57 languages

set -e

BASE_DIR="/Users/yuki/workspace/ai/elio/LocalAIAgent/Resources"
EN_FILE="$BASE_DIR/en.lproj/Localizable.strings"

# Language codes and their full names
declare -A LANGUAGES=(
    ["pt-PT"]="Portuguese (Portugal)"
    ["ru"]="Russian"
    ["tr"]="Turkish"
    ["pl"]="Polish"
    ["nl"]="Dutch"
    ["sv"]="Swedish"
    ["da"]="Danish"
    ["nb"]="Norwegian"
    ["fi"]="Finnish"
    ["el"]="Greek"
    ["cs"]="Czech"
    ["hu"]="Hungarian"
    ["ro"]="Romanian"
    ["uk"]="Ukrainian"
    ["vi"]="Vietnamese"
    ["th"]="Thai"
    ["id"]="Indonesian"
    ["ms"]="Malay"
    ["fil"]="Filipino"
    ["he"]="Hebrew"
    ["fa"]="Persian"
    ["ur"]="Urdu"
    ["bn"]="Bengali"
    ["ta"]="Tamil"
    ["te"]="Telugu"
    ["mr"]="Marathi"
    ["gu"]="Gujarati"
    ["kn"]="Kannada"
    ["ml"]="Malayalam"
    ["pa"]="Punjabi"
    ["si"]="Sinhala"
    ["my"]="Burmese"
    ["km"]="Khmer"
    ["lo"]="Lao"
    ["ne"]="Nepali"
    ["am"]="Amharic"
    ["sw"]="Swahili"
    ["zu"]="Zulu"
    ["af"]="Afrikaans"
    ["ha"]="Hausa"
    ["yo"]="Yoruba"
    ["ig"]="Igbo"
    ["so"]="Somali"
    ["sr"]="Serbian"
    ["hr"]="Croatian"
    ["bs"]="Bosnian"
    ["sk"]="Slovak"
    ["sl"]="Slovenian"
    ["bg"]="Bulgarian"
    ["mk"]="Macedonian"
    ["sq"]="Albanian"
    ["lt"]="Lithuanian"
    ["lv"]="Latvian"
    ["et"]="Estonian"
    ["is"]="Icelandic"
    ["ca"]="Catalan"
    ["eu"]="Basque"
)

echo "Generating localizations for 57 languages..."
echo "Base directory: $BASE_DIR"
echo ""

# Check if English source file exists
if [ ! -f "$EN_FILE" ]; then
    echo "Error: English source file not found at $EN_FILE"
    exit 1
fi

# Counter
COUNT=0

# Generate for each language
for LANG_CODE in "${!LANGUAGES[@]}"; do
    LANG_NAME="${LANGUAGES[$LANG_CODE]}"
    TARGET_DIR="$BASE_DIR/$LANG_CODE.lproj"
    TARGET_FILE="$TARGET_DIR/Localizable.strings"

    # Skip if already exists and has content
    if [ -f "$TARGET_FILE" ] && [ -s "$TARGET_FILE" ]; then
        echo "✓ Skipping $LANG_CODE ($LANG_NAME) - already exists"
        continue
    fi

    echo "Generating $LANG_CODE ($LANG_NAME)..."

    # Create directory
    mkdir -p "$TARGET_DIR"

    # Use Claude to generate translation
    # Note: This requires the elio CLI or API access to Claude
    # For now, we'll mark it as needing manual translation

    echo "/* Localizable.strings ($LANG_NAME) - Elio */" > "$TARGET_FILE"
    echo "// TODO: Translate from English source" >> "$TARGET_FILE"
    echo "" >> "$TARGET_FILE"

    COUNT=$((COUNT + 1))
done

echo ""
echo "Created placeholder files for $COUNT languages"
echo "To complete translations, use Claude API or translation service"
echo ""
echo "Example command to translate with Claude:"
echo "  claude translate --from en.lproj/Localizable.strings --to <lang-code> --context 'iOS AI assistant app'"
