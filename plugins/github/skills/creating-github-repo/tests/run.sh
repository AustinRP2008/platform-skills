#!/usr/bin/env bash
# Offline tests: audit policy on fixtures (green and red controls), baseline files, name validation.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
s=$here/../scripts
root=$(cd "$here/../../../../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
ok()  { echo "ok   $*"; }
bad() { echo "FAIL $*"; failures=$((failures+1)); }
expect_pass() { local l=$1; shift; if "$@" >"$tmp/log" 2>&1; then ok "$l"; else bad "$l"; tail -20 "$tmp/log"; fi; }
expect_deny() {
  local l=$1 reason=$2; shift 2
  if "$@" >"$tmp/log" 2>&1; then bad "$l (should have failed)"
  elif command grep -qF -- "$reason" "$tmp/log"; then ok "$l"
  else bad "$l (failed, but not with: $reason)"; tail -5 "$tmp/log"; fi
}
# mutate NAME JQ: a copy of the compliant public fixture with one control broken.
mutate() { jq "$2" "$here/public-compliant.json" > "$tmp/$1.json"; echo "$tmp/$1.json"; }

expect_pass "audit: compliant public repo" "$s/audit.sh" --state "$here/public-compliant.json"
expect_pass "audit: compliant private repo (rulesets N/A on Free)" "$s/audit.sh" --state "$here/private-compliant.json"
expect_deny "audit: force push allowed" "force pushes to main are allowed" \
  "$s/audit.sh" --state "$(mutate fp '(.rulesets[0].rules) |= map(select(.type != "non_fast_forward"))')"
expect_deny "audit: ruleset in evaluate mode does not count" "no active ruleset targets main" \
  "$s/audit.sh" --state "$(mutate eval '.rulesets[0].enforcement = "evaluate"')"
expect_deny "audit: bypass actor" "someone can bypass the ruleset" \
  "$s/audit.sh" --state "$(mutate bp '.rulesets[0].bypass_actors = [{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]')"
expect_deny "audit: push protection off" "secrets can be pushed" \
  "$s/audit.sh" --state "$(mutate pp '.repo.security_and_analysis.secret_scanning_push_protection.status = "disabled"')"
expect_deny "audit: writable workflow token" "the default GITHUB_TOKEN can write" \
  "$s/audit.sh" --state "$(mutate wt '.workflow_permissions.default_workflow_permissions = "write"')"
jq '.files[".github/workflows/security.yml"] = false' "$here/private-compliant.json" > "$tmp/nosec.json"
expect_deny "audit: private repo without the compensating scan" ".github/workflows/security.yml is missing" \
  "$s/audit.sh" --state "$tmp/nosec.json"

for v in public private; do
  mkdir -p "$tmp/$v"
  expect_pass "files: $v baseline" "$s/files.sh" "$tmp/$v" --visibility "$v" --owner example
  expect_pass "files: $v workflows pinned + actionlint" \
    "$root/plugins/delivery/skills/onboarding-repo-ci/scripts/validate.sh" "$tmp/$v"
done
if [[ -e $tmp/private/LICENSE ]]; then bad "files: private repo got a LICENSE"; else ok "files: private repo has no LICENSE"; fi
echo "keep me" > "$tmp/public/README.md"
"$s/files.sh" "$tmp/public" --visibility public --owner example >/dev/null
if [[ $(cat "$tmp/public/README.md") == "keep me" ]]; then ok "files: existing file kept"; else bad "files: overwrote README.md"; fi

expect_deny "create: bad name rejected before any API call" "name must be lowercase" \
  "$s/create.sh" --name Bad_Name --visibility public --description x --owner example
expect_deny "create: unknown visibility rejected" "visibility must be public or private" \
  "$s/create.sh" --name ok-name --visibility internal --description x --owner example

if [[ $failures -ne 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "ALL PASS"
