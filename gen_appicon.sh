#!/bin/bash
# Generate the macOS AppIcon set from one square source image.
# Usage: ./gen_appicon.sh /path/to/logo.png
set -e
SRC="${1:?Usage: gen_appicon.sh <source-image.png>}"
DST="$(cd "$(dirname "$0")" && pwd)/TheVault/Resources/Assets.xcassets/AppIcon.appiconset"

for size in 16 32 64 128 256 512 1024; do
  sips -s format png -z "$size" "$size" "$SRC" --out "$DST/icon_${size}.png" >/dev/null
done
echo "Wrote icon_{16,32,64,128,256,512,1024}.png to AppIcon.appiconset"
