#!/usr/bin/env bash
# Exit-code propagation and the optional debug log (toggle + size cap).
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

printf 'http://h.test/exit.mkv\n' > "$TMP/e.strm"
: > "$TMP/m.mkv"

# Exit code from the FULL path propagates.
export STUB_EXIT=3
run_wrapper "$TMP/e.strm"
assert_which FULL
assert_exit 3
unset STUB_EXIT

# Exit code from the REAL pass-through propagates.
export STUB_EXIT=2
run_wrapper "$TMP/m.mkv"
assert_which REAL
assert_exit 2
unset STUB_EXIT

# Logging disabled -> no log file written.
export STRMPROBE_LOGFILE="$TMP/wrap.log"
export STRMPROBE_LOG=0
rm -f "$TMP/wrap.log"
run_wrapper "$TMP/e.strm"
assert_file_absent "$TMP/wrap.log"

# Logging enabled -> file created with a route= line.
export STRMPROBE_LOG=1
run_wrapper "$TMP/e.strm"
assert_file_exists "$TMP/wrap.log"
assert_file_contains "$TMP/wrap.log" "route=full"

# Size cap: a pre-seeded oversized log is truncated and re-stamped.
export STRMPROBE_LOG_MAX=100
head -c 500 /dev/zero | tr '\0' 'x' > "$TMP/wrap.log"
run_wrapper "$TMP/e.strm"
assert_file_contains "$TMP/wrap.log" "log truncated"
if grep -q 'xxxxxxxx' "$TMP/wrap.log"; then
    record notok "oversized log content purged"
else
    record ok "oversized log content purged"
fi
