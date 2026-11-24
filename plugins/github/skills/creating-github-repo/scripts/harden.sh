#!/usr/bin/env bash
# Apply the baseline settings, security features and rulesets to a repo. Dry run unless --apply.
# Usage: harden.sh <owner>/<repo> [--approvals N] [--require-check NAME ...] [--apply]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
repo=${1:?usage: harden.sh <owner>/<repo> [--approvals N] [--require-check NAME ...] [--apply]}
shift
apply=false approvals=1 checks='[]'
while [[ $# -gt 0 ]]; do
  case $1 in
    --apply) apply=true;;
    --approvals) approvals=$2; shift;;
    --require-check) checks=$(jq -c --arg c "$2" '. + [$c]' <<<"$checks"); shift;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift
done
[[ $approvals =~ ^[1-6]$ ]] || { echo "approvals must be 1-6 (code-owner review needs at least one)" >&2; exit 64; }
r=repos/$repo
visibility=$(gh api "$r" -q .visibility) || { echo "cannot read $repo" >&2; exit 2; }
$apply || echo "dry run for $repo ($visibility); re-run with --apply"

# call METHOD PATH [JSON]: run it, or print it in a dry run.
call() {
  local m=$1 p=$2 body=${3:-}
  # shellcheck disable=SC2016 # the quotes are printed for copy-paste; $body expands inside the outer double quotes
  if ! $apply; then echo "gh api -X $m $p${body:+ <<< '$body'}"; return; fi
  if [[ -n $body ]]; then gh api -X "$m" "$p" --input - <<<"$body" >/dev/null; else gh api -X "$m" "$p" >/dev/null; fi
  echo "done   $m $p"
}
# upsert_ruleset FILE-JSON: replace a ruleset with the same name, or create it.
upsert_ruleset() {
  local body=$1 name id
  name=$(jq -r .name <<<"$body")
  id=$(gh api "$r/rulesets" -q ".[] | select(.name == \"$name\") | .id") || { echo "cannot list rulesets of $repo" >&2; exit 2; }
  if [[ -n $id ]]; then call PUT "$r/rulesets/$id" "$body"; else call POST "$r/rulesets" "$body"; fi
}

call PATCH "$r" '{"allow_merge_commit":false,"allow_squash_merge":true,"allow_rebase_merge":true,"delete_branch_on_merge":true,"allow_update_branch":true,"allow_auto_merge":true,"has_wiki":false,"has_projects":false,"squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}'
call PUT "$r/vulnerability-alerts"
call PUT "$r/automated-security-fixes"
call PUT "$r/actions/permissions/workflow" '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}'
call PUT "$r/actions/permissions" '{"enabled":true,"allowed_actions":"all","sha_pinning_required":true}'

if [[ $visibility == public ]]; then
  call PATCH "$r" '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
  call PUT "$r/private-vulnerability-reporting"
  call PATCH "$r/code-scanning/default-setup" '{"state":"configured","query_suite":"default"}'
  branch=$(jq -c --argjson n "$approvals" --argjson extra "$checks" '
    (.rules[] | select(.type == "pull_request") | .parameters.required_approving_review_count) = $n
    | (.rules[] | select(.type == "pull_request") | .parameters.require_code_owner_review) = true
    | (.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks) +=
        [ $extra[] | {context: ., integration_id: 15368} ]' "$here/assets/ruleset-branch.json")
  upsert_ruleset "$branch"
  upsert_ruleset "$(jq -c . "$here/assets/ruleset-tags.json")"
else
  echo "skip   rulesets, secret scanning, code scanning, private vulnerability reporting:"
  echo "       not available on GitHub Free private repos (see references/free-tier-matrix.md)"
fi
