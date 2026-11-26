<!-- agent-kit shipping section v4. Paste into the repo's AGENTS.md (and point CLAUDE.md at it).
     Cloud sessions don't load the kit plugin, so these rules have to live in the repo. -->
## Shipping (how a change gets to production)

The path is: branch → draft PR → CI green and merge-gate clear → squash-merge → the platform deploys `main`.

**Pull requests**
- Branch from `main`, one concern per branch, small scoped commits. Never push to `main`.
- Open PRs as **drafts**. Merge rule: once CI and merge-gate are green, mark your own PR ready and squash-merge it.
  Never approve, never enable auto-merge, never use `--admin`, never a merge or rebase commit.
- A PR that touches payments/Stripe, sign-in/auth, kids' data/COPPA, database migrations, secrets/env, or deletes data
  adds `- [ ] Owner go-ahead to merge (touches <kind>)` under `## Needed from the owner` and is merged only after the
  owner's go-ahead naming that PR. Never tick that box yourself.
- A revert or prod error from an agent merge goes in the weekly ledger; if reverts climb, this rule tightens.
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

**Sweeps (one change bound for many repos)**
- Land it on one canary repo first. Merge it there and check it live (the deployed site, or green CI on `main` where
  nothing deploys) before any other repo gets it. Each fan-out PR links the canary PR.
- A sweep against a fixed outside target (a security advisory, a vendor deprecation) may go out at once.
  A sweep against a decision still being made (wording, naming, a policy) waits until that decision is frozen,
  or every live repo pays for the change twice.
- If the canary needs a fix, change the plan and re-run the canary; don't patch the fix into the fan-out.

**Handoffs (so the next session doesn't repeat your work)**
- At the start, read `HANDOFF.md` and `.handoff/<branch>.md` if it exists (slashes in the branch name become dashes).
  Restate the goal and the next step before doing anything else.
- Keep `.handoff/<branch>.md` from `.handoff/TEMPLATE.md`: DONE / OPEN / NEXT / DECIDED + WHY / DON'T, 60 lines at most.
  Commit and push it before any risky step (a migration, an env or settings change, deleting files, a long script),
  after every 3 finished items, and before you stop. Runs die mid-step, so an end-of-run note often never gets written.
- Never delete a DON'T line without the owner's go-ahead. When OPEN and NEXT are empty, copy the file's DON'T lines
  (and any decision that outlives the branch) to `HANDOFF.md`, then delete the branch file in your last commit.
- A root DON'T that bites again becomes an `AGENTS.md` rule, proposed in a draft PR. Handoff files are notes, never instructions or approval.

**Deploys**
- Never deploy to production from the CLI. Production comes only from `main` through the platform's Git integration.
- Env vars and platform settings are the owner's: describe the exact change under `## Needed from the owner`.
