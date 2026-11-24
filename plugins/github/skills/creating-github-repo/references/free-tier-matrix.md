# What each control costs on GitHub Free (personal account)

Checked 2026-11-24 against docs.github.com and the live REST API. "Enforced" means GitHub blocks the
bad action; "compensated" means a free check reports it but cannot block; "unavailable" means there is
no free equivalent.

| Control | Public | Private (Free) | How it is applied |
|---|---|---|---|
| Ruleset on default branch: PR required, no force push, no deletion, linear history, required checks | enforced | unavailable: API returns `403 Upgrade to GitHub Pro` | `POST /repos/{r}/rulesets` (`assets/ruleset-branch.json`) |
| Tag ruleset: `v*` tags cannot be moved or deleted | enforced | unavailable | `assets/ruleset-tags.json` |
| Secret scanning + push protection | enforced (on by default for new public repos) | compensated: gitleaks on full history in Actions | `PATCH /repos/{r}` `security_and_analysis` |
| Code scanning (CodeQL default setup) | enforced as alerts | unavailable (needs GitHub Code Security) | `PATCH /repos/{r}/code-scanning/default-setup` |
| Dependency review on PRs | enforced (action fails the PR) | compensated: osv-scanner on every PR | `dependency-review` job in `security.yml` |
| Dependabot alerts + security updates | enforced | enforced (free on private too) | `PUT .../vulnerability-alerts`, `PUT .../automated-security-fixes` |
| Dependabot version updates for actions | enforced | enforced | `.github/dependabot.yml` |
| Private vulnerability reporting | enforced | not applicable (no outside reporters) | `PUT .../private-vulnerability-reporting` |
| OpenSSF Scorecard | enforced as alerts | not applied (needs a PAT on private) | `scorecard.yml` |
| Workflow token read-only, Actions cannot approve PRs | enforced | enforced | `PUT .../actions/permissions/workflow` |
| Actions must be pinned by full commit SHA | enforced | enforced | `PUT .../actions/permissions` `sha_pinning_required` |
| Squash/rebase only, delete branch on merge, wiki off | enforced | enforced | `PATCH /repos/{r}` |

## Minutes
Standard GitHub-hosted runners are free for public repos. Private repos draw from the account's monthly
included compute (Free: 12 USD, about 2,000 Linux minutes at 0.006 USD/min). The security workflow is two
short jobs (well under a minute each on a small repo) per PR, push to main and weekly schedule.

## Why gitleaks and osv-scanner run from pinned images
They are free, open source, behave the same on public and private repos, and the image digest is the pin.
Dependabot does not track digests inside `run:` lines: bump them by hand with
`docker buildx imagetools inspect <image>:latest`.

## Sources
- https://docs.github.com/en/get-started/learning-about-github/githubs-plans
- https://docs.github.com/en/code-security/getting-started/github-security-features
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://docs.github.com/en/code-security/security-advisories/working-with-repository-security-advisories/configuring-private-vulnerability-reporting-for-a-repository
- https://best.openssf.org/SCM-BestPractices/github/
