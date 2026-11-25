#!/usr/bin/env bash
# Validate an argocd-apps checkout: schemas, platform policy for every add-on and app, and a helm render of
# every add-on with each of its values files. Usage: validate.sh <repo-dir> [--offline]
# --offline skips the helm render (it downloads charts). Exit 0 PASS, 1 FAIL, 64 usage.
set -euo pipefail
dir=${1:?usage: validate.sh <repo-dir> [--offline]}
offline=false; [[ ${2:-} == --offline ]] && offline=true
cd "$dir"
shopt -s nullglob
fail=0
deny() { echo "  DENY $*"; fail=1; }
has() { V=$3 yq -e ".spec.$2[] | select($4 == strenv(V))" "$1" >/dev/null 2>&1; }

addons=(addons/*.yaml) apps=(apps/*.yaml)
echo "== schemas"
catalog='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
kubeconform -strict -summary -schema-location "$catalog" bootstrap/*.yaml "${addons[@]}" "${apps[@]}" || fail=1

echo "== root app"
inc=$(yq '.spec.source.directory.include' bootstrap/root.yaml)
[[ $inc == *bootstrap/project.yaml* || $inc == *bootstrap/\*project.yaml* ]] || deny "bootstrap/root.yaml: include must cover bootstrap/project.yaml"
if [[ ${#apps[@]} -gt 0 ]]; then
  [[ $inc == *apps/* ]] || deny "bootstrap/root.yaml: include does not cover apps/, so apps/*.yaml would never sync"
  [[ $inc == *bootstrap/\*project.yaml* || $inc == *apps-project.yaml* ]] || deny "bootstrap/root.yaml: include does not cover bootstrap/apps-project.yaml"
fi

# common FILE PROJECT: rules every ApplicationSet here follows.
common() {
  [[ $(yq '.kind' "$1") == ApplicationSet ]] || deny "$1: not an ApplicationSet"
  [[ $(yq '.spec.template.spec.project' "$1") == "$2" ]] || deny "$1: project must be $2"
  [[ $(yq '.spec.goTemplateOptions[0]' "$1") == missingkey=error ]] || deny "$1: goTemplateOptions must be missingkey=error"
  [[ $(yq '.spec.template.spec.syncPolicy.automated.prune' "$1") == true && $(yq '.spec.template.spec.syncPolicy.automated.selfHeal' "$1") == true ]] \
    || deny "$1: syncPolicy.automated must set prune and selfHeal (git is the source of truth)"
  [[ $(yq '.spec.template.metadata.name' "$1") == *'{{.name}}'* ]] || deny "$1: application name must include {{.name}} (one app per cluster)"
}

echo "== add-ons"
proj=bootstrap/project.yaml
for f in "${addons[@]}"; do
  n=$(basename "$f" .yaml) src='.spec.template.spec.sources[0]'
  common "$f" platform-addons
  [[ $(yq '.metadata.name' "$f") == "addon-$n" ]] || deny "$f: metadata.name must be addon-$n"
  [[ $(yq ".spec.generators[0].clusters.selector.matchLabels[\"addon/$n\"]" "$f") == "true" ]] || deny "$f: must select clusters by label addon/$n: \"true\""
  ver=$(yq "$src.targetRevision" "$f")
  [[ $ver =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || deny "$f: chart version '$ver' is not an exact x.y.z pin"
  repo=$(yq "$src.repoURL" "$f"); has "$proj" sourceRepos "$repo" . || deny "$f: $repo not in $proj sourceRepos"
  ns=$(yq '.spec.template.spec.destination.namespace' "$f"); has "$proj" destinations "$ns" .namespace || deny "$f: namespace $ns not in $proj destinations"
  [[ -f addons/values/$n/default.yaml ]] || deny "$f: addons/values/$n/default.yaml missing"
  echo "  $n: $(yq "$src.chart" "$f") $ver -> $ns"
done
for d in addons/values/*/; do n=$(basename "$d"); [[ -f addons/$n.yaml ]] || deny "addons/values/$n has no addons/$n.yaml"; done

echo "== apps"
proj=bootstrap/apps-project.yaml
for f in "${apps[@]}"; do
  n=$(basename "$f" .yaml)
  [[ -f $proj ]] || { deny "$f: $proj missing"; continue; }
  [[ $(yq '.metadata.name' "$f") == "app-$n" ]] || deny "$f: metadata.name must be app-$n"
  k=$(yq '.kind' "$f")
  if [[ $k == ApplicationSet ]]; then
    spec='.spec.template.spec'
    common "$f" platform-apps
    [[ $(yq '.spec.generators[0].clusters.selector.matchExpressions[0].key' "$f") == env ]] || deny "$f: must select clusters by their env label"
    [[ $(yq "$spec.source.path" "$f") == *'/overlays/{{index .metadata.labels "env"}}' ]] || deny "$f: path must end in /overlays/{{index .metadata.labels \"env\"}}"
  elif [[ $k == Application ]]; then
    spec='.spec'
    [[ $(yq '.spec.project' "$f") == platform-apps ]] || deny "$f: project must be platform-apps"
    [[ $(yq '.spec.syncPolicy.automated.prune' "$f") == true && $(yq '.spec.syncPolicy.automated.selfHeal' "$f") == true ]] \
      || deny "$f: syncPolicy.automated must set prune and selfHeal (git is the source of truth)"
    srv=$(yq '.spec.destination.server // .spec.destination.name // ""' "$f")
    [[ -n $srv && $srv != *'{{'* ]] || deny "$f: destination must name one cluster (server or name)"
  else
    deny "$f: kind must be Application or ApplicationSet, not $k"; continue
  fi
  src="$spec.source"
  [[ $(yq "$spec.syncPolicy.syncOptions[] | select(. == \"CreateNamespace=true\")" "$f") ]] || deny "$f: syncOptions must include CreateNamespace=true"
  rev=$(yq "$src.targetRevision" "$f") chart=$(yq "$src.chart // \"\"" "$f")
  if [[ -n $chart ]]; then
    [[ $rev =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || deny "$f: chart version '$rev' is not an exact x.y.z pin"
  else
    [[ -n $rev && $rev != null && $rev != HEAD ]] || deny "$f: targetRevision must name a branch, tag or commit, not HEAD"
  fi
  repo=$(yq "$src.repoURL" "$f"); has "$proj" sourceRepos "$repo" . || deny "$f: $repo not in $proj sourceRepos"
  ns=$(yq "$spec.destination.namespace" "$f")
  case $ns in kube-system|kube-public|argocd|default) deny "$f: workloads may not deploy into $ns";; esac
  has "$proj" destinations "$ns" .namespace || deny "$f: namespace $ns not in $proj destinations"
  echo "  $n ($k): $repo ${chart:-$(yq "$src.path" "$f")}@$rev -> $ns"
done
if [[ -f $proj ]]; then
  [[ $(yq '.spec.clusterResourceWhitelist | map(select(.kind != "Namespace")) | length' "$proj") == 0 ]] \
    || deny "$proj: workload apps may create only Namespace at cluster scope"
fi

if ! $offline && [[ ${#addons[@]} -gt 0 ]]; then
  echo "== helm render"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  for f in "${addons[@]}"; do
    n=$(basename "$f" .yaml) src='.spec.template.spec.sources[0]'
    repo=$(yq "$src.repoURL" "$f") chart=$(yq "$src.chart" "$f") ver=$(yq "$src.targetRevision" "$f")
    for vf in addons/values/"$n"/*.yaml; do
      args=(-f "addons/values/$n/default.yaml"); [[ $vf == */default.yaml ]] || args+=(-f "$vf")
      if [[ $repo == oci://* ]]; then ref=("$repo/$chart"); else ref=("$chart" --repo "$repo"); fi
      if helm template "$n" "${ref[@]}" --version "$ver" "${args[@]}" > "$tmp/out.yaml" 2> "$tmp/err"; then
        echo "  $n with $(basename "$vf"): $(command grep -c '^kind:' "$tmp/out.yaml") objects"
      else
        deny "$n with $(basename "$vf"): helm template failed: $(head -2 "$tmp/err")"
      fi
    done
  done
fi

if [[ $fail -ne 0 ]]; then echo FAIL; exit 1; fi
echo PASS
