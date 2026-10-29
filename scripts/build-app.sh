#!/usr/bin/env bash
# Build build/Stackbar.app (macOS only): release binary + Info.plist with the version from VERSION
# and the commit count as build number. Signed with $SIGN_IDENTITY (default "Stackbar Dev", see
# make-dev-cert.sh), or ad-hoc when that identity isn't in the keychain (CI, or before `make cert`).
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:-Stackbar Dev}"
app="build/Stackbar.app"
plist="$app/Contents/Info.plist"
version="$(tr -d '[:space:]' < VERSION)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"

swift build -c release --product Stackbar
bin="$(swift build -c release --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Stackbar" "$app/Contents/MacOS/Stackbar"
cp Resources/Info.plist "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"

if security find-identity -v -p codesigning | grep -qF "\"$identity\""; then
  codesign --force --options runtime --sign "$identity" "$app"
else
  echo "warning: signing identity \"$identity\" not found, signing ad-hoc." \
    "Privacy permissions reset on every build; run 'make cert' once to fix." >&2
  codesign --force --options runtime --sign - "$app"
fi
codesign --verify --strict "$app"

echo "Built $app ($version, build $build)"
