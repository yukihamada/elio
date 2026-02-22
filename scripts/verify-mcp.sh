#!/bin/bash

# ElioChat MCP機能検証スクリプト
# Usage: ./scripts/verify-mcp.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=================================================="
echo "ElioChat MCP機能検証スクリプト"
echo "=================================================="
echo ""

# カラー定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 結果カウンター
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# テスト結果記録
log_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASS_COUNT++))
}

log_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAIL_COUNT++))
}

log_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARN_COUNT++))
}

log_info() {
    echo -e "ℹ INFO: $1"
}

# 1. ディレクトリ構造確認
echo "=== 1. ディレクトリ構造確認 ==="
echo ""

if [ -d "LocalAIAgent/MCP" ]; then
    log_pass "MCP ディレクトリが存在"
else
    log_fail "MCP ディレクトリが見つかりません"
    exit 1
fi

if [ -d "LocalAIAgent/MCP/Servers" ]; then
    log_pass "MCP/Servers ディレクトリが存在"
else
    log_fail "MCP/Servers ディレクトリが見つかりません"
    exit 1
fi

echo ""

# 2. MCPサーバー実装ファイルの確認
echo "=== 2. MCPサーバー実装ファイルの確認 ==="
echo ""

SERVER_FILES=(
    "CalendarServer.swift"
    "RemindersServer.swift"
    "ContactsServer.swift"
    "PhotosServer.swift"
    "LocationServer.swift"
    "FileSystemServer.swift"
    "WebSearchServer.swift"
    "NotesServer.swift"
    "WeatherServer.swift"
    "ShortcutsServer.swift"
    "EmergencyKnowledgeBaseServer.swift"
    "TranslationServer.swift"
)

FOUND_COUNT=0
for file in "${SERVER_FILES[@]}"; do
    if [ -f "LocalAIAgent/MCP/Servers/$file" ]; then
        log_pass "実装確認: $file"
        ((FOUND_COUNT++))
    else
        log_fail "未実装: $file"
    fi
done

echo ""
log_info "実装済みサーバー数: $FOUND_COUNT / ${#SERVER_FILES[@]}"
echo ""

# 3. MCPプロトコル実装の確認
echo "=== 3. MCPプロトコル実装の確認 ==="
echo ""

if grep -q "protocol MCPServer" LocalAIAgent/MCP/MCPProtocol.swift; then
    log_pass "MCPServer プロトコル定義が存在"
else
    log_fail "MCPServer プロトコル定義が見つかりません"
fi

if grep -q "struct MCPRequest.*Codable" LocalAIAgent/MCP/MCPProtocol.swift; then
    log_pass "MCPRequest (JSON-RPC 2.0) が実装されている"
else
    log_fail "MCPRequest の実装が不完全"
fi

if grep -q "struct MCPResponse.*Codable" LocalAIAgent/MCP/MCPProtocol.swift; then
    log_pass "MCPResponse が実装されている"
else
    log_fail "MCPResponse の実装が不完全"
fi

if grep -q "enum MCPMethod.*String" LocalAIAgent/MCP/MCPProtocol.swift; then
    log_pass "MCPMethod enum が定義されている"
else
    log_warn "MCPMethod enum が見つかりません (オプショナル)"
fi

echo ""

# 4. MCPClient の実装確認
echo "=== 4. MCPClient の実装確認 ==="
echo ""

if grep -q "func registerBuiltInServers" LocalAIAgent/MCP/MCPClient.swift; then
    log_pass "registerBuiltInServers() メソッドが存在"
else
    log_fail "registerBuiltInServers() が見つかりません"
fi

if grep -q "func callTool" LocalAIAgent/MCP/MCPClient.swift; then
    log_pass "callTool() メソッドが実装されている"
else
    log_fail "callTool() が実装されていません"
fi

if grep -q "func listAllTools" LocalAIAgent/MCP/MCPClient.swift; then
    log_pass "listAllTools() メソッドが実装されている"
else
    log_fail "listAllTools() が実装されていません"
fi

echo ""

# 5. Info.plist 権限確認
echo "=== 5. Info.plist 権限確認 ==="
echo ""

REQUIRED_PERMISSIONS=(
    "NSCalendarsUsageDescription"
    "NSContactsUsageDescription"
    "NSPhotoLibraryUsageDescription"
    "NSLocationWhenInUseUsageDescription"
    "NSRemindersUsageDescription"
)

for permission in "${REQUIRED_PERMISSIONS[@]}"; do
    if grep -q "$permission" LocalAIAgent/Resources/Info.plist; then
        log_pass "権限定義: $permission"
    else
        log_fail "権限定義なし: $permission"
    fi
done

echo ""

# 6. AppState での MCP 有効化確認
echo "=== 6. AppState での MCP 有効化確認 ==="
echo ""

if grep -q "enabledMCPServers.*Set<String>" LocalAIAgent/App/AppState.swift; then
    log_pass "enabledMCPServers プロパティが存在"
else
    log_fail "enabledMCPServers が見つかりません"
fi

if grep -q "registerBuiltInServers" LocalAIAgent/App/AppState.swift; then
    log_pass "AppState で registerBuiltInServers() が呼び出されている"
else
    log_warn "AppState で registerBuiltInServers() の呼び出しが見つかりません"
fi

echo ""

# 7. ToolParser の実装確認
echo "=== 7. ToolParser の実装確認 ==="
echo ""

if grep -q "struct ToolParser" LocalAIAgent/Agent/ToolParser.swift; then
    log_pass "ToolParser が実装されている"
else
    log_fail "ToolParser が見つかりません"
fi

if grep -q "extractToolCalls" LocalAIAgent/Agent/ToolParser.swift; then
    log_pass "extractToolCalls() メソッドが存在"
else
    log_fail "extractToolCalls() が実装されていません"
fi

echo ""

# 8. テストファイルの確認
echo "=== 8. テストファイルの確認 ==="
echo ""

if [ -f "LocalAIAgentTests/ToolParserTests.swift" ]; then
    log_pass "ToolParserTests.swift が存在"

    # テストケース数をカウント
    TEST_COUNT=$(grep -c "func test" LocalAIAgentTests/ToolParserTests.swift || echo 0)
    log_info "テストケース数: $TEST_COUNT"
else
    log_warn "ToolParserTests.swift が見つかりません"
fi

echo ""

# 9. Xcode プロジェクトの確認
echo "=== 9. Xcode プロジェクトの確認 ==="
echo ""

if [ -f "ElioChat.xcodeproj/project.pbxproj" ]; then
    log_pass "Xcode プロジェクトファイルが存在"
else
    log_fail "Xcode プロジェクトが見つかりません"
    exit 1
fi

# スキーム確認
if xcodebuild -list -project ElioChat.xcodeproj 2>&1 | grep -q "LocalAIAgent"; then
    log_pass "LocalAIAgent スキームが存在"
else
    log_fail "LocalAIAgent スキームが見つかりません"
fi

echo ""

# 10. ビルド可能性チェック (オプション)
echo "=== 10. ビルド可能性チェック (オプション) ==="
echo ""

read -p "Xcode ビルドチェックを実行しますか? (時間がかかります) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "ビルドチェック開始..."

    if xcodebuild \
        -project ElioChat.xcodeproj \
        -scheme LocalAIAgent \
        -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
        -dry-run \
        build > /dev/null 2>&1; then
        log_pass "ビルド設定は正常"
    else
        log_warn "ビルドに問題がある可能性があります"
    fi
else
    log_info "ビルドチェックをスキップ"
fi

echo ""

# 11. コード品質チェック
echo "=== 11. コード品質チェック ==="
echo ""

# MCP関連のコード行数
MCP_LINES=$(find LocalAIAgent/MCP -name "*.swift" -exec wc -l {} + | tail -1 | awk '{print $1}')
log_info "MCP関連コード行数: $MCP_LINES 行"

# Swiftファイル数
MCP_FILES=$(find LocalAIAgent/MCP -name "*.swift" | wc -l | xargs)
log_info "MCP関連Swiftファイル数: $MCP_FILES ファイル"

# TODO/FIXME の確認
TODO_COUNT=$(grep -r "TODO\|FIXME" LocalAIAgent/MCP --include="*.swift" | wc -l | xargs)
if [ "$TODO_COUNT" -gt 0 ]; then
    log_warn "TODO/FIXME が $TODO_COUNT 箇所あります"
else
    log_pass "未解決のTODO/FIXMEはありません"
fi

echo ""

# 結果サマリー
echo "=================================================="
echo "検証結果サマリー"
echo "=================================================="
echo ""
echo -e "${GREEN}PASS:${NC} $PASS_COUNT"
echo -e "${RED}FAIL:${NC} $FAIL_COUNT"
echo -e "${YELLOW}WARN:${NC} $WARN_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ 全ての必須チェックに合格しました${NC}"
    exit 0
else
    echo -e "${RED}✗ $FAIL_COUNT 件の問題が見つかりました${NC}"
    echo ""
    echo "詳細は MCP_VERIFICATION_GUIDE.md を参照してください"
    exit 1
fi
