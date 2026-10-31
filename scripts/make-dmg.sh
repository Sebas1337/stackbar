#!/usr/bin/env bash
# Pack build/Stackbar.app into dist/Stackbar-<VERSION>.dmg (macOS only): a window with the app, a
# link to Applications and an arrow between them on the background (scripts/dmg-background.swift),
# so it is clear where to drag it. Finder lays the window out (AppleScript) on a writable image,
# which is then compressed. Signed with $SIGN_IDENTITY like the app when it is in the keychain.
# Run `make app` first (`make dmg` does).
#
# REQUIRE_LAYOUT=1: fail instead of warning when Finder couldn't lay the window out (CI, release).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/signing.sh

identity="${SIGN_IDENTITY:-Stackbar Dev}"
version="$(tr -d '[:space:]' < VERSION)"
app="build/Stackbar.app"
dmg="dist/Stackbar-$version.dmg"
volume="Stackbar $version"

[ -d "$app" ] || { echo "error: $app not found; run 'make app' first" >&2; exit 1; }

work="$(mktemp -d)"
mountpoint=""
cleanup() {
  if [ -n "$mountpoint" ]; then hdiutil detach -quiet -force "$mountpoint" || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/Stackbar.app"
ln -s /Applications "$stage/Applications"

# Background: drawn at 1x and 2x, joined into one TIFF Finder picks the right size from.
swiftc -O -o "$work/dmg-background" scripts/dmg-background.swift
"$work/dmg-background" "$work"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" \
  -out "$stage/.background/background.tiff" 2>/dev/null

# A volume of that name already mounted would get the Finder layout instead of ours.
if [ -d "/Volumes/$volume" ]; then
  echo "error: /Volumes/$volume is mounted; eject it first" >&2
  exit 1
fi

rw="$work/rw.dmg"
# Room for Finder's .DS_Store on top of the app.
size="$(( $(du -sm "$stage" | cut -f1) + 20 ))m"
hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW -size "$size" "$rw"
mountpoint="$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')"
[ -n "$mountpoint" ] || { echo "error: could not mount $rw" >&2; exit 1; }

# Window geometry and icon centres match scripts/dmg-background.swift (540 × 380 pt).
layout() {
  osascript <<EOF
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- 380 pt of content (the background's height) plus the 28 pt title bar.
    set the bounds of container window to {200, 120, 740, 528}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Stackbar.app" of container window to {140, 170}
    set position of item "Applications" of container window to {400, 170}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF
}

# Finder may still be indexing the fresh volume: try twice. Without Finder (or without the
# Automation permission) the DMG still works, just without the arrow.
if layout || { sleep 3; layout; }; then
  # Finder writes .DS_Store lazily; wait for it so the layout ends up in the image.
  for _ in $(seq 1 10); do
    [ -f "$mountpoint/.DS_Store" ] && break
    sleep 1
  done
fi
if [ ! -f "$mountpoint/.DS_Store" ]; then
  if [ "${REQUIRE_LAYOUT:-}" = 1 ]; then
    echo "error: Finder couldn't lay out the DMG window" >&2
    exit 1
  fi
  echo "warning: Finder couldn't lay out the DMG window; it shows the plain file list" >&2
fi
# Mounting adds macOS's bookkeeping folders; they don't belong in the image.
rm -rf "$mountpoint/.fseventsd" "$mountpoint/.Trashes" 2>/dev/null || true

sync
hdiutil detach -quiet "$mountpoint" || hdiutil detach -quiet -force "$mountpoint"
mountpoint=""

mkdir -p dist
rm -f "$dmg"
hdiutil convert -quiet "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg"

hash="$(require_signing_hash "$identity")"
if [ -n "$hash" ]; then
  codesign --force --sign "$hash" "$dmg"
fi
hdiutil verify -quiet "$dmg"
echo "Built $dmg"
