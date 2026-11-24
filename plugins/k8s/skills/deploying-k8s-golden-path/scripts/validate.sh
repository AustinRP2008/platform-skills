#!/usr/bin/env bash
# Build every overlay, schema-check it, apply platform policies. Usage: validate.sh <app-dir>
set -euo pipefail
dir=${1:?usage: validate.sh <app-dir>}
fail=0
for ov in "$dir"/overlays/*/; do
  env=$(basename "$ov")
  out=$(mktemp --suffix=.yaml)
  echo "== $env: kustomize build"
  kustomize build "$ov" > "$out"
  echo "== $env: kubeconform"
  kubeconform -strict -summary -kubernetes-version 1.33.0 "$out"
  echo "== $env: policies"
  # Each query prints offending "Kind/name: reason" lines; any output is a failure.
  violations=$(yq -o=json -I=0 '.' "$out" | jq -rs '
    .[] | select(.kind == "Deployment") | .metadata.name as $n | .spec.template.spec as $p |
    ( if ($p.securityContext.runAsNonRoot // false) != true then "\($n): runAsNonRoot not set" else empty end ),
    ( $p.containers[] |
      ( if (.image | test(":latest$")) or ((.image | test(":|@sha256:")) | not) then "\($n): image not pinned (\(.image))" else empty end ),
      ( if .resources.requests == null or .resources.limits.memory == null then "\($n)/\(.name): requests/limits missing" else empty end ),
      ( if .readinessProbe == null or .livenessProbe == null then "\($n)/\(.name): probes missing" else empty end ) )')
  if [[ -n $violations ]]; then while IFS= read -r v; do echo "  DENY $v"; done <<< "$violations"; fail=1; fi
  rm -f "$out"
done
if [[ $fail -ne 0 ]]; then echo FAIL; exit 1; fi
echo PASS
