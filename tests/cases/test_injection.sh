#!/usr/bin/env bash
# Option injection: the probe options are added with correct values, before the
# URL, and the caller's original options are preserved in order.
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

URL="http://h.test/probe.mkv"
printf '%s\n' "$URL" > "$TMP/in.strm"
run_wrapper -v error -print_format json -show_format -show_streams "$TMP/in.strm"
assert_which FULL

# Injected options present with the expected values (adjacency).
assert_arg_pair "-protocol_whitelist" "file,http,https,tcp,tls"
assert_arg_pair "-analyzeduration" "5000000"
assert_arg_pair "-probesize" "5000000"

# Injected options come before the URL.
assert_arg_before "-protocol_whitelist" "$URL"
assert_arg_before "-analyzeduration" "$URL"
assert_arg_before "-probesize" "$URL"

# Caller's original options are preserved and ordered.
assert_arg_pair "-print_format" "json"
assert_has_arg "-show_format"
assert_has_arg "-show_streams"
assert_arg_before "-print_format" "-show_format"
assert_arg_before "-show_format" "-show_streams"

# The .strm path is replaced by the URL.
assert_missing_arg "$TMP/in.strm"
assert_has_arg "$URL"
