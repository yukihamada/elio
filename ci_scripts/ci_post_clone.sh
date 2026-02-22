#!/bin/sh
set -e

echo "=== Xcode Cloud: Post-clone ==="
echo "Branch: ${CI_BRANCH}"
echo "Commit: ${CI_COMMIT}"
echo "Workspace: ${CI_WORKSPACE}"

# Print Xcode version
xcodebuild -version

# Print available disk space
df -h /

echo "=== Post-clone complete ==="
