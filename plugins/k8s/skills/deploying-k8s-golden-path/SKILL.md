---
name: deploying-k8s-golden-path
description: Generate Kubernetes manifests for a service on the platform golden path (Kustomize base plus dev/prod overlays with probes, resource limits, non-root security context, HPA and PDB), validate them with kubeconform and the platform policy checks, and open a PR. Use when someone asks to deploy, onboard or containerize a service onto Kubernetes.
license: MIT
---

# Deploying a service on the Kubernetes golden path

## 1. Collect inputs
| Input | Rule | Default |
|---|---|---|
| `name` | DNS-1123 label | required |
| `image` | must include a tag or digest, never `:latest` | required |
| `port` | container port | 8080 |
| `team` | owning team, becomes a label | required |
| `dest` | output dir in the target repo | `apps/<name>` |

Health endpoints are assumed at `/healthz` (liveness) and `/readyz` (readiness). Ask if the service differs,
then edit the generated base. Read `references/golden-path.md` for what each default protects against.

## 2. Render
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh --name <name> --image <image> --team <team> [--port 8080] [--dest apps/<name>]
```

## 3. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh <dest>
```
It builds every overlay with kustomize, checks the output with `kubeconform -strict`, then applies the
platform policies (no `:latest`, requests and limits set, non-root, probes present). Fix and re-run until `PASS`.

## 4. Open the PR
Branch `feat/deploy-<name>`, commit `feat(<name>): add golden-path manifests`. In the PR body, list the
overlays and paste the validation summary. Do not apply to a cluster; GitOps (Argo CD) syncs after merge.
