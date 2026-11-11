#!/usr/bin/env bash
# Server-side guarantee: no direct pushes, force-pushes or deletion of any repo's default branch;
# changes land only through PRs. An organization gets one org-level ruleset (current AND future repos);
# a personal account gets a repo-level ruleset on each repo it owns (re-run after creating repos).
# Usage: ./apply-ruleset.sh OWNER   (needs `gh auth login` as that owner). Safe to re-run.
# Exclude repos whose automation commits straight to the default branch: one repo name per line
# (no owner, # comments ok) in $KIT_RULESET_EXCLUDE, default ~/.config/agent-kit/ruleset-exclude.
# Kept outside this repo on purpose: repo names can be private. Excluding never removes an existing ruleset.
set -euo pipefail; owner="${1:?usage: ./apply-ruleset.sh OWNER}"; here="$(cd "$(dirname "$0")" && pwd)"
name=protect-default-branch; failed=0
xfile="${KIT_RULESET_EXCLUDE:-$HOME/.config/agent-kit/ruleset-exclude}"
exclude=$( [ -f "$xfile" ] && sed -e 's/#.*//' -e 's/[[:space:]]//g' "$xfile" | grep -v '^$' || true)
[ -n "$exclude" ] && echo "excluding $(printf '%s\n' "$exclude" | wc -l | tr -d ' ') repo(s) listed in $xfile"
type=$(gh api "users/$owner" -q .type)
has(){ gh api "$1" -q '.[].name' | grep -qx "$name"; }
post(){ local out; if out=$(gh api -X POST "$1" --input - 2>&1 >/dev/null); then return 0; fi; echo "${out##*$'\n'}"; return 1; }

if [ "$type" = Organization ]; then
  if has "orgs/$owner/rulesets"; then echo "exists  org ruleset in $owner (update its repository exclusions in the org settings if the list changed)"; exit 0; fi
  org=$(printf '%s\n' "$exclude" | python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["conditions"]["repository_name"]["exclude"]=[l for l in sys.stdin.read().split() if l];print(json.dumps(d))' "$here/$name.json")
  if err=$(printf '%s' "$org" | post "orgs/$owner/rulesets"); then echo "applied org ruleset: all current and future repos in $owner except the excluded ones"; exit 0; fi
  echo "org ruleset not applied ($err); falling back to repo-level rulesets"
fi

per=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["conditions"]={"ref_name":d["conditions"]["ref_name"]};d["bypass_actors"]=[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}];print(json.dumps(d))' "$here/$name.json")
while read -r r; do
  if printf '%s\n' "$exclude" | grep -qxF "${r#*/}"; then echo "skipped $r (excluded)"
  elif has "repos/$r/rulesets" 2>/dev/null; then echo "exists  $r"
  elif err=$(printf '%s' "$per" | post "repos/$r/rulesets"); then echo "applied $r"
  else echo "FAILED  $r: $err"; failed=1; fi
done < <(gh repo list "$owner" --limit 1000 --no-archived --json nameWithOwner -q '.[].nameWithOwner')
[ "$type" = Organization ] || echo "Personal account: new repos are not covered until you re-run this script."
exit $failed
