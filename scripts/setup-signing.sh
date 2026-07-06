#!/bin/zsh
# Create a stable, self-signed code-signing identity for Glance so that
# calendar (TCC) permission survives rebuilds.
#
# Why this exists: ad-hoc signing (`codesign -s -`) gives the app a new code
# hash on every build. macOS ties calendar permission to the app's designated
# requirement, so with ad-hoc signing every rebuild looks like a "new" app and
# silently wipes the permission. Signing with a fixed self-signed certificate
# keeps the designated requirement constant (identifier + cert leaf), so you
# grant calendar access once and it persists across all future builds.
#
# Idempotent: does nothing if the identity already exists. Run once.
set -euo pipefail

IDENTITY="Glance Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "✓ '$IDENTITY' already exists — nothing to do."
    exit 0
fi

# LibreSSL (the system default) can't produce a keychain-importable PKCS#12,
# so prefer a real OpenSSL 3 if one is installed (Homebrew).
OSSL=openssl
for candidate in /opt/homebrew/opt/openssl@3/bin/openssl /opt/homebrew/bin/openssl /usr/local/opt/openssl@3/bin/openssl /usr/local/bin/openssl; do
    if [[ -x "$candidate" ]] && "$candidate" version | grep -q "^OpenSSL 3"; then
        OSSL="$candidate"
        break
    fi
done
if ! "$OSSL" version | grep -q "^OpenSSL 3"; then
    echo "Error: OpenSSL 3 not found. Install it with: brew install openssl@3" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$OSSL" req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -legacy: use the older PKCS#12 MAC that Apple's `security` can import.
"$OSSL" pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/glance-signing.p12" -passout pass:glance -name "$IDENTITY" >/dev/null 2>&1

# -A lets codesign use the key without a per-build authorization prompt.
security import "$TMP/glance-signing.p12" -k "$KEYCHAIN" -P glance -A >/dev/null

echo "✓ Created '$IDENTITY'. Calendar permission will now persist across rebuilds."
echo "  (The certificate shows as untrusted — that's expected and fine for local signing.)"
