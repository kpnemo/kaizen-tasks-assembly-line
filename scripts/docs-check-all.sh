#!/usr/bin/env bash
# Root Stop hook: run each nested repo's docs-check when that repo has changes.
# Usage: scripts/docs-check-all.sh --hook
#   stdin: the Stop hook JSON from Claude Code, for example
#          {"hook_event_name":"Stop","stop_hook_active":false,"session_id":"...","cwd":"..."}.
#          It is forwarded unchanged to each nested script.
#   KAIZEN_WORKSPACE_ROOT=<dir> overrides the workspace root (used by the fixture test).
#
# Exit code, mapped from the nested scripts (master plan section 4, "Docs-check"):
#   every nested exit 0, or no nested repo with changes  -> exit 0, report on stdout
#   any nested exit 2                                    -> exit 2, report on stderr: Claude Code blocks the stop
#                                                           and feeds stderr back to the model
#   otherwise (a nested exit that is neither 0 nor 2)    -> exit 1, report on stderr, non-blocking. This is the
#                                                           nested escape hatch: after three consecutive blocks a
#                                                           nested docs-check stops blocking, prints its banner
#                                                           "DOCS CHECK FAILED, human intervention required",
#                                                           writes .claude/DOCS-CHECK-FAILED, and exits non-zero
#                                                           without exiting 2. A failure is never turned into
#                                                           exit 0 here.
#
# stop_hook_active is true when Claude Code is already continuing because a Stop hook blocked. This script keeps
# checking when it is true (skipping would let a real failure through on the second attempt); the nested
# three-strike counter is the loop guard. As a safety net it reads the flag and, when it is true and a nested
# repo carries the marker .claude/DOCS-CHECK-FAILED after its run, treats that repo as escape-hatched (exit 1,
# not 2) even if the nested script exited 2, so a root session can never loop on a repo that has already given
# up. This script adds no docs rules of its own.
set -uo pipefail

if [ "${1:-}" != "--hook" ]; then
  echo "usage: $0 --hook   (reads the Stop hook JSON on stdin)" >&2
  exit 1
fi

ROOT="${KAIZEN_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK_INPUT=""
if [ ! -t 0 ]; then IFS= read -r -t 5 HOOK_INPUT || true; fi
STOP_HOOK_ACTIVE="$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [ "$STOP_HOOK_ACTIVE" != "true" ]; then STOP_HOOK_ACTIVE=false; fi

# A repo "has changes" when the working tree is dirty or HEAD has commits beyond its base
# (merge-base with origin/develop, else local develop).
has_changes() {
  local repo="$1" base=""
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then return 0; fi
  if git -C "$repo" rev-parse --verify -q origin/develop >/dev/null 2>&1; then
    base="$(git -C "$repo" merge-base HEAD origin/develop 2>/dev/null || true)"
  elif git -C "$repo" rev-parse --verify -q develop >/dev/null 2>&1; then
    base="$(git -C "$repo" merge-base HEAD develop 2>/dev/null || true)"
  fi
  if [ -n "$base" ] && [ -n "$(git -C "$repo" rev-list "$base"..HEAD 2>/dev/null)" ]; then return 0; fi
  return 1
}

blocked=0
hatched=0
report="stop_hook_active=$STOP_HOOK_ACTIVE"$'\n'
for name in backend frontend; do
  repo="$ROOT/$name"
  if [ ! -d "$repo/.git" ]; then continue; fi
  if [ ! -f "$repo/scripts/docs-check.sh" ]; then
    report="$report[$name] scripts/docs-check.sh not found, skipped"$'\n'
    continue
  fi
  if ! has_changes "$repo"; then
    report="$report[$name] no changes, docs-check skipped"$'\n'
    continue
  fi
  output="$(cd "$repo" && printf '%s' "$HOOK_INPUT" | bash scripts/docs-check.sh --hook 2>&1)"
  code=$?
  report="$report$(printf '%s\n' "$output" | sed "s/^/[$name] /")"$'\n'
  if [ "$code" -eq 0 ]; then
    continue
  fi
  if [ "$code" -eq 2 ] && [ "$STOP_HOOK_ACTIVE" = true ] && [ -f "$repo/.claude/DOCS-CHECK-FAILED" ]; then
    report="$report[$name] exit 2 with the marker .claude/DOCS-CHECK-FAILED present while stop_hook_active is true: treated as the escape hatch, not blocking again"$'\n'
    code=1
  fi
  if [ "$code" -eq 2 ]; then
    blocked=1
    report="$report[$name] docs-check exit 2, blocking the stop"$'\n'
  else
    hatched=1
    report="$report[$name] docs-check exit $code, escape hatch, not blocking"$'\n'
  fi
done

if [ "$blocked" -ne 0 ]; then
  printf '%s' "$report" >&2
  exit 2
fi
if [ "$hatched" -ne 0 ]; then
  printf '%s' "$report" >&2
  exit 1
fi
printf '%s' "$report"
exit 0
