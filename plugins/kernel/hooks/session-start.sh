#!/usr/bin/env bash
# Adds the shared rules to every session and warns about stale registry entries. Never blocks.
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cat "$root/kernel.md" 2>/dev/null
if command -v python3 >/dev/null 2>&1; then
python3 - "$root/registry.yaml" <<'PY' 2>/dev/null
import sys,re,datetime
stale=[];key=None;v=None
for line in open(sys.argv[1]):
    m=re.match(r'^([a-z0-9_]+):\s*$',line)
    if m: key=m.group(1); v=None; continue
    m=re.match(r'^\s+verified_on:\s*"?(\d{4}-\d{2}-\d{2})',line)
    if m: v=datetime.date.fromisoformat(m.group(1)); continue
    m=re.match(r'^\s+reverify_after_days:\s*(\d+)',line)
    if m and key and v and (datetime.date.today()-v).days>int(m.group(1)): stale.append(key)
if stale: print("\nREGISTRY STALE: re-verify before relying on: "+", ".join(stale)+" (registry.yaml in the kit repo).")
PY
fi
exit 0
