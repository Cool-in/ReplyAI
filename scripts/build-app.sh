#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

cache="$HOME/Library/Developer/BuildCaches/ReplyAI/macos/Debug/ReplyAI"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ "${1:-}" != "--package-only" ]]; then
    swift build --scratch-path "$cache"
fi

bundle="$cache/ReplyAI.app"
binary_dir="$(swift build --scratch-path "$cache" --show-bin-path)"
if /usr/bin/pgrep -x ReplyAI >/dev/null; then
    echo "Quit ReplyAI before replacing its local app bundle." >&2
    exit 1
fi

mkdir -p "$bundle/Contents/MacOS"
install -m 755 "$binary_dir/ReplyAI" "$bundle/Contents/MacOS/ReplyAI"
install -m 644 scripts/Info.plist "$bundle/Contents/Info.plist"
mkdir -p "$bundle/Contents/Resources"
install -m 644 Resources/AppIcon.icns "$bundle/Contents/Resources/AppIcon.icns"
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
printf '%s\n' "$bundle"
