#!/bin/bash
# Merge a Cotor PR without forcing the current worktree onto the base branch.

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin${PATH:+:$PATH}"

METHOD="squash"
WAIT_FOR_CHECKS=0
DELETE_BRANCH=0
DRY_RUN=0
CHECK_INTERVAL="${COTOR_PR_CHECK_INTERVAL_SECONDS:-10}"

usage() {
    cat <<'USAGE'
Usage: shell/cotor-merge-pr.sh [options] <pr-number-or-url>

Options:
  --wait              Wait for GitHub checks before merging.
  --delete-branch     Delete the remote head branch after a successful merge.
  --method <method>   Merge method: squash, merge, or rebase. Default: squash.
  --dry-run           Print the planned actions without mutating GitHub or git.
  -h, --help          Show this help.

The helper avoids `gh pr merge` local checkout behavior. It merges through the
GitHub API, then locates the worktree that owns the PR base branch and runs
`git pull --ff-only` there.
USAGE
}

PR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait)
            WAIT_FOR_CHECKS=1
            shift
            ;;
        --delete-branch)
            DELETE_BRANCH=1
            shift
            ;;
        --method)
            METHOD="${2:-}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -n "$PR" ]]; then
                echo "Unexpected argument: $1"
                usage
                exit 2
            fi
            PR="$1"
            shift
            ;;
    esac
done

if [[ -z "$PR" ]]; then
    usage
    exit 2
fi

case "$METHOD" in
    squash|merge|rebase) ;;
    *)
        echo "Unsupported merge method: $METHOD"
        exit 2
        ;;
esac

REPO="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
BASE_BRANCH="$(gh pr view "$PR" --json baseRefName --jq '.baseRefName')"
HEAD_BRANCH="$(gh pr view "$PR" --json headRefName --jq '.headRefName')"
PR_TITLE="$(gh pr view "$PR" --json title --jq '.title')"
MERGED_AT="$(gh pr view "$PR" --json mergedAt --jq '.mergedAt // ""')"

find_base_worktree() {
    git worktree list --porcelain | awk -v branch="refs/heads/$BASE_BRANCH" '
        $1 == "worktree" { path = substr($0, 10) }
        $1 == "branch" && $2 == branch { print path; exit }
    '
}

BASE_WORKTREE="$(find_base_worktree || true)"

echo "Cotor PR ship helper"
echo "  Repo:   $REPO"
echo "  PR:     $PR"
echo "  Base:   $BASE_BRANCH"
echo "  Head:   $HEAD_BRANCH"
echo "  Method: $METHOD"
if [[ -n "$BASE_WORKTREE" ]]; then
    echo "  Base worktree: $BASE_WORKTREE"
else
    echo "  Base worktree: not found locally"
fi

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run complete."
    exit 0
fi

if [[ "$WAIT_FOR_CHECKS" == "1" ]]; then
    gh pr checks "$PR" --watch --interval "$CHECK_INTERVAL"
fi

if [[ -z "$MERGED_AT" ]]; then
    api_args=(
        -X PUT \
        "repos/$REPO/pulls/$PR/merge" \
        -f "merge_method=$METHOD"
    )
    if [[ "$METHOD" != "rebase" ]]; then
        api_args+=(-f "commit_title=$PR_TITLE")
    fi
    gh api \
        "${api_args[@]}" \
        --jq '.sha'
else
    echo "PR is already merged at $MERGED_AT."
fi

if [[ "$DELETE_BRANCH" == "1" ]]; then
    git push origin --delete "$HEAD_BRANCH" || true
fi

if [[ -n "$BASE_WORKTREE" ]]; then
    if [[ -n "$(git -C "$BASE_WORKTREE" status --short)" ]]; then
        echo "Base worktree has local changes; refusing to pull there:"
        git -C "$BASE_WORKTREE" status --short
        exit 1
    fi
    git -C "$BASE_WORKTREE" fetch origin "$BASE_BRANCH"
    git -C "$BASE_WORKTREE" pull --ff-only origin "$BASE_BRANCH"
else
    echo "No local worktree owns $BASE_BRANCH; remote merge is complete, but local sync was skipped."
fi
