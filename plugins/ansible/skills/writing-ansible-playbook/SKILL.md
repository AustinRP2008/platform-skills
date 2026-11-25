---
name: writing-ansible-playbook
description: Scaffold an Ansible playbook and role (pinned collections, group-targeted plays, role-prefixed variables, no plaintext secrets), validate it with a syntax check, ansible-lint at the production profile and platform policy, and open a PR. Use when someone asks to write an Ansible playbook or role, configure hosts with Ansible, or automate server setup.
license: MIT
---

# Writing an Ansible playbook

## 1. Collect inputs
| Input | Rule |
|---|---|
| `name` | playbook name, lowercase with `-` |
| `hosts` | one inventory group; never `all` |
| `role` | defaults to `name` with `-` as `_` (ansible-lint role-name) |
| `packages` | optional, space-separated |

## 2. Render
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh --dest <ansible-project> --name <name> --hosts <group> [--role <role>] [--packages "a b"]
```
Creates `ansible.cfg`, `inventory/hosts.yml`, `requirements.yml` and `.ansible-lint` on first use, then
`playbooks/<name>.yml` and `roles/<role>/`. Edit the role's tasks; keep every variable prefixed `<role>_`.

## 3. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <ansible-project> [--offline]
```
Denies plays targeting `all`, unpinned collections and plaintext secrets (use `ansible-vault` or a lookup),
then runs `ansible-playbook --syntax-check` and `ansible-lint` (production profile). Fix until `PASS`.

## 4. Dry run against real hosts, then PR
`ansible-playbook playbooks/<name>.yml --check --diff -l <host>` shows what would change without changing it.
Branch `feat/ansible-<name>`; paste the validate summary and the `--check` diff in the PR body.
