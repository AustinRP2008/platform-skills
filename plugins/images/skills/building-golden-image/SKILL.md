---
name: building-golden-image
description: Create, validate, build and promote a hardened golden container image with Packer. Writes an image manifest (pinned base digest, owner, channel, packages, support date), checks it against the image policy, builds it locally with the Packer docker builder, and smoke-tests that it runs as non-root. Use when someone asks for a base image, a golden image, a hardened image, an approved container base, or to promote an image from dev to staging or prod.
license: MIT
---

# Golden images

A golden image is a product: it has an owner, a version, a support date and a promotion path. Teams build
`FROM` it instead of from a random upstream tag. Read `references/image-lifecycle.md` when the user asks
why, or about promotion and deprecation.

## 1. Create the image definition
```bash
${CLAUDE_SKILL_DIR}/scripts/render.sh --name python-base --owner platform \
  --base debian@sha256:<64 hex> [--packages "ca-certificates python3"] [--dest images]
```
Writes `images/<name>/image.yaml` (the only file a team edits) and a generic `image.pkr.hcl` plus
`files/harden.sh`. The base must come from `assets/approved-bases.txt` and be pinned by digest; resolve one
with `docker buildx imagetools inspect <repo>:<tag> --format '{{json .Manifest.Digest}}'`.

## 2. Validate (the same script CI runs)
```bash
${CLAUDE_SKILL_DIR}/scripts/validate.sh images/<name>
```
Policy (approved base, digest pin, channel, owner, support date within 18 months), then `packer init`,
`packer fmt -check` and `packer validate`.

## 3. Build and smoke-test locally (needs docker)
```bash
${CLAUDE_SKILL_DIR}/scripts/build.sh images/<name>
```
Builds `local/golden/<name>:<channel>`, then checks the image runs, runs as a non-root UID, and has no
package-manager cache left. In CI the next gates are scan (fail on fixable critical CVEs), SBOM and
signature; they are described in the reference, not run here.

## 4. Promote
Promotion is a PR that changes `spec.channel` (`dev` -> `staging` -> `prod`) and nothing else. Never
skip a channel, and never change the base digest in the same PR as a promotion.
