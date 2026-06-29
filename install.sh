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
URL="${BASE}/download/${TAG}/${ARCHIVE}"
SUMS_URL="${BASE}/download/${TAG}/${SUMS}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "infrix-install: downloading ${ARCHIVE} (${TAG})"
$DLO "$tmp/$ARCHIVE" "$URL"      || err "download failed: $URL"
$DLO "$tmp/$SUMS"    "$SUMS_URL" || err "checksums download failed: $SUMS_URL"

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
