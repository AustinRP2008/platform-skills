#!/usr/bin/env bash
# Validate one module directory exactly as CI does. Usage: validate.sh <module-dir>
set -euo pipefail
dir=${1:?usage: validate.sh <module-dir>}
cd "$dir"
step() { printf '== %s\n' "$*"; }
step fmt;      tofu fmt -check -recursive
step init;     tofu init -backend=false -input=false >/dev/null
step validate; tofu validate -no-color
step tflint;   tflint --init >/dev/null && tflint --no-color
step test;     tofu test -no-color
echo PASS
