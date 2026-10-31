#!/usr/bin/env bash
# One-time, on the macOS host: create the self-signed "Stackbar Release" code-signing certificate
# that signs every release (docs/RELEASING.md, Signing). macOS ties Accessibility and Screen
# Recording to it: releases signed with the same certificate keep the permissions across updates,
# and the in-app updater only installs releases signed with it.
#
# Writes stackbar-release.p12 (certificate + private key) and its password into OUT_DIR (default
# ~/Stackbar Release Certificate), outside the repository. Back that folder up (a password manager
# is fine): a lost certificate means every user has to grant the permissions again after the
# next update. Then store it as two GitHub Actions secrets (see the end of this script).
set -euo pipefail

name="Stackbar Release"
out="${OUT_DIR:-$HOME/Stackbar Release Certificate}"

if [ "$(uname)" != Darwin ]; then
  echo "error: run this on the macOS host, not in the container" >&2
  exit 1
fi
if [ -e "$out/stackbar-release.p12" ]; then
  echo "error: $out/stackbar-release.p12 already exists. Never replace a certificate releases were signed with." >&2
  exit 1
fi

mkdir -p "$out"
chmod 700 "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

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

# /usr/bin/openssl is LibreSSL, whose .p12 encryption `security import` understands (see
# make-dev-cert.sh). 20 years: signatures aren't timestamped, so the certificate must outlive
# every release.
openssl=/usr/bin/openssl
legacy=()
"$openssl" version | grep -q '^OpenSSL 3' && legacy=(-legacy)
"$openssl" req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.conf" \
  -keyout "$tmp/key.pem" -out "$out/stackbar-release.pem" 2>/dev/null
pass="$("$openssl" rand -hex 16)"
"$openssl" pkcs12 -export ${legacy[@]+"${legacy[@]}"} -inkey "$tmp/key.pem" -in "$out/stackbar-release.pem" \
  -name "$name" -out "$out/stackbar-release.p12" -passout "pass:$pass"
printf '%s\n' "$pass" > "$out/password.txt"
chmod 600 "$out"/*

fingerprint="$("$openssl" x509 -in "$out/stackbar-release.pem" -noout -fingerprint -sha256 | cut -d= -f2)"
cat <<DONE

Created "$name" in $out
SHA-256 fingerprint: $fingerprint

1. Back up that folder now.
2. GitHub → Sebas1337/stackbar → Settings → Environments → release (tag rule v*) → Add environment secret:
     RELEASE_CERT_P12       run: base64 -i "$out/stackbar-release.p12" | pbcopy   then paste
     RELEASE_CERT_PASSWORD  run: tr -d '\n' < "$out/password.txt" | pbcopy       then paste
DONE
