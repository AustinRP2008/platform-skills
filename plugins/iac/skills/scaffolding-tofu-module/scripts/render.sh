#!/usr/bin/env bash
# Render a new module from the template. Usage: render.sh <name> <dest> [purpose]
set -euo pipefail
name=${1:?usage: render.sh <name> <dest> [purpose]}
dest=${2:?usage: render.sh <name> <dest> [purpose]}
purpose=${3:-"TODO: one-sentence purpose."}
[[ $name =~ ^[a-z][a-z0-9-]{1,40}$ ]] || { echo "name must be kebab-case" >&2; exit 64; }
[[ -e $dest ]] && { echo "refusing: $dest already exists" >&2; exit 65; }
here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$(dirname "$dest")"
cp -R "$here/assets/module-template" "$dest"
find "$dest" -type f -exec sed -i \
  -e "s|__MODULE_NAME_US__|${name//-/_}|g" \
  -e "s|__MODULE_NAME__|$name|g" \
  -e "s|__MODULE_PURPOSE__|$purpose|g" {} +
echo "rendered $dest"
