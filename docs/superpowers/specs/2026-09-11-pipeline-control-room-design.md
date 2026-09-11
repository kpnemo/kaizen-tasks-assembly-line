# Pipeline control room: design

Date: 2026-09-11. Owner: Mike (facilitator). Status: approved in design review, awaiting spec review.

## Why

The workshop's ship half is invisible and manual. After `/implement-issue` opens pull requests, the room cannot see where an issue stands, the move to staging is "press Merge on GitHub", and the move to production is a nine-step sequence the facilitator runs by hand (release cut in two repos, four pull requests, two smoke gates, read-backs, label, close). On 2026-09-10 that sequence took 25 minutes and one deadlock to debug.

This design gives the room one screen inside the product, `/pipeline`, that explains the flow, shows live status per environment and per issue, and carries the only two clicks the facilitator makes after the code is written: **Deploy to staging** and **Deploy to production**. The production click dispatches a GitHub Actions workflow that performs the whole sequence, idempotently, and closes the issue as shipped after the production read-back.

## Decisions taken in the design review (2026-09-11)

| Question | Decision |
| --- | --- |
| Where the control room lives | In the app, a `/pipeline` page. |
| How an issue reaches staging | A "Deploy to staging" button on the page merges its green pull requests. |
| Who sees, who presses | Every signed-in user sees the page; buttons appear only for facilitator accounts, and every press requires a deploy passphrase checked by the API. |
| Release version | Automatic: minor when either repo's `[Unreleased]` has `### Added` or `### Changed`, patch otherwise; same number in both repos; shown on the button. |
| Ship mechanics | A `ship` workflow (`workflow_dispatch`) in the harness repo, dispatched by the API. The API never orchestrates a ship itself. |
| Order of work | The request-page list first (through the assembly line, as issue filed 2026-09-11), then the ship workflow, then the page. |

## Scope

In scope: the `/pipeline` page and its header link; the API endpoints that feed and drive it; the `ship.yml` workflow in the harness repo; configuration and tokens; docs and runbook updates. Out of scope: any change to triage or implement-issue; notifications; rollback from the page (a rollback is a Railway action, documented in the runbook); multi-tenant or multi-project support; anything for the `bug` path beyond showing bug issues in the list.

## Architecture

```
browser (/pipeline) ── /api/v1/pipeline ──▶ API ──▶ GitHub REST (issues, pulls, check-runs, deployments, contents, dispatch)
                                            │  └──▶ staging /api/v1/health, /version.json
                                            │  └──▶ production /api/v1/health, /version.json
                                            └── 10 s cache (Redis)
GitHub Actions: kaizen-tasks-assembly-line/.github/workflows/ship.yml
   release cut (api, web) → release PRs → merge on ci → staging read-back
   → promotion PRs → merge on ci+promote (api, then web) → production read-back
   → issue comment, `shipped`, close, board row
```

The API is the only thing that talks to GitHub or to the other environment, with a token that stays server-side. The browser polls one endpoint. The ship runs in Actions, where the log is public to the room and a Railway redeploy of the API cannot interrupt it. The workflow's own check suite lives on the harness repository, so it can never hold up Railway's wait-for-CI on an app commit (the 2026-09-10 deadlock class).

## The page: `/pipeline`

Route under `RequireAuth` and `AppShell` in `frontend/src/app/router.tsx`; header link "Pipeline" after "Tags" in `frontend/src/app/layout.tsx`, rendered only when health reports `features.pipeline: true` (same pattern as `FeatureRequestLink`). Feature folder `frontend/src/features/pipeline/`. All controls follow `docs/ui-conventions.md`; the page follows the projector rules (18 px base, 44 px targets, both themes).

Blocks, top to bottom:

1. **How it flows.** An inline SVG diagram with eight nodes: Request → Triage → Implement → Pull requests → Develop → Staging → Production → Shipped. Under each node one line: who or what does it (person, `/triage-requests`, `/implement-issue`, reviewers, Railway, `staging-label`, `ship`, lifecycle workflow). The two facilitator clicks are marked on the Develop and Production arrows. Static content, no data.
2. **Environments.** Two `Card`s, "Staging" and "Production". Each: API version and short commit, web version and short commit, db and redis checks, the last deploy time, and a line "matches develop" / "matches main" or "behind develop by N commits". Data from the API's environment read-backs and branch heads.
3. **Issues.** A table of feature-request and bug issues: open ones first, then issues shipped in the last 14 days. Columns: number and title (link to GitHub), stage chip (New, Triaged, Implementing, Staging, Shipped), readiness (from `clarity`/`complexity`/`risk` labels through the rubric formula, blank when unlabelled), pull requests (one `Badge` per PR: repo short name, number, state: checks pending / green / red / merged), and Action. The Action cell shows exactly one of:
   - `Button` "Deploy to staging" when stage is Implementing, at least one PR is open, and every open PR has green checks and no failing check;
   - `Button` "Deploy <version> to production" when stage is Staging and no ship run is active;
   - a `Badge` "Shipping: <step name>" linking to the Actions run while a ship is active for this issue;
   - a `Badge` "Ship failed at <step>" linking to the run, plus the production button again (rerun), when the last ship run for this issue failed;
   - nothing otherwise, with a muted hint when a PR is red ("a check is red") or pending ("checks running").
   Buttons render only when `canDeploy` is true for the caller.
4. **Passphrase dialog.** An `alert-dialog` shared by both buttons: title "Deploy #<n> to staging" or "Deploy <version> to production"; one paragraph saying what will happen (which PRs merge; or release, promote, and close); a `Field` "Deploy passphrase" (`type="password"`, autocomplete off); Cancel and the verb button ("Deploy to staging" / "Deploy to production"). A wrong passphrase shows the field error "Wrong passphrase"; a lockout shows "Too many attempts, try again in N minutes". Success closes the dialog and the row updates on the next poll.

Screen states: loading (`role="status"` "Loading pipeline"), error (`role="alert"` with the envelope message), empty issues ("No requests yet"), content. The page refetches every 10 seconds while mounted (TanStack Query `refetchInterval`), the interval the task list already uses while the assistant works.

Looks: the diagram uses the brand accent for the two click arrows and muted strokes elsewhere; stage chips use the `Badge` variants (default for Shipped, secondary for Staging, outline for Implementing, ghost for New/Triaged); PR badges carry a lucide icon per state (`CircleDashed` pending, `CircleCheck` green, `CircleX` red, `GitMerge` merged). Both themes captured by `scripts/screenshot.mjs pipeline`.

## The API

All under `/api/v1`, all behind the session, all mounted only when the pipeline feature is on (below). Envelopes as everywhere: `{ data, meta }` and `{ error: { code, message, details, requestId } }`.

### `GET /pipeline`

Returns one snapshot, served from a 10-second Redis cache (key `pipeline:snapshot`) so a room of open tabs costs one GitHub round trip per refresh:

```json
{
  "data": {
    "generatedAt": "2026-09-11T08:00:00Z",
    "canDeploy": true,
    "nextVersion": "1.4.0",
    "environments": {
      "staging":    { "api": { "version": "1.3.0", "commit": "c4ec3f4", "db": "ok", "redis": "ok" }, "web": { "version": "1.3.0", "commit": "e9b52c8" }, "deployedAt": "…", "matchesBranch": true, "behindBy": 0 },
      "production": { "api": { … }, "web": { … }, "deployedAt": "…", "matchesBranch": true, "behindBy": 0 }
    },
    "branches": { "api": { "develop": "c4ec3f4", "main": "a1774e5" }, "web": { "develop": "e9b52c8", "main": "33272c5" } },
    "issues": [
      { "number": 19, "title": "…", "kind": "feature-request", "state": "open", "stage": "staging", "readiness": 17,
        "url": "…", "labels": ["…"],
        "pullRequests": [ { "repo": "web", "number": 15, "url": "…", "state": "merged", "checks": "green" } ],
        "ship": { "runId": 123, "url": "…", "status": "in_progress", "step": "Wait for promote on api", "version": "1.4.0" } }
    ]
  }
}
```

Sources: harness issues with label `feature-request` or `bug` (`state=all`, sorted, capped at 100, shipped ones kept only when closed within 14 days); for each open issue the pull requests found through the issue's timeline cross-references and the branch name `feat/<n>-*` / `fix/<n>-*` in both app repos, each with its combined check-runs conclusion; branch heads from `GET /repos/{repo}/commits/{branch}`; environment read-backs by server-side `fetch` of `STAGING_WEB_URL` and `PRODUCTION_WEB_URL` (`/api/v1/health`, `/version.json`, 5 s timeout, a failed read becomes `"unreachable"` rather than an error); the active or last ship run per issue from the harness `ship.yml` runs (`workflow_dispatch` inputs are read from the run's `display_title`, which the workflow sets to `ship #<n> <version>`); `nextVersion` from both repos' `package.json` and `CHANGELOG.md` on `develop` (contents API): minor when either `[Unreleased]` contains `### Added` or `### Changed` with at least one bullet, else patch, from the higher of the two current versions (they are equal by rule). `canDeploy` is true when the caller's email is in `FACILITATOR_EMAILS`.

Stage derivation, in order: `shipped` label → `shipped`; `staging` → `staging`; `implementing` → `implementing`; `triaged` → `triaged`; otherwise `new`. A closed issue without `shipped` is shown as `closed` and never carries an action.

### `POST /pipeline/issues/{number}/deploy-staging`

Body `{ "passphrase": string }`. Guards, in order: caller allowlisted (else `FORBIDDEN`); passphrase equals `DEPLOY_PASSPHRASE` by constant-time comparison (else `FORBIDDEN` with `details.reason: "passphrase"`, counted toward the lockout); lockout: five failures per user in ten minutes → `RATE_LIMITED` (reuse `src/lib/rate-limit.ts`, key `pipeline:passphrase:<userId>`). Then: recompute the issue's open pull requests fresh (no cache); if any has non-green checks → `CONFLICT` naming it; otherwise merge each with `PUT /repos/{repo}/pulls/{n}/merge` (`merge_method: squash`), API repo first, and return `{ data: { merged: [ { repo, number, sha } ] } }`. Merging is idempotent: an already-merged PR is skipped. The staging label, comment and board row follow from the existing `staging-label` workflow; this endpoint does not touch labels.

### `POST /pipeline/issues/{number}/ship`

Same guards. Then: refuse with `CONFLICT` when the issue's stage is not `staging`, when any pull request for it is still open, or when a ship run is already active for any issue (one ship at a time, the workflow enforces it too). Compute `nextVersion` fresh, dispatch `POST /repos/kpnemo/kaizen-tasks-assembly-line/actions/workflows/ship.yml/dispatches` with `{ ref: "develop", inputs: { issue, version } }`, then poll the runs list for up to 15 s to find the new run (match `display_title`), and return `{ data: { runId, url, version } }`. The snapshot cache is invalidated on both POSTs.

### Configuration and the feature flag

New settings in `backend/src/config.ts`: `PIPELINE_GITHUB_TOKEN` (falls back to `GITHUB_TOKEN`), `FACILITATOR_EMAILS` (comma-separated, lower-cased on load), `DEPLOY_PASSPHRASE` (min 12 chars), `STAGING_WEB_URL`, `PRODUCTION_WEB_URL`. The three repositories are constants in code, not settings. The feature is on, and `features.pipeline` in `/health` is true, exactly when the token, the passphrase, both URLs and a non-empty allowlist are present. When off, the routes are not mounted and the web hides the link and the route (a direct visit shows the not-found page).

The GitHub port already used by feature requests (`backend/src/app.ts`, injected in tests) grows the calls this needs: list issues, issue timeline, list pulls by head, combined check runs for a ref, get branch head, get file contents, merge pull, dispatch workflow, list workflow runs. Tests inject a fake port; no test reaches GitHub.

## The ship workflow: `.github/workflows/ship.yml` (harness repo)

`on: workflow_dispatch` with inputs `issue` (number), `version` (semver), `dry_run` (boolean, default false). `concurrency: { group: ship, cancel-in-progress: false }` so ships queue rather than overlap. `run-name: ship #${{ inputs.issue }} ${{ inputs.version }}` so the API can find the run. Secret `SHIP_TOKEN` for every cross-repo write; `github.token` for nothing but reading this repo.

Steps, each a named step so the page can show "Shipping: <step name>", each idempotent so a rerun after a failure resumes:

1. **Preflight**: read the issue; require label `staging`, no open `feat/`/`fix/` PR referencing it in either app repo; require both `develop` heads served by staging (health and `version.json`); require both repos at the same current version; require `inputs.version` greater than it. Fail with a clear message otherwise.
2. **Cut release in api** (skip when `develop` already carries `inputs.version`): checkout `kpnemo/kaizen-tasks-api@develop` with `SHIP_TOKEN`, Node from `.nvmrc`, `npm ci`, move `[Unreleased]` under `## [<version>] - <today UTC>` in `CHANGELOG.md`, `npm version --no-git-tag-version <version>`, `npm run product-map`, `npm run lint`, commit `chore: release <version>` with the trailer, push `release/<version>` (reuse if it exists), open the PR to `develop` (reuse if open).
3. **Cut release in web**: the same for `kpnemo/kaizen-tasks-web`.
4. **Merge release PRs**: wait for `ci` on each (up to 15 min), merge (`merge`), api then web. Skip a PR already merged.
5. **Wait for staging** to serve both new `develop` heads at `inputs.version` (up to 15 min). This is the read-back the runbook requires before a promotion PR opens, and it keeps `promote` clear of the wait-for-CI deadlock class.
6. **Open promotion PRs** `develop → main` in both repos (reuse if open), titled `release: <version>`.
7. **Promote api**: wait for `ci` and `promote` (up to 30 min), merge, wait for production health to report `<version>`.
8. **Promote web**: the same, then wait for production `version.json` to report `<version>`.
9. **Close the issue**: comment `Shipped in api <version> (<sha>) and web <version> (<sha>): <production url>`, add `shipped`, close as completed, flip the Triage board row to `shipped` (one cell, as `implement-issue` does), and comment `Ship complete` with the run URL. The existing `issue-lifecycle` workflow retires `implementing` and `staging`.

On any failure the workflow's last step (`if: failure()`) comments `Ship failed at "<step>": <run url>` on the issue and exits non-zero; the page shows the same and offers the production button again, which reruns from step 1 and skips what is done. With `dry_run: true` every step performs its reads and checks and prints what it would do, but pushes, merges, comments and labels are skipped; the rehearsal runs it once for real on a throwaway issue.

The merge policy stays honest with the repo rules: the buttons are the facilitator's merge, authenticated twice (account and passphrase); nothing merges without a person pressing.

## Security

- Tokens never leave the API or Actions. The browser sees `canDeploy` and nothing about credentials.
- Both POSTs require the session, the allowlist and the passphrase; the passphrase is compared with `crypto.timingSafeEqual` on equal-length buffers and never logged; failures are rate-limited per user; successes are logged with user id, issue and action.
- `GET /pipeline` exposes nothing a signed-in user could not read on GitHub; the harness and app repos are public.
- The ship workflow reads `inputs.version` as data and validates it against semver and against the current version before use; the issue number is validated as an integer that carries the `staging` label.

## Tokens and settings Mike provides

Fine-grained personal access tokens (Settings → Developer settings → Fine-grained tokens), expiry after the workshop:

| Token | Repositories | Permissions | Set where |
| --- | --- | --- | --- |
| `PIPELINE_GITHUB_TOKEN` (API) | kaizen-tasks-assembly-line, kaizen-tasks-api, kaizen-tasks-web | Issues: read and write (harness); Pull requests: read and write (app repos); Checks: read; Actions: read and write (harness, for dispatch); Contents: read; Deployments: read; Metadata: read | Railway variables on `api`, staging and production |
| `SHIP_TOKEN` (workflow) | the same three | Contents: read and write (app repos); Pull requests: read and write (app repos); Issues: read and write (harness); Workflows: read and write (app repos; GitHub refuses a push that touches `.github/workflows/` without it, and a release commit can carry such a change); Metadata: read | GitHub secret on the harness repo |

Also on the API in both Railway environments: `FACILITATOR_EMAILS`, `DEPLOY_PASSPHRASE`, `STAGING_WEB_URL=https://web-staging-52c0.up.railway.app`, `PRODUCTION_WEB_URL=https://web-production-7ef71.up.railway.app`. The existing `ASSEMBLY_LINE_TOKEN` in the app repos is untouched.

## Error handling summary

| Failure | What the room sees |
| --- | --- |
| GitHub rate limit or outage | Environments still render from the last cached snapshot with "GitHub unreachable, showing HH:MM:SS"; buttons disabled. |
| Staging or production unreachable | That card shows "unreachable"; nothing else changes. |
| Wrong passphrase | Field error; after five, "Too many attempts". |
| A PR turns red between poll and press | `CONFLICT` naming the PR; the row shows the red badge. |
| Ship fails mid-way | Badge "Ship failed at <step>" with the run link; issue comment; the button reruns idempotently. |
| Two facilitators press Ship | Second gets `CONFLICT` "a ship is already running"; the workflow's concurrency group is the backstop. |

## Testing

- API: integration tests with the fake GitHub port for the snapshot (stage derivation, PR aggregation, `nextVersion` rule, cache), for both POSTs (allowlist, passphrase, lockout, conflict cases, merge order, dispatch payload), and for the feature flag (routes absent when settings are missing). No network.
- Web: component tests with MSW for the four screen states, viewer versus facilitator rendering, each Action variant, the dialog's error states, and the header link toggling on the health flag. Screenshots in both themes.
- Workflow: `dry_run: true` run from the Actions tab against issue #19's successor; one real rehearsal on a throwaway request before the session; `actionlint` in the harness `ci` if it is easy to add, otherwise a YAML parse test.
- Runbook: the Ship segment becomes "press Deploy to production, narrate the run", with the manual sequence kept in an appendix as the fallback.

## Sequencing

1. Request-page list (issue filed 2026-09-11 in the harness repo) through `/triage-requests` and `/implement-issue`: it adds `GET /feature-requests`, which the pipeline reuses for issue listing.
2. `ship.yml` in the harness repo, dry-run tested, then a real run shipping item 1 to production.
3. API: config, port calls, `GET /pipeline`, the two POSTs, health flag.
4. Web: the page, the link, the dialog, screenshots.
5. Runbook and playbook updates; rehearsal.

Each of 2, 3 and 4 is its own plan and its own pull requests, API before web as always.

## Open risks

- Fine-grained token scoping is easy to get slightly wrong; the plan's first task in each repo is a probe script that calls every GitHub endpoint the feature needs and prints which one is denied.
- GitHub's check-runs API can lag a merge by a minute; the page shows "checks running" rather than a stale red or green, and the POST recomputes fresh.
- A ship that fails after the API release merged but before the web one leaves the versions unequal on `develop` for the duration; the rerun completes the web cut. The Environments block shows the mismatch honestly meanwhile.
