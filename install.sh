#!/usr/bin/env bash
# One-time install. Idempotent: safe to re-run. Usage: ./install.sh OWNER_ORG/agent-kit
set -euo pipefail
repo="${1:?usage: ./install.sh OWNER_ORG/agent-kit}"
f="$HOME/.claude/settings.json"; mkdir -p "$HOME/.claude"; [ -f "$f" ] || echo '{}' > "$f"
cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"
merge='
const fs=require("fs"),[f,repo]=process.argv.slice(1);
const s=JSON.parse(fs.readFileSync(f,"utf8")||"{}");
s.extraKnownMarketplaces=s.extraKnownMarketplaces||{};
s.extraKnownMarketplaces.kit={source:{source:"github",repo},autoUpdate:true};
s.enabledPlugins=s.enabledPlugins||{}; s.enabledPlugins["kernel@kit"]=true;
fs.writeFileSync(f,JSON.stringify(s,null,2)+"\n"); console.log("updated",f);'
if command -v node >/dev/null 2>&1; then node -e "$merge" "$f" "$repo"
else python3 - "$f" "$repo" <<'PY'
import json,sys;f,repo=sys.argv[1:];s=json.load(open(f))
s.setdefault("extraKnownMarketplaces",{})["kit"]={"source":{"source":"github","repo":repo},"autoUpdate":True}
s.setdefault("enabledPlugins",{})["kernel@kit"]=True
json.dump(s,open(f,"w"),indent=2);print("updated",f)
PY
fi
echo "Done. Start a new Claude Code session; run /plugin to confirm kernel@kit is enabled, and /agents to see gatherer, reviewer, fixer."
