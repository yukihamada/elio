#!/bin/sh
set -e

echo "=== Xcode Cloud: Pre-xcodebuild ==="
echo "Action: ${CI_XCODEBUILD_ACTION}"

if [ "$CI_XCODEBUILD_ACTION" = "test" ]; then
    echo "Running unit tests only (UnitTests.xctestplan)"
fi

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
    echo "Building for archive (Release)"
fi

echo "=== Pre-xcodebuild complete ==="
