#!/usr/bin/env bash
# Download a network-capable static ffprobe ("ffprobe-full") and verify it
# supports http/https/tcp/tls. For host/local use (e.g. pre-seeding
# /srv/<app>/bin/ffprobe-full on Unraid). The container init script
# src/strmprobe-init.sh performs the same download automatically.
#
# Requires GNU tar (the --wildcards option). BSD/macOS tar does NOT support it;
# on macOS run `brew install gnu-tar` and put its gnubin dir on PATH first, e.g.:
#   PATH="/opt/homebrew/opt/gnu-tar/libexec/gnubin:$PATH" scripts/fetch-ffprobe-full.sh
#
# Usage: scripts/fetch-ffprobe-full.sh [destination]
#        (default destination: ./bin/ffprobe-full)
#
# Source: John Van Sickle static builds (https://johnvansickle.com/ffmpeg/).
# Fallback source if needed: BtbN (https://github.com/BtbN/FFmpeg-Builds/releases).
set -euo pipefail

DEST="${1:-./bin/ffprobe-full}"
ARCH="${STRMPROBE_ARCH:-$(uname -m)}"

case "$ARCH" in
    x86_64|amd64)  JVS="ffmpeg-release-amd64-static" ;;
    aarch64|arm64) JVS="ffmpeg-release-arm64-static" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 2 ;;
esac

URL="https://johnvansickle.com/ffmpeg/releases/${JVS}.tar.xz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$TMP/ff.tar.xz" "$URL"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMP/ff.tar.xz" "$URL"
else
    echo "Need curl or wget to download." >&2
    exit 1
fi

echo "Extracting ffprobe ..."
tar -C "$TMP" -xJf "$TMP/ff.tar.xz" --wildcards '*/ffprobe'
SRC="$(find "$TMP" -type f -name ffprobe | head -n1)"
[ -n "$SRC" ] || { echo "ffprobe not found in archive" >&2; exit 3; }

echo "Verifying network protocol support ..."
OUT="$("$SRC" -hide_banner -protocols 2>/dev/null | tr -d ' ')"
for proto in http https tcp tls; do
    if ! printf '%s\n' "$OUT" | grep -qix "$proto"; then
        echo "Downloaded ffprobe lacks '$proto' protocol support!" >&2
        "$SRC" -hide_banner -protocols || true
        exit 4
    fi
done

mkdir -p "$(dirname "$DEST")"
install -m 0755 "$SRC" "$DEST"
echo "Installed network-capable ffprobe -> $DEST"
"$DEST" -hide_banner -version | head -n1
