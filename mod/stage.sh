#!/usr/bin/env bash
# Stage the wrapper + init script from src/ into mod/root/ so the Docker mod
# image (mod/Dockerfile: COPY root/ /) overlays them onto the target container:
#
#   src/strmprobe-init.sh  -> /custom-cont-init.d/99-strmprobe
#   src/ffprobe-wrapper.sh -> /usr/local/share/strmprobe/ffprobe-wrapper.sh
#
# src/ stays the single source of truth; mod/root/ is generated (git-ignored).
# Used by both mod/build.sh (local) and the build-mod GitHub Actions workflow.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

INIT_DEST="$HERE/root/custom-cont-init.d/99-strmprobe"
WRAP_DEST="$HERE/root/usr/local/share/strmprobe/ffprobe-wrapper.sh"

mkdir -p "$(dirname "$INIT_DEST")" "$(dirname "$WRAP_DEST")"
cp "$REPO/src/strmprobe-init.sh"  "$INIT_DEST"
cp "$REPO/src/ffprobe-wrapper.sh" "$WRAP_DEST"
chmod 0755 "$INIT_DEST" "$WRAP_DEST"

echo "Staged mod files under $HERE/root/:"
echo "  $INIT_DEST"
echo "  $WRAP_DEST"
