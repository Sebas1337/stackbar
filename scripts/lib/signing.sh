# Sourced by build-app.sh and make-dmg.sh: the code-signing identity to use.

# Prints the SHA-1 of the valid code-signing identity named $1, empty when there is none. By hash:
# a name can match several identities (e.g. after re-creating the cert).
signing_hash() {
  security find-identity -v -p codesigning | awk -v name="\"$1\"" 'index($0, name) { print $2; exit }'
}

# Like signing_hash, but exits when the identity is missing and REQUIRE_IDENTITY=1 (releases must
# never be signed ad-hoc).
require_signing_hash() {
  local hash
  hash="$(signing_hash "$1")"
  if [ -z "$hash" ] && [ "${REQUIRE_IDENTITY:-0}" = 1 ]; then
    echo "error: signing identity \"$1\" not found (REQUIRE_IDENTITY=1)" >&2
    exit 1
  fi
  printf '%s' "$hash"
}
