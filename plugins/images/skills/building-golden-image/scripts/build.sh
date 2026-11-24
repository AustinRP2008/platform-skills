#!/usr/bin/env bash
# Build the image locally with the Packer docker builder, then smoke-test it.
# Usage: build.sh <image-dir>
set -euo pipefail
dir=${1:?usage: build.sh <image-dir>}
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
. "$here/scripts/lib.sh"
"$here/scripts/validate.sh" "$dir"
mapfile -t vars < <(packer_vars "$dir")
name=$(yq '.metadata.name' "$dir/image.yaml")
channel=$(yq '.spec.channel' "$dir/image.yaml")
packer build -color=false "${vars[@]}" "$dir"
ref="local/golden/$name:$channel"
fail=0
uid=$(docker run --rm --entrypoint id "$ref" -u) || { echo "DENY image does not run"; exit 1; }
if [[ $uid == 0 ]]; then echo "DENY image runs as root"; fail=1; else echo "ok runs as uid $uid"; fi
leftover=$(docker run --rm --entrypoint sh "$ref" -c 'ls /var/lib/apt/lists 2>/dev/null | grep -vc "^lock$\|^partial$\|^auxfiles$" || true')
if [[ ${leftover:-0} -gt 0 ]]; then echo "DENY apt lists left in image ($leftover files)"; fail=1; else echo "ok no package-manager cache"; fi
docker image inspect "$ref" --format '{{json .Config.Labels}}' | jq -e '."platform.local/owner"' >/dev/null || { echo "DENY owner label missing"; fail=1; }
if [[ $fail -ne 0 ]]; then echo "FAIL"; exit 1; fi
echo "PASS $ref"
