#!/usr/bin/env bash
# Validate an Ansible project: platform policy, pinned collections installed, syntax check of every playbook,
# then ansible-lint at the production profile. Usage: validate.sh <project-dir> [--offline]
# --offline skips the collection install (collections must already be in .ansible/collections).
# Exit 0 PASS, 1 FAIL, 64 usage. Nothing here connects to a host.
set -euo pipefail
dir=${1:?usage: validate.sh <project-dir> [--offline]}
offline=false; [[ ${2:-} == --offline ]] && offline=true
cd "$dir"
export ANSIBLE_CONFIG=$PWD/ansible.cfg
shopt -s nullglob globstar
fail=0
deny() { echo "  DENY $*"; fail=1; }
[[ -f ansible.cfg ]] || { echo "FAIL: no ansible.cfg in $dir (render a playbook first)"; exit 1; }
playbooks=(playbooks/*.yml)
[[ ${#playbooks[@]} -gt 0 ]] || { echo "FAIL: no playbooks/*.yml"; exit 1; }

echo "== policy"
for f in "${playbooks[@]}"; do
  while IFS= read -r h; do
    [[ $h == all || $h == '*' || $h == ungrouped ]] && deny "$f: play targets '$h'; target an inventory group"
  done < <(yq '.[].hosts // ""' "$f")
done
if [[ -f requirements.yml ]]; then
  while IFS=$'\t' read -r n v; do
    [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || deny "requirements.yml: $n must pin an exact version (x.y.z), not '${v}'"
  done < <(yq -r '(.collections // [])[] | [(.name // .), (.version // "")] | @tsv' requirements.yml)
fi
# A secret-looking key holding a literal string is a plaintext secret; !vault values and {{ lookups }} are fine.
secret_re='(?i)(pass(word|wd)?|secret|token|api_?key|private_?key|credential)'
for f in inventory/**/*.yml group_vars/**/*.yml host_vars/**/*.yml roles/*/defaults/*.yml roles/*/vars/*.yml "${playbooks[@]}"; do
  [[ -f $f ]] || continue
  while IFS= read -r k; do
    [[ -n $k ]] && deny "$f: $k holds a plaintext secret; use ansible-vault (!vault) or a lookup"
  done < <(R=$secret_re yq '[.. | select(tag == "!!map") | to_entries[] | select(.key | test(strenv(R)))
           | select(.value | tag == "!!str") | select(.value != "") | select(.value | test("\{\{") | not) | .key] | .[]' "$f")
done

if [[ -f requirements.yml ]] && ! $offline; then
  echo "== collections"
  ansible-galaxy collection install -r requirements.yml -p .ansible/collections >/dev/null || deny "ansible-galaxy collection install failed"
fi

echo "== syntax"
for f in "${playbooks[@]}"; do
  if out=$(ansible-playbook --syntax-check "$f" 2>&1); then echo "  ok $f"; else deny "$f: syntax check failed: $(tail -3 <<< "$out")"; fi
done

echo "== ansible-lint (production profile)"
if lint=$(ansible-lint --nocolor 2>&1); then echo "  ok"; else tail -20 <<< "$lint" | sed 's/^/  /'; fail=1; fi

if [[ $fail -ne 0 ]]; then echo FAIL; exit 1; fi
echo PASS
