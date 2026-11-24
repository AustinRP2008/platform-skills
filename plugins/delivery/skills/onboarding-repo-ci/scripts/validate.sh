#!/usr/bin/env bash
# actionlint + pinning policy over every workflow in a repo.
# Usage: validate.sh <repo-dir>
set -euo pipefail
repo=${1:?usage: validate.sh <repo-dir>}
shopt -s nullglob
files=("$repo"/.github/workflows/*.yml "$repo"/.github/workflows/*.yaml)
[[ ${#files[@]} -gt 0 ]] || { echo "FAIL: no workflows in $repo/.github/workflows"; exit 1; }
fail=0
actionlint "${files[@]}" || fail=1
for f in "${files[@]}"; do
  json=$(yq -o=json '.' "$f")
  if [[ $(jq 'has("permissions")' <<< "$json") != true ]]; then
    echo "DENY $f: no top-level permissions block (default token is read-write)"; fail=1
  fi
  # every uses: (job-level reusable workflows and step actions) must be pinned to a 40-hex sha; ./local is fine.
  while IFS= read -r u; do
    [[ $u == ./* || $u == docker://*@sha256:* ]] && continue
    if [[ ! $u =~ @[0-9a-f]{40}$ ]]; then echo "DENY $f: '$u' is not pinned to a full commit sha"; fail=1; fi
  done < <(jq -r '.jobs[]? | (.uses // empty), (.steps[]?.uses // empty)' <<< "$json")
done
if [[ $fail -ne 0 ]]; then echo "FAIL"; exit 1; fi
echo "PASS"
