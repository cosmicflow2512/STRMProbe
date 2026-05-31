#!/usr/bin/env bash
# Routing: which inputs go to FULL (network ffprobe) vs REAL (original binary).
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Normal media file -> REAL, untouched (no injected options).
: > "$TMP/movie.mkv"
run_wrapper -v error -print_format json -show_format -show_streams "$TMP/movie.mkv"
assert_which REAL
assert_missing_arg "-protocol_whitelist"

# Informational queries with no input -> REAL.
run_wrapper -version
assert_which REAL
assert_has_arg "-version"

run_wrapper -protocols
assert_which REAL

run_wrapper -hide_banner -formats
assert_which REAL

# stdin / pipe inputs -> REAL.
run_wrapper -i pipe:0
assert_which REAL

run_wrapper -i -
assert_which REAL

# Valid .strm (last-arg form) -> FULL, probing the URL.
printf 'http://example.test/a.mkv\n' > "$TMP/good.strm"
run_wrapper -v error -print_format json -show_format "$TMP/good.strm"
assert_which FULL
assert_has_arg "http://example.test/a.mkv"

# Bare positional .strm (no options) -> FULL.
run_wrapper "$TMP/good.strm"
assert_which FULL

# Non-existent .strm -> REAL (preserves the app's prior behaviour).
run_wrapper -v error "$TMP/ghost.strm"
assert_which REAL
