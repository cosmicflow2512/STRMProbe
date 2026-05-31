#!/usr/bin/env bash
# STRMProbe ffprobe wrapper v1
#
# Drop-in replacement for /app/<app>/bin/ffprobe in LinuxServer.io containers.
#
# Sonarr/Radarr/etc. call ffprobe on every imported file to read media info. A
# ".strm" file is plain text holding a streaming URL, so the shipped ffprobe
# reads text instead of a container and fails with "Invalid data found when
# processing input". Worse, the LSIO ffprobe is built --disable-network and
# cannot probe HTTP URLs at all.
#
# This wrapper detects .strm inputs, extracts the URL, and probes it with a
# network-capable static ffprobe ("ffprobe-full"). Every other call is passed
# through unchanged to the original binary ("ffprobe.real").
#
# Project: https://github.com/cosmicflow2512/strmprobe

set -u
# NOTE: deliberately NOT 'set -e'. The wrapper must always reach its final
# exec/exit so it can propagate the child's exit code; it must never abort on an
# intermediate non-zero test.

readonly STRMPROBE_VERSION="1.0.0"

# --- Version flag (handled before anything else) ---
if [ "${1:-}" = "--strmprobe-version" ]; then
    printf 'STRMProbe wrapper v%s\n' "$STRMPROBE_VERSION"
    exit 0
fi

# --- Resolve our own location so we can find ffprobe.real next to us ---
SELF="${BASH_SOURCE[0]}"
while [ -h "$SELF" ]; do
    self_dir="$(cd -P "$(dirname "$SELF")" && pwd)"
    SELF="$(readlink "$SELF")"
    case "$SELF" in
        /*) ;;
        *) SELF="$self_dir/$SELF" ;;
    esac
done
BIN_DIR="$(cd -P "$(dirname "$SELF")" && pwd)"

# --- Configuration (env overridable; also used by the test harness) ---
REAL_FFPROBE="${STRMPROBE_REAL:-$BIN_DIR/ffprobe.real}"
FULL_FFPROBE="${STRMPROBE_FULL:-/config/bin/ffprobe-full}"

LOG_ENABLED="${STRMPROBE_LOG:-0}"
LOG_FILE="${STRMPROBE_LOGFILE:-/config/logs/ffprobe-wrapper.log}"
LOG_MAX_BYTES="${STRMPROBE_LOG_MAX:-1048576}"   # 1 MiB

# Per-input demuxer options injected immediately before the input when probing a
# .strm URL. Order matters: these must precede the input (or its -i flag).
INJECT_OPTS=(
    -protocol_whitelist "file,http,https,tcp,tls"
    -analyzeduration 5000000
    -probesize 5000000
)

# --- Logging (gated on STRMPROBE_LOG=1; size-capped, no logrotate dependency) ---
log() {
    [ "$LOG_ENABLED" = "1" ] || return 0
    local dir
    dir="$(dirname "$LOG_FILE")"
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0
    if [ -f "$LOG_FILE" ]; then
        local sz
        sz="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
        if [ "${sz:-0}" -gt "$LOG_MAX_BYTES" ]; then
            : > "$LOG_FILE"
            printf '%s [log truncated, exceeded %s bytes]\n' \
                "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$LOG_MAX_BYTES" \
                >> "$LOG_FILE" 2>/dev/null || true
        fi
    fi
    printf '%s [%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$$" "$*" \
        >> "$LOG_FILE" 2>/dev/null || true
}

# --- Double-fail guard: we must be able to fall back to the original binary.
#     Distinguish "missing" (127) from "present but not executable" (126) so bug
#     reports can tell the two apart. ---
if [ ! -e "$REAL_FFPROBE" ]; then
    printf 'STRMProbe: critical - ffprobe.real missing at %s\n' "$REAL_FFPROBE" >&2
    log "FATAL real-missing $REAL_FFPROBE"
    exit 127
fi
if [ ! -x "$REAL_FFPROBE" ]; then
    printf 'STRMProbe: critical - ffprobe.real not executable at %s\n' "$REAL_FFPROBE" >&2
    log "FATAL real-not-exec $REAL_FFPROBE"
    exit 126
fi

ARGS=( "$@" )
N=${#ARGS[@]}

# Pass everything through to the original binary, then stop.
route_real() {
    log "route=real argc=$N"
    exec "$REAL_FFPROBE" ${ARGS[@]+"${ARGS[@]}"}
}

# Options that consume the following token as their value, so the scanner does
# not mistake that value for the input path. The list is conservative; unknown
# -flags are treated as value-less. A mis-scan is harmless because the chosen
# input must additionally be an existing *.strm regular file to be rerouted.
takes_value() {
    case "$1" in
        -f|-loglevel|-v|-print_format|-of|-read_intervals|-select_streams| \
        -show_entries|-sections|-probesize|-analyzeduration|-fpsprobesize| \
        -timeout|-rw_timeout|-user_agent|-headers|-protocol_whitelist|-o)
            return 0 ;;
        *) return 1 ;;
    esac
}

# --- Locate the input: the token after a literal -i, else the last free
#     positional. -i is authoritative (a later bare positional cannot override). ---
input_idx=-1
input_via_i=0
i=0
while [ "$i" -lt "$N" ]; do
    tok="${ARGS[$i]}"
    if [ "$tok" = "-i" ]; then
        if [ $((i + 1)) -lt "$N" ]; then
            input_idx=$((i + 1))
            input_via_i=1
        fi
        i=$((i + 2))
        continue
    fi
    if takes_value "$tok"; then
        i=$((i + 2))
        continue
    fi
    case "$tok" in
        -*) i=$((i + 1)) ;;
        *)
            [ "$input_via_i" = "0" ] && input_idx="$i"
            i=$((i + 1))
            ;;
    esac
done

# No detectable input (e.g. -version, -protocols, -formats, -h) -> pass through.
if [ "$input_idx" -lt 0 ]; then
    route_real
fi

INPUT="${ARGS[$input_idx]}"

# stdin/pipe inputs are never .strm files.
case "$INPUT" in
    pipe:*|-|/dev/stdin) route_real ;;
esac

# Only a regular file ending in .strm/.STRM qualifies. Missing/dir/other -> real
# (a non-existent .strm preserves the app's prior behaviour rather than crashing).
if [ ! -f "$INPUT" ]; then
    route_real
fi
case "$INPUT" in
    *.strm|*.STRM) : ;;
    *) route_real ;;
esac

# --- Extract the URL: first line beginning with http:// or https:// after
#     stripping a trailing CR (Windows CRLF) and surrounding whitespace. ---
URL=""
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"   # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"   # trim trailing whitespace
    case "$line" in
        http://*|https://*) URL="$line"; break ;;
    esac
done < "$INPUT"

# Empty .strm, comments-only, or non-http scheme -> fall back so the app sees the
# same (pre-existing) behaviour instead of a wrapper error.
if [ -z "$URL" ]; then
    log "strm-no-url input=$INPUT -> fallback real"
    route_real
fi

# ffprobe-full absent/not executable -> degrade to real rather than break probing.
if [ ! -x "$FULL_FFPROBE" ]; then
    printf 'STRMProbe: %s not found or not executable; falling back to ffprobe.real\n' \
        "$FULL_FFPROBE" >&2
    log "full-missing $FULL_FFPROBE input=$INPUT -> fallback real"
    route_real
fi

# --- Rebuild the argument list: replace the input token with the URL and splice
#     the injected options in immediately before the input. For the -i form the
#     options must precede -i itself, not sit between -i and its value. ---
inject_at="$input_idx"
if [ "$input_via_i" = "1" ]; then
    inject_at=$((input_idx - 1))
fi

NEW=()
j=0
while [ "$j" -lt "$N" ]; do
    if [ "$j" -eq "$inject_at" ]; then
        NEW+=( "${INJECT_OPTS[@]}" )
    fi
    if [ "$j" -eq "$input_idx" ]; then
        NEW+=( "$URL" )
    else
        NEW+=( "${ARGS[$j]}" )
    fi
    j=$((j + 1))
done

log "route=full input=$INPUT url=$URL argc_new=${#NEW[@]}"
exec "$FULL_FFPROBE" "${NEW[@]}"
