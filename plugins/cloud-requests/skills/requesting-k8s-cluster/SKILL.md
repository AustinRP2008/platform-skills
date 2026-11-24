---
name: requesting-k8s-cluster
description: Request a managed Kubernetes cluster (GKE or EKS) through the platform. Writes a ClusterRequest file with opinionated defaults, checks it against platform policy, estimates monthly cost, decides the approval tier, runs a plan of the real OpenTofu module with mock providers, and opens a PR for review. Use when someone asks for a new cluster, a GKE cluster, an EKS cluster, or Kubernetes capacity for a team.
license: MIT
---

# Requesting a Kubernetes cluster

You are the front door, not the gate. Never apply anything and never ask for cloud access: the PR
is the request, CI re-runs the same checks, and CODEOWNERS approval decides.

## 1. Interview (only these fields are exposed)
| Field | Allowed | Default / rule |
|---|---|---|
| `provider` | `gke`, `eks` | ask |
| `name` | 4-40 chars, kebab-case | `<team>-<env>` |
| `team` | kebab-case | ask |
| `env` | `dev`, `staging`, `prod` | ask |
| `region` | see `assets/environments.json` | first listed for the provider |
| `size` | `S`, `M`, `L` | `S` (explain the table in `references/request-model.md` if asked) |
| `mode` | gke: `autopilot`/`standard`; eks: `auto`/`managed` | `autopilot` / `auto` |
| `ttl` | `1h`-`168h` | required for dev/staging, forbidden for prod |
| `costCenter` | `cc-` + 4 digits | ask |
| `budgetMonthlyUSD` | number | must cover the estimate |

Everything else (private nodes, workload identity, KMS, audit logs, network, project/account) is a hidden
platform default. If the user asks to change one, explain it needs a platform-team exception and stop.

## 2. Render
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh --provider gke --name payments-dev --team payments --env dev \
  --size S --ttl 72h --cost-center cc-1234 --budget 300 [--region us-central1] [--mode autopilot] [--dest requests/clusters]
```

## 3. Check (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/check.sh requests/clusters/<name>.yaml
```
It prints a PR-ready summary: policy result, cost estimate, approval tier and the `tofu test` plan result.
Fix policy denials by changing the request (smaller size, shorter TTL, higher budget), never by editing
the policy. The plan uses mock providers, so it proves the module accepts the request, not that the cloud will.

## 4. Open the PR
Branch `request/cluster-<name>`, commit `request(cluster): <name> (<provider>, <env>, <size>)`, PR body =
the summary from step 3. Label it with the approval tier (`approval:auto`, `approval:platform`,
`approval:platform-2`) so CODEOWNERS and the merge rules apply.
