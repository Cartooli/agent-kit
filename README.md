# agent-kit: install once, then exception-only

**What it does.** Every Claude Code session on a machine where you ran `install.sh` gets the shared rules, the guard, the scoped sub-agents and the stale-fact warnings. The code host itself refuses direct pushes to the default branch. Rule changes reach those machines without you copying anything.

| Layer | Enforces | How it stays current |
|---|---|---|
| `plugins/kernel/kernel.md` (injected at session start) | Shared rules: evidence, fail loud, draft PRs, verify, stop rule, owner-writing rules | Edit it once in this repo; plugin auto-update pulls it (see setup step 2) |
| `plugins/kernel/hooks/guard.sh` | Blocks PR merges, pushes to main/master (including `HEAD`/`@` and git/gh global options), mirror pushes, CLI prod deploys | Same; tested by `tests/test_guard.sh` |
| `plugins/kernel/agents/*` | `gatherer` (read-only, can't deliver), `reviewer` (fresh-context check before every PR), `fixer` (draft PRs only) | Same; models are aliases, never pinned versions |
| `plugins/kernel/registry.yaml` | Every fast-changing fact, dated | Every session warns when an entry is past its re-verify window |
| `server/` ruleset | No direct push, force-push or deletion on default branches, at the code host | Organization: one org ruleset covers future repos. Personal account: re-run the script after creating repos |
| Ratchet `rules/kit-installed.yaml` | Adds the kit snippet (`repo-snippet/`) to every repo's `.claude/settings.json` | Rule Ratchet waves, as draft PRs |
| Ratchet `rules/default-branch-protected.yaml` | Lists the ruleset as an advisory rule | Advisory only: Ratchet's checks can't read GitHub settings yet |

## One-time setup (3 commands, about 10 minutes)
1. Create a repo named `agent-kit` under the account that owns your repos and push this folder:
   `cd agent-kit && git init -b main && git add -A && git commit -m "agent kit v1" && gh repo create OWNER/agent-kit --source . --push --private`
   Public is also fine: there are no secrets or IDs in it.
2. On each machine, run `./install.sh OWNER/agent-kit`. It merges two keys (`extraKnownMarketplaces.kit`, `enabledPlugins["kernel@kit"]`) into `~/.claude/settings.json`, backs up the old file, and is safe to re-run. In a new session, open `/plugin` to confirm `kernel@kit` is enabled and that auto-update is on for the `kit` marketplace (turn it on there if not; it is off by default for third-party marketplaces). Open `/agents` to see the three agents.
3. Run `./server/apply-ruleset.sh OWNER` signed in as that owner. It is safe to re-run.
   - Organization: one org-level ruleset; if the plan refuses it, the script prints the error and applies a ruleset to each repo instead.
   - Personal account: a ruleset on each non-archived repo you own. Private repos on a free plan may be refused; each refusal is printed as `FAILED repo: reason`, and the script exits non-zero.

## After that
- **To change a rule:** edit the file here and push. Sessions on installed machines pick it up through plugin auto-update.
- **Overrides:** you are the only one who can override. Start a session with `KIT_OVERRIDE=1 claude` to switch the guard hook off, or merge your own PR on the server side. Agents can set neither.
  - To let a session merge a PR you have reviewed (for example with a merge skill), start it with `KIT_OVERRIDE=1 claude`. The server ruleset still requires a PR for every change.
- **What still reaches you, by design:**
  - draft PRs waiting for your merge;
  - "REGISTRY STALE" lines at session start;
  - a red Rule Ratchet run.

  Everything else is enforced or self-updating.
- **Known limits:**
  - Cloud sessions (Claude Code on the web) do not install plugins that a repo enables in `.claude/settings.json`, and claude-code-action needs its own `plugin_marketplaces` / `plugins` inputs. There, only the server ruleset applies.
  - The guard needs `jq` or `python3`. Without either it stands down, with a warning, and the server ruleset still holds.
  - The guard is deliberately conservative: a command that merely *mentions* pushing to main is blocked too.
  - The guard checks the branch of the session's folder (or `git -C DIR`). `cd other-repo && git push` is judged by the session folder's branch; the server ruleset catches the rest.
  - Agents running with your own token can still merge PRs through the API from tools outside Claude Code. The guard covers sessions in Claude Code only.
