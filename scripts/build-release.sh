#!/bin/bash
# Builds an optimized ReplyAI.app and zips it into dist/.
#
# Optional environment:
#   SIGN_IDENTITY   Developer ID Application identity. Defaults to ad hoc ("-").
#   NOTARY_PROFILE  notarytool keychain profile. When set with a Developer ID
#                   identity, the zip is notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:--}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then unset DEVELOPER_DIR; fi

if /usr/bin/pgrep -x ReplyAI >/dev/null; then
    echo "Quit ReplyAI before packaging a release." >&2
    exit 1
fi

cache="${TMPDIR:-/tmp}/ReplyAI-release-build"
swift build -c release --scratch-path "$cache"
binary_dir="$(swift build -c release --scratch-path "$cache" --show-bin-path)"

rm -rf dist && mkdir -p dist
bundle="dist/ReplyAI.app"
mkdir -p "$bundle/Contents/MacOS"
install -m 755 "$binary_dir/ReplyAI" "$bundle/Contents/MacOS/ReplyAI"
install -m 644 scripts/Info.plist "$bundle/Contents/Info.plist"
plutil -lint "$bundle/Contents/Info.plist"

if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$bundle"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
fi
codesign --verify --strict "$bundle"

zip="dist/ReplyAI-$version.zip"
ditto -c -k --keepParent "$bundle" "$zip"

if [[ "$identity" != "-" && -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$bundle"
    rm "$zip"
    ditto -c -k --keepParent "$bundle" "$zip"
fi

shasum -a 256 "$zip"
echo "$zip"
