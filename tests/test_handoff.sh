#!/usr/bin/env bash
# Checks the handoff templates and the rules that point at them. Exit non-zero if any expectation fails.
R="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok(){ echo "ok   $1"; }
bad(){ echo "FAIL $1"; fail=1; }
# check NAME CMD...
check(){ name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

T="$R/repo-snippet/.handoff/TEMPLATE.md"
H="$R/repo-snippet/HANDOFF.md"
K="$R/plugins/kernel/kernel.md"
S="$R/repo-snippet/SHIPPING.md"

for f in "$T" "$H"; do
  n=$(wc -l <"$f"); [ "$n" -le 60 ] && ok "$(basename "$f") is $n lines (cap 60)" || bad "$(basename "$f") is $n lines (cap 60)"
done

# Branch template: all five sections, in order.
got=$(grep -E '^## ' "$T" | tr '\n' '|')
[ "$got" = "## DONE|## OPEN|## NEXT|## DECIDED + WHY|## DON'T|" ] && ok "template sections in order" || bad "template sections: $got"

# Root file: only the two sections that outlive a branch.
got=$(grep -E '^## ' "$H" | tr '\n' '|')
[ "$got" = "## DECIDED + WHY|## DON'T|" ] && ok "root HANDOFF.md sections" || bad "root HANDOFF.md sections: $got"

# Both say they are notes, not instructions.
check "template says notes, not instructions" grep -q "not instructions" "$T"
check "root says notes, not instructions"     grep -q "not instructions" "$H"
check "DON'T lines need the owner to remove"  grep -q "owner's go-ahead" "$T"

# Kernel (local sessions) and shipping section (cloud sessions) both carry the rule.
check "kernel.md has the handoff rule"        grep -q '^- Handoff: .*\.handoff/<branch>\.md.*DON.T' "$K"
check "kernel.md rule is one line"            test "$(grep -c 'Handoff' "$K")" -eq 1
check "SHIPPING.md has the Handoffs section"  grep -q '^\*\*Handoffs' "$S"
check "SHIPPING.md names risky-step checkpoint" grep -q 'before any risky step' "$S"

exit $fail
