#!/bin/sh

echo "=== Xcode Cloud: Post-xcodebuild ==="
echo "Action: ${CI_XCODEBUILD_ACTION}"
echo "Exit status: ${CI_XCODEBUILD_EXIT_CODE}"

if [ "$CI_XCODEBUILD_ACTION" = "test" ]; then
    echo "Test results: ${CI_RESULT_BUNDLE_PATH}"

    if [ "${CI_XCODEBUILD_EXIT_CODE}" -ne 0 ]; then
        echo "TESTS FAILED"
    else
        echo "ALL TESTS PASSED"
    fi
fi

echo "=== Post-xcodebuild complete ==="
