#!/usr/bin/env bash
# Pack build/Stackbar.app into dist/Stackbar-<VERSION>.dmg (macOS only): the app next to a link to
# Applications, to drag across. Signed with $SIGN_IDENTITY like the app when it is in the keychain.
# Run `make app` first (`make dmg` does).
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${SIGN_IDENTITY:-Stackbar Dev}"
version="$(tr -d '[:space:]' < VERSION)"
app="build/Stackbar.app"
dmg="dist/Stackbar-$version.dmg"

[ -d "$app" ] || { echo "error: $app not found; run 'make app' first" >&2; exit 1; }

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Stackbar.app"
ln -s /Applications "$stage/Applications"

mkdir -p dist
rm -f "$dmg"
hdiutil create -quiet -volname "Stackbar $version" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"

hash="$(security find-identity -v -p codesigning | awk -v name="\"$identity\"" 'index($0, name) { print $2; exit }')"
if [ -n "$hash" ]; then
  codesign --force --sign "$hash" "$dmg"
elif [ "${REQUIRE_IDENTITY:-0}" = 1 ]; then
  echo "error: signing identity \"$identity\" not found (REQUIRE_IDENTITY=1)" >&2
  exit 1
fi
hdiutil verify -quiet "$dmg"
echo "Built $dmg"
