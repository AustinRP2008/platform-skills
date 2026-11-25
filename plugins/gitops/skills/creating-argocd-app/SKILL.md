---
name: creating-argocd-app
description: Add an Argo CD Application (one source to one cluster) or ApplicationSet (a cluster add-on from a pinned Helm chart on every cluster labelled addon/<name>, or a team workload deployed to clusters by env label) to the argocd-apps repo, update the AppProject allow-lists, validate with kubeconform, platform policy and a helm render, and open a PR. Use when someone asks to deploy something with Argo CD, create an Argo CD Application or ApplicationSet, add an add-on or operator to the clusters, or onboard a service to GitOps.
license: MIT
---

# Creating an Argo CD Application or ApplicationSet

Everything Argo CD runs comes from the argocd-apps repo; the hub's root app syncs it. Read
`references/argocd-apps-layout.md` for the layout and why each rule exists.

## 1. Pick the kind
| Kind | Renders | Use for | Lands in | Targets |
|---|---|---|---|---|
| `addon` | ApplicationSet | shared platform software from a Helm chart (cert-manager, keda, an operator) | `addons/<name>.yaml` + `addons/values/<name>/` | clusters labelled `addon/<name>: "true"` |
| `appset` | ApplicationSet | a team service with golden-path overlays (`deploying-k8s-golden-path`) on many clusters | `apps/<name>.yaml` | clusters whose `env` label is in `--envs` |
| `application` | Application | one thing on one cluster: a git path or a Helm chart | `apps/<name>.yaml` | `--cluster-server` (default the hub itself) |

Prefer an ApplicationSet whenever the same thing should run on more than one cluster: adding a cluster then
means labelling it, not copying an Application.

## 2. Collect inputs
| Input | Rule |
|---|---|
| `name` | DNS-1123 label, at most 42 chars |
| `namespace` | defaults to `name`; workloads may not use kube-system, kube-public, argocd or default |
| chart source: `chart`, `chart-repo`, `version` | `https://` or `oci://` repo; version is an exact `x.y.z` (look it up, never a range) |
| git source: `git-repo`, `path`, `revision` | `revision` defaults to `main`, never `HEAD`; for `appset`, `path` holds `overlays/<env>` per env |
| `cluster-server` | `application` only; an `https://` API server registered in Argo CD |

## 3. Render into an argocd-apps checkout
```bash
S=${CLAUDE_SKILL_DIR}/scripts
$S/render.sh addon --repo-dir <argocd-apps> --name <n> --chart <chart> --chart-repo <url> --version <x.y.z> [--namespace <ns>]
$S/render.sh appset --repo-dir <argocd-apps> --name <n> --git-repo <url> --path apps/<n> --envs dev,prod [--revision main]
$S/render.sh application --repo-dir <argocd-apps> --name <n> --git-repo <url> --path <dir> [--revision main] [--cluster-server <url>]
$S/render.sh application --repo-dir <argocd-apps> --name <n> --chart <chart> --chart-repo <url> --version <x.y.z>
```
It prints each file it wrote or changed and adds the source repo and namespace to the AppProject. For an add-on,
put chart values in `addons/values/<n>/default.yaml` and per-env overrides in `<env>.yaml` beside it; for a chart
Application, add `helm.valuesObject` under `source`. The first workload creates `bootstrap/apps-project.yaml`
and, if needed, widens the root app's include to `apps/`; then re-apply each hub's root app once
(homelab: `kubectl apply -f argocd/root-app.yaml`).

## 4. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <argocd-apps> [--offline]
```
Fix every `DENY` line and re-run until `PASS`. `--offline` skips the helm render; use it only when there is no network.

## 5. Open the PR
Branch `feat/<kind>-<name>`, commit `feat(<kind>): <name>`. In the PR body, name the chart or repo, version or
revision, namespace and which clusters will receive it. Do not `kubectl apply` it: the root app syncs after merge.

## 6. After merge
- add-on: add `<name>` to a cluster's `addons` (homelab: `cluster.yaml`, then `scripts/bootstrap.sh --apply`;
  cloud clusters: the request's `addons`, which must be in the platform-skills catalog `assets/addons.json`).
- appset: the target clusters need the `env` label on their Argo CD cluster entry.
- private git repo: Argo CD needs a read-only deploy key for it (homelab bootstrap shows the pattern).
- Confirm with `kubectl -n argocd get applications`: the new app should reach Synced/Healthy.
