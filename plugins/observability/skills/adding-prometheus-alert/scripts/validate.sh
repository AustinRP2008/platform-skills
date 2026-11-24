#!/usr/bin/env bash
# Check and unit-test every rule file under a monitoring dir. Usage: validate.sh <dest>
set -euo pipefail
dir=${1:?usage: validate.sh <monitoring-dir>}
shopt -s nullglob
rules=("$dir"/rules/*.yaml) tests=("$dir"/tests/*.yaml)
[[ ${#rules[@]} -gt 0 ]] || { echo "no rule files under $dir/rules" >&2; exit 1; }
echo "== promtool check rules"; promtool check rules "${rules[@]}"
[[ ${#tests[@]} -gt 0 ]] || { echo "FAIL: no tests under $dir/tests (every rule file needs one)" >&2; exit 1; }
echo "== promtool test rules"; promtool test rules "${tests[@]}"
echo PASS
