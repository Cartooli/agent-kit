# Conclusion of the latest finished production live check before this run ($me), or "none".
# Counts runs from any deploy trigger; skips hand-run drills (workflow_dispatch), skipped
# runs (preview or non-Vercel events) and cancelled ones. Input: a workflow runs listing,
# newest first.
[.workflow_runs[]
  | select(.id != $me and .event != "workflow_dispatch"
           and (.conclusion == "success" or .conclusion == "failure"))]
| first | .conclusion // "none"
