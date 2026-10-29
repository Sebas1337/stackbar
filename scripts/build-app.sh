#!/usr/bin/env bash
# Build build/Stackbar.app (macOS only): release binary + Info.plist with the version from VERSION
# and the commit count as build number. Signed with $SIGN_IDENTITY (default "Stackbar Dev", see
# make-dev-cert.sh), or ad-hoc when that identity isn't in the keychain (CI, or before `make cert`).
#
# ARCHS: space-separated architectures, default the host's. "arm64 x86_64" builds a universal
# binary (release and CI do, because macOS 26 still runs on some Intel Macs).
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:-Stackbar Dev}"
archs="${ARCHS:-$(uname -m)}"
app="build/Stackbar.app"
plist="$app/Contents/Info.plist"
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

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Stackbar"
cp Resources/Info.plist "$plist"
plutil -replace CFBundleShortVersionString -string "$version" "$plist"
plutil -replace CFBundleVersion -string "$build" "$plist"
if [ "$(plutil -extract LSMinimumSystemVersion raw "$plist")" != "$min_macos" ]; then
  echo "error: LSMinimumSystemVersion in Resources/Info.plist is not $min_macos" >&2
  exit 1
fi

# Sign by certificate hash: a name can match several identities (e.g. after re-creating the cert).
hash="$(security find-identity -v -p codesigning | awk -v name="\"$identity\"" 'index($0, name) { print $2; exit }')"
if [ -n "$hash" ]; then
  codesign --force --options runtime --sign "$hash" "$app"
else
  echo "warning: signing identity \"$identity\" not found, signing ad-hoc." \
    "Privacy permissions reset on every build; run 'make cert' once to fix." >&2
  codesign --force --options runtime --sign - "$app"
fi
codesign --verify --strict "$app"

echo "Built $app ($version, build $build, $(lipo -archs "$app/Contents/MacOS/Stackbar"))"
