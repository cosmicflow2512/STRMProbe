#!/usr/bin/env bash
# Regression test for ffprobe-full extraction: it must work with BusyBox tar
# (Alpine LSIO images) — i.e. no GNU-only `tar --wildcards`. Self-contained;
# does not use the wrapper harness. See GitHub issue: Alpine --wildcards failure.
set -u

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$CASE_DIR/../.." && pwd)"
FETCH="$REPO/scripts/fetch-ffprobe-full.sh"
INIT="$REPO/src/strmprobe-init.sh"

n=0
fails=0
ok()    { n=$((n + 1)); printf 'ok %d - %s\n' "$n" "$1"; }
notok() { n=$((n + 1)); fails=$((fails + 1)); printf 'not ok %d - %s\n' "$n" "$1"; [ -n "${2:-}" ] && printf '#   %s\n' "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1) Static guard: no *active* (non-comment) use of GNU tar's --wildcards.
if grep -hE '^[^#]*--wildcards' "$FETCH" "$INIT" >/dev/null 2>&1; then
    notok "no active GNU tar --wildcards usage" "$(grep -nE '^[^#]*--wildcards' "$FETCH" "$INIT")"
else
    ok "no active GNU tar --wildcards usage"
fi

# Build a synthetic JVS-like tarball: a fake ffprobe that answers -protocols and
# -version, plus ffmpeg and extras, under a versioned top-level directory.
SRCDIR="$TMP/ffmpeg-test-amd64-static"
mkdir -p "$SRCDIR/manpages"
cat > "$SRCDIR/ffprobe" <<'EOF'
#!/bin/sh
case "$*" in
    *-protocols*) printf 'Input:\n file\n http\n https\n tcp\n tls\nOutput:\n file\n' ;;
    *-version*)   echo 'ffprobe version test-fake' ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho fake-ffmpeg\n' > "$SRCDIR/ffmpeg"
printf 'GPLv3\n' > "$SRCDIR/GPLv3.txt"
printf 'manual\n' > "$SRCDIR/manpages/ffprobe.1"
chmod +x "$SRCDIR/ffprobe" "$SRCDIR/ffmpeg"
tar -C "$TMP" -cJf "$TMP/ff.tar.xz" ffmpeg-test-amd64-static

# run_fetch <label> <extra-PATH-dir-or-empty>
run_fetch() {
    local label="$1" shim="$2"
    local dest="$TMP/out-$label/ffprobe-full"
    local path="$PATH" rc
    [ -n "$shim" ] && path="$shim:$PATH"
    rm -rf "$TMP/out-$label"
    PATH="$path" STRMPROBE_ARCH=amd64 STRMPROBE_URL="file://$TMP/ff.tar.xz" \
        bash "$FETCH" "$dest" > "$TMP/fetch-$label.log" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ] && [ -x "$dest" ]; then
        ok "fetch + extract works with $label tar"
    else
        notok "fetch + extract works with $label tar" "rc=$rc: $(tail -n2 "$TMP/fetch-$label.log" | tr '\n' ' ')"
    fi
}

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    ok "SKIP functional fetch test (no curl/wget available)"
else
    run_fetch system ""
    # BusyBox-specific: force `tar` to resolve to BusyBox so we exercise the exact
    # Alpine path that the bug report hit.
    if command -v busybox >/dev/null 2>&1; then
        SHIM="$TMP/shim"
        mkdir -p "$SHIM"
        printf '#!/bin/sh\nexec busybox tar "$@"\n' > "$SHIM/tar"
        chmod +x "$SHIM/tar"
        run_fetch busybox "$SHIM"
    else
        ok "SKIP busybox tar test (busybox not installed)"
    fi
fi

printf '# %d assertions, %d failed\n' "$n" "$fails"
[ "$fails" -eq 0 ]
