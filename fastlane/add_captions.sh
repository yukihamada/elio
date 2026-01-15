#!/bin/bash

# Add marketing captions to screenshots with improved design
# Usage: ./add_captions.sh

SCREENSHOTS_DIR="$(dirname "$0")/screenshots"
OUTPUT_DIR="$(dirname "$0")/screenshots_final"

# Create output directories
mkdir -p "$OUTPUT_DIR/ja"
mkdir -p "$OUTPUT_DIR/en-US"

get_ja_caption() {
    case "$1" in
        "01_WelcomeScreen") echo "秘密を守るAI" ;;
        "02_ChatSchedule") echo "予定管理" ;;
        "03_ChatCode") echo "コード支援" ;;
        "04_ChatTravel") echo "旅行計画" ;;
        "05_ChatPrivacy") echo "完全非公開" ;;
        "06_ChatCreative") echo "文章作成" ;;
        "07_Settings") echo "AI選択" ;;
        "08_ConversationList") echo "履歴検索" ;;
        *) echo "" ;;
    esac
}

get_en_caption() {
    case "$1" in
        "01_WelcomeScreen") echo "Private AI" ;;
        "02_ChatSchedule") echo "Schedule" ;;
        "03_ChatCode") echo "Coding" ;;
        "04_ChatTravel") echo "Travel" ;;
        "05_ChatPrivacy") echo "Private" ;;
        "06_ChatCreative") echo "Writing" ;;
        "07_Settings") echo "Models" ;;
        "08_ConversationList") echo "History" ;;
        *) echo "" ;;
    esac
}

add_caption() {
    local input="$1"
    local output="$2"
    local caption="$3"
    local lang="$4"

    # Get image dimensions
    local width=$(magick identify -format "%w" "$input")
    local height=$(magick identify -format "%h" "$input")

    # Caption area - 10% of image height (overlay on top)
    local caption_height=$((height * 10 / 100))

    # Font settings - 40% of caption height
    local font_size=$((caption_height * 40 / 100))
    local font

    if [ "$lang" = "ja" ]; then
        font="Hiragino-Sans-W7"
    else
        font="Avenir-Black"
    fi

    # Create gradient caption bar
    magick -size ${width}x${caption_height} \
        gradient:'#6366F1'-'#8B5CF6' \
        -gravity center \
        -font "$font" \
        -pointsize $font_size \
        -fill white \
        -stroke none \
        -annotate +0+0 "$caption" \
        /tmp/caption_header.png

    # Overlay caption on top of screenshot (keeps original size)
    magick "$input" /tmp/caption_header.png -gravity north -composite "$output"

    echo "Created: $output"
}

# Device patterns to process
DEVICES=("iPhone 16 Pro Max" "iPad Pro 13-inch (M4)")

# Process Japanese screenshots
echo "Processing Japanese screenshots..."
for device in "${DEVICES[@]}"; do
    for file in "$SCREENSHOTS_DIR/ja/${device}-"*.png; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            key=$(echo "$filename" | sed "s/${device}-//" | sed 's/\.png//')
            caption=$(get_ja_caption "$key")
            if [ -n "$caption" ]; then
                add_caption "$file" "$OUTPUT_DIR/ja/$filename" "$caption" "ja"
            fi
        fi
    done
done

# Process English screenshots
echo "Processing English screenshots..."
for device in "${DEVICES[@]}"; do
    for file in "$SCREENSHOTS_DIR/en-US/${device}-"*.png; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            key=$(echo "$filename" | sed "s/${device}-//" | sed 's/\.png//')
            caption=$(get_en_caption "$key")
            if [ -n "$caption" ]; then
                add_caption "$file" "$OUTPUT_DIR/en-US/$filename" "$caption" "en"
            fi
        fi
    done
done

# Cleanup
rm -f /tmp/caption_header.png

echo "Done! Screenshots with captions saved to: $OUTPUT_DIR"
open "$OUTPUT_DIR"
