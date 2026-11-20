<!-- agent-kit shipping section v1. Paste into the repo's AGENTS.md (and point CLAUDE.md at it).
     Cloud sessions don't load the kit plugin, so these rules have to live in the repo. -->
## Shipping (how a change gets to production)

The path is: branch → draft PR → CI green and merge-gate clear → the owner merges → the platform deploys `main`.
Agents do every step except the merge.

**Pull requests**
- Branch from `main`, one concern per branch, small scoped commits. Never push to `main`.
- Open PRs as **drafts**. Never merge, never mark ready, never approve, never enable auto-merge, never use `--admin`.
- Fill in `.github/pull_request_template.md`: Before / After / How / How I verified / Needed from the owner / After merge.
- Anything the owner must do before merge goes under `## Needed from the owner`, one `- [ ]` box per item
  (a decision, an env var, a setting). merge-gate stays red until every box is ticked or the section says `None`.
  Never write a "HOLD" note instead. Post-merge steps go under `## After merge`.
- Don't name the owner. No real names, emails, phones or handles in code, fixtures, commits or PRs; use fake test accounts.

**CI**
- Required checks are matched by job `name:`. Don't rename or remove a job that a ruleset requires; ask first.
- Never skip, disable or weaken a check or test to get green. A flaky failure: quote the log line, re-run once.
- Run lint, typecheck, tests and the build locally before opening the PR, and say what you ran.

**Databases**
- Migrations run in a required CI job on `main` after merge, never inside the deploy platform's build.
- The readiness route returns 503 unless the expected tables and migrations exist (schema shape, not just a connection).
- A PR that adds a migration says so in its title and lists any env var it needs under `## Needed from the owner`.

**Fail closed**
- Anything that needs a secret or config denies when it's missing. Auth allowlists public routes; never the reverse.
- Rate-limit auth routes per IP.
- Internal docs (`*.md`, `docs/`, `.claude/`, audits) are never served by the deployed site.

**Deploys**
- Never deploy to production from the CLI. Production comes only from `main` through the platform's Git integration.
- Env vars and platform settings are the owner's: describe the exact change under `## Needed from the owner`.
