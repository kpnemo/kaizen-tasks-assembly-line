#!/usr/bin/env bash
# Helpers for .github/workflows/ship.yml. Sourced by every step of the ship job; every function
# reads its configuration from the environment the workflow sets: GH_TOKEN (the SHIP_TOKEN
# secret), DRY_RUN, HARNESS, API_REPO, WEB_REPO, STAGING_WEB_URL, PRODUCTION_WEB_URL, RUN_URL,
# REQUEST_ID, VERSION, ISSUES.
set -euo pipefail

TRAILER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"

# --- step bookkeeping ---------------------------------------------------------------------------
# step "<name>" records the step for the failure reporter (and the pipeline page) and opens a log
# group; endstep closes it.
step() {
  echo "STEP=$1" >>"$GITHUB_ENV"
  echo "::group::$1"
}
endstep() { echo "::endgroup::"; }
dry() { [[ "${DRY_RUN:-false}" == "true" ]]; }
# run "<what>" -- <command...>: in a dry run prints the intent; otherwise prints it and executes.
run() {
  local what="$1"
  shift
  [[ "${1:-}" == "--" ]] && shift
  if dry; then
    echo "dry-run: would $what"
  else
    echo "$what"
    "$@"
  fi
}
fail() {
  echo "::error::$*" >&2
  exit 1
}

# --- GitHub reads -------------------------------------------------------------------------------
head_of() { gh api "repos/$1/commits/$2" --jq .sha; } # head_of <repo> <branch>
version_on() {                                       # version_on <repo> <branch>
  gh api "repos/$1/contents/package.json?ref=$2" --jq .content | base64 -d | jq -r .version
}
issue_labels() { gh issue view "$1" --repo "$HARNESS" --json labels --jq '[.labels[].name]|join(",")'; }
has_label() { case ",$(issue_labels "$1")," in *",$2,"*) return 0 ;; *) return 1 ;; esac; }
# Open feat/<n>- or fix/<n>- pull requests for issue <n> in the three repos, one "repo#number" per line.
open_prs_for() {
  local n="$1" repo
  for repo in "$API_REPO" "$WEB_REPO" "$HARNESS"; do
    gh pr list --repo "$repo" --state open --limit 100 --json number,headRefName |
      jq -r --arg n "$n" --arg repo "$repo" \
        '.[] | select(.headRefName | test("^(feat|fix)/" + $n + "-")) | "\($repo)#\(.number)"'
  done
}
pr_number() { # pr_number <repo> <head> <base> <state> -> number or empty
  gh pr list --repo "$1" --head "$2" --base "$3" --state "$4" --limit 1 --json number --jq '.[0].number // empty'
}
pr_head_sha() { gh pr view "$2" --repo "$1" --json headRefOid --jq .headRefOid; } # pr_head_sha <repo> <n>

# --- environment read-backs ---------------------------------------------------------------------
api_served() { curl -fsS --max-time 10 "$1/api/v1/health" | jq -r '.data.commit + " " + .data.version'; }
web_served() {
  curl -fsS --max-time 10 -H 'Cache-Control: no-cache' "$1/version.json" | jq -r '.commit + " " + .version'
}
# serves <api|web> <url> <sha> <version>: true when that environment serves exactly that build.
serves() {
  local kind="$1" url="$2" sha="$3" version="$4" got
  got="$("${kind}_served" "$url" 2>/dev/null || true)"
  [[ "$got" == "$sha $version" ]]
}
# wait_for <seconds> <interval> "<what>" <command...>: polls until the command succeeds.
wait_for() {
  local limit="$1" every="$2" what="$3"
  shift 3
  local deadline=$((SECONDS + limit))
  until "$@"; do
    if ((SECONDS >= deadline)); then fail "timed out after ${limit}s waiting for $what"; fi
    echo "waiting for $what …"
    sleep "$every"
  done
  echo "ok: $what"
}

# --- semver -------------------------------------------------------------------------------------
semver_gt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

# --- merging ------------------------------------------------------------------------------------
# merge_when_green <repo> <number> <seconds> <merge|squash>: waits for the required checks on the
# current head (ci on develop, ci and promote on main), then merges exactly that head. A pull
# request already merged is skipped, so a rerun passes straight through.
merge_when_green() {
  local repo="$1" n="$2" limit="$3" method="$4" state sha
  state="$(gh pr view "$n" --repo "$repo" --json state --jq .state)"
  if [[ "$state" == "MERGED" ]]; then
    echo "$repo#$n already merged"
    return 0
  fi
  sha="$(pr_head_sha "$repo" "$n")"
  base="$(gh pr view "$n" --repo "$repo" --json baseRefName --jq .baseRefName)"
  local required="ci"
  [[ "$base" == "main" ]] && required="ci promote"
  if dry; then
    echo "dry-run: would wait for $required on $repo#$n ($sha) and merge with --$method"
    return 0
  fi
  # Poll the rollup by the required names until every one has succeeded. `gh pr checks --watch`
  # is not used: it returns at once when no check has registered yet (a promotion pull request
  # opened seconds ago), and a missing check must wait, not fail.
  local deadline=$((SECONDS + limit)) name conclusion pending
  while :; do
    pending=""
    for name in $required; do
      conclusion="$(gh pr view "$n" --repo "$repo" --json statusCheckRollup |
        jq -r --arg name "$name" '[.statusCheckRollup[] | select(.name == $name)] | last | (.conclusion // .status // "missing")')"
      case "$conclusion" in
      SUCCESS) ;;
      FAILURE | CANCELLED | TIMED_OUT | ACTION_REQUIRED | STARTUP_FAILURE) fail "$repo#$n: required check $name is $conclusion" ;;
      *) pending="$pending $name=$conclusion" ;;
      esac
    done
    [[ -z "$pending" ]] && break
    if ((SECONDS >= deadline)); then fail "$repo#$n: required checks not green after ${limit}s:$pending"; fi
    echo "$repo#$n: waiting for$pending"
    sleep 20
  done
  gh pr merge "$n" --repo "$repo" "--$method" --match-head-commit "$sha"
}

# --- issue comments -----------------------------------------------------------------------------
comment() { run "comment on #$1: $(head -c 60 <<<"$2")…" -- gh issue comment "$1" --repo "$HARNESS" --body "$2"; }
# marker_of <issue> -> the JSON of the newest kaizen-ship marker on the issue, or empty.
marker_of() {
  gh api "repos/$HARNESS/issues/$1/comments" --paginate --jq '.[] | .body' |
    grep -o '<!-- kaizen-ship {.*} -->' | tail -1 | sed -E 's/^<!-- kaizen-ship (\{.*\}) -->$/\1/' || true
}
