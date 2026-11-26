#!/usr/bin/env bash
# On a pull request: if anything under plugins/kernel/ changed, plugin.json's version must change too.
# Installed sessions keep their cached plugin until the version string changes.
R="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${BASE_REF:-}"
if [ -z "$BASE" ] || ! git -C "$R" rev-parse --verify -q "$BASE" >/dev/null; then
  echo "skip version check (no base ref)"; exit 0
fi
P="plugins/kernel/.claude-plugin/plugin.json"
changed=$(git -C "$R" diff --name-only "$BASE"...HEAD -- plugins/kernel/ | grep -v "^$P\$" || true)
[ -z "$changed" ] && { echo "ok   plugin unchanged"; exit 0; }
old=$(git -C "$R" show "$BASE:$P" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
new=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$R/$P")
if [ -n "$new" ] && [ "$old" != "$new" ]; then echo "ok   plugin version $old -> $new"; exit 0; fi
echo "FAIL plugins/kernel/ changed but $P version is still '$new'. Bump it, or installed sessions keep the old copy."
echo "$changed"
exit 1
