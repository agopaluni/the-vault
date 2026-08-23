#!/bin/bash
# Build The Vault (Release) and install it to /Applications.
# Usage: ./build_and_install.sh
set -e
cd "$(dirname "$0")"

echo "Regenerating Xcode project..."
python3 gen_pbxproj.py

echo "Quitting any running instance..."
osascript -e 'quit app "The Vault"' 2>/dev/null || true
pkill -f "The Vault.app/Contents/MacOS" 2>/dev/null || true
sleep 1

echo "Building (Release)..."
rm -rf /tmp/vault_build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TheVault.xcodeproj -target "The Vault" -configuration Release \
  SYMROOT=/tmp/vault_build build

echo "Installing to /Applications..."
rm -rf /Applications/"The Vault.app"
cp -R "/tmp/vault_build/Release/The Vault.app" /Applications/
xattr -dr com.apple.quarantine /Applications/"The Vault.app" 2>/dev/null || true

echo "Launching..."
open /Applications/"The Vault.app"
echo "Done — The Vault.app is in /Applications."
