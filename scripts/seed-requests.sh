#!/usr/bin/env bash
# File seeds/requests/*.md as feature-request issues. Skips a seed whose title already exists as an open issue.
# Usage: scripts/seed-requests.sh [--dry-run]
#   REPO=<owner/name> overrides the target (default kpnemo/kaizen-tasks-assembly-line).
# Seed format: a front matter block with a `title:` line (plain or quoted; one layer of surrounding quotes is
# stripped so a YAML formatter cannot change the issue title), then the body in the issue form's section
# structure (### Problem, ### Proposed behavior, ### Acceptance criteria, ### Out of scope, ### Your role).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-kpnemo/kaizen-tasks-assembly-line}"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

# Titles of open issues, one per line. Empty when gh cannot reach the repo (dry run before the repo exists).
open_titles=""
if gh auth status >/dev/null 2>&1; then
  open_titles="$(gh issue list --repo "$REPO" --state open --limit 200 --json title --jq '.[].title' 2>/dev/null || true)"
fi

created=0
skipped=0
for seed in "$ROOT"/seeds/requests/*.md; do
  name="$(basename "$seed")"
  # Front matter is between the first line (---) and the next --- line.
  title="$(sed -n '2,/^---$/p' "$seed" | sed -n 's/^title:[[:space:]]*//p' | head -1)"
  case "$title" in
    \"*\") title="${title#\"}"; title="${title%\"}" ;;
    \'*\') title="${title#\'}"; title="${title%\'}" ;;
  esac
  if [ -z "$title" ]; then
    echo "SKIP     $name: no title: line in the front matter" >&2
    continue
  fi
  body="$(mktemp)"
  # Everything after the second --- line is the body.
  awk 'f >= 2 { print } /^---$/ { f++ }' "$seed" | sed '1{/^$/d;}' >"$body"

  if printf '%s\n' "$open_titles" | grep -Fxq -- "$title"; then
    echo "SKIP     $title (an open issue with this title exists)"
    skipped=$((skipped + 1))
    rm -f "$body"
    continue
  fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "WOULD CREATE  $title  [$name, $(wc -l <"$body" | tr -d ' ') body lines]"
    rm -f "$body"
    continue
  fi
  url="$(gh issue create --repo "$REPO" --label feature-request --title "$title" --body-file "$body")"
  echo "CREATED  $title  $url"
  created=$((created + 1))
  rm -f "$body"
done

if [ "$DRY_RUN" = 0 ]; then
  echo "Done: $created created, $skipped skipped."
fi
