#!/usr/bin/env bash
# Runs actions/merge-gate/gate.sh against known PR shapes. Exit non-zero if any expectation fails.
G="$(cd "$(dirname "$0")/.." && pwd)/actions/merge-gate/gate.sh"
fail=0
# t WANT NAME TITLE BODY [LABELS] [COMMENTS]
t(){ want=$1 name=$2
  PR_TITLE=$3 PR_BODY=$4 PR_LABELS=${5:-[]} PR_COMMENTS=${6:-[]} "$G" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 0 ] && echo clear || { [ $rc -eq 1 ] && echo block || echo "error($rc)"; })
  [ "$got" = "$want" ] && echo "ok   $want  $name" || { echo "FAIL want=$want got=$got  $name"; fail=1; }; }

NL=$'\n'
t clear "plain PR"                    "fix: typo" "## Before:${NL}x${NL}## After:${NL}y"
t block "hold label"                  "fix: typo" "" '["Hold"]'
t block "do not merge in body"        "feat: x"   "Please DO NOT MERGE yet"
t block "needs owner yes in title"    "Needs owner yes: price change" ""
t block "HOLD title token"            "HOLD: pricing" ""
t clear "hold inside a word"          "fix: household filter" ""
t clear "hold in body sentence"       "fix: x" "we hold the lock briefly"
t block "unchecked before-merge box"  "x" "## Before merge${NL}- [ ] set env"
t clear "checked before-merge box"    "x" "## Before merge${NL}- [x] set env"
t block "needed: plain bullet"        "x" "## Needed from the owner${NL}- Spanish transcript check"
t block "needed: sentence"            "x" "## Needed from the owner${NL}Set DATABASE_URL in Production first."
t block "needed: unchecked box"       "x" "## Needed from the owner${NL}- [ ] Set DATABASE_URL in Production"
t clear "needed: all ticked"          "x" "## Needed from the owner${NL}- [x] Set DATABASE_URL${NL}* [X] Pick the price"
t block "needed: one of two open"     "x" "## Needed from the owner${NL}- [x] Set DATABASE_URL${NL}- [ ] Pick the price"
t clear "needed: None"                "x" "## Needed from the owner${NL}None."
t clear "needed: - Nothing"           "x" "## Needed from the owner${NL}- Nothing"
t clear "needed: empty then next"     "x" "## Needed from the owner${NL}${NL}## After merge${NL}- turn the flag on"
t clear "after merge is not gated"    "x" "## After merge${NL}- Set FLAG=true in Production"
t clear "template comment ignored"    "x" "## Needed from the owner${NL}<!-- list blockers as - [ ] items -->${NL}None"
t clear "multi-line comment ignored"  "x" "## Needed from the owner${NL}<!--${NL}- [ ] example${NL}-->${NL}- [x] done"
t block "### heading level counts"    "x" "### Needed from the owner:${NL}- approve the copy"
t clear "section ends at next heading" "x" "## Needed from the owner${NL}- [x] ok${NL}## Notes${NL}- informational"
t clear "CRLF body"                   "x" "## Needed from the owner"$'\r\n'"- [x] ok"$'\r\n'
t clear "owner override comment"      "x" "## Needed from the owner${NL}- open" '[]' '["LGTM, Merged by the owner"]'
t block "other comments do not clear" "x" "## Needed from the owner${NL}- open" '[]' '["owner approved"]'
t error\(3\) "bad labels json"        "x" "" 'not-json'

exit $fail
