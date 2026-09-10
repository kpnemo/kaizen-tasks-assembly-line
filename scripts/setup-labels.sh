#!/usr/bin/env bash
# Create or update the label set in the assembly-line repo and create the pinned "Triage board" issue if missing.
# Usage: scripts/setup-labels.sh [--dry-run]
#   REPO=<owner/name> overrides the target (default kpnemo/kaizen-tasks-assembly-line).
# Idempotent: gh label create --force updates color and description; the board is created only when no open
# issue carries the triage-board label.
set -euo pipefail

REPO="${REPO:-kpnemo/kaizen-tasks-assembly-line}"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

label() { # name color description
  run gh label create "$1" --repo "$REPO" --force --color "$2" --description "$3"
}

label feature-request 1D76DB "A request filed through the feature request form"
label bug D73A4A "A defect filed through the bug report form; skips the rubric, goes straight to implement-issue"

# One gray-to-green gradient per scale, index 1..5.
GRADIENT="BFBFBF A9CBA4 8FC48A 5FB35A 2EA043"
for scale in clarity complexity risk; do
  i=1
  for color in $GRADIENT; do
    label "$scale:$i" "$color" "Rubric $scale score $i of 5"
    i=$((i + 1))
  done
done

label arch-change B60205 "Implies an architecture change; sorts after every other request"
label triaged D4C5F9 "Scored by triage-requests"
# The three lifecycle states, in order, on one purple ramp: implementing -> staging -> shipped.
label implementing 9B6FE0 "implement-issue has taken the issue into work"
label staging 7744E3 "Every pull request for the issue is merged and staging serves them"
label shipped 5319E7 "Merged to main and live in production"
label triage-board FBCA04 "The pinned Triage board issue; carried by exactly one issue"

# Triage board: one open issue, pinned, body rewritten by the triage skill.
if [ "$DRY_RUN" = 1 ]; then
  echo "DRY-RUN: would create and pin the 'Triage board' issue if no open issue carries the triage-board label"
  exit 0
fi

existing="$(gh issue list --repo "$REPO" --label triage-board --state open --json number --jq '.[0].number // empty')"
if [ -n "$existing" ]; then
  echo "Triage board exists: #$existing"
  exit 0
fi

body="$(mktemp)"
cat >"$body" <<'EOF'
<!-- kaizen-triage-board -->
# Triage board

No triage run yet. The `triage-requests` skill rewrites this body with the current ranking.
EOF
url="$(gh issue create --repo "$REPO" --title "Triage board" --label triage-board --body-file "$body")"
number="${url##*/}"
gh issue pin "$number" --repo "$REPO"
rm -f "$body"
echo "Triage board created and pinned: #$number ($url)"
