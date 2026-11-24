---
name: onboarding-repo-ci
description: Onboard a repository to the platform's shared CI. Detects OpenTofu modules, Kubernetes apps, Prometheus rule directories and golden image definitions, writes one caller workflow that runs the platform's reusable workflows pinned to a commit SHA, and checks the result with actionlint and a pinning policy. Use when someone asks to add CI, set up GitHub Actions, onboard a repo to the platform, or why their repo has no checks.
license: MIT
---

# Onboarding a repo to shared CI

The platform owns the pipelines; a product repo owns one short caller file. Teams get fixes by bumping one
SHA (Renovate or Dependabot can do it), never by copying YAML.

## 1. Detect what the repo contains
```bash
${CLAUDE_SKILL_DIR}/scripts/detect.sh <repo-dir>
```
Prints one `kind<TAB>path` line per target: `tofu` (a dir with `versions.tf`), `k8s` (a dir with
`base/kustomization.yaml` and `overlays/`), `prometheus` (a dir with `rules/` and `tests/`), `image` (a dir with `image.yaml` and `image.pkr.hcl`). If it finds
nothing, tell the user which layout each kind expects (`references/ci-contract.md`) and stop.

## 2. Render the caller workflow
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh <repo-dir> --ref <40-char platform-skills commit sha>
```
Writes `<repo-dir>/.github/workflows/platform.yml`: one job per kind, a matrix over its paths, every
reusable workflow and every action pinned to a full SHA, `permissions: contents: read`. It refuses to
overwrite an existing file; show the diff and let the user decide.

Get the SHA from the platform's latest release, never from a branch name:
`gh api repos/AustinRP2008/platform-skills/commits/main --jq .sha`.

## 3. Check
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <repo-dir>
```
Runs actionlint and the pinning policy (no `@main`, `@v1` or other mutable refs; top-level permissions
present). Then open a PR titled `ci: onboard to platform CI` with the detected targets in the body.
