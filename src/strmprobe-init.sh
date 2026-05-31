#!/usr/bin/env bash
# STRMProbe init script for LinuxServer.io containers.
#
# Place in /config/custom-cont-init.d/ (e.g. as 99-strmprobe). LSIO runs these as
# root before the app starts, on every boot, so re-patching here is exactly what
# survives image updates.
#
# It (1) validates and locates the wrapper source, (2) auto-downloads a
# network-capable ffprobe ("ffprobe-full") if missing, and (3) replaces every
# /app/*/bin/ffprobe with the wrapper, backing up the original to ffprobe.real.
#
# This script must be idempotent and must ALWAYS exit 0 — a non-zero exit can
# abort container startup.
#
# Project: https://github.com/cosmicflow2512/strmprobe

set -u

readonly WRAPPER_MARKER="STRMProbe ffprobe wrapper v"
FULL_BIN="${STRMPROBE_FULL:-/config/bin/ffprobe-full}"

log() { printf '[STRMProbe] %s\n' "$*"; }

# --- 1. Locate and validate the wrapper source ---------------------------------
WRAPPER_SRC="${STRMPROBE_WRAPPER_SRC:-/config/strmprobe/ffprobe-wrapper.sh}"
if [ ! -f "$WRAPPER_SRC" ]; then
    for candidate in /config/bin/ffprobe-wrapper.sh /config/custom-cont-init.d/ffprobe-wrapper.sh; do
        if [ -f "$candidate" ]; then
            WRAPPER_SRC="$candidate"
            break
        fi
    done
fi
if [ ! -f "$WRAPPER_SRC" ]; then
    log "ERROR: wrapper source not found (looked at ${STRMPROBE_WRAPPER_SRC:-/config/strmprobe/ffprobe-wrapper.sh}); skipping."
    exit 0
fi
# A.2: never overwrite a working ffprobe with a corrupt/empty wrapper.
if [ ! -s "$WRAPPER_SRC" ] || ! head -n1 "$WRAPPER_SRC" | grep -q '^#!.*bash'; then
    log "ERROR: wrapper source $WRAPPER_SRC is empty or not a bash script; aborting install."
    exit 0
fi

# --- Helpers -------------------------------------------------------------------
# Verify a static ffprobe supports the network protocols we need.
verify_protocols() {
    local bin="$1" proto out
    [ -x "$bin" ] || return 1
    out="$("$bin" -hide_banner -protocols 2>/dev/null | tr -d ' ')" || return 1
    for proto in http https tcp tls; do
        printf '%s\n' "$out" | grep -qix "$proto" || return 1
    done
    return 0
}

# Download + verify + install ffprobe-full. Arch-aware (amd64/arm64).
# MIRRORED IN scripts/fetch-ffprobe-full.sh — keep the two in sync.
fetch_ffprobe_full() {
    local dest="$1" arch jvs url tmp src rc=0
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  jvs="ffmpeg-release-amd64-static" ;;
        aarch64|arm64) jvs="ffmpeg-release-arm64-static" ;;
        *) log "WARN: unsupported arch '$arch'; cannot auto-download ffprobe-full"; return 2 ;;
    esac
    url="https://johnvansickle.com/ffmpeg/releases/${jvs}.tar.xz"
    tmp="$(mktemp -d)" || return 1
    log "downloading network-capable ffprobe ($arch) from johnvansickle.com ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$tmp/ff.tar.xz" "$url" || rc=1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$tmp/ff.tar.xz" "$url" || rc=1
    else
        log "WARN: neither curl nor wget available; cannot download ffprobe-full"
        rm -rf "$tmp"
        return 1
    fi
    if [ "$rc" -ne 0 ]; then
        log "WARN: download failed (network policy or upstream unavailable)"
        rm -rf "$tmp"
        return 1
    fi
    # Extract the whole archive, then locate ffprobe with find. We intentionally
    # avoid GNU tar's --wildcards: Alpine-based LSIO images ship BusyBox tar,
    # which rejects that option. The tarball expands to ~150 MB in $tmp briefly.
    if ! tar -C "$tmp" -xJf "$tmp/ff.tar.xz" 2>>"$tmp/tar.err"; then
        log "WARN: could not extract archive: $(head -n1 "$tmp/tar.err" 2>/dev/null)"
        rm -rf "$tmp"
        return 1
    fi
    src="$(find "$tmp" -type f -name ffprobe 2>/dev/null | head -n1)"
    if [ -z "$src" ]; then
        log "WARN: ffprobe not found in archive"
        rm -rf "$tmp"
        return 1
    fi
    if ! verify_protocols "$src"; then
        log "WARN: downloaded ffprobe lacks http/https/tcp/tls support; discarding"
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p "$(dirname "$dest")"
    if install -m 0755 "$src" "$dest"; then
        log "installed ffprobe-full -> $dest"
        rm -rf "$tmp"
        return 0
    fi
    log "WARN: failed to install ffprobe-full to $dest"
    rm -rf "$tmp"
    return 1
}

# --- 2. Ensure ffprobe-full is present -----------------------------------------
if [ ! -x "$FULL_BIN" ]; then
    log "ffprobe-full not present at $FULL_BIN; attempting auto-download ..."
    fetch_ffprobe_full "$FULL_BIN" \
        || log "WARN: could not provide ffprobe-full; .strm probing will fall back to the original ffprobe"
fi

# --- 3. Patch every app's ffprobe ----------------------------------------------
# STRMPROBE_APP_GLOB is overridable for testing; defaults to the LSIO layout.
APP_GLOB="${STRMPROBE_APP_GLOB:-/app/*/bin/ffprobe}"
shopt -s nullglob
# Intentional word-splitting + globbing of APP_GLOB.
# shellcheck disable=SC2206
targets=( $APP_GLOB )
shopt -u nullglob
if [ "${#targets[@]}" -eq 0 ]; then
    log "no /app/*/bin/ffprobe found; nothing to patch."
    exit 0
fi

for ff in "${targets[@]}"; do
    dir="$(dirname "$ff")"
    real="$dir/ffprobe.real"

    # Marker-based backup logic (survives image updates without going stale):
    #   - already our wrapper  -> leave the backup alone
    #   - genuine, no backup   -> first run, create backup
    #   - genuine, backup exists -> image updated the binary, refresh backup
    if grep -aq "$WRAPPER_MARKER" "$ff" 2>/dev/null; then
        : # current ffprobe is our wrapper; do not touch ffprobe.real
    elif [ ! -e "$real" ]; then
        cp -p "$ff" "$real" && log "backed up original ffprobe -> $real"
    else
        cp -p "$ff" "$real" && log "image update detected; refreshed backup $real"
    fi

    # Install / refresh the wrapper.
    if cp "$WRAPPER_SRC" "$ff" && chmod 0755 "$ff"; then
        log "wrapper installed at $ff"
    else
        log "ERROR: failed to install wrapper at $ff"
        continue
    fi
    if [ -x "$real" ]; then
        log "  original binary backed up at $real"
    else
        log "  WARN: no usable backup at $real (wrapper will exit 126/127 until fixed)"
    fi
done

# --- 4. Verbose status summary -------------------------------------------------
if verify_protocols "$FULL_BIN"; then
    log "ffprobe-full at $FULL_BIN (HTTP/HTTPS/TCP/TLS verified)"
else
    log "WARN: ffprobe-full at $FULL_BIN missing or lacks network protocols; .strm probing will fall back"
fi

exit 0
