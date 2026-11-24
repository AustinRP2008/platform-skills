#!/usr/bin/env bash
# Image policy + packer init/fmt/validate for one image dir.
# Usage: validate.sh <image-dir>
set -euo pipefail
dir=${1:?usage: validate.sh <image-dir>}
here=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
. "$here/scripts/lib.sh"
approved=$(command grep -v '^#' "$here/assets/approved-bases.txt" | sed '/^$/d' | jq -R . | jq -sc .)
today=$(date -u +%F)
limit=$(date -u -d '+18 months' +%F)
denials=$(yq -o=json '.' "$dir/image.yaml" | jq -r --argjson ok "$approved" --arg today "$today" --arg limit "$limit" '
  .spec as $s | ($s.base // "" | split("@")[0]) as $repo |
  ( if .kind != "GoldenImage" then "kind must be GoldenImage" else empty end ),
  ( if (.metadata.name // "" | test("^[a-z][a-z0-9-]{1,40}$")) then empty else "metadata.name must be kebab-case" end ),
  ( if (.metadata.owner // "" | test("^[a-z][a-z0-9-]+$")) then empty else "metadata.owner must be a team slug" end ),
  ( if ($s.base // "" | test("@sha256:[0-9a-f]{64}$")) then empty else "spec.base must be pinned by digest (repo@sha256:...)" end ),
  ( if ($ok | index($repo)) == null then "spec.base repository \($repo) is not in approved-bases.txt" else empty end ),
  ( if ($s.channel | IN("dev","staging","prod")) then empty else "spec.channel must be dev, staging or prod" end ),
  ( if ($s.packages | type) != "array" or ($s.packages | length) == 0 then "spec.packages must be a non-empty list" else empty end ),
  ( if ($s.packages // [] | map(test("^[a-z0-9][a-z0-9+.-]*$")) | all) then empty else "spec.packages entries must be plain package names" end ),
  ( if ($s.supportedUntil // "" | tostring) <= $today then "spec.supportedUntil must be in the future" else empty end ),
  ( if ($s.supportedUntil // "" | tostring) > $limit then "spec.supportedUntil must be within 18 months (\($limit))" else empty end )
')
if [[ -n $denials ]]; then
  while IFS= read -r d; do echo "DENY $d"; done <<< "$denials"
  echo "FAIL"; exit 1
fi
echo "policy: ALLOW"
mapfile -t vars < <(packer_vars "$dir")
packer init "$dir" >/dev/null
packer fmt -check -recursive "$dir"
packer validate "${vars[@]}" "$dir"
echo "PASS"
