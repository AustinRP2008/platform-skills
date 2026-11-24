#!/usr/bin/env bash
# Create images/<name>/ with image.yaml and the generic Packer template.
# Usage: render.sh --name N --owner TEAM --base repo@sha256:... [--packages "a b"] [--dest images]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
dest=images packages="ca-certificates"
while [[ $# -gt 0 ]]; do
  case $1 in
    --name) name=$2;; --owner) owner=$2;; --base) base=$2;; --packages) packages=$2;; --dest) dest=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${name:?--name required}" "${owner:?--owner required}" "${base:?--base required}"
out="$dest/$name"
[[ -e $out ]] && { echo "refusing: $out exists" >&2; exit 65; }
mkdir -p "$out"
cp -r "$here/assets/template/." "$out/"
chmod +x "$out/files/harden.sh"
read -ra pkgs <<< "$packages"
pk=$(printf '%s\n' "${pkgs[@]}" | jq -R . | jq -sc .)
{
  echo "apiVersion: platform.local/v1alpha1"
  echo "kind: GoldenImage"
  echo "metadata:"
  echo "  name: $name"
  echo "  owner: $owner"
  echo "spec:"
  echo "  base: $base"
  echo "  channel: dev"
  echo "  packages: $pk"
  echo "  supportedUntil: \"$(date -u -d '+12 months' +%F)\""
} > "$out/image.yaml"
echo "$out"
