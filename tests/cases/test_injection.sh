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

# Default network timeout is injected before the URL.
assert_arg_pair "-rw_timeout" "30000000"
assert_arg_before "-rw_timeout" "$URL"

# --- Probe-tuning env overrides are honoured ---
export STRMPROBE_PROBESIZE=1000000 STRMPROBE_ANALYZEDURATION=2000000 STRMPROBE_RW_TIMEOUT=60000000
run_wrapper -v error -print_format json "$TMP/in.strm"
assert_arg_pair "-probesize" "1000000"
assert_arg_pair "-analyzeduration" "2000000"
assert_arg_pair "-rw_timeout" "60000000"
unset STRMPROBE_PROBESIZE STRMPROBE_ANALYZEDURATION STRMPROBE_RW_TIMEOUT

# Timeout disabled with 0 -> no -rw_timeout token injected at all.
export STRMPROBE_RW_TIMEOUT=0
run_wrapper -v error -print_format json "$TMP/in.strm"
assert_which FULL
assert_missing_arg "-rw_timeout"
unset STRMPROBE_RW_TIMEOUT
