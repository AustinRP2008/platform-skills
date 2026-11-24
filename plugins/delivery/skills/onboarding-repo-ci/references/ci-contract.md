# CI contract

| Kind | Detected when a dir has | Reusable workflow | Runs |
|---|---|---|---|
| `tofu` | `versions.tf` | `reusable-tofu-module.yml` | fmt, validate, tflint, `tofu test` |
| `k8s` | `base/kustomization.yaml` and `overlays/` | `reusable-k8s-app.yml` | kustomize build, kubeconform, policy |
| `prometheus` | `rules/` and `tests/` | `reusable-prometheus-rules.yml` | `promtool check rules`, `promtool test rules` |
| `image` | `image.yaml` and `image.pkr.hcl` | `reusable-golden-image.yml` | image policy, `packer validate` |

Each reusable workflow checks out platform-skills at `platform-ref` and runs the same `validate.sh` the
skills run locally, so "passes on my laptop" and "passes in CI" mean the same thing.

## Why pin by SHA
A tag can be moved; a SHA cannot. In March 2026 the tags of a widely used scanner action were repointed to
malicious commits (CVE-2026-33634), and every workflow that referenced it by tag ran the payload. Pin
`uses:` to a full SHA with the version in a comment, and let a bot open the bump PRs.

## Why one caller file
Copy-pasted pipelines drift within weeks. A caller that only says *what* to check and *which platform
version* keeps the *how* in one place, and a platform fix reaches every repo as a one-line bump.
