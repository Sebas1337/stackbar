#!/usr/bin/env bash
# Print the CHANGELOG.md section for a version (without its heading).
# Usage: scripts/changelog-notes.sh 0.1.0 [CHANGELOG.md]
set -euo pipefail

version="${1:?usage: $0 <version> [changelog]}"
changelog="${2:-CHANGELOG.md}"

notes="$(awk -v v="$version" '
  /^## \[/ { if (found) exit; found = index($0, "## [" v "]") == 1; next }
  found { print }
' "$changelog")"

if [ -z "${notes//[[:space:]]/}" ]; then
  echo "error: no entries for [$version] in $changelog" >&2
  exit 1
fi
printf '%s\n' "$notes"
