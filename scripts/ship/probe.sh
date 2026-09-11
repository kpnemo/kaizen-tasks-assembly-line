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
# The dry run needs an issue that is really on staging to get past Preflight; PROBE_ISSUE defaults
# to 22. "workflow not found" here means ship.yml is not on develop yet, not a permission problem.
probe "dispatch ship.yml (dry run for #${PROBE_ISSUE:-22})" "Actions: read and write (harness)" gh workflow run ship.yml --repo "$HARNESS" -f request_id=probe -f version=9.9.9 -f "issues=${PROBE_ISSUE:-22}" -f dry_run=true
for repo in "${APPS[@]}"; do
  short="${repo#kpnemo/}"
  sha="$(gh api "repos/$repo/commits/develop" --jq .sha 2>/dev/null)"
  probe "$short: read check runs" "Checks: read" gh api "repos/$repo/commits/$sha/check-runs" --jq .total_count
  probe "$short: read pull requests" "Pull requests: read" gh pr list --repo "$repo" --limit 1
  probe "$short: create branch probe/ship-token" "Contents: write" gh api -X POST "repos/$repo/git/refs" -f ref=refs/heads/probe/ship-token -f sha="$sha"
  # A pull request needs a commit the base lacks: an empty commit on the probe branch through the API.
  tree="$(gh api "repos/$repo/commits/$sha" --jq .commit.tree.sha 2>/dev/null)"
  probe_sha="$(gh api -X POST "repos/$repo/git/commits" -f message="ship-token probe" -f tree="$tree" -f "parents[]=$sha" --jq .sha 2>/dev/null || true)"
  if [[ -n "$probe_sha" ]] && gh api -X PATCH "repos/$repo/git/refs/heads/probe/ship-token" -f sha="$probe_sha" -F force=true >/dev/null 2>&1; then
    pr="$(gh pr create --repo "$repo" --base develop --head probe/ship-token --title "ship-token probe (closed at once)" --body "Opened and closed by scripts/ship/probe.sh." --draft 2>/dev/null || true)"
    if [[ -n "$pr" ]]; then echo "ok       $short: open a pull request"; probe "$short: close the probe pull request" "Pull requests: write" gh pr close "$pr" --repo "$repo"; else echo "DENIED   $short: open a pull request -> grant: Pull requests: read and write"; status=1; fi
  else
    echo "DENIED   $short: commit on the probe branch -> grant: Contents: write"; status=1
  fi
  probe "$short: delete branch probe/ship-token" "Contents: write" gh api -X DELETE "repos/$repo/git/refs/heads/probe/ship-token"
done
echo; [[ $status == 0 ]] && echo "every probe passed: the token is enough for ship.yml" || echo "some probes were denied: adjust the token and run again"
exit $status
