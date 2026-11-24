# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Use GitHub's private vulnerability reporting instead: [report a vulnerability](https://github.com/Cartooli/agent-kit/security/advisories/new). Include:

- what the issue is and where it lives (file, command or page)
- steps to reproduce, or a minimal example
- the impact you expect

We aim to acknowledge reports within 5 business days and will agree a fix and disclosure timeline with you.

## Scope

In scope: the guard hook, install script, ruleset script, merge-gate action and anything that could let an agent bypass those controls or leak data. Out of scope: Claude Code itself (report that to Anthropic) and repositories that only consume this kit.

## Supported versions

Only the latest commit on the default branch is maintained.
