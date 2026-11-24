#!/usr/bin/env bash
# Write the baseline files into a checkout. Existing files are kept, never overwritten.
# Usage: files.sh <dir> --visibility public|private --owner <login> [--description <text>]
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
dir=${1:?usage: files.sh <dir> --visibility public|private --owner <login> [--description <text>]}
shift
description=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --visibility) visibility=$2;; --owner) owner=$2;; --description) description=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${visibility:?--visibility required}" "${owner:?--owner required}"
[[ $visibility == public || $visibility == private ]] || { echo "visibility must be public or private" >&2; exit 64; }
[[ -d $dir ]] || { echo "no such directory: $dir" >&2; exit 66; }

# put PATH CONTENT-FILE: copy unless PATH already exists. Prints what it did.
put() {
  local rel=$1 src=$2
  if [[ -e $dir/$rel ]]; then echo "keep   $rel"; return 1; fi
  mkdir -p "$(dirname "$dir/$rel")"
  cp "$src" "$dir/$rel"
  echo "write  $rel"
}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

(cd "$here/assets/files" && command find . -type f -printf '%P\n') | sort | while read -r rel; do
  if [[ $rel == .github/workflows/security.yml && $visibility == public ]]; then
    cat "$here/assets/files/$rel" "$here/assets/files-public/dependency-review-job.yml" > "$tmp/security.yml"
    put "$rel" "$tmp/security.yml" || true
  else
    put "$rel" "$here/assets/files/$rel" || true
  fi
done

printf '* @%s\n' "$owner" > "$tmp/CODEOWNERS"
put .github/CODEOWNERS "$tmp/CODEOWNERS" || true

if [[ $visibility == public ]]; then
  put .github/workflows/scorecard.yml "$here/assets/files-public/.github/workflows/scorecard.yml" || true
  {
    echo "# Security policy"
    echo
    echo "Please report vulnerabilities privately through GitHub: open the **Security** tab of this"
    echo "repository and choose **Report a vulnerability**. Do not open a public issue."
    echo
    echo "Only the latest commit on \`main\` is supported."
  } > "$tmp/SECURITY.md"
  sed "s/{{YEAR}}/$(date +%Y)/; s/{{OWNER}}/$owner/" "$here/assets/MIT-LICENSE.tmpl" > "$tmp/LICENSE"
  put LICENSE "$tmp/LICENSE" || true
else
  {
    echo "# Security policy"
    echo
    echo "This is a private repository. Report suspected vulnerabilities or leaked credentials to the"
    echo "code owners in \`.github/CODEOWNERS\` directly, not in an issue or PR description."
  } > "$tmp/SECURITY.md"
fi
put SECURITY.md "$tmp/SECURITY.md" || true

printf '# %s\n\n%s\n' "$(basename "$(cd "$dir" && pwd)")" "$description" > "$tmp/README.md"
put README.md "$tmp/README.md" || true
