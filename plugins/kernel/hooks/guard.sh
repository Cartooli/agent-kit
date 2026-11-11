#!/usr/bin/env bash
# Blocks: merging PRs, pushing to the default branch, force-pushing it, and production deploys from the CLI.
# Override (owner only): start Claude Code with KIT_OVERRIDE=1 in your own shell. Agents cannot set it.
[ "${KIT_OVERRIDE:-}" = "1" ] && exit 0
input=$(cat)
if command -v jq >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
  cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
elif command -v python3 >/dev/null 2>&1; then
  cmd=$(printf '%s' "$input" | python3 -c 'import sys,json;d=json.load(sys.stdin);print((d.get("tool_input") or {}).get("command",""))')
  cwd=$(printf '%s' "$input" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("cwd",""))')
else
  echo "kit guard: neither jq nor python3 found; guard inactive (server-side branch rules still apply)" >&2; exit 0
fi
[ -z "$cmd" ] && exit 0
block(){ echo "Blocked by kit guard: $1. Open a draft PR instead and list it under '## Needed from the owner'." >&2; exit 2; }
# normalise: one line, squeeze spaces
c=$(printf '%s' "$cmd" | tr '\n' ' ' | tr -s ' ')
# remember `git -C DIR` for the branch lookup, then drop git/gh global options so `git -c k=v push` and `gh -R o/r pr merge` are still seen
gitdir=$(printf '%s' "$c" | grep -Eo '(^|[;&|( ])git +-C +[^ ;&|]+' | head -1 | sed -E 's/.*-C +//')
c=$(printf '%s' "$c" | sed -E 's/(^|[;&|( ])git(( +-[Cc] +[^ ;&|]+)|( +--[a-z-]+(=[^ ;&|]+)?))+ +push/\1git push/g; s/(^|[;&|( ])gh(( +-R +[^ ;&|]+)|( +--repo[ =][^ ;&|]+))+ +pr/\1gh pr/g')
# 1) merging PRs
printf '%s' "$c" | grep -Eq '(^|[;&|( ])gh +pr +merge( |$)' && block "agents never merge PRs"
printf '%s' "$c" | grep -Eq 'gh +api .*pulls/[0-9]+/merge' && block "agents never merge PRs"
# 2) production deploys from the CLI
printf '%s' "$c" | grep -Eq '(^|[;&|( ])(npx +)?vercel( +deploy)?( +[^;&|]*)?--prod' && block "production deploys go through a merged PR, not the CLI"
# 3) pushes that target main/master (explicit refspec)
if printf '%s' "$c" | grep -Eq '(^|[;&|( ])git +push( |$)'; then
  pushpart=$(printf '%s' "$c" | grep -Eo 'git +push[^;&|]*' | head -1)
  printf '%s' "$pushpart" | grep -Eq '(^| |:|\+)(refs/heads/)?(main|master)( |$)' && block "pushes to main/master"
  printf '%s' "$pushpart" | grep -Eq -- '--mirror|--all' && block "mirror/all-branch pushes"
  # 4) a push of the current branch (no refspec, or HEAD / @) while on main/master
  # word-split on purpose; globbing is off
  set -f
  # shellcheck disable=SC2046
  set -- $(printf '%s' "${pushpart#git push}" | tr ' ' '\n' | grep -v '^-')
  set +f
  current=no; [ $# -le 1 ] && current=yes
  [ $# -ge 2 ] && for r in "${@:2}"; do case "$r" in HEAD|@|+HEAD|+@) current=yes;; esac; done
  if [ "$current" = yes ]; then
    dir="${cwd:-.}"; [ -n "$gitdir" ] && case "$gitdir" in /*) dir="$gitdir";; *) dir="$dir/$gitdir";; esac
    br=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    case "$br" in main|master) block "push while on $br";; esac
  fi
fi
exit 0
