#!/usr/bin/env bash
# live-check act: carries out decide.sh's choice after a confirmed failure.
#   revert -> branch + `git revert` of the squash commit, a PR labelled `auto-revert`, squash-merged.
#   issue  -> one open issue labelled `live-check-failed` (later failures comment on it).
# A revert that can't finish at any step falls back to the issue.
#
# Why the revert may merge without CI: decide.sh only picks revert when the broken commit is still
# the tip, and this script checks that the revert's tree is byte-identical to the parent commit,
# the tree that was live and passing before. PRs opened with the workflow token don't start other
# workflows, so CI could never go green on it; there is nothing new to test.
#
# Inputs (env): GH_TOKEN REPO SHA DEFAULT_BRANCH ACTION REASON FAILURES RUN_URL RUN_ID
#   PR_NUMBER PR_TITLE PR_LABELS (JSON array)  DRILL (none|revert|issue)
#   GH_API (default "gh api"), GIT (default git) for tests.
set -u
api() { ${GH_API:-gh api} "$@"; }
g() { ${GIT:-git} "$@"; }
short=${SHA:0:7}
drill=${DRILL:-none}
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
line() { echo "live-check | $REPO | $short | FAIL | $1 | $2" | tee -a "$summary"; }
uri() { jq -rn --arg s "$1" '$s|@uri'; }

ensure_label() {
  api "repos/$REPO/labels/$(uri "$1")" >/dev/null 2>&1 && return 0
  api -X POST "repos/$REPO/labels" -f name="$1" -f color="$2" -f description="$3" >/dev/null 2>&1 || true
}

failures_md=$(printf '%s\n' "${FAILURES:-}" | sed 's/^/    /')

open_issue() {
  local why=$1 label=live-check-failed n title body
  [ "$drill" = "none" ] || label=live-check-drill
  # A failure caused by a drill PR stays countable apart from real ones.
  if jq -e 'map(ascii_downcase) | index("live-check-drill") != null' <<<"${PR_LABELS:-[]}" >/dev/null 2>&1; then label=live-check-drill; fi
  ensure_label "$label" "b60205" "Live check failed after a production deploy"
  body=$(printf 'The live check failed after the production deploy of %s and did not revert it automatically.\n\n**Why no auto-revert:** %s\n\n**Failed checks:**\n\n%s\n\nRun: %s\n' "$SHA" "$why" "$failures_md" "$RUN_URL")
  if [ "$drill" = "none" ]; then
    n=$(api "repos/$REPO/issues?state=open&labels=$label&per_page=1" --jq '.[0].number // empty' 2>/dev/null || true)
    if [ -n "$n" ]; then
      api -X POST "repos/$REPO/issues/$n/comments" -f body="$body" >/dev/null && { line "issue #$n (comment)" "$why"; return 0; }
    fi
  fi
  title="Live check failed after deploy of $short"
  [ "$drill" = "none" ] || title="[drill] $title"
  n=$(api -X POST "repos/$REPO/issues" -f title="$title" -f body="$body" -f "labels[]=$label" --jq '.number') \
    || { line "issue FAILED to open" "$why"; return 1; }
  if [ "$drill" != "none" ]; then
    api -X PATCH "repos/$REPO/issues/$n" -f state=closed -f state_reason=completed >/dev/null || true
    line "drill issue #$n (opened, closed)" "$why"
  else
    line "issue #$n" "$why"
  fi
}

do_revert() {
  local branch="auto-revert/$short-${RUN_ID:-0}" pr head merged out label=auto-revert
  [ "$drill" = "none" ] || label=live-check-drill
  # A revert of a drill PR stays countable apart from real ones.
  if jq -e 'map(ascii_downcase) | index("live-check-drill") != null' <<<"${PR_LABELS:-[]}" >/dev/null 2>&1; then label=live-check-drill; fi
  g fetch --no-tags --depth=2 origin "$SHA" >/dev/null 2>&1 || { echo "fetch"; return 1; }
  g sparse-checkout disable >/dev/null 2>&1 || true
  g checkout -q -B "$branch" "$SHA" || { echo "checkout"; return 1; }
  g -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    revert --no-edit "$SHA" >/dev/null || { echo "git revert"; return 1; }
  g diff --quiet "$SHA^" HEAD || { echo "the revert does not restore the parent tree"; return 1; }
  head=$(g rev-parse HEAD)
  g push -q origin "HEAD:refs/heads/$branch" || { echo "push"; return 1; }
  ensure_label "$label" "5319e7" "Reverted automatically after a failed live check"
  body=$(printf '## Before\nThe production deploy of %s (#%s) failed its live check.\n\n## After\nThis reverts that squash commit. The tree is identical to the parent commit, the version that was live and passing before.\n\n## How\nOpened by the live check. It merges without waiting on CI: PRs from the workflow token start no workflows, and the tree it restores already passed.\n\n**Failed checks:**\n\n%s\n\nRun: %s\n\n## Needed from the owner\nNone\n' "$SHA" "$PR_NUMBER" "$failures_md" "$RUN_URL")
  title="Revert \"${PR_TITLE:-$short}\" (live check failed)"
  [ "$drill" = "none" ] || title="[drill] $title"
  out=$(api -X POST "repos/$REPO/pulls" -f title="$title" -f head="$branch" -f base="$DEFAULT_BRANCH" -f body="$body" 2>&1) \
    || { g push -q origin --delete "$branch" >/dev/null 2>&1; echo "open PR: $(printf '%s' "$out" | jq -r '.message? // empty' 2>/dev/null | head -c 160)"; return 1; }
  pr=$(printf '%s' "$out" | jq -r '.number')
  api -X POST "repos/$REPO/issues/$pr/labels" -f "labels[]=$label" >/dev/null || true
  if [ "$drill" != "none" ]; then
    api -X PATCH "repos/$REPO/pulls/$pr" -f state=closed >/dev/null || true
    g push -q origin --delete "$branch" >/dev/null 2>&1 || true
    line "drill revert PR #$pr (opened, closed, not merged)" "$REASON"
    return 0
  fi
  for _ in 1 2 3 4; do
    merged=$(api -X PUT "repos/$REPO/pulls/$pr/merge" -f merge_method=squash -f sha="$head" --jq '.merged' 2>/dev/null || true)
    [ "$merged" = "true" ] && break
    sleep 5
  done
  if [ "$merged" != "true" ]; then echo "merge PR #$pr"; return 1; fi
  g push -q origin --delete "$branch" >/dev/null 2>&1 || true
  line "reverted #$PR_NUMBER via #$pr" "$REASON"
}

if [ "$ACTION" = "revert" ]; then
  if err=$(do_revert); then echo "$err"; exit 0; fi
  REASON="auto-revert could not finish (${err##*$'\n'})"
fi
open_issue "$REASON"
