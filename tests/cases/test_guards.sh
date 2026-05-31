#!/usr/bin/env bash
# Safety guards: version flag, double-fail (missing/non-exec real), full missing.
# shellcheck source=tests/lib/harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"

: > "$TMP/g.mkv"
printf 'http://h.test/fb.mkv\n' > "$TMP/fb.strm"

# Version flag: prints and exits 0 without invoking any probe binary.
run_wrapper --strmprobe-version
assert_exit 0
assert_no_invocation
assert_stdout_contains "STRMProbe wrapper v"

# Double-fail (A.1): ffprobe.real missing -> exit 127.
export STRMPROBE_REAL="$TMP/does-not-exist"
run_wrapper "$TMP/g.mkv"
assert_exit 127
assert_err_contains "missing"
export STRMPROBE_REAL="$TMP/ffprobe.real"

# Double-fail (A.1): ffprobe.real present but not executable -> exit 126.
cp "$STUB_REAL" "$TMP/noexec.real"
chmod -x "$TMP/noexec.real"
export STRMPROBE_REAL="$TMP/noexec.real"
run_wrapper "$TMP/g.mkv"
assert_exit 126
assert_err_contains "not executable"
export STRMPROBE_REAL="$TMP/ffprobe.real"

# ffprobe-full missing -> degrade to REAL for a .strm (don't break probing).
export STRMPROBE_FULL="$TMP/no-full-here"
run_wrapper "$TMP/fb.strm"
assert_which REAL
assert_err_contains "falling back"
export STRMPROBE_FULL="$TMP/ffprobe-full"
