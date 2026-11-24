#!/usr/bin/env bash
# Read-only audit of a repo against the baseline. Exit 1 on any DENY.
# Usage: audit.sh <owner>/<repo> [--dump-state FILE]   |   audit.sh --state FILE
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
state="" dump="" repo=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --state) state=$2; shift;; --dump-state) dump=$2; shift;;
    -*) echo "unknown arg $1" >&2; exit 64;;
    *) repo=$1;;
  esac
  shift
done
[[ -n $repo || -n $state ]] || { echo "usage: audit.sh <owner>/<repo> | --state FILE" >&2; exit 64; }

# get PATH: JSON body, or null when the API refuses (404, 403 on Free private repos).
get() { local out; out=$(gh api "$1" 2>/dev/null) && [[ -n $out ]] && printf '%s' "$out" || printf 'null'; }
exists() { gh api --silent "$1" >/dev/null 2>&1 && echo true || echo false; }

if [[ -z $state ]]; then
  r=repos/$repo
  repo_json=$(get "$r")
  [[ $repo_json != null ]] || { echo "cannot read $repo" >&2; exit 2; }
  rulesets='[]'
  ids=$(get "$r/rulesets" | jq -r 'if type == "array" then .[].id else empty end')
  for id in $ids; do rulesets=$(jq -c --argjson x "$(get "$r/rulesets/$id")" '. + [$x]' <<<"$rulesets"); done
  files='{}'
  for f in SECURITY.md LICENSE .github/CODEOWNERS .github/dependabot.yml .github/workflows/security.yml .github/workflows/scorecard.yml; do
    files=$(jq -c --arg f "$f" --argjson e "$(exists "$r/contents/$f")" '. + {($f): $e}' <<<"$files")
  done
  state=$(mktemp)
  trap 'rm -f "$state"' EXIT
  jq -n \
    --argjson repo "$repo_json" \
    --argjson va "$(exists "$r/vulnerability-alerts")" \
    --argjson asf "$(get "$r/automated-security-fixes")" \
    --argjson pvr "$(get "$r/private-vulnerability-reporting")" \
    --argjson cs "$(get "$r/code-scanning/default-setup")" \
    --argjson wf "$(get "$r/actions/permissions/workflow")" \
    --argjson ap "$(get "$r/actions/permissions")" \
    --argjson rulesets "$rulesets" --argjson files "$files" '{
      repo: ($repo | {full_name, visibility, default_branch, allow_merge_commit, delete_branch_on_merge, has_wiki, security_and_analysis}),
      vulnerability_alerts: $va,
      automated_security_fixes: ($asf.enabled // false),
      private_vulnerability_reporting: ($pvr.enabled // false),
      code_scanning_default_setup: ($cs.state // null),
      workflow_permissions: $wf, actions_permissions: $ap,
      rulesets: $rulesets, files: $files }' > "$state"
  [[ -n $dump ]] && cp "$state" "$dump"
fi

jq -r '"audit \(.repo.full_name) (\(.repo.visibility))"' "$state"
rows=$(jq -c -f "$here/assets/policy.jq" "$state")
jq -r '.[] | if .why == "" then "\(.v)  \(.c)" else "\(.v)  \(.c): \(.why)" end' <<<"$rows"
denies=$(jq '[.[] | select(.v == "DENY")] | length' <<<"$rows")
if [[ $denies -gt 0 ]]; then echo "FAIL: $denies control(s) denied"; exit 1; fi
echo "PASS"
