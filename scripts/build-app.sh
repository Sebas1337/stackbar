#!/usr/bin/env bash
# Build build/Stackbar.app (macOS only): release binary + Info.plist with the version from VERSION
# and the commit count as build number. Signed with $SIGN_IDENTITY (default "Stackbar Dev", see
# make-dev-cert.sh), or ad-hoc when that identity isn't in the keychain (CI, or before `make cert`).
#
# REQUIRE_IDENTITY=1: fail instead of signing ad-hoc (releases: docs/RELEASING.md).
#
# ARCHS: space-separated architectures, default the host's. "arm64 x86_64" builds a universal
# binary (release and CI do, because macOS 26 still runs on some Intel Macs).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

identity="${SIGN_IDENTITY:-Stackbar Dev}"
archs="${ARCHS:-$(uname -m)}"
app="build/Stackbar.app"
version="$(tr -d '[:space:]' < VERSION)"
build="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
# Keep in sync with `platforms` in Package.swift and LSMinimumSystemVersion in Info.plist.
min_macos="26.0"

binaries=()
for arch in $archs; do
  triple="$arch-apple-macosx$min_macos"
  swift build -c release --product Stackbar --triple "$triple"
  binaries+=("$(swift build -c release --triple "$triple" --show-bin-path)/Stackbar")
done

# Assemble and sign in a temporary folder, then copy without extended attributes: in iCloud
# Drive (Desktop/Documents) files pick up Finder info, which codesign refuses ("detritus").
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
bundle="$stage/Stackbar.app"
plist="$bundle/Contents/Info.plist"

mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
lipo -create "${binaries[@]}" -output "$bundle/Contents/MacOS/Stackbar"
cp -X Resources/Info.plist "$plist"
# App icon, drawn by scripts/app-icon.swift (no image files in git).
swiftc -O -o "$stage/app-icon" scripts/app-icon.swift
"$stage/app-icon" "$stage/AppIcon.iconset"
iconutil -c icns -o "$bundle/Contents/Resources/AppIcon.icns" "$stage/AppIcon.iconset"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"
if [ "$(plutil -extract LSMinimumSystemVersion raw "$plist")" != "$min_macos" ]; then
  echo "error: LSMinimumSystemVersion in Resources/Info.plist is not $min_macos" >&2
  exit 1
fi
xattr -cr "$bundle" 2>/dev/null || true

hash="$(require_signing_hash "$identity")"
if [ -n "$hash" ]; then
  codesign --force --options runtime --sign "$hash" "$bundle"
else
  echo "warning: signing identity \"$identity\" not found, signing ad-hoc." \
    "Privacy permissions reset on every build; run 'make cert' once to fix." >&2
  codesign --force --options runtime --sign - "$bundle"
fi

rm -rf "$app"
mkdir -p "$(dirname "$app")"
ditto --noextattr --norsrc "$bundle" "$app"
codesign --verify --strict "$app"

echo "Built $app ($version, build $build, $(lipo -archs "$app/Contents/MacOS/Stackbar"))"
