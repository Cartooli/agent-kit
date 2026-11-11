#!/usr/bin/env bash
# Runs the guard against known commands. Exit non-zero if any expectation fails.
G="$(cd "$(dirname "$0")/.." && pwd)/plugins/kernel/hooks/guard.sh"
tmp=$(mktemp -d); git -C "$tmp" init -q -b main; git -C "$tmp" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m i
fb=$(mktemp -d); git -C "$fb" init -q -b feat/x; git -C "$fb" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m i
fail=0
t(){ want=$1; dir=$2; shift 2; cmd="$*"
  json=$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"cwd":sys.argv[2]}))' "$cmd" "$dir")
  printf '%s' "$json" | "$G" >/dev/null 2>&1; rc=$?
  got=$([ $rc -eq 2 ] && echo block || echo allow)
  [ "$got" = "$want" ] && echo "ok   $want  $cmd" || { echo "FAIL want=$want got=$got  $cmd"; fail=1; }; }
t block $fb gh pr merge 12 --squash
t block $fb 'cd repo && gh pr merge --auto 5'
t block $fb gh api -X PUT repos/o/r/pulls/7/merge
t block $fb git push origin main
t block $fb git push origin HEAD:main
t block $fb git push -f origin master
t block $fb git push origin +main
t block $fb git push --mirror
t block $fb npx vercel --prod
t block $fb vercel deploy --prod --yes
t block $tmp git push
t block $tmp git push -u origin
t allow $fb git push -u origin feat/x
t allow $fb git push
t allow $fb git push origin feat/main-menu
t allow $fb gh pr create --draft --fill
t allow $fb gh pr list
t allow $fb vercel deploy
t allow $fb git log --oneline main
t block $tmp git push origin HEAD
t block $tmp git push origin @
t block $tmp git push --force-with-lease origin +HEAD
t block $fb git -c core.hooksPath=/dev/null push origin main
t block $fb git --no-pager push origin main
t block $fb "git -C $tmp push"
t block $fb gh -R o/r pr merge 5
t block $fb gh --repo o/r pr merge 5
t block $fb gh --repo=o/r pr merge 5
t allow $tmp git push origin HEAD:feat/x
t allow $fb git push origin HEAD
t allow $tmp "git -C $fb push"
t allow $fb gh -R o/r pr view 5
t block $fb echo git push origin main  # conservative: text mentioning a push to main is blocked too
KIT_OVERRIDE=1 t allow $fb git push origin main
exit $fail
