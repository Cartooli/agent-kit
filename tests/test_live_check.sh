#!/usr/bin/env bash
# Tests actions/live-check: decide.sh (pure), probe.sh (stub curl), act.sh (stub gh and git).
D="$(cd "$(dirname "$0")/.." && pwd)/actions/live-check"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# ---------- decide.sh ----------
S=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
PR='{"number":12,"merge_commit_sha":"'$S'","labels":["ui"]}'
d() { # d WANT NAME [VAR=VALUE ...]
  local want=$1 name=$2; shift 2
  got=$(env SHA=$S TIP_SHA=$S PARENTS=1 SUBJECT="fix: button (#12)" PRIOR=success PR_JSON="$PR" FILES="src/app/page.tsx" "$@" bash "$D/decide.sh")
  [ "${got%% *}" = "$want" ] && ok "decide $want  $name" || bad "decide want=$want got='$got'  $name"; }
d revert "clean agent squash-merge"
d issue  "prior check failed"           PRIOR=failure
d issue  "no prior check"               PRIOR=none
d issue  "newer commit on top"          TIP_SHA=bbbb
d issue  "merge commit"                 PARENTS=2
d issue  "no PR"                        PR_JSON=
d issue  "PR squash sha differs"        PR_JSON='{"number":12,"merge_commit_sha":"cccc","labels":[]}'
d issue  "gate label"                   PR_JSON='{"number":12,"merge_commit_sha":"'$S'","labels":["gate:payments"]}'
d issue  "released gate still sensitive" PR_JSON='{"number":12,"merge_commit_sha":"'$S'","labels":["gate:owner-ok"]}'
d issue  "hold label"                   PR_JSON='{"number":12,"merge_commit_sha":"'$S'","labels":["Hold"]}'
d issue  "commit is a revert"           SUBJECT='Revert "fix: button (#12)"'
d issue  "PR is an auto-revert"         PR_JSON='{"number":12,"merge_commit_sha":"'$S'","labels":["auto-revert"]}'
d issue  "migration path"               FILES=$'src/a.ts\ndrizzle/0047_add.sql'
d issue  "auth file"                    FILES='src/auth.ts'
d issue  "stripe route"                 FILES='src/app/api/stripe/webhook/route.ts'
d issue  "env file"                     FILES='.env.example'
d issue  "privacy page"                 FILES='src/app/privacy/page.tsx'
d issue  "workflow file"                FILES='.github/workflows/ci.yml'
d revert "author-ish word is not auth"  FILES='src/components/AuthorCard.tsx'
d revert "legalese word is fine"        FILES='docs/paralegal-notes.md'

# ---------- probe.sh ----------
cat >"$T/curl" <<'EOF'
#!/usr/bin/env bash
# stub: -o FILE ... URL ; routes from $ROUTES as "path code body" lines
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift 2;; -w|--max-time|-H|-A) shift 2;; -*) shift;; *) url=$1; shift;; esac; done
path="/${url#https://*/}"; [ "$url" = "${url%/*}" ] && path="/"
line=$(grep -E "^$(printf '%s' "$path" | sed 's/[.[\*^$/]/\\&/g') " "$ROUTES" | head -1)
[ -n "$line" ] || { printf 'not found' >"$out"; printf '404'; exit 0; }
set -- $line; printf '%s' "${*:3}" >"$out"; printf '%s' "$2"
EOF
chmod +x "$T/curl"
cat >"$T/routes" <<'EOF'
/ 200 <title>Example Home</title>
/workspace 307 redirect
/api/models 401 {"error":"unauthorized"}
EOF
cfg='{"base_url":"https://www.example.com/","checks":[{"path":"/","contains":"Example Home"},{"path":"/workspace","status":[302,307]},{"path":"/api/models","status":401}]}'
p() { # p WANT_RC NAME CONFIG [VAR=VALUE ...]
  local want=$1 name=$2; printf '%s' "$3" >"$T/cfg.json"; shift 3
  env CONFIG="$T/cfg.json" CURL="$T/curl" ROUTES="$T/routes" "$@" bash "$D/probe.sh" >"$T/probe.out" 2>&1; rc=$?
  [ "$rc" = "$want" ] && ok "probe rc=$want  $name" || { bad "probe want=$want got=$rc  $name"; cat "$T/probe.out"; }; }
p 0 "all pass" "$cfg"
p 1 "text missing" '{"base_url":"https://www.example.com","checks":[{"path":"/","contains":"Nope"}]}'
p 1 "auth gate open (200 instead of redirect)" '{"base_url":"https://www.example.com","checks":[{"path":"/","status":[302,307]}]}'
p 1 "unknown path 404s" '{"base_url":"https://www.example.com","checks":[{"path":"/gone"}]}'
p 1 "drill extra check fails" "$cfg" EXTRA_CHECK='{"path":"/__live-check-drill-1","status":200}'
p 3 "http base_url refused" '{"base_url":"http://www.example.com","checks":[{"path":"/"}]}'
p 3 "no checks" '{"base_url":"https://www.example.com","checks":[]}'
p 3 "not json" 'nope'
grep -q '^FAIL /__live-check-drill-1 got HTTP 404' "$T/probe.out" 2>/dev/null || true

# ---------- act.sh ----------
cat >"$T/gh" <<'EOF'
#!/usr/bin/env bash
# stub gh api: logs calls; behaviour from env STUB_PR_FAIL / STUB_MERGE
echo "$*" >>"$CALLS"
case "$*" in
  *"-X POST repos/o/r/pulls "*) [ -n "${STUB_PR_FAIL:-}" ] && { echo '{"message":"GitHub Actions is not permitted to create or approve pull requests."}'; exit 1; }; echo '{"number":77}';;
  *"-X PUT repos/o/r/pulls/77/merge"*) echo "${STUB_MERGE:-true}";;
  *"-X POST repos/o/r/issues "*) echo 5;;
  *"issues?state=open"*) echo "${STUB_OPEN:-}";;
  *) echo '{}';;
esac
EOF
cat >"$T/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$CALLS"
case "$*" in *"diff --quiet"*) exit "${STUB_DIFF:-0}";; *"rev-parse HEAD"*) echo headsha;; esac
EOF
chmod +x "$T/gh" "$T/git"
a() { # a NAME EXPECT_REGEX ACTION [VAR=VALUE ...]
  local name=$1 re=$2 action=$3; shift 3; : >"$T/calls"; : >"$T/sum"
  env CALLS="$T/calls" GH_API="$T/gh api" GIT="$T/git" GITHUB_STEP_SUMMARY="$T/sum" \
    REPO=o/r SHA=$S DEFAULT_BRANCH=main ACTION=$action REASON="test reason" FAILURES="FAIL / got HTTP 500" \
    RUN_URL=https://x/run RUN_ID=9 PR_NUMBER=12 PR_TITLE="fix: button" PR_LABELS='["ui"]' DRILL=none "$@" \
    bash "$D/act.sh" >/dev/null 2>&1
  grep -qE "$re" "$T/sum" && ok "act  $name" || { bad "act  $name: summary was '$(cat "$T/sum")'"; }; }
a "revert merges"                      'reverted #12 via #77'                    revert
grep -q 'merge_method=squash' "$T/calls" && ok "act  revert uses squash" || bad "act  revert uses squash"
grep -q 'labels\[\]=auto-revert' "$T/calls" && ok "act  revert labelled auto-revert" || bad "act  revert labelled auto-revert"
a "tree mismatch falls back to issue"  'issue #5 \| auto-revert could not finish \(the revert does not restore' revert STUB_DIFF=1
a "PR blocked falls back to issue"     'issue #5 \| auto-revert could not finish \(open PR: GitHub Actions is not permitted' revert STUB_PR_FAIL=1
a "merge refused falls back to issue"  'issue #5 \| auto-revert could not finish \(merge PR #77\)' revert STUB_MERGE=false
a "issue opens"                        'issue #5 \| test reason'                 issue
a "open issue gets a comment"          'issue #3 \(comment\)'                    issue STUB_OPEN=3
a "drill revert closes, never merges"  'drill revert PR #77 \(opened, closed, not merged\)' revert DRILL=revert
grep -q 'pulls/77/merge' "$T/calls" && bad "act  drill never merges" || ok "act  drill never merges"
grep -q 'labels\[\]=live-check-drill' "$T/calls" && ok "act  drill labelled live-check-drill" || bad "act  drill labelled live-check-drill"
a "drill issue closes"                 'drill issue #5 \(opened, closed\)'       issue DRILL=issue
a "revert of a drill PR keeps the drill label" 'reverted #12 via #77'           revert PR_LABELS='["live-check-drill"]'
grep -q 'labels\[\]=live-check-drill' "$T/calls" && ok "act  drill-PR revert labelled live-check-drill" || bad "act  drill-PR revert labelled live-check-drill"

a "drill PR failure files a drill issue" 'issue #5 \| test reason'              issue PR_LABELS='["live-check-drill"]'
grep -q 'labels\[\]=live-check-drill' "$T/calls" && ok "act  drill-PR issue labelled live-check-drill" || bad "act  drill-PR issue labelled live-check-drill"

# ---------- prior.jq (the previous production check) ----------
pr() { # pr WANT NAME RUNS_JSON
  got=$(printf '{"workflow_runs":%s}' "$3" | jq -r --argjson me 9 -f "$D/prior.jq")
  [ "$got" = "$1" ] && ok "prior $1  $2" || bad "prior want=$1 got=$got  $2"; }
pr success "status-triggered pass counts"     '[{"id":8,"event":"status","conclusion":"success"}]'
pr failure "deployment_status failure counts" '[{"id":8,"event":"deployment_status","conclusion":"failure"}]'
pr failure "drills and skips ignored"         '[{"id":8,"event":"workflow_dispatch","conclusion":"success"},{"id":7,"event":"status","conclusion":"skipped"},{"id":6,"event":"status","conclusion":"failure"}]'
pr success "own run ignored"                  '[{"id":9,"event":"status","conclusion":"failure"},{"id":5,"event":"status","conclusion":"success"}]'
pr none    "nothing before"                   '[{"id":4,"event":"workflow_dispatch","conclusion":"success"}]'

# ---------- trigger wiring (newer Vercel projects post only a commit status) ----------
W="$D/../../repo-snippet/.github/workflows/live-check.yml"
grep -qE '^  status:' "$W" && ok "snippet runs on commit status" || bad "snippet runs on commit status"
grep -q "contains(github.event.branches.\*.name, github.event.repository.default_branch)" "$W" \
  && ok "snippet: status must be on the default branch" || bad "snippet: status must be on the default branch"
grep -q "github.event.context == 'Vercel'" "$W" && ok "snippet: only Vercel statuses" || bad "snippet: only Vercel statuses"
n=$(grep -c 'github.event.deployment.sha || github.event.sha || github.event.client_payload.git.sha || github.sha' "$D/action.yml")
[ "$n" -ge 3 ] && ok "action: deployed sha from deployment, status or dispatch" || bad "action: deployed sha (found $n)"
grep -q 'event=deployment_status' "$D/action.yml" && bad "action: prior check not tied to one trigger" || ok "action: prior check not tied to one trigger"

exit $fail
