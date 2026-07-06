#!/usr/bin/env sh
# Infrix CLI installer (ADOPTION-03).
#
#   curl -fsSL https://raw.githubusercontent.com/opendlt/infrix-cli/main/install.sh | sh
#
# Downloads the prebuilt `infrix` binary for your OS/arch from the public
# releases repo, verifies its SHA-256 against the signed checksums file, and
# installs it to a bin dir on your PATH. Override version with INFRIX_VERSION,
# install dir with INFRIX_INSTALL_DIR.
set -eu

REPO="opendlt/infrix-cli"
BASE="https://github.com/${REPO}/releases"

err() { echo "infrix-install: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || err "required tool not found: $1"; }

need uname
need tar
# Prefer curl; fall back to wget.
if command -v curl >/dev/null 2>&1; then DL="curl -fsSL"; DLO="curl -fsSL -o"; else need wget; DL="wget -qO-"; DLO="wget -qO"; fi

# --- detect platform ---
os="$(uname -s)"; arch="$(uname -m)"
case "$os" in
  Linux)  OS=linux ;;
  Darwin) OS=darwin ;;
  *) err "unsupported OS: $os (use the Windows install.ps1, or build from source)" ;;
esac
case "$arch" in
  x86_64|amd64)        ARCH=amd64 ;;
  arm64|aarch64)       ARCH=arm64 ;;
  *) err "unsupported architecture: $arch" ;;
esac

# --- resolve version ---
if [ "${INFRIX_VERSION:-}" != "" ]; then
  TAG="$INFRIX_VERSION"
else
  TAG="$($DL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name" *: *"([^"]+)".*/\1/')"
  [ -n "$TAG" ] || err "could not resolve latest release tag (set INFRIX_VERSION)"
fi
VER="${TAG#v}"   # goreleaser strips the leading v in artifact names

ARCHIVE="infrix_${VER}_${OS}_${ARCH}.tar.gz"
SUMS="infrix_${VER}_checksums.txt"
SIG="infrix_${VER}_checksums.txt.ed25519.sig"
URL="${BASE}/download/${TAG}/${ARCHIVE}"
SUMS_URL="${BASE}/download/${TAG}/${SUMS}"
SIG_URL="${BASE}/download/${TAG}/${SIG}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "infrix-install: downloading ${ARCHIVE} (${TAG})"
$DLO "$tmp/$ARCHIVE" "$URL"      || err "download failed: $URL"
$DLO "$tmp/$SUMS"    "$SUMS_URL" || err "checksums download failed: $SUMS_URL"
$DLO "$tmp/$SIG"     "$SIG_URL"  || err "checksums signature download failed: $SIG_URL"

# --- authenticate the checksums file BEFORE trusting any hash in it ---
# Pass-17 audit P0-1: the checksums file is downloaded from the same endpoint as
# the payload, so a compromised endpoint could swap both. Verify the detached
# Ed25519 signature over the checksums against a PINNED release public key that is
# embedded here (never fetched from the endpoint). Fail closed on any mismatch.
need openssl
# Pinned Ed25519 release key (RELEASE-SIGNING-KEY.pub, fingerprint d5c3c240…).
PIN_KEY_B64="KayNyxm3HuYpCkyi24G2rWXWiXJji0KktABtI2gDui8="
# Wrap the raw 32-byte key in a DER SubjectPublicKeyInfo PEM. The 12-byte Ed25519
# SPKI prefix is a multiple of 3 bytes, so its base64 ("MCowBQYDK2VwAyEA")
# concatenates cleanly with the key's base64.
{
  echo "-----BEGIN PUBLIC KEY-----"
  echo "MCowBQYDK2VwAyEA${PIN_KEY_B64}"
  echo "-----END PUBLIC KEY-----"
} > "$tmp/relkey.pem"
# The signature ships base64-encoded; decode to the raw 64-byte signature.
openssl base64 -d -in "$tmp/$SIG" -out "$tmp/sig.bin" 2>/dev/null || err "could not decode checksums signature"
openssl pkeyutl -verify -pubin -inkey "$tmp/relkey.pem" -rawin -in "$tmp/$SUMS" -sigfile "$tmp/sig.bin" >/dev/null 2>&1 \
  || err "checksums signature does NOT verify against the pinned release key — refusing to install (possible tampered release endpoint)"
echo "infrix-install: checksums signature verified against the pinned release key"

# --- verify checksum ---
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
want="$(grep " ${ARCHIVE}\$" "$tmp/$SUMS" | awk '{print $1}')"
[ -n "$want" ] || err "no checksum entry for ${ARCHIVE}"
got="$(cd "$tmp" && $SHA "$ARCHIVE" | awk '{print $1}')"
[ "$want" = "$got" ] || err "checksum mismatch (expected $want, got $got) — refusing to install"
echo "infrix-install: checksum verified"

# --- install ---
tar -xzf "$tmp/$ARCHIVE" -C "$tmp"
if [ "${INFRIX_INSTALL_DIR:-}" != "" ]; then DEST="$INFRIX_INSTALL_DIR"
elif [ -w /usr/local/bin ]; then DEST=/usr/local/bin
else DEST="$HOME/.local/bin"; fi
mkdir -p "$DEST"
install -m 0755 "$tmp/infrix" "$DEST/infrix" 2>/dev/null || { cp "$tmp/infrix" "$DEST/infrix"; chmod 0755 "$DEST/infrix"; }

echo "infrix-install: installed to $DEST/infrix"
case ":$PATH:" in *":$DEST:"*) : ;; *) echo "infrix-install: add $DEST to your PATH";; esac
"$DEST/infrix" version || true
echo "infrix-install: done — try 'infrix doctor'"
