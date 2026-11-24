#!/usr/bin/env bash
# Print "kind<TAB>path" for every CI target in a repo, paths relative to the repo root, sorted.
# Usage: detect.sh <repo-dir>
set -euo pipefail
repo=${1:?usage: detect.sh <repo-dir>}
cd "$repo"
prune=(-name .git -o -name .terraform -o -name node_modules -o -name .platform)
{
  command find . \( "${prune[@]}" \) -prune -o -type f -name versions.tf -print |
    while IFS= read -r f; do d=$(dirname "$f"); case $d in */tests|*/examples/*) continue;; esac; printf 'tofu\t%s\n' "${d#./}"; done
  command find . \( "${prune[@]}" \) -prune -o -type f -path '*/base/kustomization.yaml' -print |
    while IFS= read -r f; do d=$(dirname "$(dirname "$f")"); if [[ -d $d/overlays ]]; then printf 'k8s\t%s\n' "${d#./}"; fi; done
  command find . \( "${prune[@]}" \) -prune -o -type d -name rules -print |
    while IFS= read -r r; do d=$(dirname "$r"); if [[ -d $d/tests ]]; then printf 'prometheus\t%s\n' "${d#./}"; fi; done
  command find . \( "${prune[@]}" \) -prune -o -type f -name image.pkr.hcl -print |
    while IFS= read -r f; do d=$(dirname "$f"); if [[ -f $d/image.yaml ]]; then printf 'image\t%s\n' "${d#./}"; fi; done
} | sort -u
