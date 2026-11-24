#!/usr/bin/env bash
# Create a repo with the baseline already in place. Dry run unless --apply.
# Usage: create.sh --name N --visibility public|private --description TEXT [--owner LOGIN] [--approvals N] [--apply]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
apply=false approvals=0 owner=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --apply) apply=true; shift; continue;;
    --name) name=$2;; --visibility) visibility=$2;; --description) description=$2;;
    --owner) owner=$2;; --approvals) approvals=$2;;
    *) echo "unknown arg $1" >&2; exit 64;;
  esac
  shift 2
done
: "${name:?--name required}" "${visibility:?--visibility required}" "${description:?--description required}"
[[ $name =~ ^[a-z0-9][a-z0-9.-]{0,99}$ ]] || { echo "name must be lowercase letters, digits, '-' or '.', 1-100 chars" >&2; exit 64; }
[[ $visibility == public || $visibility == private ]] || { echo "visibility must be public or private" >&2; exit 64; }
[[ $approvals =~ ^[0-6]$ ]] || { echo "approvals must be 0-6" >&2; exit 64; }
[[ -n $owner ]] || owner=$(gh api user -q .login)
repo=$owner/$name
if gh api --silent "repos/$repo" >/dev/null 2>&1; then
  echo "refusing: $repo already exists (use harden.sh and audit.sh for an existing repo)" >&2; exit 65
fi

echo "plan: create $repo ($visibility)"
if [[ $visibility == public ]]; then
  cat <<'EOF'
  enforced     ruleset on main: PR required, no force push, no deletion, linear history, gitleaks + osv-scanner required
  enforced     release tags v* cannot be moved or deleted
  enforced     secret scanning + push protection, CodeQL default setup, dependency review, private vulnerability reporting
  enforced     Dependabot alerts + security updates + weekly action updates, OpenSSF Scorecard
  enforced     read-only workflow token, actions pinned by SHA, squash/rebase only, wiki off
EOF
else
  cat <<'EOF'
  enforced     Dependabot alerts + security updates + weekly action updates
  enforced     read-only workflow token, actions pinned by SHA, squash/rebase only, wiki off
  compensated  secret scanning -> gitleaks on full history in Actions (reports, cannot block a push)
  compensated  dependency review -> osv-scanner on every PR (reports, cannot block a merge)
  unavailable  ruleset / branch protection on main (GitHub Free returns 403 for private repos)
  unavailable  code scanning (paid on private repos)
  cost         Actions minutes draw from the account's monthly included compute
EOF
fi
if ! $apply; then
  echo "files:"
  probe=$(mktemp -d); trap 'rm -rf "$probe"' EXIT
  "$here/files.sh" "$probe" --visibility "$visibility" --owner "$owner" --description "$description" | sed 's/^/  /'
  echo "settings:"
  echo "  (harden.sh runs against the new repo after the first push; run it with no --apply on any repo to preview)"
  echo "dry run: re-run with --apply"
  exit 0
fi

uid=$(gh api user -q .id)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
gh repo create "$repo" "--$visibility" --description "$description" --disable-wiki >/dev/null
echo "done   created $repo"
git -C "$work" init -q -b main
"$here/files.sh" "$work" --visibility "$visibility" --owner "$owner" --description "$description" | sed 's/^/       /'
git -C "$work" add -A
git -C "$work" -c user.name="$owner" -c user.email="$uid+$owner@users.noreply.github.com" \
  commit -q -m "chore: repository baseline (security workflow, dependabot, policy files)"
git -C "$work" push -q "https://github.com/$repo.git" main
echo "done   pushed baseline to main"
"$here/harden.sh" "$repo" --approvals "$approvals" --apply
echo
"$here/audit.sh" "$repo"
