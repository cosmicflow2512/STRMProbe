# shellcheck shell=bash
# STRMProbe test harness. Sourced by each tests/cases/test_*.sh file.
#
# It runs the real wrapper against stub binaries (which report whether the REAL
# or FULL path was taken and echo their arguments), so the routing, URL parsing,
# option injection and exit-code logic can be asserted without any real ffprobe.
#
# Provides: run_wrapper, plus assert_* helpers that emit TAP-ish output and an
# EXIT trap that fails the case file if any assertion failed.

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

WRAPPER="${STRMPROBE_WRAPPER:-$REPO_ROOT/src/ffprobe-wrapper.sh}"
STUB_REAL="$HARNESS_DIR/../stubs/ffprobe.real.stub"
STUB_FULL="$HARNESS_DIR/../stubs/ffprobe-full.stub"

TESTS_RUN=0
TESTS_FAILED=0

# Results of the most recent run_wrapper call.
WHICH=""
RC=0
OUT=""
ERRTEXT=""
ARGV=()

setup_case() {
    TMP="$(mktemp -d "${TMPDIR:-/tmp}/strmprobe.XXXXXX")"
    cp "$STUB_REAL" "$TMP/ffprobe.real"
    cp "$STUB_FULL" "$TMP/ffprobe-full"
    chmod +x "$TMP/ffprobe.real" "$TMP/ffprobe-full"
    export STRMPROBE_REAL="$TMP/ffprobe.real"
    export STRMPROBE_FULL="$TMP/ffprobe-full"
    export STRMPROBE_LOG="0"
    ERRFILE="$TMP/stderr"
}

teardown_case() {
    [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# run_wrapper <args...> : invoke the wrapper, capturing routing tag, args, exit
# code and stderr. Tests may export STUB_EXIT / STRMPROBE_* beforehand.
run_wrapper() {
    OUT="$("$WRAPPER" "$@" 2>"$ERRFILE")"
    RC=$?
    WHICH=""
    ARGV=()
    local line
    while IFS= read -r line; do
        case "$line" in
            WHICH=*) WHICH="${line#WHICH=}" ;;
            ARG=*) ARGV+=( "${line#ARG=}" ) ;;
        esac
    done <<< "$OUT"
    ERRTEXT="$(cat "$ERRFILE" 2>/dev/null || true)"
}

# --- low-level result recording -------------------------------------------------
record() {
    # record ok|notok <desc> [diag]
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$1" = "ok" ]; then
        printf 'ok %d - %s\n' "$TESTS_RUN" "$2"
    else
        printf 'not ok %d - %s\n' "$TESTS_RUN" "$2"
        [ -n "${3:-}" ] && printf '#   %s\n' "$3"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# --- argument helpers -----------------------------------------------------------
_has_arg() {
    local want="$1" a
    for a in "${ARGV[@]}"; do
        [ "$a" = "$want" ] && return 0
    done
    return 1
}

_arg_index() {
    local want="$1" idx=0 a
    for a in "${ARGV[@]}"; do
        [ "$a" = "$want" ] && { printf '%s' "$idx"; return 0; }
        idx=$((idx + 1))
    done
    return 1
}

# --- assertions -----------------------------------------------------------------
assert_which() {
    if [ "$WHICH" = "$1" ]; then
        record ok "routes to $1"
    else
        record notok "routes to $1" "got WHICH='$WHICH' rc=$RC err='$ERRTEXT'"
    fi
}

assert_no_invocation() {
    if [ -z "$WHICH" ]; then
        record ok "no probe binary invoked"
    else
        record notok "no probe binary invoked" "WHICH=$WHICH"
    fi
}

assert_exit() {
    if [ "$RC" = "$1" ]; then
        record ok "exit code $1"
    else
        record notok "exit code $1" "got rc=$RC"
    fi
}

assert_has_arg() {
    if _has_arg "$1"; then
        record ok "has arg [$1]"
    else
        record notok "has arg [$1]" "argv: ${ARGV[*]}"
    fi
}

assert_missing_arg() {
    if _has_arg "$1"; then
        record notok "no arg [$1]" "argv: ${ARGV[*]}"
    else
        record ok "no arg [$1]"
    fi
}

assert_arg_count() {
    local want="$1" n="$2" c=0 a
    for a in "${ARGV[@]}"; do
        [ "$a" = "$want" ] && c=$((c + 1))
    done
    if [ "$c" = "$n" ]; then
        record ok "arg [$want] occurs $n time(s)"
    else
        record notok "arg [$want] occurs $n time(s)" "got $c"
    fi
}

assert_no_arg_contains() {
    local needle="$1" a
    for a in "${ARGV[@]}"; do
        case "$a" in
            *"$needle"*)
                record notok "no arg contains [$needle]" "offending: [$a]"
                return ;;
        esac
    done
    record ok "no arg contains [$needle]"
}

assert_arg_before() {
    local a="$1" b="$2" ia ib
    if ! ia="$(_arg_index "$a")"; then record notok "[$a] before [$b]" "missing [$a]"; return; fi
    if ! ib="$(_arg_index "$b")"; then record notok "[$a] before [$b]" "missing [$b]"; return; fi
    if [ "$ia" -lt "$ib" ]; then
        record ok "[$a] before [$b]"
    else
        record notok "[$a] before [$b]" "ia=$ia ib=$ib"
    fi
}

# assert that value $2 immediately follows option $1
assert_arg_pair() {
    local opt="$1" val="$2" io nxt got
    if ! io="$(_arg_index "$opt")"; then record notok "[$opt $val] adjacency" "missing [$opt]"; return; fi
    nxt=$((io + 1))
    got="${ARGV[$nxt]-}"
    if [ "$got" = "$val" ]; then
        record ok "[$opt] immediately followed by [$val]"
    else
        record notok "[$opt] immediately followed by [$val]" "after [$opt] got [$got]"
    fi
}

assert_stdout_contains() {
    case "$OUT" in
        *"$1"*) record ok "stdout contains [$1]" ;;
        *) record notok "stdout contains [$1]" "stdout: $OUT" ;;
    esac
}

assert_err_contains() {
    case "$ERRTEXT" in
        *"$1"*) record ok "stderr contains [$1]" ;;
        *) record notok "stderr contains [$1]" "stderr: $ERRTEXT" ;;
    esac
}

assert_file_exists() {
    if [ -f "$1" ]; then record ok "file exists: $1"; else record notok "file exists: $1"; fi
}

assert_file_absent() {
    if [ -f "$1" ]; then record notok "file absent: $1"; else record ok "file absent: $1"; fi
}

assert_file_contains() {
    if grep -q -- "$2" "$1" 2>/dev/null; then
        record ok "file $1 contains [$2]"
    else
        record notok "file $1 contains [$2]"
    fi
}

# --- finalisation ---------------------------------------------------------------
_harness_finish() {
    local rc=$?
    teardown_case 2>/dev/null || true
    if [ "$TESTS_FAILED" -gt 0 ]; then
        printf '# %d of %d assertions FAILED\n' "$TESTS_FAILED" "$TESTS_RUN"
        exit 1
    fi
    if [ "$rc" -ne 0 ]; then
        printf '# case script exited rc=%d before completing\n' "$rc"
        exit "$rc"
    fi
    printf '# %d assertions passed\n' "$TESTS_RUN"
    exit 0
}
trap _harness_finish EXIT

setup_case
