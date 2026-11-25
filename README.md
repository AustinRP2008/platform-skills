# platform-skills

A practice platform team in a repo: Agent Skills that give engineers self-service for infrastructure,
Kubernetes, monitoring, CI, cluster requests and golden images, with the same checks running locally and
in GitHub Actions. Everything runs on a laptop; nothing touches a cloud account.

## The pattern
```
engineer asks the agent  ->  skill interviews (only the exposed knobs)
                         ->  render.sh writes files from a template
                         ->  validate.sh / check.sh: policy + tests (same script CI runs)
                         ->  PR  ->  reusable workflow re-runs the checks  ->  CODEOWNERS approve
```
- **Skills are thin.** `SKILL.md` says when and how; deterministic scripts do the work, so the result does
  not depend on how the model phrases things.
- **The PR is the request.** No skill applies anything. Review, CI and approval tiers stay with people.
- **Golden paths, not guard rails alone.** Defaults are opinionated; the few knobs are typed and
  validated; everything else is a hidden platform default that needs an exception to change.

## Plugins and skills
| Plugin | Skill | Self-service for |
|---|---|---|
| `iac` | `scaffolding-tofu-module` | a new OpenTofu module with tests, tflint and docs |
| `k8s` | `deploying-k8s-golden-path` | a Kustomize app (probes, limits, non-root, HPA, PDB) that passes kubeconform and policy |
| `observability` | `adding-prometheus-alert` | SLO burn-rate alerts with promtool unit tests and a runbook |
| `cloud-requests` | `requesting-k8s-cluster` | a GKE or EKS cluster: policy, cost estimate, approval tier, mock-provider plan |
| `delivery` | `onboarding-repo-ci` | one caller workflow running the platform's reusable workflows pinned by SHA |
| `images` | `building-golden-image` | a hardened container base built with Packer, smoke-tested, promoted by channel |
| `github` | `creating-github-repo` | a new repo with branch ruleset, secret/code scanning, Dependabot and pinned Actions from the first commit (free tier only), plus `audit.sh` for drift on existing repos |
| `gitops` | `creating-argocd-app` | an Argo CD Application or ApplicationSet (label-selected add-on or env-selected workload) with AppProject allow-lists, kubeconform, policy and a helm render |
| `ansible` | `writing-ansible-playbook` | a playbook and role with pinned collections and no plaintext secrets that passes syntax check and ansible-lint production profile |

## Install
In Claude Code:
```
/plugin marketplace add AustinRP2008/platform-skills
/plugin install cloud-requests@platform-skills
```
Other agents that read the Agent Skills format can use the `plugins/*/skills/*` folders directly.

## Run the checks
```bash
mise install                 # pinned tools: opentofu, tflint, kubeconform, kustomize, promtool, packer, ...
scripts/lint-skills.sh       # SKILL.md spec: name, description with "Use when", size, executable scripts
scripts/test-skills.sh       # every skill end to end, each with red controls that must fail for the right reason
```
The cluster-request skill plans against [tofu-modules](https://github.com/AustinRP2008/tofu-modules);
set `PLATFORM_MODULES_SOURCE=<path>/modules` to use a local checkout.

## Reusable workflows
`.github/workflows/reusable-{tofu-module,k8s-app,prometheus-rules,golden-image}.yml`. Callers pin
them by commit SHA; the `onboarding-repo-ci` skill writes the caller for you.

## Local only
Cloud resources are modelled, not created: OpenTofu runs `tofu test` with mock providers, prices are an
illustrative table, and project IDs and subnets are placeholders. The cluster-request flow shows what
asking for a GKE or EKS cluster feels like for an engineer without a cloud bill.
