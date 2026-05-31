#!/usr/bin/env bash
# Health check for a STRMProbe-patched LinuxServer.io container.
#
# Reports whether the ffprobe wrapper is active, whether the original binary was
# backed up to ffprobe.real, and whether the network-capable ffprobe-full is
# present. Exits non-zero if the wrapper or the backup are missing.
#
# Usage: scripts/health-check.sh <container> [app]
#   <container>  docker container name (e.g. sonarr)
#   [app]        app dir under /app (default: first /app/*/bin/ffprobe found)
set -u

CONTAINER="${1:-}"
APP="${2:-}"
if [ -z "$CONTAINER" ]; then
    echo "Usage: $0 <container> [app]" >&2
    exit 2
fi

dex() { docker exec "$CONTAINER" "$@"; }

if [ -n "$APP" ]; then
    FF="/app/$APP/bin/ffprobe"
else
    FF="$(dex sh -c 'ls /app/*/bin/ffprobe 2>/dev/null | head -n1' | tr -d '\r')"
fi
if [ -z "$FF" ]; then
    echo "FAIL: no /app/*/bin/ffprobe found in container $CONTAINER"
    exit 1
fi
REAL="${FF%ffprobe}ffprobe.real"
FULL="${STRMPROBE_FULL:-/config/bin/ffprobe-full}"

status=0

if version="$(dex "$FF" --strmprobe-version 2>/dev/null)"; then
    echo "OK   wrapper active at $FF ($version)"
else
    echo "FAIL wrapper NOT active at $FF"
    status=1
fi

if dex sh -c "test -x '$REAL'"; then
    echo "OK   original backup present at $REAL"
else
    echo "FAIL original backup missing at $REAL"
    status=1
fi

if dex sh -c "test -x '$FULL'"; then
    echo "OK   ffprobe-full present at $FULL"
else
    echo "WARN ffprobe-full missing at $FULL (.strm probing will fall back)"
fi

exit "$status"
