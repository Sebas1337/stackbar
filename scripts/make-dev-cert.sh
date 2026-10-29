#!/usr/bin/env bash
# One-time, on the macOS host: create the self-signed "Stackbar Dev" code-signing identity in the
# login keychain. Signing every build with the same certificate keeps macOS privacy permissions
# (Accessibility, Screen Recording) across rebuilds; ad-hoc signatures reset them every build.
set -euo pipefail

name="${SIGN_IDENTITY:-Stackbar Dev}"
keychain="$HOME/Library/Keychains/login.keychain-db"

if [ "$(uname)" != Darwin ]; then
  echo "error: run this on the macOS host, not in the container" >&2
  exit 1
fi
if security find-identity -v -p codesigning | grep -qF "\"$name\""; then
  echo "Signing identity \"$name\" already exists."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

trust() {
  echo "Trusting the certificate for code signing (macOS asks for your password)..."
  security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$1"
  security find-identity -v -p codesigning | grep -F "\"$name\""
  echo "Done. 'make app' now signs with \"$name\"."
}

# Imported earlier but not trusted yet (e.g. the password prompt was cancelled): finish that.
if security find-certificate -c "$name" -p "$keychain" > "$tmp/existing.pem" 2>/dev/null; then
  trust "$tmp/existing.pem"
  exit 0
fi

cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

# /usr/bin/openssl is LibreSSL, whose .p12 encryption `security import` understands. OpenSSL 3
# needs -legacy for that.
openssl=/usr/bin/openssl
legacy=()
"$openssl" version | grep -q '^OpenSSL 3' && legacy=(-legacy)

"$openssl" req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.conf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
pass="$("$openssl" rand -hex 16)"
"$openssl" pkcs12 -export ${legacy[@]+"${legacy[@]}"} -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -name "$name" -out "$tmp/identity.p12" -passout "pass:$pass"

security import "$tmp/identity.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign
trust "$tmp/cert.pem"
