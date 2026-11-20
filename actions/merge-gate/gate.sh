#!/usr/bin/env bash
# merge-gate core: decides whether a PR is clear to merge.
# Pure function of its inputs (no network), so tests/test_merge_gate.sh can run it.
#
# Inputs (env):
#   PR_TITLE     PR title
#   PR_BODY      PR body (markdown)
#   PR_LABELS    JSON array of label names, e.g. ["hold","docs"]
#   PR_COMMENTS  JSON array of issue-comment bodies
# Exit 0 = clear, 1 = blocked (reason on stderr as a GitHub ::error::), 3 = bad input.
#
# Blocks when:
#   1. the PR has the `hold` label;
#   2. the title or body contains "do not merge", "needs owner yes", "owner-gated" or "gate:";
#   3. the title contains the word HOLD;
#   4. a "## Before merge" section has an unchecked "- [ ]" box;
#   5. a "## Needed from the owner" section has anything other than ticked boxes ("- [x]")
#      or a none-marker ("None", "Nothing", "N/A"). Fail closed: a plain bullet or a
#      sentence there is an open owner item. Post-merge steps belong under "## After merge".
# Clears 1-5 when an issue comment contains "merged by the owner" (kept for compatibility
# with the per-repo gates this replaces).
set -u

command -v jq >/dev/null 2>&1 || { echo "::error::merge-gate needs jq" >&2; exit 3; }

title=${PR_TITLE-}
body=${PR_BODY-}
labels=${PR_LABELS:-[]}
comments=${PR_COMMENTS:-[]}

printf '%s' "$labels" | jq -e 'type == "array"' >/dev/null 2>&1 || { echo "::error::PR_LABELS is not a JSON array" >&2; exit 3; }
printf '%s' "$comments" | jq -e 'type == "array"' >/dev/null 2>&1 || { echo "::error::PR_COMMENTS is not a JSON array" >&2; exit 3; }

if printf '%s' "$comments" | jq -e 'map((. // "") | ascii_downcase | test("merged by the owner")) | any' >/dev/null; then
  echo "merge-gate: clear (a comment contains 'merged by the owner')"
  exit 0
fi

fail() { echo "::error::$1" >&2; exit 1; }

if printf '%s' "$labels" | jq -e 'map(ascii_downcase) | index("hold") != null' >/dev/null; then
  fail "This PR has the 'hold' label. Remove the label once the owner says yes."
fi

title_body=$(printf '%s\n%s' "$title" "$body")
for phrase in 'do not merge' 'needs owner yes' 'owner-gated' 'gate:'; do
  if printf '%s' "$title_body" | grep -qiF -- "$phrase"; then
    fail "The PR title or body contains '$phrase'. Clear that text once the owner says yes."
  fi
done

if printf '%s' "$title" | grep -qiE '(^|[^[:alnum:]_])hold([^[:alnum:]_]|$)'; then
  fail "The PR title contains 'HOLD'. Edit the title once the owner says yes."
fi

# Scan gated sections. HTML comments (template hints) are ignored.
open_items=$(printf '%s\n' "$body" | tr -d '\r' | awk '
  BEGIN { sec = ""; incomment = 0 }
  {
    line = $0
    # strip HTML comments, including ones spanning lines
    out = ""
    while (length(line) > 0) {
      if (incomment) {
        e = index(line, "-->")
        if (e == 0) { line = ""; break }
        line = substr(line, e + 3); incomment = 0
      } else {
        s = index(line, "<!--")
        if (s == 0) { out = out line; line = ""; break }
        out = out substr(line, 1, s - 1); line = substr(line, s + 4); incomment = 1
      }
    }
    l = tolower(out)
    if (l ~ /^[ \t]*##?#?[ \t]/) {
      h = l; sub(/^[ \t]*#+[ \t]+/, "", h); sub(/[ \t:]+$/, "", h)
      if (h ~ /^before merge/) sec = "before"
      else if (h ~ /^needed from the owner/) sec = "needed"
      else sec = ""
      next
    }
    if (sec == "") next
    t = l; gsub(/^[ \t]+|[ \t]+$/, "", t)
    if (t == "") next
    if (sec == "before") {
      if (t ~ /^[-*+][ \t]+\[ \]/) print "before: " t
      next
    }
    # sec == needed: fail closed
    if (t ~ /^[-*+][ \t]+\[[x]\]/) next
    n = t; sub(/^[-*+][ \t]+/, "", n); gsub(/[.!_*]/, "", n); gsub(/^[ \t]+|[ \t]+$/, "", n)
    if (n == "none" || n == "nothing" || n == "n/a" || n == "na" || n == "nothing needed" || n == "none needed") next
    print "needed: " t
  }
')

if [ -n "$open_items" ]; then
  first=$(printf '%s\n' "$open_items" | head -1)
  count=$(printf '%s\n' "$open_items" | wc -l | tr -d ' ')
  case "$first" in
    before:*) fail "An unchecked box sits under 'Before merge' ($count open). Tick each box when it is done." ;;
    *) fail "'Needed from the owner' has $count open item(s), e.g. \"${first#needed: }\". Tick each one as '- [x]' when done, write 'None' if nothing is needed, and move post-merge steps under '## After merge'." ;;
  esac
fi

echo "merge-gate: clear (no hold label, no gate phrases, no open owner items)"
exit 0
