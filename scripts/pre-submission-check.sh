#!/bin/bash

# ElioChat - App Store Submission Pre-Check Script
# このスクリプトは、App Store申請前に必要な項目を自動チェックします

set -e

# カラー出力設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# プロジェクトルート
PROJECT_ROOT="/Users/yuki/workspace/ai/elio"
INFO_PLIST="${PROJECT_ROOT}/LocalAIAgent/Resources/Info.plist"
PRIVACY_MANIFEST="${PROJECT_ROOT}/LocalAIAgent/Resources/PrivacyInfo.xcprivacy"
XCODE_PROJECT="${PROJECT_ROOT}/ElioChat.xcodeproj"

# カウンター
PASSED=0
FAILED=0
WARNINGS=0

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}ElioChat - App Store 申請前チェック${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# チェック関数
check_passed() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++))
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++))
}

check_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++))
}

# 1. プロジェクトファイルの存在確認
echo -e "${BLUE}[1] プロジェクトファイル確認${NC}"
if [ -f "$INFO_PLIST" ]; then
    check_passed "Info.plist 存在確認"
else
    check_failed "Info.plist が見つかりません: $INFO_PLIST"
fi

if [ -f "$PRIVACY_MANIFEST" ]; then
    check_passed "PrivacyInfo.xcprivacy 存在確認"
else
    check_failed "PrivacyInfo.xcprivacy が見つかりません: $PRIVACY_MANIFEST"
fi

if [ -d "$XCODE_PROJECT" ]; then
    check_passed "Xcodeプロジェクト 存在確認"
else
    check_failed "Xcodeプロジェクトが見つかりません: $XCODE_PROJECT"
fi

echo ""

# 2. Info.plistのバージョン確認
echo -e "${BLUE}[2] バージョン情報確認${NC}"
if [ -f "$INFO_PLIST" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "")
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" 2>/dev/null || echo "")

    if [ -n "$VERSION" ]; then
        echo -e "  バージョン: ${GREEN}${VERSION}${NC}"
        check_passed "CFBundleShortVersionString 設定確認"
    else
        check_failed "CFBundleShortVersionString が設定されていません"
    fi

    if [ -n "$BUILD" ]; then
        echo -e "  ビルド番号: ${GREEN}${BUILD}${NC}"
        check_passed "CFBundleVersion 設定確認"
    else
        check_failed "CFBundleVersion が設定されていません"
    fi
else
    check_failed "Info.plistが見つからないため、バージョン確認をスキップ"
fi

echo ""

# 3. Bundle ID確認
echo -e "${BLUE}[3] Bundle ID確認${NC}"
if [ -f "$XCODE_PROJECT/project.pbxproj" ]; then
    BUNDLE_ID=$(grep -m 1 "PRODUCT_BUNDLE_IDENTIFIER = " "$XCODE_PROJECT/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | xargs)

    if [ "$BUNDLE_ID" = "love.elio.app" ]; then
        echo -e "  Bundle ID: ${GREEN}${BUNDLE_ID}${NC}"
        check_passed "Bundle ID 正常"
    else
        echo -e "  Bundle ID: ${RED}${BUNDLE_ID}${NC}"
        check_warning "Bundle ID が love.elio.app ではありません"
    fi
else
    check_failed "project.pbxprojが見つかりません"
fi

echo ""

# 4. 権限説明文の確認
echo -e "${BLUE}[4] 権限説明文 (Usage Descriptions) 確認${NC}"
REQUIRED_PERMISSIONS=(
    "NSCalendarsUsageDescription"
    "NSContactsUsageDescription"
    "NSPhotoLibraryUsageDescription"
    "NSLocationWhenInUseUsageDescription"
    "NSRemindersUsageDescription"
    "NSCameraUsageDescription"
    "NSMicrophoneUsageDescription"
    "NSSpeechRecognitionUsageDescription"
    "NSPhotoLibraryAddUsageDescription"
)

if [ -f "$INFO_PLIST" ]; then
    for permission in "${REQUIRED_PERMISSIONS[@]}"; do
        VALUE=$(/usr/libexec/PlistBuddy -c "Print :$permission" "$INFO_PLIST" 2>/dev/null || echo "")

        if [ -n "$VALUE" ]; then
            check_passed "$permission: ${VALUE}"
        else
            check_failed "$permission が設定されていません"
        fi
    done
else
    check_failed "Info.plistが見つからないため、権限確認をスキップ"
fi

echo ""

# 5. 暗号化使用の申告確認
echo -e "${BLUE}[5] 暗号化使用申告確認${NC}"
if [ -f "$INFO_PLIST" ]; then
    ENCRYPTION=$(/usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$INFO_PLIST" 2>/dev/null || echo "")

    if [ "$ENCRYPTION" = "false" ]; then
        check_passed "ITSAppUsesNonExemptEncryption = false (暗号化不使用)"
    else
        check_warning "ITSAppUsesNonExemptEncryption が false でないか、設定されていません"
    fi
else
    check_failed "Info.plistが見つかりません"
fi

echo ""

# 6. アプリアイコンの確認
echo -e "${BLUE}[6] アプリアイコン確認${NC}"
ICON_PATH="${PROJECT_ROOT}/LocalAIAgent/Resources/Assets.xcassets/AppIcon.appiconset"

if [ -d "$ICON_PATH" ]; then
    ICON_COUNT=$(find "$ICON_PATH" -name "*.png" | wc -l | xargs)

    if [ "$ICON_COUNT" -gt 0 ]; then
        echo -e "  アイコン数: ${GREEN}${ICON_COUNT}${NC} 個"
        check_passed "アプリアイコン 設定確認"
    else
        check_failed "アイコン画像が見つかりません"
    fi
else
    check_failed "AppIcon.appiconset が見つかりません"
fi

echo ""

# 7. プライバシーマニフェストの内容確認
echo -e "${BLUE}[7] プライバシーマニフェスト確認${NC}"
if [ -f "$PRIVACY_MANIFEST" ]; then
    # NSPrivacyTracking = false の確認
    if grep -q "<key>NSPrivacyTracking</key>" "$PRIVACY_MANIFEST" && grep -q "<false/>" "$PRIVACY_MANIFEST"; then
        check_passed "NSPrivacyTracking = false"
    else
        check_warning "NSPrivacyTracking が false でない可能性があります"
    fi

    # NSPrivacyCollectedDataTypes の確認
    if grep -q "<key>NSPrivacyCollectedDataTypes</key>" "$PRIVACY_MANIFEST"; then
        check_passed "NSPrivacyCollectedDataTypes 設定確認"
    else
        check_warning "NSPrivacyCollectedDataTypes が設定されていません"
    fi

    # NSPrivacyAccessedAPITypes の確認
    if grep -q "<key>NSPrivacyAccessedAPITypes</key>" "$PRIVACY_MANIFEST"; then
        check_passed "NSPrivacyAccessedAPITypes 設定確認"
    else
        check_warning "NSPrivacyAccessedAPITypes が設定されていません"
    fi
else
    check_failed "PrivacyInfo.xcprivacy が見つかりません"
fi

echo ""

# 8. App Store Connect必須資料の確認
echo -e "${BLUE}[8] App Store Connect資料確認${NC}"
APPSTORE_DIR="${PROJECT_ROOT}/AppStore"

if [ -d "$APPSTORE_DIR" ]; then
    check_passed "AppStore ディレクトリ 存在確認"

    # 必須ファイルの確認
    REQUIRED_FILES=(
        "Description_en.txt"
        "Description_ja.txt"
        "Keywords.txt"
        "Subtitle.txt"
        "ReviewNotes.txt"
        "privacy.html"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$APPSTORE_DIR/$file" ]; then
            check_passed "$file 存在確認"
        else
            check_warning "$file が見つかりません (作成推奨)"
        fi
    done
else
    check_warning "AppStore ディレクトリが見つかりません"
fi

echo ""

# 9. ビルド設定の確認
echo -e "${BLUE}[9] ビルド設定確認${NC}"
if [ -f "$XCODE_PROJECT/project.pbxproj" ]; then
    # Bitcode設定 (iOS 14以降は非推奨だが念のため確認)
    if grep -q "ENABLE_BITCODE = YES" "$XCODE_PROJECT/project.pbxproj"; then
        check_passed "Bitcode有効 (オプション)"
    else
        check_warning "Bitcode無効 (iOS 14以降では問題なし)"
    fi

    # Swift Version確認
    SWIFT_VERSION=$(grep -m 1 "SWIFT_VERSION = " "$XCODE_PROJECT/project.pbxproj" | sed 's/.*= \(.*\);/\1/' | xargs)
    if [ -n "$SWIFT_VERSION" ]; then
        echo -e "  Swift Version: ${GREEN}${SWIFT_VERSION}${NC}"
        check_passed "Swift Version 設定確認"
    else
        check_warning "Swift Version が明示的に設定されていません"
    fi
else
    check_failed "project.pbxproj が見つかりません"
fi

echo ""

# 10. Git状態の確認
echo -e "${BLUE}[10] Gitリポジトリ状態確認${NC}"
cd "$PROJECT_ROOT"

if git rev-parse --git-dir > /dev/null 2>&1; then
    check_passed "Gitリポジトリ 確認"

    # 未コミットの変更確認
    if [ -z "$(git status --porcelain)" ]; then
        check_passed "未コミットの変更なし (クリーンな状態)"
    else
        check_warning "未コミットの変更があります (申請前にコミット推奨)"
        git status --short
    fi

    # 現在のブランチ確認
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo -e "  現在のブランチ: ${GREEN}${CURRENT_BRANCH}${NC}"

    # 最新コミット確認
    LAST_COMMIT=$(git log -1 --pretty=format:"%h - %s (%ar)")
    echo -e "  最新コミット: ${GREEN}${LAST_COMMIT}${NC}"
else
    check_warning "Gitリポジトリではありません"
fi

echo ""

# 11. ストレージ空き容量確認
echo -e "${BLUE}[11] ストレージ空き容量確認${NC}"
AVAILABLE_SPACE=$(df -h "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
echo -e "  利用可能: ${GREEN}${AVAILABLE_SPACE}${NC}"

# 空き容量が5GB未満の場合は警告
AVAILABLE_GB=$(df -g "$PROJECT_ROOT" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_GB" -lt 5 ]; then
    check_warning "ストレージ空き容量が5GB未満です (ビルド時に問題が発生する可能性)"
else
    check_passed "ストレージ空き容量 十分"
fi

echo ""

# 12. Xcodeバージョン確認
echo -e "${BLUE}[12] Xcodeバージョン確認${NC}"
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    XCODE_BUILD=$(xcodebuild -version | tail -n 1)

    echo -e "  ${GREEN}${XCODE_VERSION}${NC}"
    echo -e "  ${GREEN}${XCODE_BUILD}${NC}"
    check_passed "Xcode インストール確認"

    # Xcode 15以上かチェック
    XCODE_MAJOR=$(echo "$XCODE_VERSION" | grep -o '[0-9]\+' | head -n 1)
    if [ "$XCODE_MAJOR" -ge 15 ]; then
        check_passed "Xcode 15以上 (推奨バージョン)"
    else
        check_warning "Xcode 15以上を推奨します"
    fi
else
    check_failed "xcodebuild コマンドが見つかりません (Xcodeがインストールされていない可能性)"
fi

echo ""

# 13. CocoaPods/Swift Package Manager確認
echo -e "${BLUE}[13] 依存関係管理確認${NC}"
if [ -f "${PROJECT_ROOT}/Podfile" ]; then
    check_passed "CocoaPods 使用"

    if [ -f "${PROJECT_ROOT}/Podfile.lock" ]; then
        check_passed "Podfile.lock 存在確認"
    else
        check_warning "Podfile.lock が見つかりません (pod install 実行推奨)"
    fi
fi

# SPM (Swift Package Manager) の確認
if [ -d "${XCODE_PROJECT}/project.xcworkspace/xcshareddata/swiftpm" ]; then
    check_passed "Swift Package Manager 使用"
else
    check_warning "Swift Package Manager の設定が見つかりません"
fi

echo ""

# ========================================
# 最終結果サマリー
# ========================================
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}チェック結果サマリー${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "${GREEN}成功: ${PASSED}${NC}"
echo -e "${RED}失敗: ${FAILED}${NC}"
echo -e "${YELLOW}警告: ${WARNINGS}${NC}"
echo ""

# 判定
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 全ての必須チェックが完了しました!${NC}"
    echo -e "${GREEN}App Store申請の準備ができています。${NC}"
    echo ""
    echo -e "${BLUE}次のステップ:${NC}"
    echo "1. Xcode → Product → Archive でアーカイブ作成"
    echo "2. Organizer → Distribute App → App Store Connect"
    echo "3. App Store Connectで全情報を入力"
    echo "4. 審査のために提出"
    echo ""
    echo -e "${BLUE}参考資料:${NC}"
    echo "- /Users/yuki/workspace/ai/elio/APP_STORE_SUBMISSION_CHECKLIST.md"
    echo "- /Users/yuki/workspace/ai/elio/APP_STORE_REVIEW_NOTES.md"
    echo "- /Users/yuki/workspace/ai/elio/APP_STORE_PRIVACY_DETAILS.md"

    exit 0
else
    echo -e "${RED}✗ ${FAILED}個の必須項目でエラーが発生しました。${NC}"
    echo -e "${RED}上記のエラーを修正してから、再度実行してください。${NC}"

    exit 1
fi
