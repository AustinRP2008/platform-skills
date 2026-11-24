---
name: scaffolding-tofu-module
description: Scaffold a new OpenTofu/Terraform module that meets the platform standard (versions pinned, variables validated, generated README, tofu test with mock providers), validate it, and open a PR. Use when someone asks to create, start or scaffold a Terraform or OpenTofu module.
license: MIT
---

# Scaffolding an OpenTofu module

The scripts do the work. Your job is to collect inputs, run them, fix what validation reports, and open a PR.

## 1. Collect inputs
- `name`: kebab-case module name, e.g. `gcs-bucket`. Ask if not given.
- `dest`: where modules live in the target repo. Default `modules/<name>`.
- `purpose`: one sentence for the README.

Read `references/module-standards.md` once before editing generated files.

## 2. Render
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh <name> <dest> "<purpose>"
```
It refuses to overwrite an existing directory. Do not work around that; ask the user.

## 3. Implement
Replace the `terraform_data` placeholder in `main.tf` with real resources. Keep every input in `variables.tf`
with a `description`, a `type` and a `validation` where it makes sense. Add a `run` block to
`tests/defaults.tftest.hcl` for each behaviour you add; use `mock_provider` so tests never need credentials.

## 4. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <dest>
```
It runs `tofu fmt -check`, `tofu init -backend=false`, `tofu validate`, `tflint` and `tofu test`.
Fix every failure and re-run until it prints `PASS`. Never skip a check or loosen a test to get green.

## 5. Open the PR
Branch `feat/module-<name>`, conventional commit `feat(<name>): add module`, PR body = the purpose, the
inputs/outputs table from the README, and the `validate.sh` output summary.
