# Input: the state document audit.sh collects. Output: one {v, c, why} row per control.
def pass($c): {v: "PASS", c: $c, why: ""};
def deny($c; $why): {v: "DENY", c: $c, why: $why};
def na($c; $why): {v: "N/A", c: $c, why: $why};
def check($c; cond; $why): if cond then pass($c) else deny($c; $why) end;

. as $s
| ($s.repo.default_branch // "main") as $db
| [ ($s.rulesets // [])[]
    | select(.enforcement == "active" and .target == "branch")
    | select((.conditions.ref_name.include // []) | any(. == "~DEFAULT_BRANCH" or . == "~ALL" or . == "refs/heads/\($db)")) ] as $br
| [ $br[].rules[]? ] as $rules
| [ $rules[].type ] as $types
| [
    check("dependabot alerts"; $s.vulnerability_alerts == true; "Dependabot alerts are off"),
    check("dependabot security updates"; $s.automated_security_fixes == true; "Dependabot security update PRs are off"),
    check("workflow token read-only"; $s.workflow_permissions.default_workflow_permissions == "read"; "the default GITHUB_TOKEN can write"),
    check("actions cannot approve PRs"; $s.workflow_permissions.can_approve_pull_request_reviews == false; "workflows can approve pull requests"),
    check("actions pinned by sha"; $s.actions_permissions.sha_pinning_required == true; "actions may be referenced by a mutable tag"),
    check("merge commits disabled"; $s.repo.allow_merge_commit == false; "merge commits are allowed (history is not linear)"),
    check("delete branch on merge"; $s.repo.delete_branch_on_merge == true; "merged branches are left behind"),
    check("wiki disabled"; $s.repo.has_wiki == false; "the wiki is on (content outside review)"),
    ( if $s.collaborators == null then deny("only code owners can merge"; "collaborators could not be read (undetermined is a deny)")
      else [ $s.collaborators[] | select(.push == true) | .login | select(. as $l | ($s.codeowners // []) | index($l) | not) ] as $extra
      | check("only code owners can merge"; ($extra | length) == 0;
              "write access for non-code-owners: \($extra | join(", ")) (personal-repo collaborators always get write; use forks)")
      end ),
    ( ["SECURITY.md", ".github/CODEOWNERS", ".github/dependabot.yml", ".github/workflows/security.yml"][] as $f
      | check("file \($f)"; $s.files[$f] == true; "\($f) is missing") ),
    ( if $s.repo.visibility == "public" then
        check("secret scanning"; $s.repo.security_and_analysis.secret_scanning.status == "enabled"; "secret scanning is off"),
        check("push protection"; $s.repo.security_and_analysis.secret_scanning_push_protection.status == "enabled"; "secrets can be pushed"),
        check("private vulnerability reporting"; $s.private_vulnerability_reporting == true; "reporters have no private channel"),
        check("codeql default setup"; $s.code_scanning_default_setup == "configured"; "code scanning is not configured"),
        check("file LICENSE"; $s.files["LICENSE"] == true; "a public repo without a LICENSE is all rights reserved"),
        check("file .github/workflows/scorecard.yml"; $s.files[".github/workflows/scorecard.yml"] == true; "scorecard.yml is missing"),
        check("ruleset on default branch"; ($br | length) > 0; "no active ruleset targets \($db)"),
        check("ruleset: no force push"; $types | index("non_fast_forward"); "force pushes to \($db) are allowed"),
        check("ruleset: no deletion"; $types | index("deletion"); "\($db) can be deleted"),
        check("ruleset: pull request required"; $types | index("pull_request"); "direct pushes to \($db) are allowed"),
        check("ruleset: linear history"; $types | index("required_linear_history"); "merge commits can land on \($db)"),
        check("ruleset: gitleaks required";
              [ $rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context ] | index("gitleaks");
              "the gitleaks check is not required"),
        check("ruleset: code-owner approval required";
              any($rules[]; .type == "pull_request" and .parameters.require_code_owner_review == true and .parameters.required_approving_review_count >= 1);
              "PRs can merge without a code owner's approval"),
        check("ruleset: approval after last push";
              any($rules[]; .type == "pull_request" and .parameters.require_last_push_approval == true);
              "new commits can be pushed after the code owner approved"),
        check("ruleset: bypass only admin, only via PR";
              all($br[]; (.bypass_actors // [])[] | .actor_type == "RepositoryRole" and .actor_id == 5 and .bypass_mode == "pull_request");
              "someone can bypass the ruleset outside a PR, or a non-admin can bypass"),
        check("ruleset: release tags immutable";
              any(($s.rulesets // [])[]; .enforcement == "active" and .target == "tag" and ([.rules[]?.type] | index("deletion") and index("update")));
              "release tags can be moved or deleted")
      else
        na("ruleset on default branch"; "GitHub Free cannot enforce rules on private repos (403); checks report but cannot block"),
        na("secret scanning"; "paid on private repos; compensated by gitleaks in security.yml"),
        na("code scanning"; "paid on private repos; no free equivalent applied"),
        na("private vulnerability reporting"; "public repos only")
      end )
  ]
