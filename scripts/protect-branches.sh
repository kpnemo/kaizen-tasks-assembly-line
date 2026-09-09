#!/usr/bin/env bash
# Apply branch protection to develop and main of one app repo.
# Usage: scripts/protect-branches.sh <owner/repo> [--dry-run]
#   develop: required status check ci.  main: required status checks ci and promote.
#   Both: a pull request is required with zero required approvals, no force pushes, no deletions,
#   enforce_admins off so the facilitator can merge as soon as the checks are green.
# Replayable: PUT replaces the whole protection object.
set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "usage: $0 <owner/repo> [--dry-run]" >&2
  exit 1
fi
DRY_RUN=0
if [ "${2:-}" = "--dry-run" ]; then DRY_RUN=1; fi

payload() { # branch
  local contexts='["ci"]'
  if [ "$1" = "main" ]; then contexts='["ci", "promote"]'; fi
  cat <<EOF
{
  "required_status_checks": { "strict": false, "contexts": $contexts },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": false
}
EOF
}

for branch in develop main; do
  body="$(payload "$branch")"
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN: gh api -X PUT -H 'Accept: application/vnd.github+json' repos/$REPO/branches/$branch/protection --input - <<'JSON'"
    echo "$body"
    echo "JSON"
    continue
  fi
  printf '%s' "$body" | gh api -X PUT -H "Accept: application/vnd.github+json" \
    "repos/$REPO/branches/$branch/protection" --input - \
    --jq "{branch: \"$branch\", checks: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count, force_pushes: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}"
done
