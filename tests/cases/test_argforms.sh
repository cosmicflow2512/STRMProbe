#!/usr/bin/env bash
# Argument forms: last-positional vs -i, spaces in paths, value-options.
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Last-argument form: options injected before the input/URL.
printf 'http://h.test/last.mkv\n' > "$TMP/last.strm"
run_wrapper -loglevel quiet -print_format json -show_format "$TMP/last.strm"
assert_which FULL
assert_arg_before "-protocol_whitelist" "http://h.test/last.mkv"

# -i form: options injected BEFORE -i; URL replaces the path after -i.
printf 'http://h.test/iform.mkv\n' > "$TMP/iform.strm"
run_wrapper -loglevel quiet -i "$TMP/iform.strm" -show_streams
assert_which FULL
assert_arg_before "-protocol_whitelist" "-i"
assert_arg_pair "-i" "http://h.test/iform.mkv"
assert_arg_before "-i" "-show_streams"
assert_missing_arg "$TMP/iform.strm"

# Path containing a space is handled as a single argument throughout.
printf 'http://h.test/spaced.mkv\n' > "$TMP/my show.strm"
run_wrapper -v error "$TMP/my show.strm"
assert_which FULL
assert_arg_count "http://h.test/spaced.mkv" 1
assert_missing_arg "$TMP/my show.strm"

# A value-option's argument that happens to be an existing .strm must be consumed
# as the option's value, not mistaken for the input -> routes to REAL.
printf 'http://h.test/trap.mkv\n' > "$TMP/trap.strm"
run_wrapper -print_format "$TMP/trap.strm"
assert_which REAL
