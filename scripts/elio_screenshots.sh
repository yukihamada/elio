#!/bin/bash
# ElioChat iOS Screenshot Automation Script

set -e

echo "🎬 ElioChat Screenshot Automation Starting..."
echo "================================================"

# Configuration
PROJECT_DIR="/Users/yuki/workspace/ai/elio"
OUTPUT_DIR="$PROJECT_DIR/screenshots"
SIMULATOR_NAME="iPhone 15 Pro Max"
BUNDLE_ID="love.elio.app"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo ""
echo "📱 Step 1: Starting iOS Simulator..."
xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || echo "Simulator already running"
open -a Simulator
sleep 5

echo ""
echo "🚀 Step 2: Installing ElioChat..."
if [ -f "$PROJECT_DIR/ElioChat.xcodeproj" ]; then
    cd "$PROJECT_DIR"
    xcodebuild -scheme ElioChat -destination "name=$SIMULATOR_NAME" -configuration Debug
    echo "✓ Build complete"
else
    echo "⚠️  Xcode project not found. Please build manually."
fi

echo ""
echo "📸 Step 3: Taking Screenshots..."

# Function to take screenshot
take_screenshot() {
    local name=$1
    local delay=${2:-2}
    echo "  → Capturing: $name"
    sleep $delay
    xcrun simctl io booted screenshot "$OUTPUT_DIR/${name}.png"
}

# Screenshot 1: Hero Shot (MCP Integration)
echo ""
echo "Screenshot 1/10: MCP Hero Shot"
xcrun simctl launch booted "$BUNDLE_ID"
sleep 3
# User needs to manually trigger "Show me today's schedule" in the app
read -p "Press Enter after triggering calendar demo..."
take_screenshot "01-mcp-hero" 1

# Screenshot 2: Before/After Comparison
echo ""
echo "Screenshot 2/10: Before/After Comparison"
echo "⚠️  This requires manual Figma editing"
echo "   Use template: iPhone Mockup with split view"

# Screenshot 3: Model Selection
echo ""
echo "Screenshot 3/10: Model Selection"
# Navigate to Settings → Models
read -p "Navigate to Model Selection screen, then press Enter..."
take_screenshot "03-model-selection" 1

# Screenshot 4: Vision AI Demo
echo ""
echo "Screenshot 4/10: Vision AI"
read -p "Attach image and show AI analysis, then press Enter..."
take_screenshot "04-vision-ai" 1

# Screenshot 5: Voice Input
echo ""
echo "Screenshot 5/10: Voice Input"
read -p "Show microphone UI active, then press Enter..."
take_screenshot "05-voice-input" 1

# Screenshot 6: Conversation Search
echo ""
echo "Screenshot 6/10: Conversation Search"
read -p "Show search results screen, then press Enter..."
take_screenshot "06-conversation-search" 1

# Screenshot 7: Privacy Emphasis
echo ""
echo "Screenshot 7/10: Privacy Screen"
read -p "Show privacy/offline features screen, then press Enter..."
take_screenshot "07-privacy" 1

# Screenshot 8: Calendar Integration
echo ""
echo "Screenshot 8/10: Calendar Integration"
read -p "Show calendar MCP demo, then press Enter..."
take_screenshot "08-calendar-integration" 1

# Screenshot 9: Reminder Integration
echo ""
echo "Screenshot 9/10: Reminder Integration"
read -p "Show reminder creation demo, then press Enter..."
take_screenshot "09-reminder-integration" 1

# Screenshot 10: Offline Proof
echo ""
echo "Screenshot 10/10: Offline Mode"
echo "  1. Enable Airplane Mode"
echo "  2. Start new conversation"
read -p "Show airplane mode + working chat, then press Enter..."
take_screenshot "10-offline-proof" 1

echo ""
echo "✅ Screenshot capture complete!"
echo "📂 Output directory: $OUTPUT_DIR"
echo ""
echo "📋 Next Steps:"
echo "  1. Review screenshots in $OUTPUT_DIR"
echo "  2. Edit in Figma using templates"
echo "  3. Add captions and annotations"
echo "  4. Export at 1290x2796px (iPhone) or 1270x760px (Product Hunt)"
echo ""
echo "🎨 Figma Template: https://figma.com/file/..."
echo "📖 Full Guide: $PROJECT_DIR/../SCREENSHOT_CAPTURE_GUIDE.md"
