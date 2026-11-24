#!/usr/bin/env bash
# Lint every SKILL.md against the agentskills.io core rules. Usage: scripts/lint-skills.sh
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
fail=0
err() { echo "FAIL $1: $2"; fail=1; }
for f in plugins/*/skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$f")")
  [[ $(head -1 "$f") == "---" ]] || { err "$f" "missing frontmatter"; continue; }
  fm=$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")
  name=$(yq '.name // ""' <<< "$fm")
  desc=$(yq '.description // ""' <<< "$fm")
  [[ $name == "$dir" ]] || err "$f" "name '$name' must equal directory '$dir'"
  [[ $name =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && ${#name} -le 64 ]] || err "$f" "name must be lowercase-hyphenated, <=64 chars"
  [[ -n $desc ]] || err "$f" "description required"
  (( ${#desc} <= 1024 )) || err "$f" "description is ${#desc} chars (max 1024)"
  [[ $desc == *"Use when"* ]] || err "$f" "description should say when to use it ('Use when ...')"
  lines=$(wc -l < "$f"); (( lines <= 500 )) || err "$f" "$lines lines (keep under 500; move detail to references/)"
  for s in "$(dirname "$f")"/scripts/*; do [[ -x $s ]] || err "$s" "not executable"; done
done
for p in plugins/*/; do
  jq -e --arg n "$(basename "$p")" '.name == $n' "$p/.claude-plugin/plugin.json" >/dev/null || err "$p" "plugin.json name mismatch"
  jq -e --arg n "$(basename "$p")" '.plugins | map(.name) | index($n)' .claude-plugin/marketplace.json >/dev/null || err "$p" "not listed in marketplace.json"
done
[[ $fail -eq 0 ]] || exit 1
skills=(plugins/*/skills/*/SKILL.md)
echo "PASS: ${#skills[@]} skills"
