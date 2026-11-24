#!/usr/bin/env bash
# Policy + cost + approval tier + mock-provider plan for one ClusterRequest. Prints a PR summary.
# Usage: check.sh <request.yaml>
# Env: PLATFORM_MODULES_SOURCE  module source prefix (a local path for development);
#      PLATFORM_MODULES_REF     tag of tofu-modules used with the default git source.
set -euo pipefail
req=${1:?usage: check.sh <request.yaml>}
here=$(cd "$(dirname "$0")/.." && pwd)
src=${PLATFORM_MODULES_SOURCE:-"git::https://github.com/AustinRP2008/tofu-modules.git//modules"}
ref=${PLATFORM_MODULES_REF:-v0.1.0}
json=$(yq -o=json '.' "$req")
envs=$(cat "$here/assets/environments.json")
prices=$(cat "$here/assets/prices.json")

# ---- policy: every rule prints a reason; no output means allowed.
denials=$(jq -r --argjson envs "$envs" '
  def ttl_hours: ((.spec.ttl // "") | capture("^(?<h>[0-9]+)h$") | .h | tonumber) // 0;
  .spec as $s | ttl_hours as $h |
  ( if .apiVersion != "platform.local/v1alpha1" or .kind != "ClusterRequest" then "apiVersion/kind must be platform.local/v1alpha1 ClusterRequest" else empty end ),
  ( if (.metadata.name // "" | test("^[a-z][a-z0-9-]{2,38}[a-z0-9]$")) then empty else "metadata.name must be 4-40 chars kebab-case" end ),
  ( if (.metadata.team // "" | test("^[a-z][a-z0-9-]+$")) then empty else "metadata.team must be kebab-case" end ),
  ( if ($s.provider | IN("gke","eks")) then empty else "spec.provider must be gke or eks" end ),
  ( if ($s.env | IN("dev","staging","prod")) then empty else "spec.env must be dev, staging or prod" end ),
  ( if ($s.size | IN("S","M","L")) then empty else "spec.size must be S, M or L" end ),
  ( if $s.provider == "gke" and ($s.mode | IN("autopilot","standard") | not) then "gke mode must be autopilot or standard" else empty end ),
  ( if $s.provider == "eks" and ($s.mode | IN("auto","managed") | not) then "eks mode must be auto or managed" else empty end ),
  ( if ($s.provider | IN("gke","eks")) and (($envs[$s.provider].regions | index($s.region)) == null) then "spec.region \($s.region) is not offered for \($s.provider)" else empty end ),
  ( if ($s.costCenter // "" | tostring | test("^cc-[0-9]{4}$")) then empty else "spec.costCenter must look like cc-1234" end ),
  ( if ($s.budgetMonthlyUSD | type) != "number" then "spec.budgetMonthlyUSD must be a number" else empty end ),
  ( if $s.env == "prod" and $s.ttl != null then "prod clusters must not have a ttl" else empty end ),
  ( if $s.env != "prod" and $s.ttl == null then "\($s.env) clusters need a ttl (max 168h)" else empty end ),
  ( if $s.ttl != null and ($h < 1 or $h > 168) then "ttl must be 1h-168h" else empty end ),
  ( if $s.env == "dev" and $s.size == "L" then "dev clusters are capped at size M" else empty end ),
  ( (keys - ["apiVersion","kind","metadata","spec"])[] | "unknown top-level field: \(.)" ),
  ( ($s | keys) - ["provider","env","region","mode","size","ttl","costCenter","budgetMonthlyUSD"] | .[] | "spec.\(.) is not requestable (platform default)" )
' <<< "$json")

provider=$(jq -r .spec.provider <<< "$json")
env=$(jq -r .spec.env <<< "$json")
mode=$(jq -r .spec.mode <<< "$json")
size=$(jq -r .spec.size <<< "$json")
name=$(jq -r .metadata.name <<< "$json")
budget=$(jq -r .spec.budgetMonthlyUSD <<< "$json")
cost=$(jq -r --arg p "$provider" --arg m "$mode" --arg s "$size" '.[$p][$m][$s] // empty' <<< "$prices")
if [[ -n $cost && $budget =~ ^[0-9]+(\.[0-9]+)?$ ]] && awk -v c="$cost" -v b="$budget" 'BEGIN{exit !(c > b)}'; then
  denials+=$'\n'"estimated \$$cost/month exceeds budgetMonthlyUSD \$$budget"
fi
denials=$(sed '/^$/d' <<< "$denials")

# ---- approval tier
tier=$(jq -r '.spec as $s | (($s.ttl // "0h") | rtrimstr("h") | tonumber? // 0) as $h |
  if $s.env == "prod" or $s.size == "L" then "platform-2"
  elif $s.env == "dev" and ($s.size | IN("S","M")) and $h <= 72 then "auto"
  else "platform" end' <<< "$json")

echo "## Cluster request: $name"
echo
echo "| | |"
echo "|---|---|"
jq -r '"| provider | \(.spec.provider) (\(.spec.mode)) |", "| env / region | \(.spec.env) / \(.spec.region) |",
       "| size | \(.spec.size) |", "| team / cost center | \(.metadata.team) / \(.spec.costCenter) |",
       "| ttl | \(.spec.ttl // "none (prod)") |"' <<< "$json"
echo "| estimated cost | \$${cost:-?}/month (illustrative) vs budget \$$budget |"
echo "| approval tier | \`approval:$tier\` |"
echo
if [[ -n $denials ]]; then
  echo "### Policy: DENY"
  while IFS= read -r d; do echo "- $d"; done <<< "$denials"
  exit 1
fi
echo "### Policy: ALLOW"

# ---- plan: a root module that calls the pinned module, run with tofu test and mock providers.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tests"
module_src="$src/$provider-cluster"
if [[ $src == git::* ]]; then module_src+="?ref=$ref"; fi
labels=$(jq -c '{team: .metadata.team, env: .spec.env, "cost-center": .spec.costCenter, ttl: (.spec.ttl // "none")}' <<< "$json")
if [[ $provider == gke ]]; then
  e=$(jq --arg env "$env" '.gke[$env]' <<< "$envs")
  vars=$(jq -c --argjson e "$e" --argjson l "$labels" '{
    name: .metadata.name, region: .spec.region, mode: .spec.mode, size: .spec.size,
    project_id: $e.project_id, network: $e.network, subnetwork: "\($e.subnetwork_prefix)-\(.spec.region)",
    deletion_protection: (.spec.env == "prod"), labels: $l }' <<< "$json")
  mock='mock_provider "google" {}'
else
  e=$(jq --arg env "$env" '.eks[$env]' <<< "$envs")
  vars=$(jq -c --argjson e "$e" --argjson l "$labels" '{
    name: .metadata.name, compute_mode: .spec.mode, size: .spec.size, subnet_ids: $e.subnet_ids, tags: $l }' <<< "$json")
  mock='mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/mock" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-2:000000000000:key/mock" }
  }
}'
fi
{
  printf 'module "cluster" {\n  source = "%s"\n' "$module_src"
  jq -r 'to_entries[] | "  \(.key) = \(.value | tojson)"' <<< "$vars"
  echo "}"
} > "$work/main.tf"
printf '%s\n\nrun "plan" {\n  command = plan\n}\n' "$mock" > "$work/tests/plan.tftest.hcl"
echo
echo "### Plan (mock providers, no cloud access)"
if (cd "$work" && tofu init -backend=false -input=false >/dev/null && tofu test -no-color) > "$work/plan.log" 2>&1; then
  echo "PASS: module \`$provider-cluster\` accepts this request ($module_src)"
else
  echo "FAIL: see log"
  echo '```'
  tail -30 "$work/plan.log"
  echo '```'
  exit 1
fi
