#!/usr/bin/env bash
# probe.sh: run once with GH_TOKEN set to the SHIP_TOKEN candidate. Exercises every write the ship
# workflow needs on disposable objects and names the permission to add when one is denied.
#   GH_TOKEN=<token> bash scripts/ship/probe.sh
set -uo pipefail
HARNESS=kpnemo/kaizen-tasks-assembly-line
APPS=(kpnemo/kaizen-tasks-api kpnemo/kaizen-tasks-web)
[[ -n "${GH_TOKEN:-}" ]] || { echo "set GH_TOKEN to the token under test"; exit 1; }
status=0
probe() { # probe "<what>" "<permission if denied>" <command...>
  local what="$1" perm="$2"; shift 2
  if out="$("$@" 2>&1)"; then echo "ok       $what"; else echo "DENIED   $what -> grant: $perm"; echo "         $(head -1 <<<"$out")"; status=1; fi
}
probe "identify the token user" "Metadata: read" gh api user --jq .login
probe "read harness issues" "Issues: read (harness)" gh issue list --repo "$HARNESS" --limit 1
board="$(gh issue list --repo "$HARNESS" --label triage-board --state open --json number --jq '.[0].number // empty')"
if [[ -n "$board" ]]; then
  cid="$(gh api -X POST "repos/$HARNESS/issues/$board/comments" -f body="ship-token probe $(date -u +%FT%TZ), deleted right away" --jq .id 2>/dev/null || true)"
  if [[ -n "$cid" ]]; then echo "ok       comment on the board issue"; probe "delete the probe comment" "Issues: write (harness)" gh api -X DELETE "repos/$HARNESS/issues/comments/$cid"; else echo "DENIED   comment on the board issue -> grant: Issues: read and write (harness)"; status=1; fi
fi
probe "dispatch ship.yml (dry run)" "Actions: read and write (harness)" gh workflow run ship.yml --repo "$HARNESS" -f request_id=probe -f version=0.0.1 -f issues=1 -f dry_run=true
for repo in "${APPS[@]}"; do
  short="${repo#kpnemo/}"
  sha="$(gh api "repos/$repo/commits/develop" --jq .sha 2>/dev/null)"
  probe "$short: read check runs" "Checks: read" gh api "repos/$repo/commits/$sha/check-runs" --jq .total_count
  probe "$short: read pull requests" "Pull requests: read" gh pr list --repo "$repo" --limit 1
  probe "$short: create branch probe/ship-token" "Contents: write" gh api -X POST "repos/$repo/git/refs" -f ref=refs/heads/probe/ship-token -f sha="$sha"
  probe "$short: delete branch probe/ship-token" "Contents: write" gh api -X DELETE "repos/$repo/git/refs/heads/probe/ship-token"
done
echo; [[ $status == 0 ]] && echo "every probe passed: the token is enough for ship.yml" || echo "some probes were denied: adjust the token and run again"
exit $status
