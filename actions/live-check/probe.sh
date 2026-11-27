#!/usr/bin/env bash
# live-check probe: requests each path in the repo's .livecheck.json against the live site.
# No redirects are followed, so an auth gate can be asserted as a redirect or a 401.
#
# Inputs (env):
#   CONFIG       path to the config file (default .livecheck.json)
#   EXTRA_CHECK  optional JSON object appended to the checks (used by drills)
#   CURL         curl command (tests point this at a stub)
# Output: one line per check ("ok ..." / "FAIL ...").
# Exit 0 = all pass, 1 = at least one failed, 3 = config missing or invalid (fail closed).
#
# Config shape:
#   { "base_url": "https://www.example.com",
#     "checks": [ { "path": "/", "status": 200, "contains": "Example" },
#                 { "path": "/workspace", "status": [302, 303, 307, 308] },
#                 { "path": "/api/models", "status": 401 } ] }
# "status" defaults to 200 and may be a list. "contains" is an optional plain-text match on the body.
set -u
command -v jq >/dev/null 2>&1 || { echo "::error::live-check needs jq"; exit 3; }
cfg=${CONFIG:-.livecheck.json}
curl_cmd=${CURL:-curl}

[ -f "$cfg" ] || { echo "::error::live-check: $cfg not found"; exit 3; }
jq -e '(.base_url|type=="string") and (.base_url|startswith("https://")) and (.checks|type=="array") and (.checks|length>0)' "$cfg" >/dev/null 2>&1 \
  || { echo "::error::live-check: $cfg needs an https base_url and at least one check"; exit 3; }

base=$(jq -r '.base_url|rtrimstr("/")' "$cfg")
checks=$(jq -c '.checks' "$cfg")
if [ -n "${EXTRA_CHECK:-}" ]; then checks=$(jq -c --argjson x "$EXTRA_CHECK" '. + [$x]' <<<"$checks"); fi

body=$(mktemp); trap 'rm -f "$body"' EXIT
fail=0
while IFS= read -r c; do
  path=$(jq -r '.path // "/"' <<<"$c")
  want=$(jq -c '(.status // 200) | if type=="array" then . else [.] end | map(tostring)' <<<"$c")
  needle=$(jq -r '.contains // ""' <<<"$c")
  : >"$body"
  code=$($curl_cmd -sS -o "$body" -w '%{http_code}' --max-time 15 -H 'Cache-Control: no-cache' -A 'live-check' "$base$path" 2>/dev/null) || code=${code:-000}
  [ -n "$code" ] || code=000
  if ! jq -e --arg c "$code" 'index($c) != null' <<<"$want" >/dev/null; then
    echo "FAIL $path got HTTP $code, want $(jq -r 'join("|")' <<<"$want")"; fail=1; continue
  fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" "$body"; then
    echo "FAIL $path HTTP $code but the body lacks \"$needle\""; fail=1; continue
  fi
  echo "ok   $path HTTP $code"
done < <(jq -c '.[]' <<<"$checks")
exit $fail
