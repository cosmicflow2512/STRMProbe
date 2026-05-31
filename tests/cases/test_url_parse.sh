#!/usr/bin/env bash
# URL extraction from .strm contents (line endings, comments, whitespace, etc.).
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

# Plain LF line.
printf 'http://h.test/lf.mkv\n' > "$TMP/lf.strm"
run_wrapper "$TMP/lf.strm"
assert_which FULL
assert_has_arg "http://h.test/lf.mkv"

# CRLF (A.3): the trailing carriage return must be stripped everywhere.
printf 'http://h.test/crlf.mkv\r\n' > "$TMP/crlf.strm"
run_wrapper "$TMP/crlf.strm"
assert_which FULL
assert_has_arg "http://h.test/crlf.mkv"
assert_no_arg_contains $'\r'

# Leading blank lines, comment lines and whitespace-only lines are skipped.
printf '\n# a comment\n   \nhttp://h.test/cmt.mkv\n' > "$TMP/cmt.strm"
run_wrapper "$TMP/cmt.strm"
assert_which FULL
assert_has_arg "http://h.test/cmt.mkv"

# Surrounding whitespace around the URL is trimmed.
printf '   http://h.test/sp.mkv   \n' > "$TMP/sp.strm"
run_wrapper "$TMP/sp.strm"
assert_which FULL
assert_has_arg "http://h.test/sp.mkv"

# Multi-URL (D.2): the first http(s) line wins, the second never appears.
printf 'http://first.test/a.mkv\nhttp://second.test/b.mkv\n' > "$TMP/multi.strm"
run_wrapper "$TMP/multi.strm"
assert_which FULL
assert_has_arg "http://first.test/a.mkv"
assert_no_arg_contains "second.test"

# https is recognised.
printf 'https://secure.test/s.mkv\n' > "$TMP/https.strm"
run_wrapper "$TMP/https.strm"
assert_which FULL
assert_has_arg "https://secure.test/s.mkv"

# Empty .strm -> REAL fallback.
: > "$TMP/empty.strm"
run_wrapper "$TMP/empty.strm"
assert_which REAL

# .strm with text but no http(s) line -> REAL fallback.
printf '# just a comment\nnot-a-url\n' > "$TMP/nourl.strm"
run_wrapper "$TMP/nourl.strm"
assert_which REAL
