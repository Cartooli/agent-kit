# agent-kit: install once, then exception-only

**What it does.** Every Claude Code session on a machine where you ran `install.sh` gets the shared rules, the guard, the scoped sub-agents and the stale-fact warnings. The code host itself refuses direct pushes to the default branch. Rule changes reach those machines without you copying anything.

| Layer | Enforces | How it stays current |
|---|---|---|
| `plugins/kernel/kernel.md` (injected at session start) | Shared rules: evidence, fail loud, draft PRs and the merge rule, canary-first sweeps, verify, stop rule, owner-writing rules | Edit it once in this repo and bump the plugin `version`; plugin auto-update pulls it (see setup step 2) |
| `plugins/kernel/hooks/guard.sh` | Allows only squash merges (no `--admin`, `--auto`, merge or rebase commits); blocks pushes to main/master (including `HEAD`/`@` and git/gh global options), mirror pushes, CLI prod deploys | Same; tested by `tests/test_guard.sh` |
| `plugins/kernel/agents/*` | `gatherer` (read-only, can't deliver), `reviewer` (fresh-context check before every PR), `fixer` (opens draft PRs, never merges) | Same; models are aliases, never pinned versions |
| `plugins/kernel/registry.yaml` | Every fast-changing fact, dated | Every session warns when an entry is past its re-verify window |
| `server/` ruleset | No direct push, force-push or deletion on default branches, at the code host | Organization: one org ruleset covers future repos. Personal account: re-run the script after creating repos |
| Ratchet `rules/kit-installed.yaml` | Adds the kit snippet (`repo-snippet/`) to every repo's `.claude/settings.json` | Rule Ratchet waves, as draft PRs |
| Ratchet `rules/default-branch-protected.yaml` | Lists the ruleset as an advisory rule | Advisory only: Ratchet's checks can't read GitHub settings yet |

## One-time setup (3 commands, about 10 minutes)
1. Create a repo named `agent-kit` under the account that owns your repos and push this folder:
   `cd agent-kit && git init -b main && git add -A && git commit -m "agent kit v1" && gh repo create OWNER/agent-kit --source . --push --private`
   Public is also fine: there are no secrets or IDs in it.
2. On each machine, run `./install.sh OWNER/agent-kit`. It merges two keys (`extraKnownMarketplaces.kit`, `enabledPlugins["kernel@kit"]`) into `~/.claude/settings.json`, backs up the old file, and is safe to re-run. In a new session, open `/plugin` to confirm `kernel@kit` is enabled and that auto-update is on for the `kit` marketplace (turn it on there if not; it is off by default for third-party marketplaces). Open `/agents` to see the three agents.
3. First find repos whose automation commits straight to the default branch (scheduled workflows that check out the default branch and run a bare `git push`). The ruleset rejects those pushes. List each such repo name (without the owner), one per line, in `~/.config/agent-kit/ruleset-exclude` (or the file named by `KIT_RULESET_EXCLUDE`); `#` comments and blank lines are fine, and names are case-sensitive. The list lives outside this repo because repo names can be private. Move a repo off the list once its automation opens PRs instead.
   Then run `./server/apply-ruleset.sh OWNER` signed in as that owner. It is safe to re-run. Excluded repos are skipped, but a ruleset they already have is left in place: remove it in the repo's settings. For an organization the list is applied only when the org ruleset is first created; after that, edit the ruleset's repository exclusions in the org settings.
   - Organization: one org-level ruleset; if the plan refuses it, the script prints the error and applies a ruleset to each repo instead.
   - Personal account: a ruleset on each non-archived repo you own. Private repos on a free plan may be refused; each refusal is printed as `FAILED repo: reason`, and the script exits non-zero.

## After that
- **To change a rule:** edit the file here, bump `version` in `plugins/kernel/.claude-plugin/plugin.json` in the same PR, and push. Sessions on installed machines pick it up through plugin auto-update; without the bump they keep their cached copy (`tests/test_version.sh` fails a PR that changes the plugin without one).
- **Overrides:** you are the only one who can override. Start a session with `KIT_OVERRIDE=1 claude` to switch the guard hook off, or merge your own PR on the server side. Agents can set neither.
  - Agents squash-merge their own green PRs under the merge rule in `kernel.md`. PRs touching payments, auth, kids' data, migrations, secrets/env or deletes wait on a `## Needed from the owner` box. The server ruleset still requires a PR for every change.
- **What still reaches you, by design:**
  - PRs waiting on your go-ahead (the risky kinds in the merge rule);
  - "REGISTRY STALE" lines at session start;
  - a red Rule Ratchet run.

  Everything else is enforced or self-updating.
- **Known limits:**
  - Cloud sessions (Claude Code on the web) do not install plugins that a repo enables in `.claude/settings.json`, and claude-code-action needs its own `plugin_marketplaces` / `plugins` inputs. There, only the server ruleset applies.
  - The guard needs `jq` or `python3`. Without either it stands down, with a warning, and the server ruleset still holds.
  - The guard is deliberately conservative: a command that merely *mentions* pushing to main is blocked too.
  - The guard checks the branch of the session's folder (or `git -C DIR`). `cd other-repo && git push` is judged by the session folder's branch; the server ruleset catches the rest.
  - Agents running with your own token can still merge PRs through the API from tools outside Claude Code. The guard covers sessions in Claude Code only, and it checks the merge method, not what the PR touches: the risky-kinds part of the merge rule is held by the merge-gate box.

## Shared merge-gate and shipping snippets
- `actions/merge-gate/` is one composite action for every repo's `merge-gate` check. It blocks a PR with the `hold` label, gate phrases (`do not merge`, `needs owner yes`, `owner-gated`, `gate:`, a `HOLD` title), an unchecked box under `## Before merge`, or any open item under `## Needed from the owner` (only ticked boxes or `None` clear it). Tests: `tests/test_merge_gate.sh`.
- `repo-snippet/.github/workflows/merge-gate.yml` is the 30-line caller a repo keeps. Its job is still named `merge-gate`, so a ruleset that requires `merge-gate` keeps working when a repo swaps its own copy for the caller.
- `repo-snippet/.github/pull_request_template.md` is the standard PR body (Before / After / How / How I verified / Needed from the owner / After merge).
- `repo-snippet/SHIPPING.md` is the standard shipping section for a repo's `AGENTS.md`. Cloud sessions don't load the kit plugin, so the rules they need must be in the repo itself.
- `repo-snippet/HANDOFF.md` and `repo-snippet/.handoff/TEMPLATE.md` are the handoff files. Each branch keeps its own `.handoff/<branch>.md` (DONE / OPEN / NEXT / DECIDED + WHY / DON'T), so parallel PRs never conflict on it. The root `HANDOFF.md` keeps only the decisions and dead ends that outlive a branch. Both cap at 60 lines. When a branch finishes, its DON'T lines move to the root file; a root line that bites again (or overflows the cap) becomes an `AGENTS.md` rule in a draft PR. That's the ratchet, applied to handoffs. Tests: `tests/test_handoff.sh`.

## Live check after production deploys (auto-revert)
**Add it to a repo (one workflow file plus one config file, no secret):**
1. Copy `repo-snippet/.github/workflows/live-check.yml` to the repo's `.github/workflows/`, replace `OWNER`, and pin `REF` to an agent-kit commit SHA.
2. Add `.livecheck.json` at the repo root (`repo-snippet/.livecheck.json` is the shape): the production `base_url` (the custom domain, not a `*.vercel.app` deployment URL, which deployment protection may block) and 3 to 6 paths. Give each a `status` (default 200, or a list) and an optional `contains` text. Assert at least one signed-out redirect or 401, so a broken auth gate fails the check.
3. In the Actions tab, run **live-check** by hand once with `drill: revert`. It adds a path that must fail, then opens a revert PR (or an issue) labelled `live-check-drill` and closes it at once. Nothing is merged and production is not touched.

**What it does on each Production `deployment_status` from Vercel:** it checks once after `settle_seconds` (default 15). A pass ends the run, so a healthy deploy costs about 20 seconds. A failure is re-checked twice, `retry_seconds` apart (default 75). If it still fails, `decide.sh` picks one of two outcomes:
- **Revert** happens only when all of these hold: the commit is a squash-merge from a PR (agents can only squash), it is still the tip of the default branch, the PR has no `hold` or `gate:*` label, it touches no migration, auth, payments, env, legal or workflow path, the previous production live check passed, and the commit is not itself a revert. The revert PR (labelled `auto-revert`) is squash-merged without CI, because its tree is checked to be identical to the parent commit, the tree that was live and passing before. Vercel then deploys the revert, and the live check runs on it too.
- **Issue** covers everything else, plus any revert that can't finish at some step: one open issue labelled `live-check-failed`, and later failures add comments to it.

**For the weekly ledger:** each run writes one line to its job summary (`live-check | repo | sha | PASS/FAIL | action | reason`). Count real reverts with `is:pr label:auto-revert` and failures with `label:live-check-failed`. Drills carry `live-check-drill` instead, and so does the revert of a PR labelled `live-check-drill`.

**Limits:** the check only sees HTTP status and page text, not runtime errors in logs. The repo setting "Allow GitHub Actions to create and approve pull requests" must be on, or every revert falls back to an issue (the drill shows which). Tests: `tests/test_live_check.sh`.
