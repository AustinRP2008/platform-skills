#!/usr/bin/env bash
# Add an Argo CD Application or ApplicationSet to an argocd-apps checkout.
#   render.sh addon       --repo-dir DIR --name N --chart C --chart-repo URL --version X.Y.Z [--namespace NS]
#   render.sh appset      --repo-dir DIR --name N --git-repo URL --path P --envs e1,e2 [--revision main] [--namespace NS]
#   render.sh application --repo-dir DIR --name N (--git-repo URL --path P [--revision main] | --chart C --chart-repo URL --version X.Y.Z)
#                         [--cluster-server URL] [--namespace NS]
# addon:       ApplicationSet addons/<n>.yaml + addons/values/<n>/default.yaml, on clusters labelled addon/<n>: "true".
# appset:      ApplicationSet apps/<n>.yaml, deploying <path>/overlays/<env> to every cluster whose env label is in --envs.
# application: Application apps/<n>.yaml, one source to one cluster (default: the hub, https://kubernetes.default.svc).
# The source repo and namespace are added to the matching AppProject. Prints the files written.
# Exit 0 ok, 64 usage, 65 refuses to overwrite.
set -euo pipefail
usage() { echo "usage: render.sh addon|appset|application --repo-dir DIR --name N ... (see header)" >&2; exit 64; }
kind=${1:-}; [[ $kind == addon || $kind == appset || $kind == application ]] || usage; shift
ns="" revision=main server=https://kubernetes.default.svc
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 ]] || usage
  case $1 in
    --repo-dir) dir=$2;; --name) name=$2;; --namespace) ns=$2;;
    --chart) chart=$2;; --chart-repo) chart_repo=$2;; --version) version=$2;;
    --git-repo) git_repo=$2;; --path) path=$2;; --envs) envs=$2;; --revision) revision=$2;;
    --cluster-server) server=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${dir:?--repo-dir required}" "${name:?--name required}"
die() { echo "$*" >&2; exit 64; }
[[ $name =~ ^[a-z]([-a-z0-9]{0,40}[a-z0-9])?$ ]] || die "name must be a DNS-1123 label of at most 42 chars"
ns=${ns:-$name}
[[ $ns =~ ^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || die "namespace must be a DNS-1123 label"
root=$dir/bootstrap/root.yaml
[[ -f $root && -f $dir/bootstrap/project.yaml ]] || die "$dir does not look like argocd-apps (bootstrap/root.yaml, bootstrap/project.yaml)"
self=$(yq '.spec.source.repoURL' "$root")

# allow PROJECT_FILE REPO NAMESPACE: add the repo and namespace to the AppProject if missing.
allow() {
  R=$2 yq -e '.spec.sourceRepos[] | select(. == strenv(R))' "$1" >/dev/null 2>&1 \
    || R=$2 yq -i '.spec.sourceRepos += [strenv(R)]' "$1"
  N=$3 yq -e '.spec.destinations[] | select(.namespace == strenv(N))' "$1" >/dev/null 2>&1 \
    || N=$3 yq -i '.spec.destinations += [{"server": "*", "namespace": strenv(N)}] | .spec.destinations[-1] style="flow"' "$1"
}
check_chart() {
  : "${chart:?--chart required}" "${chart_repo:?--chart-repo required}" "${version:?--version required}"
  [[ $version =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be an exact x.y.z chart version, not '$version'"
  [[ $chart_repo == https://* || $chart_repo == oci://* ]] || die "chart-repo must be https:// or oci://"
}

if [[ $kind == addon ]]; then
  check_chart
  f=$dir/addons/$name.yaml vals=$dir/addons/values/$name
  [[ -e $f || -e $vals ]] && { echo "refusing: $f or $vals already exists" >&2; exit 65; }
  mkdir -p "$vals"
  cat > "$f" <<YAML
# Installs $chart $version on every cluster labelled addon/$name: "true".
# Values: addons/values/$name/default.yaml, then <env>.yaml for the cluster's env label (optional).
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: addon-$name
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters:
        selector:
          matchLabels:
            addon/$name: "true"
  template:
    metadata:
      name: '$name-{{.name}}'
    spec:
      project: platform-addons
      sources:
        - repoURL: $chart_repo
          chart: $chart
          targetRevision: $version
          helm:
            releaseName: $name
            ignoreMissingValueFiles: true
            valueFiles:
              - \$values/addons/values/$name/default.yaml
              - '\$values/addons/values/$name/{{index .metadata.labels "env"}}.yaml'
        - repoURL: $self
          targetRevision: main
          ref: values
      destination:
        server: '{{.server}}'
        namespace: $ns
      syncPolicy:
        automated: { prune: true, selfHeal: true }
        syncOptions: [CreateNamespace=true, ServerSideApply=true]
YAML
  printf '# %s %s values for every cluster. Per-env overrides go in <env>.yaml beside this file.\n{}\n' "$chart" "$version" > "$vals/default.yaml"
  allow "$dir/bootstrap/project.yaml" "$chart_repo" "$ns"
  printf '%s\n' "$f" "$vals/default.yaml" "$dir/bootstrap/project.yaml"
  exit 0
fi

# appset and application: team workloads in apps/, under the platform-apps project.
case $ns in kube-system|kube-public|argocd|default) die "workloads may not deploy into $ns";; esac
f=$dir/apps/$name.yaml
[[ -e $f ]] && { echo "refusing: $f already exists" >&2; exit 65; }
if [[ $kind == appset ]]; then
  : "${git_repo:?--git-repo required}" "${path:?--path required}" "${envs:?--envs required}"
  [[ $envs =~ ^[a-z0-9-]+(,[a-z0-9-]+)*$ ]] || die "envs must be a comma-separated list such as dev,prod"
  src_repo=$git_repo
elif [[ -n ${chart:-} || -n ${chart_repo:-} ]]; then
  [[ -z ${git_repo:-} && -z ${path:-} ]] || die "application takes either --git-repo/--path or --chart/--chart-repo/--version, not both"
  check_chart; src_repo=$chart_repo
else
  : "${git_repo:?--git-repo or --chart required}" "${path:?--path required}"
  src_repo=$git_repo
fi
[[ -n ${path:-} ]] && path=${path%/}
[[ $revision != HEAD && -n $revision ]] || die "revision must name a branch, tag or commit, not HEAD"
[[ $server == https://* ]] || die "cluster-server must be an https:// API server URL"

proj=$dir/bootstrap/apps-project.yaml
if [[ ! -f $proj ]]; then
  cat > "$proj" <<'YAML'
# Workload apps: namespace-scoped resources only, from the repos and into the namespaces listed here.
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-apps
  namespace: argocd
  annotations:
    # Wave -1: created before the Applications and ApplicationSets that reference it.
    argocd.argoproj.io/sync-wave: "-1"
spec:
  description: Team workloads, deployed as Applications or by env label as ApplicationSets
  sourceRepos: []
  destinations: []
  # Only Namespace (for CreateNamespace=true); everything else must be namespaced.
  clusterResourceWhitelist:
    - { group: "", kind: Namespace }
YAML
fi
allow "$proj" "$src_repo" "$ns"
mkdir -p "$dir/apps"

if [[ $kind == appset ]]; then
  vals=$(tr ',' '\n' <<< "$envs" | sed 's/.*/"&"/' | paste -sd, -)
  cat > "$f" <<YAML
# Deploys $path/overlays/<env> from $git_repo to every cluster whose env label is one of: $envs.
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: app-$name
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
    - clusters:
        selector:
          matchExpressions:
            - { key: env, operator: In, values: [$vals] }
  template:
    metadata:
      name: '$name-{{.name}}'
    spec:
      project: platform-apps
      source:
        repoURL: $git_repo
        targetRevision: $revision
        path: '$path/overlays/{{index .metadata.labels "env"}}'
      destination:
        server: '{{.server}}'
        namespace: $ns
      syncPolicy:
        automated: { prune: true, selfHeal: true }
        syncOptions: [CreateNamespace=true]
YAML
else
  if [[ -n ${chart:-} ]]; then
    source="    repoURL: $chart_repo
    chart: $chart
    targetRevision: $version
    helm:
      releaseName: $name"
    what="$chart $version"
  else
    source="    repoURL: $git_repo
    targetRevision: $revision
    path: $path"
    what="$git_repo $path@$revision"
  fi
  cat > "$f" <<YAML
# Deploys $what to $server, namespace $ns.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-$name
  namespace: argocd
  finalizers:
    # Deleting this Application from git deletes what it deployed.
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-apps
  source:
$source
  destination:
    server: $server
    namespace: $ns
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
YAML
fi
printf '%s\n' "$f" "$proj"
# The root app must sync apps/ and every project; widen its include if this checkout predates apps/.
inc=$(yq '.spec.source.directory.include' "$root")
if [[ $inc != *apps/* ]]; then
  yq -i '.spec.source.directory.include = "{bootstrap/*project.yaml,addons/*.yaml,apps/*.yaml}"' "$root"
  echo "$root  (include widened to apps/: re-apply the root app on each hub, e.g. homelab argocd/root-app.yaml)" >&2
  echo "$root"
fi
