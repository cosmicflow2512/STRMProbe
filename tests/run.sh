#!/usr/bin/env bash
# STRMProbe test runner. Executes every tests/cases/test_*.sh in its own process
# and aggregates pass/fail. Exits non-zero if any case file fails.
#
# Usage: bash tests/run.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

total=0
failed=0
for f in "$HERE"/cases/test_*.sh; do
    [ -e "$f" ] || continue
    total=$((total + 1))
    name="$(basename "$f")"
    printf '# ===== %s =====\n' "$name"
    if bash "$f"; then
        :
    else
        failed=$((failed + 1))
        printf '# CASE FAILED: %s\n' "$name"
    fi
done

printf '# ---------------------------------------------\n'
printf '# %d/%d case files passed\n' "$((total - failed))" "$total"

[ "$failed" -eq 0 ]
