---
name: creating-github-repo
description: Create a GitHub repository that is secure from its first commit - branch ruleset, secret scanning and push protection, CodeQL, Dependabot, private vulnerability reporting, read-only Actions token, SHA-pinned actions, and free gitleaks/osv-scanner checks - using only GitHub Free features, and audit or harden existing repos against the same baseline. Use when someone asks for a new GitHub repo, wants branch protection or security scanning set up, asks whether a repo is compliant, or asks what changes between a public and a private repo on the free plan.
license: MIT
---

# Creating a GitHub repository

The repo is created with its controls already on: there is never a window where `main` is
unprotected or a secret could be pushed unnoticed. Every script is a dry run until `--apply`.
Only free-tier features are used; `references/free-tier-matrix.md` says what each control costs.

## 1. Interview
| Field | Allowed | Default / rule |
|---|---|---|
| `name` | lowercase letters, digits, `-`, `.`; 1-100 chars | ask |
| `visibility` | `public`, `private` | ask, and explain the trade-off below before they choose |
| `description` | one line | ask |
| `approvals` | `0`-`6` | `0` for a solo owner (you cannot approve your own PR); `1`+ once there is a team |

**Public vs private on GitHub Free** (say this before they pick):
- Public gets everything free: an enforced ruleset on `main`, secret scanning with push protection,
  CodeQL, dependency review, private vulnerability reporting and OpenSSF Scorecard.
- Private on Free cannot enforce anything on `main` (rulesets and branch protection return
  `403 Upgrade to GitHub Pro`) and has no secret or code scanning. The skill compensates with
  gitleaks and osv-scanner in Actions, which report on every PR but cannot block a merge, and
  those minutes come out of the account's monthly included Actions compute.
- Nothing identifying goes into a public repo: commits use the account's noreply address.

## 2. Plan (dry run)
```bash
${CLAUDE_SKILL_DIR}/scripts/create.sh --name <name> --visibility public --description "<text>" [--approvals 0]
```
Prints every control with its status for that visibility (`enforced`, `compensated`, `unavailable`)
and the exact API calls. Show the user the table and the `unavailable` lines.

## 3. Create
Same command plus `--apply`. It creates the repo, pushes the baseline commit (README, LICENSE for
public, SECURITY.md, CODEOWNERS, dependabot.yml, security workflow), then runs `harden.sh --apply` and
`audit.sh`. Report the audit output verbatim; a `DENY` line means the repo is not done.

## Existing repos
1. Add the baseline files through a PR: `scripts/files.sh <checkout> --visibility <v> --owner <login>`
   (existing files are kept). Merge it first: the ruleset requires the `gitleaks` and `osv-scanner` checks.
2. `scripts/harden.sh <owner>/<repo> [--approvals N] [--require-check NAME ...]` then `--apply`.
   Add the repo's own CI job names with `--require-check`.
3. `scripts/audit.sh <owner>/<repo>`: read-only, exit 1 on any DENY. Safe to run any time (drift check).

## Rules
- Never weaken a control to make something merge; fix the change, or record an exception in the PR.
- Never add bypass actors to the ruleset. An admin who needs to bypass should notice that they are.
- Never paste a token or secret into a file, flag or issue; gitleaks runs on full history.
- Do not delete repos; the token used here should not have `delete_repo`.
