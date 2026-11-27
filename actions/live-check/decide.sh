#!/usr/bin/env bash
# live-check decide: after a confirmed failure, choose "revert" or "issue".
# Pure function of its inputs (no network), so tests/test_live_check.sh can run it.
#
# Inputs (env):
#   SHA        deployed commit          TIP_SHA   current tip of the default branch
#   PARENTS    parent count of SHA      SUBJECT   first line of SHA's commit message
#   PRIOR      conclusion of the previous production live check: success | failure | none
#   PR_JSON    the merged PR whose squash commit is SHA: {"number":1,"merge_commit_sha":"...","labels":["x"]}
#              or empty when there is none
#   FILES      files changed by SHA, one per line
# Output: one line, "revert <reason>" or "issue <reason>".
#
# Revert only an agent-style squash-merge that is still the tip, was not gated as sensitive,
# touches nothing sensitive, and broke a site that passed its previous check. Anything else
# becomes an issue, because reverting it could undo the wrong change or need the owner.
set -u
issue() { echo "issue $1"; exit 0; }

labels=$(printf '%s' "${PR_JSON:-}" | jq -c '[.labels[]? | ascii_downcase]' 2>/dev/null || echo '[]')
[ -n "$labels" ] || labels='[]'

case "${SUBJECT:-}" in Revert\ *|revert:*|revert\(*) issue "the broken deploy is itself a revert, so a second revert won't help";; esac
jq -e 'index("auto-revert") != null' <<<"$labels" >/dev/null && issue "the broken deploy is itself an auto-revert"
[ "${PRIOR:-none}" = "success" ] || issue "the previous live check did not pass (${PRIOR:-none}), so the breakage may predate this commit"
[ "${SHA:-}" = "${TIP_SHA:-}" ] || issue "newer commits landed on top, so a clean revert can't restore the last good tree"
[ "${PARENTS:-0}" = "1" ] || issue "this is a merge commit, not an agent squash-merge"
[ -n "${PR_JSON:-}" ] || issue "no merged PR has this commit as its squash commit"
pr_sha=$(printf '%s' "$PR_JSON" | jq -r '.merge_commit_sha // ""')
[ "$pr_sha" = "$SHA" ] || issue "no merged PR has this commit as its squash commit"

gated=$(jq -r '[.[] | select(. == "hold" or startswith("gate:"))] | join(",")' <<<"$labels")
[ -z "$gated" ] || issue "the PR was gated as needing the owner ($gated)"

# Undo-cost kinds from the merge rule, by path, for repos that don't run the undo-cost gate.
sensitive='(^|/)(migrations?|drizzle|prisma)/|\.sql$|(^|/)\.env|(^|/)(auth|stripe|billing|payments?|webhooks?|coppa|legal)([/._-]|$)|(^|/)(auth|middleware|proxy)\.(ts|js|mjs)$|(^|/)(terms|privacy)([/._-]|$)'
hits=$(printf '%s\n' "${FILES:-}" | grep -iE "$sensitive" | head -3 | paste -sd, -)
[ -z "$hits" ] || issue "the change touches sensitive paths ($hits)"
wf=$(printf '%s\n' "${FILES:-}" | grep -E '^\.github/workflows/' | head -1)
[ -z "$wf" ] || issue "the change edits workflow files, which the workflow token can't revert ($wf)"

echo "revert squash-merge of #$(printf '%s' "$PR_JSON" | jq -r '.number') broke the live site"
