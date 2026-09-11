# Ship workflow (pipeline, part 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `workflow_dispatch` in the harness repo, `ship.yml`, takes a set of issues that are on staging from release cut to production read-back and closes them as shipped, idempotently, with a dry-run mode.

**Architecture:** The workflow is thin YAML over two bash files committed beside it: `scripts/ship/lib.sh` (helpers: dry-run guard, GitHub reads, waits, merges, issue comments) and `scripts/ship/cut-release.sh` (the release commit in one app repo, reusing an existing release branch when it is exactly the expected one). Every step names itself into `$GITHUB_ENV` so the failure handler and, later, the pipeline page can say where a ship stopped. State that must survive a rerun lives on the issues as a marked comment. All cross-repo writes use the `SHIP_TOKEN` secret; the harness checkout uses `github.token`.

**Tech Stack:** GitHub Actions (`actions/checkout@v5`, `actions/setup-node@v5`), bash, `gh`, `jq`, `curl`, Node 24 for the app repos' own scripts (`npm version`, `npm run product-map`, `npm run lint`).

**Spec:** `docs/superpowers/specs/2026-09-11-pipeline-control-room-design.md`, section "The ship workflow" and "Definitions the API and the workflow share".

## Global Constraints

- Harness repo only, branch `feat/ship-workflow` off `develop`; one pull request; the workflow file becomes dispatchable once merged to `develop` (the default branch).
- Inputs: `request_id`, `version` (semver), `issues` (comma-separated), `dry_run` (boolean). `run-name: ship <request_id> <version>`. `concurrency: { group: ship, cancel-in-progress: false }`.
- Secret `SHIP_TOKEN` (Mike creates: fine-grained, repos assembly-line + api + web; Contents rw, Pull requests rw, Issues rw, Workflows rw, Metadata read). Variables `STAGING_WEB_URL`, `PRODUCTION_WEB_URL` are already set on the harness repo (2026-09-11).
- Idempotent steps: a rerun with the same inputs skips what is done. Nothing merges without the required checks green (`ci` on develop PRs; `ci` and `promote` on main PRs), and every merge passes the inspected head SHA (`gh pr merge --match-head-commit`).
- Dry run performs every read and check and prints every write as `dry-run: would …`.
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Prettier formats YAML and markdown here (`frontend/node_modules/.bin/prettier --write` from the workspace, or `npm run format` after `npm ci` in the harness).

---

### Task 1: `ship.yml` and its two scripts

**Files:**
- Create: `.github/workflows/ship.yml`
- Create: `scripts/ship/lib.sh`
- Create: `scripts/ship/cut-release.sh`
- Modify: `docs/runbook.md` (Ship section: the workflow replaces the manual sequence; the manual sequence moves to an appendix), `docs/cicd-log.md` (one row), `README.md` (layout table: `scripts/ship/`)

**Interfaces:**
- Produces: `POST /repos/kpnemo/kaizen-tasks-assembly-line/actions/workflows/ship.yml/dispatches` with `{ ref: "develop", inputs: { request_id, version, issues, dry_run } }`; runs named `ship <request_id> <version>`; step names as listed below; ship marker comment `<!-- kaizen-ship {…} -->` on each issue.

- [ ] **Step 1: The helper library**

`scripts/ship/lib.sh`:

```bash
#!/usr/bin/env bash
# Helpers for .github/workflows/ship.yml. Sourced by every step; reads GH_TOKEN (SHIP_TOKEN),
# DRY_RUN, HARNESS, API_REPO, WEB_REPO, STAGING_WEB_URL, PRODUCTION_WEB_URL, RUN_URL from the env.
set -euo pipefail

TRAILER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"

step() { echo "STEP=$1" >> "$GITHUB_ENV"; echo "::group::$1"; }
endstep() { echo "::endgroup::"; }
dry() { [[ "${DRY_RUN:-false}" == "true" ]]; }
# run "<what>" -- <command...>: in dry-run prints the intent; otherwise prints it and executes.
run() { local what="$1"; shift; [[ "${1:-}" == "--" ]] && shift; if dry; then echo "dry-run: would $what"; else echo "$what"; "$@"; fi; }
fail() { echo "::error::$*" >&2; exit 1; }

# --- GitHub reads ---------------------------------------------------------------------------
head_of() { gh api "repos/$1/commits/$2" --jq .sha; }                       # repo branch
version_on() { gh api "repos/$1/contents/package.json?ref=$2" --jq .content | base64 -d | jq -r .version; }
issue_labels() { gh issue view "$1" --repo "$HARNESS" --json labels --jq '[.labels[].name]|join(",")'; }
has_label() { case ",$(issue_labels "$1")," in *",$2,"*) return 0;; *) return 1;; esac; }
# Open feat/<n>- or fix/<n>- pull requests for issue <n> in the three repos, as "repo#number" lines.
open_prs_for() {
  local n="$1" repo
  for repo in "$API_REPO" "$WEB_REPO" "$HARNESS"; do
    gh pr list --repo "$repo" --state open --limit 100 --json number,headRefName \
      --jq --arg n "$n" --arg repo "$repo" '.[] | select(.headRefName | test("^(feat|fix)/" + $n + "-")) | "\($repo)#\(.number)"'
  done
}
pr_number() {  # repo head base state -> number or empty
  gh pr list --repo "$1" --head "$2" --base "$3" --state "$4" --limit 1 --json number --jq '.[0].number // empty'
}
pr_head_sha() { gh pr view "$2" --repo "$1" --json headRefOid --jq .headRefOid; }
merge_sha_of_pr() { gh pr view "$2" --repo "$1" --json mergeCommit --jq '.mergeCommit.oid // empty'; }

# --- environment read-backs -------------------------------------------------------------------
api_served() { curl -fsS --max-time 10 "$1/api/v1/health" | jq -r '.data.commit + " " + .data.version'; }   # "<sha> <version>"
web_served() { curl -fsS --max-time 10 -H 'Cache-Control: no-cache' "$1/version.json" | jq -r '.commit + " " + .version'; }

# wait_for <seconds> <interval> "<what>" <command...>: polls until the command succeeds.
wait_for() {
  local limit="$1" every="$2" what="$3"; shift 3
  local deadline=$((SECONDS + limit))
  until "$@"; do
    if (( SECONDS >= deadline )); then fail "timed out after ${limit}s waiting for $what"; fi
    echo "waiting for $what …"; sleep "$every"
  done
  echo "ok: $what"
}
serves() {  # serves <api|web> <url> <sha> <version>
  local kind="$1" url="$2" sha="$3" version="$4" got
  got="$("${kind}_served" "$url" 2>/dev/null || true)"
  [[ "$got" == "$sha $version" ]] || [[ "$got" == "${sha:0:7}"* && "$got" == *" $version" ]]
}

# --- semver -----------------------------------------------------------------------------------
semver_gt() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

# --- merging ----------------------------------------------------------------------------------
# merge_when_green <repo> <number> <seconds> <method: merge|squash>: waits for the required checks
# on the current head, then merges exactly that head. Skips a pull request already merged.
merge_when_green() {
  local repo="$1" n="$2" limit="$3" method="$4" state sha
  state="$(gh pr view "$n" --repo "$repo" --json state --jq .state)"
  if [[ "$state" == "MERGED" ]]; then echo "$repo#$n already merged"; return 0; fi
  sha="$(pr_head_sha "$repo" "$n")"
  if dry; then echo "dry-run: would wait for checks on $repo#$n ($sha) and merge with --$method"; return 0; fi
  timeout "$limit" gh pr checks "$n" --repo "$repo" --watch --fail-fast --required
  gh pr merge "$n" --repo "$repo" "--$method" --match-head-commit "$sha"
}

# --- issue comments ---------------------------------------------------------------------------
comment() { run "comment on #$1: ${2:0:80}…" -- gh issue comment "$1" --repo "$HARNESS" --body "$2"; }
marker_of() {  # marker_of <issue> -> the JSON of the newest kaizen-ship marker, or empty
  gh api "repos/$HARNESS/issues/$1/comments" --paginate --jq '.[] | .body' \
    | grep -o '<!-- kaizen-ship {.*} -->' | tail -1 | sed -E 's/^<!-- kaizen-ship (\{.*\}) -->$/\1/'
}
```

- [ ] **Step 2: The release-cut script**

`scripts/ship/cut-release.sh`:

```bash
#!/usr/bin/env bash
# cut-release.sh <dir> <repo> <version>: the release commit in one app repo checkout, on branch
# release/<version>, pushed and opened as a pull request to develop. Idempotent: develop already
# at <version> → nothing; release/<version> already pushed → verified and reused.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
dir="$1"; repo="$2"; version="$3"
cd "$dir"
git config user.name "kaizen-ship"
git config user.email "kaizen-ship@users.noreply.github.com"

current="$(jq -r .version package.json)"
if [[ "$current" == "$version" ]]; then echo "$repo develop is already at $version"; exit 0; fi
semver_gt "$version" "$current" || fail "$repo: $version is not greater than $current"

branch="release/$version"
if git fetch origin "$branch" 2>/dev/null; then
  count="$(git rev-list --count "origin/develop..origin/$branch")"
  files="$(git diff --name-only "origin/develop..origin/$branch" | sort | tr '\n' ' ')"
  case "$files" in
    *"CHANGELOG.md"*"package.json"*) ;;
    *) fail "$repo: $branch exists with unexpected files: $files" ;;
  esac
  [[ "$count" == "1" ]] || fail "$repo: $branch has $count commits over develop, expected 1"
  echo "$repo: reusing $branch ($files)"
else
  git switch -c "$branch"
  node - "$version" <<'JS'
const fs = require("fs");
const version = process.argv[2];
const date = new Date().toISOString().slice(0, 10);
const path = "CHANGELOG.md";
let s = fs.readFileSync(path, "utf8");
const head = "## [Unreleased]\n\n";
if (!s.includes(head)) { console.error("no [Unreleased] heading"); process.exit(1); }
if (!s.includes(`## [${version}]`)) s = s.replace(head, `${head}## [${version}] - ${date}\n\n`);
fs.writeFileSync(path, s);
JS
  npm version --no-git-tag-version "$version" >/dev/null
  npm run product-map >/dev/null
  npx prettier --write CHANGELOG.md >/dev/null
  npm run lint >/dev/null
  git add -A
  git commit -q -m "chore: release $version" -m "$TRAILER"
  run "push $repo $branch" -- git push -u origin "$branch"
fi

if ! dry; then
  n="$(pr_number "$repo" "$branch" develop open)"
  if [[ -z "$n" ]] && [[ -z "$(pr_number "$repo" "$branch" develop merged)" ]]; then
    gh pr create --repo "$repo" --base develop --head "$branch" --title "chore: release $version" --body "Cut $version (ship $REQUEST_ID)." >/dev/null
  fi
  echo "$repo release PR: #$(pr_number "$repo" "$branch" develop open || true)"
else
  echo "dry-run: would open $repo pull request $branch → develop"
fi
```

- [ ] **Step 3: The workflow**

`.github/workflows/ship.yml`:

```yaml
name: ship

# One press of "Deploy to production" (or one dispatch by hand): cut the release in both app repos,
# merge the release pull requests when ci is green, wait for staging, open and merge the
# promotion pull requests when ci and promote are green (api first), read production back by
# merge SHA, then close every issue in the set as shipped. Every step is idempotent, so a rerun
# with the same inputs resumes; the version and the issue set are recorded on the issues first, and
# a rerun trusts that record over its inputs. Runs in this repo on purpose: Railway's wait-for-CI
# holds an app deploy until every check suite on the app commit has finished, and a workflow that
# waits for a deploy must never be one of those suites (docs/cicd-log.md, 2026-09-10).
on:
  workflow_dispatch:
    inputs:
      request_id:
        description: Correlation id (a UUID from the API, or any short unique string by hand)
        required: true
        type: string
      version:
        description: Release version for both repos, e.g. 1.4.0
        required: true
        type: string
      issues:
        description: Comma-separated harness issue numbers that are on staging
        required: true
        type: string
      dry_run:
        description: Read and check everything, write nothing
        required: false
        type: boolean
        default: false

run-name: ship ${{ inputs.request_id }} ${{ inputs.version }}

concurrency:
  group: ship
  cancel-in-progress: false

permissions:
  contents: read

env:
  HARNESS: kpnemo/kaizen-tasks-assembly-line
  API_REPO: kpnemo/kaizen-tasks-api
  WEB_REPO: kpnemo/kaizen-tasks-web
  STAGING_WEB_URL: ${{ vars.STAGING_WEB_URL }}
  PRODUCTION_WEB_URL: ${{ vars.PRODUCTION_WEB_URL }}
  GH_TOKEN: ${{ secrets.SHIP_TOKEN }}
  REQUEST_ID: ${{ inputs.request_id }}
  VERSION: ${{ inputs.version }}
  ISSUES: ${{ inputs.issues }}
  DRY_RUN: ${{ inputs.dry_run }}
  RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}

jobs:
  ship:
    name: ship
    runs-on: ubuntu-latest
    timeout-minutes: 90
    steps:
      - uses: actions/checkout@v5
        with:
          token: ${{ github.token }}

      - name: Validate the inputs
        run: |
          . scripts/ship/lib.sh; step "Validate the inputs"
          [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be X.Y.Z"
          [[ "$ISSUES" =~ ^[0-9]+(,[0-9]+)*$ ]] || fail "issues must be comma-separated numbers"
          [[ "$REQUEST_ID" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || fail "request_id must be a short id"
          [[ -n "${GH_TOKEN:-}" ]] || fail "the SHIP_TOKEN secret is not set"
          [[ -n "$STAGING_WEB_URL" && -n "$PRODUCTION_WEB_URL" ]] || fail "STAGING_WEB_URL and PRODUCTION_WEB_URL variables are required"
          gh api user --jq '"token user: " + .login'
          endstep

      - name: Record the ship on the issues
        run: |
          . scripts/ship/lib.sh; step "Record the ship on the issues"
          started="$(date -u +%FT%TZ)"
          issues_json="[$(tr ',' ' ' <<<"$ISSUES" | xargs -n1 | paste -sd, -)]"
          for n in ${ISSUES//,/ }; do
            existing="$(marker_of "$n" || true)"
            if [[ -n "$existing" ]] && [[ "$(jq -r .requestId <<<"$existing")" == "$REQUEST_ID" ]]; then
              echo "#$n already carries the marker for $REQUEST_ID"; continue
            fi
            if [[ -n "$existing" ]] && [[ "$(jq -r .version <<<"$existing")" != "$VERSION" ]] && [[ "$(jq -r '.done // false' <<<"$existing")" != "true" ]]; then
              fail "#$n carries an unfinished ship for $(jq -r .version <<<"$existing") ($(jq -r .requestId <<<"$existing")); retry that one first"
            fi
            marker="$(jq -cn --arg v "$VERSION" --arg r "$REQUEST_ID" --arg s "$started" --arg u "$RUN_URL" --argjson i "$issues_json" '{version:$v,requestId:$r,startedAt:$s,runUrl:$u,issues:$i}')"
            comment "$n" "<!-- kaizen-ship $marker -->
Ship started: version $VERSION for issues $ISSUES. Run: $RUN_URL"
          done
          endstep

      - name: Preflight
        run: |
          . scripts/ship/lib.sh; step "Preflight"
          for n in ${ISSUES//,/ }; do
            has_label "$n" staging || fail "#$n is not labelled staging"
            open="$(open_prs_for "$n" | paste -sd' ' -)"
            [[ -z "$open" ]] || fail "#$n still has open pull requests: $open"
          done
          api_dev="$(head_of "$API_REPO" develop)"; web_dev="$(head_of "$WEB_REPO" develop)"
          api_cur="$(version_on "$API_REPO" develop)"; web_cur="$(version_on "$WEB_REPO" develop)"
          echo "develop: api $api_cur ${api_dev:0:7}, web $web_cur ${web_dev:0:7}; target $VERSION"
          if [[ "$api_cur" != "$web_cur" ]]; then
            [[ "$api_cur" == "$VERSION" || "$web_cur" == "$VERSION" ]] || fail "develop versions differ ($api_cur vs $web_cur) and neither is $VERSION: fix by hand"
            echo "one repo already released $VERSION: resuming"
          fi
          for cur in "$api_cur" "$web_cur"; do [[ "$cur" == "$VERSION" ]] || semver_gt "$VERSION" "$cur" || fail "$VERSION is not greater than $cur"; done
          # Staging must serve develop's heads, or a promotion pull request opened later would wait
          # on staging while Railway's wait-for-CI waits on it (the 2026-09-10 deadlock class).
          [[ "$api_cur" == "$VERSION" ]] || serves api "$STAGING_WEB_URL" "$api_dev" "$api_cur" || fail "staging api does not serve develop ($(api_served "$STAGING_WEB_URL" || echo unreachable))"
          [[ "$web_cur" == "$VERSION" ]] || serves web "$STAGING_WEB_URL" "$web_dev" "$web_cur" || fail "staging web does not serve develop ($(web_served "$STAGING_WEB_URL" || echo unreachable))"
          endstep

      - name: Check out the app repos
        uses: actions/checkout@v5
        with:
          repository: kpnemo/kaizen-tasks-api
          ref: develop
          token: ${{ secrets.SHIP_TOKEN }}
          path: api
          fetch-depth: 0
      - uses: actions/checkout@v5
        with:
          repository: kpnemo/kaizen-tasks-web
          ref: develop
          token: ${{ secrets.SHIP_TOKEN }}
          path: web
          fetch-depth: 0
      - uses: actions/setup-node@v5
        with:
          node-version-file: api/.nvmrc

      - name: Cut release in api
        run: |
          . scripts/ship/lib.sh; step "Cut release in api"
          (cd api && npm ci --no-audit --no-fund >/dev/null)
          bash scripts/ship/cut-release.sh api "$API_REPO" "$VERSION"
          endstep

      - name: Cut release in web
        run: |
          . scripts/ship/lib.sh; step "Cut release in web"
          (cd web && npm ci --no-audit --no-fund >/dev/null)
          bash scripts/ship/cut-release.sh web "$WEB_REPO" "$VERSION"
          endstep

      - name: Merge the release pull requests
        run: |
          . scripts/ship/lib.sh; step "Merge the release pull requests"
          for repo in "$API_REPO" "$WEB_REPO"; do
            if [[ "$(version_on "$repo" develop)" == "$VERSION" ]]; then echo "$repo develop already at $VERSION"; continue; fi
            n="$(pr_number "$repo" "release/$VERSION" develop open)"
            if [[ -z "$n" ]]; then dry && { echo "dry-run: no release PR yet in $repo"; continue; } || fail "no open release PR in $repo"; fi
            merge_when_green "$repo" "$n" 900 merge
          done
          endstep

      - name: Wait for staging to serve the release
        run: |
          . scripts/ship/lib.sh; step "Wait for staging to serve the release"
          dry && { echo "dry-run: would wait for staging to serve $VERSION"; exit 0; }
          api_dev="$(head_of "$API_REPO" develop)"; web_dev="$(head_of "$WEB_REPO" develop)"
          wait_for 900 15 "staging api $VERSION (${api_dev:0:7})" serves api "$STAGING_WEB_URL" "$api_dev" "$VERSION"
          wait_for 900 15 "staging web $VERSION (${web_dev:0:7})" serves web "$STAGING_WEB_URL" "$web_dev" "$VERSION"
          endstep

      - name: Open the promotion pull requests
        run: |
          . scripts/ship/lib.sh; step "Open the promotion pull requests"
          for repo in "$API_REPO" "$WEB_REPO"; do
            if [[ "$(version_on "$repo" main)" == "$VERSION" ]]; then echo "$repo main already at $VERSION"; continue; fi
            if [[ -n "$(pr_number "$repo" develop main open)" ]]; then echo "$repo promotion PR already open"; continue; fi
            run "open $repo promotion PR develop → main" -- gh pr create --repo "$repo" --base main --head develop --title "release: $VERSION" --body "Promote develop to main (ship $REQUEST_ID)."
          done
          endstep

      - name: Promote api
        run: |
          . scripts/ship/lib.sh; step "Promote api"
          if [[ "$(version_on "$API_REPO" main)" != "$VERSION" ]]; then
            n="$(pr_number "$API_REPO" develop main open)"; [[ -n "$n" ]] || { dry && exit 0 || fail "no api promotion PR"; }
            merge_when_green "$API_REPO" "$n" 1800 merge
          fi
          dry && exit 0
          main_sha="$(head_of "$API_REPO" main)"
          wait_for 900 15 "production api $VERSION (${main_sha:0:7})" serves api "$PRODUCTION_WEB_URL" "$main_sha" "$VERSION"
          echo "API_MAIN_SHA=$main_sha" >> "$GITHUB_ENV"
          endstep

      - name: Promote web
        run: |
          . scripts/ship/lib.sh; step "Promote web"
          if [[ "$(version_on "$WEB_REPO" main)" != "$VERSION" ]]; then
            n="$(pr_number "$WEB_REPO" develop main open)"; [[ -n "$n" ]] || { dry && exit 0 || fail "no web promotion PR"; }
            merge_when_green "$WEB_REPO" "$n" 1800 merge
          fi
          dry && exit 0
          main_sha="$(head_of "$WEB_REPO" main)"
          wait_for 900 15 "production web $VERSION (${main_sha:0:7})" serves web "$PRODUCTION_WEB_URL" "$main_sha" "$VERSION"
          echo "WEB_MAIN_SHA=$main_sha" >> "$GITHUB_ENV"
          endstep

      - name: Close the issues as shipped
        run: |
          . scripts/ship/lib.sh; step "Close the issues as shipped"
          for n in ${ISSUES//,/ }; do
            if [[ "$(gh issue view "$n" --repo "$HARNESS" --json state --jq .state)" == "CLOSED" ]] && has_label "$n" shipped; then echo "#$n already shipped"; continue; fi
            run "label #$n shipped" -- gh issue edit "$n" --repo "$HARNESS" --add-label shipped
            run "close #$n" -- gh issue close "$n" --repo "$HARNESS" --reason completed \
              --comment "Shipped in api $VERSION (${API_MAIN_SHA:0:7}) and web $VERSION (${WEB_MAIN_SHA:0:7}): $PRODUCTION_WEB_URL"
          done
          endstep

      - name: Bookkeeping (board rows, ship complete)
        continue-on-error: true
        run: |
          . scripts/ship/lib.sh; step "Bookkeeping"
          board="$(gh issue list --repo "$HARNESS" --label triage-board --state open --json number --jq '.[0].number // empty')"
          if [[ -n "$board" ]]; then
            gh issue view "$board" --repo "$HARNESS" --json body --jq .body > board.md
            for n in ${ISSUES//,/ }; do sed -i -E "/^\| [0-9]+ +\| #$n +\|/ s/\| (triaged|implementing|staging) +\|\$/| shipped |/" board.md; done
            run "flip the board rows to shipped" -- gh issue edit "$board" --repo "$HARNESS" --body-file board.md
          fi
          for n in ${ISSUES//,/ }; do comment "$n" "<!-- kaizen-ship $(jq -cn --arg v "$VERSION" --arg r "$REQUEST_ID" --arg u "$RUN_URL" '{version:$v,requestId:$r,runUrl:$u,done:true}') -->
Ship complete: $RUN_URL"; done
          endstep

      - name: Report a failed or cancelled ship
        if: ${{ !success() }}
        run: |
          . scripts/ship/lib.sh
          for n in ${ISSUES//,/ }; do comment "$n" "Ship failed at \"${STEP:-start}\" (${{ job.status }}): $RUN_URL. Rerun with the same inputs to resume."; done
```

- [ ] **Step 4: Parse and lint**

From the workspace root: `node -e 'require("./frontend/node_modules/js-yaml").load(require("fs").readFileSync(".github/workflows/ship.yml","utf8")); console.log("ship.yml parses")'`, `bash -n scripts/ship/lib.sh scripts/ship/cut-release.sh`, and `shellcheck` if installed (`brew list shellcheck`), then `frontend/node_modules/.bin/prettier --write .github/workflows/ship.yml docs/runbook.md docs/cicd-log.md README.md`.

- [ ] **Step 5: Docs**

`docs/runbook.md`, Ship row and command block: the production move is one dispatch of `ship.yml` (from the Actions tab, "Run workflow", inputs `request_id` = anything unique, `version`, `issues`, `dry_run` off) or, once the pipeline page exists, one press of "Deploy to production"; the room watches the run's steps; the previous manual sequence moves under a new heading "Appendix: shipping by hand" unchanged. Pre-session checklist: `SHIP_TOKEN` present (`gh secret list --repo kpnemo/kaizen-tasks-assembly-line`), a `dry_run` of `ship.yml` green in the last day. `docs/cicd-log.md`: one row for the workflow's first dry run and first real run (filled in Task 3). `README.md` layout table: `scripts/ship/` line.

- [ ] **Step 6: Commit, push, pull request**

```bash
git switch -c feat/ship-workflow origin/develop
git add .github/workflows/ship.yml scripts/ship docs/runbook.md docs/cicd-log.md README.md
git commit -m "ci: ship workflow, the production sequence as one dispatch" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/ship-workflow
gh pr create --repo kpnemo/kaizen-tasks-assembly-line --base develop --head feat/ship-workflow --title "ci: ship workflow" --body-file <tempfile>
```

The PR body: what it does, the step list, the idempotency rules, the token Mike must create (exact permissions), and the two rehearsals in Task 3.

---

### Task 2: Token probe

**Files:**
- Create: `scripts/ship/probe.sh`

A script Mike (or the agent, with `GH_TOKEN` set to the new token) runs once after creating `SHIP_TOKEN`: it calls every write the workflow needs on disposable objects and prints which one is denied: read the harness issue list; create and delete a comment on the Triage board issue; in each app repo push a branch `probe/ship-token` from `develop` and delete it (`git push origin :probe/ship-token`); open and close a draft pull request from it; read check runs; dispatch `ship.yml` with `dry_run: true`. Exits non-zero on the first denial with the permission to add.

- [ ] **Step 1: Write `scripts/ship/probe.sh`** with those calls, each wrapped as `probe "<what>" <command>` printing `ok` or `DENIED (<permission needed>)`.
- [ ] **Step 2: Run it locally** with `GH_TOKEN=<the new token> bash scripts/ship/probe.sh`; fix the token until every line is `ok`. Commit the script on `feat/ship-workflow` before the PR merges.

---

### Task 3: Rehearsals

- [ ] **Step 1: Dry run.** After the PR merges to `develop` and `SHIP_TOKEN` exists: from the Actions tab (or `gh workflow run ship.yml -f request_id=dry-1 -f version=1.4.0 -f issues=22 -f dry_run=true`) once #22 is on staging. Expected: every step green, the log full of `dry-run: would …`, no comment on #22 except none (the marker step is dry too), no branch, no PR.
- [ ] **Step 2: Real run shipping #22.** `gh workflow run ship.yml -f request_id=$(uuidgen) -f version=1.4.0 -f issues=22`. Watch with `gh run watch`. Expected: release PRs merged, staging at 1.4.0, promotion PRs merged api then web, production at 1.4.0 with the merge SHAs, #22 closed with `shipped`, board row flipped, two marker comments on #22 (started, complete). Time it; record the row in `docs/cicd-log.md`.
- [ ] **Step 3: Failure rehearsal.** On a throwaway request: cancel the run after "Merge the release pull requests", confirm the "Ship failed at" comment, rerun with the same inputs and confirm it resumes from "Wait for staging" without a second release commit.

## Self-review

- Spec coverage: marker (step 2), preflight incl. resume rule (3), release cut with branch verification (cut-release.sh), merges with head SHA (`merge_when_green`), staging wait before promotion PRs (deadlock class), api-then-web promotion with merge-SHA read-back, per-issue close, non-fatal bookkeeping, `!success()` reporter, dry run, concurrency, input validation, the probe, the rehearsals.
- Placeholders: none; the PR body content is enumerated in Step 6.
- Consistency: function names in `lib.sh` match their uses in `ship.yml` and `cut-release.sh`; `STEP` is written by `step()` and read by the reporter; `API_MAIN_SHA`/`WEB_MAIN_SHA` are written by the promote steps and read by the close step.
