#!/usr/bin/env bash
# Write a ClusterRequest file. See SKILL.md for flags.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
dest=requests/clusters size=S region="" mode="" ttl="" addons=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --provider) provider=$2;; --name) name=$2;; --team) team=$2;; --env) env=$2;; --size) size=$2;;
    --region) region=$2;; --mode) mode=$2;; --ttl) ttl=$2;; --cost-center) cc=$2;; --budget) budget=$2;;
    --dest) dest=$2;; --addons) addons=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${provider:?--provider required}" "${name:?--name required}" "${team:?--team required}" "${env:?--env required}"
: "${cc:?--cost-center required}" "${budget:?--budget required}"
case $provider in
  gke) mode=${mode:-autopilot};;
  eks) mode=${mode:-auto};;
  *) echo "provider must be gke or eks" >&2; exit 64;;
esac
region=${region:-$(jq -r --arg p "$provider" '.[$p].regions[0]' "$here/assets/environments.json")}
out="$dest/$name.yaml"
[[ -e $out ]] && { echo "refusing: $out exists (edit it, or pick another name)" >&2; exit 65; }
mkdir -p "$dest"
{
  echo "apiVersion: platform.local/v1alpha1"
  echo "kind: ClusterRequest"
  echo "metadata:"
  echo "  name: $name"
  echo "  team: $team"
  echo "spec:"
  echo "  provider: $provider"
  echo "  env: $env"
  echo "  region: $region"
  echo "  mode: $mode"
  echo "  size: $size"
  if [[ -n $ttl ]]; then echo "  ttl: $ttl"; fi
  echo "  costCenter: $cc"
  echo "  budgetMonthlyUSD: $budget"
  if [[ -n $addons ]]; then
    echo "  addons:"
    tr ',' '\n' <<<"$addons" | sed '/^ *$/d; s/^ *//; s/ *$//; s/^/    - /'
  fi
} > "$out"
echo "$out"
