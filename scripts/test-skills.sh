#!/usr/bin/env bash
# End-to-end test of every skill: render a sample, validate it (must PASS), then break it (must FAIL).
set -euo pipefail
cd "$(dirname "$0")/.."
root=$PWD tmp=$(mktemp -d) failures=0
trap 'rm -rf "$tmp"' EXIT
ok()   { echo "ok   $*"; }
bad()  { echo "FAIL $*"; failures=$((failures+1)); }
expect_pass() { local label=$1; shift; if "$@" >"$tmp/log" 2>&1; then ok "$label"; else bad "$label"; tail -20 "$tmp/log"; fi; }
expect_fail() { local label=$1; shift; if "$@" >"$tmp/log" 2>&1; then bad "$label (should have failed)"; else ok "$label"; fi; }
# expect_deny LABEL REASON CMD...: must fail, and the output must contain REASON (fails for the right reason).
expect_deny() {
  local label=$1 reason=$2; shift 2
  if "$@" >"$tmp/log" 2>&1; then bad "$label (should have failed)"
  elif command grep -qF -- "$reason" "$tmp/log"; then ok "$label"
  else bad "$label (failed, but not with: $reason)"; tail -5 "$tmp/log"; fi
}

iac=$root/plugins/iac/skills/scaffolding-tofu-module/scripts
"$iac/render.sh" demo-bucket "$tmp/modules/demo-bucket" "Demo." >/dev/null
expect_pass "iac: rendered module validates" "$iac/validate.sh" "$tmp/modules/demo-bucket"
sed -i 's/managed-by = "opentofu"/managed-by = "someone"/' "$tmp/modules/demo-bucket/main.tf"
expect_fail "iac: broken label contract is caught by tofu test" "$iac/validate.sh" "$tmp/modules/demo-bucket"
expect_fail "iac: render refuses to overwrite" "$iac/render.sh" demo-bucket "$tmp/modules/demo-bucket"

k8s=$root/plugins/k8s/skills/deploying-k8s-golden-path/scripts
"$k8s/render.sh" --name hello-api --image ghcr.io/example/hello-api:1.2.3 --team payments --dest "$tmp/apps/hello-api" >/dev/null
expect_pass "k8s: rendered app validates" "$k8s/validate.sh" "$tmp/apps/hello-api"
expect_fail "k8s: render rejects :latest" "$k8s/render.sh" --name x --image foo:latest --team t --dest "$tmp/apps/x"
sed -i 's/hello-api:1.2.3/hello-api:latest/; /runAsNonRoot/d' "$tmp/apps/hello-api/base/deployment.yaml"
expect_deny "k8s: policy denies :latest and root" "runAsNonRoot not set" "$k8s/validate.sh" "$tmp/apps/hello-api"

obs=$root/plugins/observability/skills/adding-prometheus-alert/scripts
for slo in 95 99.9 99.99; do
  "$obs/render.sh" --service "svc-${slo//./-}" --team core --slo "$slo" --dest "$tmp/mon-$slo" >/dev/null
  expect_pass "observability: slo $slo rules + tests pass" "$obs/validate.sh" "$tmp/mon-$slo"
done
sed -i 's/(14.4 \* /(1000 * /' "$tmp/mon-99.9/rules/"*.yaml
expect_fail "observability: unreachable threshold is caught by the firing test" "$obs/validate.sh" "$tmp/mon-99.9"
expect_deny "observability: slo below 95 rejected" "slo must be between 95" "$obs/render.sh" --service x --team y --slo 90 --dest "$tmp/m90"

cr=$root/plugins/cloud-requests/skills/requesting-k8s-cluster/scripts
req() { "$cr/render.sh" --dest "$tmp/requests" "$@"; }
f=$(req --provider gke --name payments-dev --team payments --env dev --ttl 72h --cost-center cc-1234 --budget 300)
expect_pass "cloud: gke dev autopilot request plans" "$cr/check.sh" "$f"
f=$(req --provider eks --name search-prod --team search --env prod --size L --mode managed --cost-center cc-4321 --budget 1500 --addons cert-manager,keda)
expect_pass "cloud: eks prod managed L request plans" "$cr/check.sh" "$f"
f=$(req --provider gke --name big-dev --team core --env dev --size L --ttl 24h --cost-center cc-0001 --budget 5000)
expect_deny "cloud: dev size L denied" "dev clusters are capped at size M" "$cr/check.sh" "$f"
f=$(req --provider eks --name ttl-prod --team core --env prod --ttl 24h --cost-center cc-0001 --budget 5000)
expect_deny "cloud: prod with ttl denied" "prod clusters must not have a ttl" "$cr/check.sh" "$f"
f=$(req --provider eks --name cheap-dev --team core --env dev --ttl 24h --cost-center cc-0001 --budget 50)
expect_deny "cloud: over budget denied" "exceeds budgetMonthlyUSD" "$cr/check.sh" "$f"
f=$(req --provider gke --name far-dev --team core --env dev --ttl 24h --region asia-east1 --cost-center cc-0001 --budget 500)
expect_deny "cloud: unoffered region denied" "is not offered for gke" "$cr/check.sh" "$f"
f=$(req --provider gke --name public-dev --team core --env dev --ttl 24h --cost-center cc-0001 --budget 500)
echo "  publicEndpoint: true" >> "$f"
expect_deny "cloud: overriding a hidden default denied" "spec.publicEndpoint is not requestable" "$cr/check.sh" "$f"

f=$(req --provider eks --name nocm-prod --team core --env prod --cost-center cc-0001 --budget 5000 --addons keda)
expect_deny "cloud: prod without cert-manager denied" "must include cert-manager for prod" "$cr/check.sh" "$f"
f=$(req --provider gke --name mesh-dev --team core --env dev --ttl 24h --cost-center cc-0001 --budget 500 --addons istio)
expect_deny "cloud: unknown add-on denied" "istio is not in the add-on catalog" "$cr/check.sh" "$f"
f=$(req --provider gke --name ms-dev --team core --env dev --ttl 24h --cost-center cc-0001 --budget 500 --addons metrics-server)
expect_deny "cloud: add-on not offered on provider denied" "metrics-server is not offered on gke" "$cr/check.sh" "$f"

ci=$root/plugins/delivery/skills/onboarding-repo-ci/scripts
mkdir -p "$tmp/svc"
cp -r "$tmp/apps" "$tmp/svc/apps"
cp -r "$tmp/mon-95" "$tmp/svc/monitoring"
sha=0123456789abcdef0123456789abcdef01234567
expect_pass "ci: onboarding renders a caller workflow" "$ci/render.sh" "$tmp/svc" --ref "$sha"
expect_pass "ci: rendered workflow passes actionlint + pinning" "$ci/validate.sh" "$tmp/svc"
expect_deny "ci: render refuses a branch ref" "full 40-char commit sha" "$ci/render.sh" "$tmp/svc" --ref main
sed -i "s/@$sha/@main/" "$tmp/svc/.github/workflows/platform.yml"
expect_deny "ci: mutable ref denied" "is not pinned to a full commit sha" "$ci/validate.sh" "$tmp/svc"

img=$root/plugins/images/skills/building-golden-image/scripts
digest=sha256:8aa5a7bf5a1955bddbe7d74fcdd0b91ab30e74362a8b73af672b0481b35b44a0
"$img/render.sh" --name py-base --owner platform --base "debian@$digest" --packages "ca-certificates python3" --dest "$tmp/images" >/dev/null
expect_pass "images: golden image policy + packer validate" "$img/validate.sh" "$tmp/images/py-base"
"$img/render.sh" --name tag-base --owner platform --base debian:trixie-slim --dest "$tmp/images" >/dev/null
expect_deny "images: tag instead of digest denied" "must be pinned by digest" "$img/validate.sh" "$tmp/images/tag-base"
"$img/render.sh" --name alpine-base --owner platform --base "alpine@$digest" --dest "$tmp/images" >/dev/null
expect_deny "images: unapproved base denied" "is not in approved-bases.txt" "$img/validate.sh" "$tmp/images/alpine-base"
sed -i 's/^  supportedUntil: .*/  supportedUntil: "2099-01-01"/' "$tmp/images/py-base/image.yaml"
expect_deny "images: support date beyond 18 months denied" "must be within 18 months" "$img/validate.sh" "$tmp/images/py-base"

gop=$root/plugins/gitops/skills/creating-argocd-app/scripts
cp -r "$root/fixtures/argocd-apps" "$tmp/argo"
"$gop/render.sh" addon --repo-dir "$tmp/argo" --name metrics-server --chart metrics-server \
  --chart-repo https://kubernetes-sigs.github.io/metrics-server --version 3.14.0 --namespace kube-system >/dev/null
"$gop/render.sh" appset --repo-dir "$tmp/argo" --name hello-api --git-repo https://github.com/example/hello-api.git \
  --path apps/hello-api --envs dev,prod >/dev/null 2>&1
"$gop/render.sh" application --repo-dir "$tmp/argo" --name hello-web --git-repo https://github.com/example/hello-web.git \
  --path deploy/overlays/homelab >/dev/null
"$gop/render.sh" application --repo-dir "$tmp/argo" --name podinfo --chart podinfo \
  --chart-repo https://stefanprodan.github.io/podinfo --version 6.9.2 >/dev/null
expect_pass "gitops: addon, ApplicationSet and Application validate" "$gop/validate.sh" "$tmp/argo" --offline
expect_fail "gitops: render refuses to overwrite" "$gop/render.sh" application --repo-dir "$tmp/argo" --name podinfo \
  --chart podinfo --chart-repo https://stefanprodan.github.io/podinfo --version 6.9.2
expect_deny "gitops: render refuses a chart range" "exact x.y.z" "$gop/render.sh" addon --repo-dir "$tmp/argo" --name keda \
  --chart keda --chart-repo https://kedacore.github.io/charts --version '2.x'
expect_deny "gitops: render refuses a workload in kube-system" "may not deploy into kube-system" "$gop/render.sh" application \
  --repo-dir "$tmp/argo" --name bad --git-repo https://github.com/example/bad.git --path deploy --namespace kube-system
cp -r "$tmp/argo" "$tmp/argo-range"; sed -i 's/targetRevision: 3.14.0/targetRevision: 3.x/' "$tmp/argo-range/addons/metrics-server.yaml"
expect_deny "gitops: chart version range is denied" "not an exact x.y.z pin" "$gop/validate.sh" "$tmp/argo-range" --offline
cp -r "$tmp/argo" "$tmp/argo-head"; sed -i 's/targetRevision: main/targetRevision: HEAD/' "$tmp/argo-head/apps/hello-api.yaml"
expect_deny "gitops: ApplicationSet on HEAD is denied" "not HEAD" "$gop/validate.sh" "$tmp/argo-head" --offline
cp -r "$tmp/argo" "$tmp/argo-repo"; sed -i 's#example/hello-web.git#evil/hello-web.git#' "$tmp/argo-repo/apps/hello-web.yaml"
expect_deny "gitops: Application from an unlisted repo is denied" "not in bootstrap/apps-project.yaml sourceRepos" "$gop/validate.sh" "$tmp/argo-repo" --offline
cp -r "$tmp/argo" "$tmp/argo-root"; yq -i '.spec.source.directory.include = "{bootstrap/project.yaml,addons/*.yaml}"' "$tmp/argo-root/bootstrap/root.yaml"
expect_deny "gitops: root app that skips apps/ is denied" "does not cover apps/" "$gop/validate.sh" "$tmp/argo-root" --offline

ans=$root/plugins/ansible/skills/writing-ansible-playbook/scripts
"$ans/render.sh" --dest "$tmp/ans" --name base-tools --hosts workstations --packages "htop jq" >/dev/null
expect_pass "ansible: rendered playbook validates" "$ans/validate.sh" "$tmp/ans" --offline
expect_fail "ansible: render refuses to overwrite" "$ans/render.sh" --dest "$tmp/ans" --name base-tools --hosts workstations
expect_deny "ansible: render refuses hosts all" "target a group" "$ans/render.sh" --dest "$tmp/ans" --name other --hosts all
cp -r "$tmp/ans" "$tmp/ans-all"; sed -i 's/hosts: workstations/hosts: all/' "$tmp/ans-all/playbooks/base-tools.yml"
expect_deny "ansible: play on all hosts is denied" "play targets 'all'" "$ans/validate.sh" "$tmp/ans-all" --offline
cp -r "$tmp/ans" "$tmp/ans-pin"; sed -i 's/version: "2.2.2"/version: ">=2.0.0"/' "$tmp/ans-pin/requirements.yml"
expect_deny "ansible: unpinned collection is denied" "must pin an exact version" "$ans/validate.sh" "$tmp/ans-pin" --offline
cp -r "$tmp/ans" "$tmp/ans-pw"; echo 'base_tools_db_password: hunter2' >> "$tmp/ans-pw/roles/base_tools/defaults/main.yml"
expect_deny "ansible: plaintext password is denied" "holds a plaintext secret" "$ans/validate.sh" "$tmp/ans-pw" --offline
cp -r "$tmp/ans" "$tmp/ans-lint"; sed -i 's/ansible.builtin.file:/file:/' "$tmp/ans-lint/roles/base_tools/tasks/main.yml"
expect_deny "ansible: non-FQCN module fails ansible-lint" "fqcn" "$ans/validate.sh" "$tmp/ans-lint" --offline

for t in "$root"/plugins/*/skills/*/tests/run.sh; do
  [[ -x $t ]] && expect_pass "$(basename "$(dirname "$(dirname "$t")")"): own test suite" "$t"
done

echo
if [[ $failures -ne 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "ALL PASS"
