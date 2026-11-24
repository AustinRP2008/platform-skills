# Golden image lifecycle

```
image.yaml PR -> policy -> packer build -> smoke test -> scan -> SBOM -> sign -> push :dev
              -> promotion PR (channel: staging) -> re-scan -> retag
              -> promotion PR (channel: prod)    -> re-scan -> retag
```

## Gates
| Gate | Here (local) | In a real pipeline |
|---|---|---|
| Policy | `validate.sh` | same script in CI |
| Build | `build.sh`, Packer docker builder | Packer on CI runners; VM images use the amazon-ebs / googlecompute builders with the same HCL shape |
| Smoke test | `build.sh`: runs, non-root, no apt cache | plus a container-structure-test file |
| Vulnerability scan | not run | Trivy or Grype; fail on fixable CRITICAL, waivers carry an expiry |
| SBOM | not run | Syft, SPDX or CycloneDX, attached as an attestation |
| Signature | not run | cosign keyless (OIDC from CI), verified by an admission policy in clusters |

Pin every CI action by SHA. In March 2026 the release tags of a popular scanner action were repointed to
malicious commits (CVE-2026-33634); workflows pinned by tag ran it, workflows pinned by SHA did not.

## Channels
`dev` is rebuilt on every merge. `staging` and `prod` move only by promotion PR, so prod always runs a
digest that was already exercised in staging. Consumers reference `:prod` in base layers, or better the
digest that Renovate bumps for them.

## Deprecation
`spec.supportedUntil` is at most 18 months ahead. Thirty days before it, a scheduled job opens issues in
repos still building `FROM` the image; after it, the image policy in clusters warns, then denies.

## Why Packer and not a Dockerfile
For containers alone a Dockerfile is fine. The point of practising with Packer is that the same build
definition and provisioners also produce AMIs and GCE images, which is where golden images matter most
for VM fleets and node pools.
