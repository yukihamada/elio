#!/bin/bash

# Install certificates and provisioning profiles for CI/CD
# This script sets up code signing for GitHub Actions

set -euo pipefail

echo "=== Installing certificates and provisioning profiles ==="

# Variables
KEYCHAIN_PATH="${HOME}/Library/Keychains/build.keychain-db"
KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-build}"

# Create a temporary keychain
echo "Creating temporary keychain..."
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" || true
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Add to search list and set as default
security list-keychains -d user -s "$KEYCHAIN_PATH" $(security list-keychains -d user | tr -d '"')
security default-keychain -s "$KEYCHAIN_PATH"

# Import certificate
if [ -n "${CERTIFICATE_BASE64:-}" ]; then
    echo "Importing certificate..."
    CERTIFICATE_PATH="${RUNNER_TEMP:-/tmp}/certificate.p12"
    echo "$CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"

    security import "$CERTIFICATE_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "${CERTIFICATE_PASSWORD:-}" \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    rm -f "$CERTIFICATE_PATH"
    echo "Certificate imported successfully"
else
    echo "Warning: CERTIFICATE_BASE64 not set, skipping certificate import"
fi

# Set key partition list
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# Install provisioning profile
if [ -n "${PROVISIONING_PROFILE_BASE64:-}" ]; then
    echo "Installing provisioning profile..."
    PROFILE_PATH="${RUNNER_TEMP:-/tmp}/profile.mobileprovision"
    echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

    # Get UUID from provisioning profile
    UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" /dev/stdin <<< $(/usr/bin/security cms -D -i "$PROFILE_PATH"))

    # Create Provisioning Profiles directory if it doesn't exist
    PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
    mkdir -p "$PROFILES_DIR"

    # Copy provisioning profile
    cp "$PROFILE_PATH" "$PROFILES_DIR/${UUID}.mobileprovision"

    rm -f "$PROFILE_PATH"
    echo "Provisioning profile installed: ${UUID}"
else
    echo "Warning: PROVISIONING_PROFILE_BASE64 not set, skipping provisioning profile installation"
fi

# Verify installation
echo "=== Verification ==="
echo "Default keychain:"
security default-keychain
echo "Keychain search list:"
security list-keychains
echo "Provisioning profiles:"
ls -la "${HOME}/Library/MobileDevice/Provisioning Profiles/" || true

echo "=== Certificate installation complete ==="
