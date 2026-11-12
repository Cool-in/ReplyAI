#!/bin/bash
# Builds an .icns from a 1024px PNG with Apple's own tools.
# Usage: make-icon.sh Resources/AppIcon.png path/to/AppIcon.icns
set -euo pipefail
source="$1"
output="$2"
work="$(mktemp -d)"
iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$source" -o "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$source" -o "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$output"
rm -rf "$work"
