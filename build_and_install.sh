#!/bin/bash
# Build The Vault (Release) and install it to /Applications.
#
# Usage:
#   ./build_and_install.sh            # build + install to /Applications, then launch
#   INSTALL_DIR=~/Applications ./build_and_install.sh
#   DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer ./build_and_install.sh
set -euo pipefail
cd "$(dirname "$0")"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d)}"
APP_NAME="The Vault.app"

# --- Locate a full Xcode (xcodebuild and actool need it; Command Line Tools
# --- alone can't compile asset catalogs). Honors DEVELOPER_DIR if already set.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  selected="$(xcode-select -p 2>/dev/null || true)"
  if [ -n "$selected" ] && [ -d "$selected/usr/bin" ] && [[ "$selected" != *CommandLineTools* ]]; then
    DEVELOPER_DIR="$selected"
  else
    for candidate in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
      if [ -d "$candidate/Contents/Developer" ]; then
        DEVELOPER_DIR="$candidate/Contents/Developer"
        break
      fi
    done
  fi
fi

if [ -z "${DEVELOPER_DIR:-}" ] || [ ! -d "$DEVELOPER_DIR" ]; then
  echo "error: full Xcode not found." >&2
  echo "Install Xcode from the App Store, then either run:" >&2
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  echo "or re-run this script with DEVELOPER_DIR set explicitly." >&2
  exit 1
fi
export DEVELOPER_DIR
echo "Using Xcode at: $DEVELOPER_DIR"

echo "Regenerating Xcode project..."
python3 gen_pbxproj.py

echo "Quitting any running instance..."
osascript -e 'quit app "The Vault"' 2>/dev/null || true
pkill -f "$APP_NAME/Contents/MacOS" 2>/dev/null || true
sleep 1

echo "Building (Release)..."
xcodebuild -project TheVault.xcodeproj -target "The Vault" -configuration Release \
  SYMROOT="$BUILD_DIR" build

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/$APP_NAME"
cp -R "$BUILD_DIR/Release/$APP_NAME" "$INSTALL_DIR/"
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo "Launching..."
open "$INSTALL_DIR/$APP_NAME"
echo "Done — $APP_NAME is in $INSTALL_DIR."
