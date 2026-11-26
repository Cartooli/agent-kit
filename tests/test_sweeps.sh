#!/usr/bin/env bash
# Checks that the canary-first sweep rule is in both places agents read it. Exit non-zero if any expectation fails.
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1"; fail=1; }
check(){ name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

K="$R/plugins/kernel/kernel.md"
S="$R/repo-snippet/SHIPPING.md"

# Kernel (local sessions): one line, canary first, live check, frozen-decision exception.
check "kernel.md has the sweeps rule"          grep -q '^- Sweeps: .*canary.*checked live' "$K"
check "kernel.md sweeps rule is one line"      test "$(grep -c '^- Sweeps:' "$K")" -eq 1
check "kernel.md names the outside-target case" grep -q 'fixed outside target' "$K"
check "kernel.md names the frozen-decision case" grep -q 'until that decision is frozen' "$K"

# Shipping section (cloud sessions).
check "SHIPPING.md has the Sweeps section"     grep -q '^\*\*Sweeps' "$S"
check "SHIPPING.md canary checked live"        grep -q 'canary repo first' "$S"
check "SHIPPING.md fan-out links the canary"   grep -q 'links the canary PR' "$S"
check "SHIPPING.md marker is v4"               grep -q 'shipping section v4' "$S"

exit $fail
