#!/usr/bin/env bash
# Result cache (STRMPROBE_CACHE_DIR): hits avoid re-invoking ffprobe-full, the key
# includes args + .strm content, and only successful probes are cached.
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

CACHE="$TMP/cache"
export STRMPROBE_CACHE_DIR="$CACHE"
export STUB_COUNT_FILE="$TMP/full.count"
: > "$STUB_COUNT_FILE"

full_calls() { wc -l < "$STUB_COUNT_FILE" 2>/dev/null | tr -d ' '; }
assert_calls() {   # assert_calls <expected> <desc>
    local got; got="$(full_calls)"
    if [ "$got" = "$1" ]; then
        record ok "$2 (ffprobe-full calls=$got)"
    else
        record notok "$2" "expected $1 calls, got $got"
    fi
}

printf 'http://h.test/movie.mkv\n' > "$TMP/m.strm"

# 1) Miss: ffprobe-full invoked once, cache file written.
run_wrapper -v error -print_format json -show_format "$TMP/m.strm"
assert_calls 1 "first probe is a cache miss"
out1="$OUT"
if ls "$CACHE"/*.json >/dev/null 2>&1; then record ok "cache file created"; else record notok "cache file created"; fi

# 2) Hit: identical .strm+args served from cache, ffprobe-full NOT re-invoked.
run_wrapper -v error -print_format json -show_format "$TMP/m.strm"
assert_calls 1 "identical probe is a cache hit (no re-invoke)"
if [ "$OUT" = "$out1" ]; then record ok "cached output identical"; else record notok "cached output identical" "differs"; fi

# 3) Different args -> different key -> re-probe (no collision).
run_wrapper -v error -print_format json -show_format -show_chapters "$TMP/m.strm"
assert_calls 2 "different args bypass the cache"

# 4) Changed .strm content (different URL) -> re-probe (correct invalidation).
printf 'http://h.test/other.mkv\n' > "$TMP/m.strm"
run_wrapper -v error -print_format json -show_format "$TMP/m.strm"
assert_calls 3 "changed .strm content invalidates the cache"

# 5) Failures are NOT cached.
: > "$STUB_COUNT_FILE"
printf 'http://h.test/fail.mkv\n' > "$TMP/f.strm"
export STUB_EXIT=2
run_wrapper -v error -print_format json "$TMP/f.strm"
assert_exit 2
run_wrapper -v error -print_format json "$TMP/f.strm"
assert_calls 2 "failed probe is not cached (re-invoked)"
unset STUB_EXIT

# 6) Cache disabled (STRMPROBE_CACHE_DIR unset) -> every call invokes ffprobe-full.
: > "$STUB_COUNT_FILE"
unset STRMPROBE_CACHE_DIR
printf 'http://h.test/nocache.mkv\n' > "$TMP/n.strm"
run_wrapper -v error -print_format json "$TMP/n.strm"
run_wrapper -v error -print_format json "$TMP/n.strm"
assert_calls 2 "cache disabled -> no caching"
