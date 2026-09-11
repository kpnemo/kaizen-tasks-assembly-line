# Pipeline control room: design

Date: 2026-09-11. Owner: Mike (facilitator). Status: approved in design review; revised after the Codex review (same day); awaiting Mike's spec read.

## Why

The workshop's ship half is invisible and manual. After `/implement-issue` opens pull requests, the room cannot see where an issue stands, the move to staging is "press Merge on GitHub", and the move to production is a nine-step sequence the facilitator runs by hand (release cut in two repos, four pull requests, two smoke gates, read-backs, label, close). On 2026-09-10 that sequence took 25 minutes and one deadlock to debug.

This design gives the room one screen inside the product, `/pipeline`, that explains the flow, shows live status per environment and per issue, and carries the only two clicks the facilitator makes after the code is written: **Deploy to staging** and **Deploy to production**. The production click dispatches a GitHub Actions workflow that performs the whole sequence, idempotently, and closes the shipped issues after the production read-back.

## Decisions taken in the design review (2026-09-11)

| Question                        | Decision                                                                                                                                                         |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Where the control room lives    | In the app, a `/pipeline` page.                                                                                                                                  |
| How an issue reaches staging    | A "Deploy to staging" button on the page merges its green pull requests (app repos and the harness docs PR).                                                     |
| Who sees, who presses           | Every signed-in user sees the page; buttons appear only for facilitator accounts, and every press requires a deploy passphrase checked by the API.               |
| Release version                 | Automatic: minor when either repo's `[Unreleased]` has `### Added` or `### Changed` bullets, patch otherwise; same number in both repos; shown on the button.     |
| Ship mechanics                  | A `ship` workflow (`workflow_dispatch`) in the harness repo, dispatched by the API. The API never orchestrates a ship itself.                                     |
| What a production ship contains | Everything on `develop`: the button names every issue at stage staging, and the workflow ships and closes all of them together. There is no per-issue isolation. |
| Order of work                   | Issue #22 (request-page list) through the assembly line, then `ship.yml`, then the API, then the page, then runbook and rehearsal.                               |

Codex review (2026-09-11, "sound with changes"): its must-fix items are folded in below and marked **(review)**. Declined or scaled down: allowlisting user ids instead of emails (ids differ per environment; pre-provisioned accounts plus unique emails give the same guarantee), making staging read-only (Mike chose the staging button), dropping the flow diagram (it is the executive visual Mike asked for).

## Scope

In scope: the `/pipeline` page and its header link; the API endpoints that feed and drive it; `ship.yml` in the harness repo; configuration and tokens; runbook and playbook updates. Out of scope: any change to triage or implement-issue; notifications; rollback from the page (a rollback is a Railway action, documented in the runbook); multi-project support; anything for the `bug` path beyond showing bug issues in the list. Deferred after the workshop **(review)**: commit-distance counts ("behind by N"), deploy timestamps, a GitHub App instead of personal tokens.

## Architecture

```
browser (/pipeline) ── /api/v1/pipeline ──▶ API ──▶ GitHub REST (issues, pulls, check-runs, compare, contents, dispatch, runs, jobs)
                                            │  └──▶ staging /api/v1/health, /version.json
                                            │  └──▶ production /api/v1/health, /version.json
                                            └── Redis: snapshot cache, last-good snapshot, action lock, lockout counters
GitHub Actions: kaizen-tasks-assembly-line/.github/workflows/ship.yml
   ship state on the issue → release cut (api, web) → release PRs → merge on ci → staging read-back
   → promotion PRs → merge on ci+promote (api, then web) → production read-back by merge SHA
   → per issue: comment, `shipped`, close; board rows (non-fatal)
```

The API is the only thing that talks to GitHub or to the other environment, with tokens that stay server-side. The browser polls one endpoint. The ship runs in Actions, where the log is public to the room and a Railway redeploy of the API cannot interrupt it. The workflow's check suite lives on the harness repository, so it can never hold up Railway's wait-for-CI on an app commit (the 2026-09-10 deadlock class).

## The page: `/pipeline`

Route under `RequireAuth` and `AppShell` in `frontend/src/app/router.tsx`; header link "Pipeline" after "Tags" in `frontend/src/app/layout.tsx`, rendered only when health reports `features.pipeline: true` (same pattern as `FeatureRequestLink`). Feature folder `frontend/src/features/pipeline/`. All controls follow `docs/ui-conventions.md`; the page follows the projector rules (18 px base, 44 px targets, both themes).

Blocks, top to bottom:

1. **How it flows.** An inline SVG diagram with eight nodes: Request → Triage → Implement → Pull requests → Develop → Staging → Production → Shipped. Under each node one line: who or what does it (person, `/triage-requests`, `/implement-issue`, reviewers, Railway, `staging-label`, `ship`, lifecycle workflow). The two facilitator clicks are marked on the Develop and Production arrows. Static content, no data.
2. **Environments.** Two `Card`s, "Staging" and "Production". Each: API version and short commit, web version and short commit, db and redis checks, and one line: "serving develop's head" / "serving main's head", "deploying" when the served commit is behind the branch head, or "unreachable". The snapshot's age is printed once under the cards ("as of 10:42:07"), in the brand colour when fresh and in the destructive colour with "GitHub unreachable" when the API is serving its last-good snapshot **(review)**.
3. **Issues.** A table of feature-request and bug issues: open ones first, then issues shipped in the last 14 days. Columns: number and title (link to GitHub), stage chip (New, Triaged, Implementing, Staging, Shipped), readiness (from `clarity`/`complexity`/`risk` labels through the rubric formula, blank when unlabelled), pull requests (one `Badge` per PR across the three repos: repo short name, number, state: checks pending / green / red / merged), and Action. The Action cell shows exactly one of:
   - `Button` "Deploy to staging" when stage is Implementing, at least one PR is open, every open PR is green (below), and no ship is running;
   - `Button` "Deploy <version> to production" when the issue is production-ready (below) and no ship is running; the same button appears on every ready row, and pressing any of them ships all of them;
   - a `Badge` "Shipping: <step name>" linking to the Actions run while a ship is queued or running;
   - a `Badge` "Ship failed at <step>" linking to the run, plus a "Retry ship <version>" button, when the last ship run failed or was cancelled; the version is the one recorded on the issue, never recomputed;
   - a muted hint otherwise: "checks running", "a check is red", "deploying to staging", "waiting for the other half", "nothing to deploy".
   Buttons render only when `canDeploy` is true for the caller.
4. **Passphrase dialog.** An `alert-dialog` shared by both buttons: title "Deploy #<n> to staging" or "Deploy <version> to production"; a paragraph that says exactly what will happen: the PRs that will merge, or the issues that will ship ("Ships #22 and #23 to production as 1.4.0"); a `Field` "Deploy passphrase" (`type="password"`, autocomplete off); Cancel and the verb button. A wrong passphrase shows the field error "Wrong passphrase"; a lockout shows "Too many attempts, try again at HH:MM"; a conflict shows the API's message ("web #17 moved since you looked, reload"). Success closes the dialog; the row updates on the next poll.

Screen states: loading (`role="status"` "Loading pipeline"), error (`role="alert"` with the envelope message), empty issues ("No requests yet"), content. The page refetches every 10 seconds while mounted (TanStack Query `refetchInterval`), the interval the task list already uses while the assistant works.

Looks: the diagram uses the brand accent for the two click arrows and muted strokes elsewhere; stage chips use the `Badge` variants (default for Shipped, secondary for Staging, outline for Implementing, ghost for New/Triaged); PR badges carry a lucide icon per state (`CircleDashed` pending, `CircleCheck` green, `CircleX` red, `GitMerge` merged). Both themes captured by `scripts/screenshot.mjs pipeline`.

## Definitions the API and the workflow share **(review)**

- **Green PR**: open, not draft, base is the expected branch, `mergeable_state` is not `dirty`/`blocked`, and every required check for that base has a completed successful check run on the current head SHA: `ci` for `develop`, `ci` and `promote` for `main`. A missing required check is *pending*, never green.
- **Merging** always passes the inspected head `sha` to `PUT /repos/{repo}/pulls/{n}/merge`; GitHub's 409 on a moved head becomes `CONFLICT` "moved since you looked".
- **On staging**: the issue's every PR is merged, and for each app repo the merge SHA is an ancestor of the commit staging serves (`GET /repos/{repo}/compare/{served}...{mergeSha}` returns `identical` or `behind`). The `staging` label is a hint, not proof.
- **Production-ready**: on staging, and the issue carries no unfinished ship marker from an earlier run for a different version.
- **Ship marker**: an issue comment `<!-- kaizen-ship {"version":"1.4.0","requestId":"…","startedAt":"…","runUrl":"…","issues":[22,23]} -->` written by the workflow's first step. It is the ship's durable state: reruns read it, the API's retry button shows its version, and the closing step deletes nothing (it appends "Ship complete").
- **Next version**: both repos on `develop` must carry the same `package.json` version, else `CONFLICT` "versions differ, fix by hand"; the bump is minor when either repo's `[Unreleased]` has at least one bullet under `### Added` or `### Changed`, patch when only `### Fixed`, and `CONFLICT` "nothing to release" when both are empty. A repo whose `[Unreleased]` is empty still gets the release commit so the versions stay equal.

## The API

All under `/api/v1`, all behind the session, all mounted only when the pipeline feature is on (below). Envelopes as everywhere: `{ data, meta }` and `{ error: { code, message, details, requestId } }`; `details` is the existing free-form object, so `FORBIDDEN` with `{ "reason": "passphrase" }` needs no schema change beyond documenting the reasons in `openapi.json` **(review)**.

### `GET /pipeline`

Returns one snapshot:

```json
{
  "data": {
    "generatedAt": "2026-09-11T08:00:00Z",
    "stale": false,
    "canDeploy": true,
    "nextVersion": "1.4.0",
    "ship": { "active": false },
    "environments": {
      "staging": { "api": { "version": "1.3.0", "commit": "c4ec3f4", "db": "ok", "redis": "ok" }, "web": { "version": "1.3.0", "commit": "e9b52c8" }, "state": "current" },
      "production": { "api": { "…": "…" }, "web": { "…": "…" }, "state": "current" }
    },
    "branches": { "api": { "develop": "c4ec3f4", "main": "a1774e5" }, "web": { "develop": "e9b52c8", "main": "33272c5" } },
    "issues": [
      { "number": 22, "title": "…", "kind": "feature-request", "state": "open", "stage": "staging", "readiness": 17, "url": "…", "labels": ["…"],
        "pullRequests": [ { "repo": "web", "number": 19, "url": "…", "state": "merged", "checks": "green", "mergeSha": "…" } ],
        "onStaging": true, "productionReady": true,
        "ship": null }
    ]
  }
}
```

Caching **(review)**: the shared part (everything but `canDeploy`) is built by one refresh at a time (Redis `SET NX` on `pipeline:refreshing`, 20 s), stored under `pipeline:snapshot` with a 10-second TTL and copied to `pipeline:last-good` with a 1-hour TTL. A request that finds no fresh snapshot and cannot refresh (GitHub error, rate limit, timeout) serves `last-good` with `stale: true` and `staleReason`; the page shows the age and disables buttons. `canDeploy` is computed per request from the session, after the cache read. Both POST endpoints delete `pipeline:snapshot` on success and on partial success.

Sources, bounded **(review)**: issues in two label queries (`feature-request`, `bug`), `state=all`, 100 per page, shipped ones kept only when closed within 14 days; pull requests listed once per repo (`state=all`, `per_page=100`, the three repos: api, web, harness) and matched locally to issues by head branch prefix `feat/<n>-`, `fix/<n>-`, or `docs/`… branches whose PR body says `Part of kaizen-tasks-assembly-line#<n>`; check runs per open PR head; branch heads per repo; served commits by server-side `fetch` of `STAGING_WEB_URL` and `PRODUCTION_WEB_URL` (`/api/v1/health`, `/version.json`, 5 s timeout; a failed read is `"unreachable"`); `onStaging` by the compare rule above; the active or last ship run from the harness `ship.yml` runs (`workflow_dispatch`, newest 10) matched by `run-name` (`ship <requestId> <version>`), with the current step read from the run's jobs endpoint and `queued`, `in_progress`, `completed:success|failure|cancelled|timed_out` all represented.

### `POST /pipeline/issues/{number}/deploy-staging`

Body `{ "passphrase": string }`. Guards, in order **(review)**: caller allowlisted (else `FORBIDDEN`); lockout check before any comparison (`pipeline:lockout:<userId>` ≥ 5 → `RATE_LIMITED` with `details.resetAt`); passphrase equal to `DEPLOY_PASSPHRASE` by `crypto.timingSafeEqual` on equal-length buffers (else `FORBIDDEN`, `details.reason: "passphrase"`, `INCR` + `EXPIRE 600` on the counter); Redis unavailable → `SERVICE_UNAVAILABLE`, never open. Then the action lock: `SET pipeline:action <requestId> NX EX 60`, else `CONFLICT` "another deploy is in progress"; refuse with `CONFLICT` while a ship run is queued or running. Then, fresh from GitHub (no cache): the issue's open PRs across the three repos; every one must be green by the shared definition, else `CONFLICT` naming the first that is not. Merge in order api, web, harness, squash, with the inspected head SHA. The response reports partial outcomes honestly: `{ data: { merged: [ { repo, number, sha } ], remaining: [ { repo, number, reason } ] } }`; a failure mid-list stops the list and returns 200 with `remaining` filled, so the next press finishes it. The staging label, comment and board row follow from the existing `staging-label` workflow; this endpoint does not touch labels.

### `POST /pipeline/ship`

Body `{ "passphrase": string, "version": string, "issues": number[] }`: the version and the issue set the button showed, echoed back so the API can refuse a stale click. Same guards and lock. Then: recompute production-ready issues and the next version; if either differs from the body → `CONFLICT` "the release changed, reload"; if any issue carries an unfinished ship marker with a different version → `CONFLICT` "retry the earlier ship first". Generate `requestId` (UUID), write `pipeline:ship:<requestId>` in Redis (10 min), dispatch `POST /repos/kpnemo/kaizen-tasks-assembly-line/actions/workflows/ship.yml/dispatches` with `{ ref: "develop", inputs: { request_id, version, issues: "22,23" } }`, then poll the runs list for up to 20 s for a run whose `run-name` carries the request id **(review)**. Response `{ data: { requestId, version, issues, run: { id, url } | null } }`; when the run is not found in time the response says `run: null` and the next snapshot reconciles it by request id. A retry after a lost response never dispatches again while `pipeline:ship:<requestId>` exists and no run carries it.

`POST /pipeline/ship/retry` with `{ passphrase, issue }` re-dispatches for an issue whose ship marker's run ended in failure or cancellation, with the marker's version and issue set, unchanged.

### Configuration and the feature flag

New settings in `backend/src/config.ts`: `PIPELINE_GITHUB_TOKEN` (required for the feature; **no fallback** to `GITHUB_TOKEN`, which stays the narrow issue-filing credential **(review)**), `FACILITATOR_EMAILS` (comma-separated, lower-cased on load), `DEPLOY_PASSPHRASE` (min 12 chars), `STAGING_WEB_URL`, `PRODUCTION_WEB_URL`. The three repositories are constants in code. The feature is on, and `features.pipeline` in `/health` is true, exactly when the token, the passphrase, both URLs and a non-empty allowlist are present. When off, the routes are not mounted and the web hides the link and the route.

A second GitHub port instance, `pipelineGitHub`, built from `PIPELINE_GITHUB_TOKEN` in `backend/src/app.ts` and injected in tests like the existing one, with: list issues by label, list pulls, get pull, check runs for a ref, compare, get branch head, get file contents, merge pull, create issue comment, dispatch workflow, list workflow runs, list run jobs. Tests inject a fake; no test reaches GitHub.

Facilitator accounts **(review)**: registration does not verify email addresses, but emails are unique in `users`, so the runbook's pre-session checklist registers the facilitator accounts in both environments *before* `FACILITATOR_EMAILS` is set, and never lists the shared demo account. The passphrase is the second factor.

## The ship workflow: `.github/workflows/ship.yml` (harness repo)

`on: workflow_dispatch` with inputs `request_id` (string), `version` (semver), `issues` (comma-separated numbers), `dry_run` (boolean, default false). `run-name: ship ${{ inputs.request_id }} ${{ inputs.version }}`. `concurrency: { group: ship, cancel-in-progress: false }`; GitHub keeps one pending run per group, so the API's lock is what keeps a third click out **(review)**. Secret `SHIP_TOKEN` for every cross-repo write; `github.token` reads this repo only. Inputs are validated as data before use: `version` against semver, `issues` as integers, `request_id` as a UUID.

Steps, each named so the page can show "Shipping: <step name>", each idempotent so a rerun with the same inputs resumes:

1. **Record the ship on the issues**: for each issue, if no marker with this `request_id` exists, comment the ship marker (version, request id, started at, run URL, issue set). Read back the marker: from here on the *marker's* version is the truth.
2. **Preflight**: each issue carries `staging` and has no open PR in any of the three repos; both `develop` heads are served by staging; both repos are at the same version or one of them is already at the target version (a resumed ship) **(review)**; the target is greater than the current. Record `develop` heads as the release base.
3. **Cut release in api** (skip when `develop` already carries the target version): checkout `kpnemo/kaizen-tasks-api@develop` with `SHIP_TOKEN`, Node from `.nvmrc`, `npm ci`, move `[Unreleased]` under `## [<version>] - <today UTC>` in `CHANGELOG.md`, `npm version --no-git-tag-version <version>`, `npm run product-map`, `npm run lint`, commit `chore: release <version>` with the trailer, push `release/<version>`. If the branch already exists, verify it contains exactly one commit over `develop` that changes only the four release files, else fail "unexpected release branch". Open the PR to `develop` (reuse if open).
4. **Cut release in web**: the same for `kpnemo/kaizen-tasks-web`.
5. **Merge release PRs**: wait for `ci` on each (up to 15 min), merge (`merge`) with the head SHA, api then web; a PR already merged is skipped. Record the two `develop` merge SHAs in the run summary.
6. **Wait for staging** to serve both new `develop` heads at the target version (up to 15 min).
7. **Open promotion PRs** `develop → main` in both repos (reuse if open), titled `release: <version>`.
8. **Promote api**: wait for `ci` and `promote` (up to 30 min), merge with the head SHA, then wait until production health reports the target version *and* the production commit equals the `main` merge SHA **(review)**.
9. **Promote web**: the same, then wait for production `version.json` to report the target version and the `main` merge SHA.
10. **Close the issues**: for each issue in the marker: comment `Shipped in api <version> (<sha>) and web <version> (<sha>): <production url>`, add `shipped`, close as completed. Then, `continue-on-error: true` **(review)**: flip each Triage board row to `shipped` and append "Ship complete: <run url>" to each marker thread. The existing `issue-lifecycle` workflow retires `implementing` and `staging`.

A final step with `if: always()` reads the job's conclusion: on failure, cancellation or timeout it comments `Ship failed at "<step>": <run url>` on each issue and exits non-zero **(review)**. With `dry_run: true` every step performs its reads and checks and prints what it would do; pushes, merges, comments and labels are skipped.

The merge policy stays honest with the repo rules: the buttons are the facilitator's merge, authenticated twice (account and passphrase); nothing merges without a person pressing.

## Security

- Tokens never leave the API or Actions. The browser sees `canDeploy` and nothing about credentials.
- Both POSTs require the session, the allowlist and the passphrase; comparison is constant-time; the passphrase is never logged; failures are rate-limited per user and the limiter fails closed; successes are logged with user id, issue, action and request id.
- `GET /pipeline` exposes nothing a signed-in user could not read on GitHub; the three repos are public.
- The workflow and ref are fixed server-side; the dispatched workflow file is edited only through reviewed pull requests to the harness repo.

## Tokens and settings Mike provides **(review)**

A fine-grained token applies one permission set to every repository it selects, so the table below lists the union each token needs and the repositories it is granted on. Expiry: the week after the workshop.

| Token                          | Granted on                                                         | Permissions (applied to all three)                                                                                                   | Set where                                                      |
| ------------------------------ | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| `PIPELINE_GITHUB_TOKEN` (API)  | kaizen-tasks-assembly-line, kaizen-tasks-api, kaizen-tasks-web     | Contents: read and write (merging needs it); Pull requests: read; Issues: read and write (ship markers); Checks: read; Actions: read and write (dispatch, runs, jobs); Metadata: read | Railway variables on `api`, staging and production             |
| `SHIP_TOKEN` (workflow)        | the same three                                                     | Contents: read and write; Pull requests: read and write; Issues: read and write; Workflows: read and write; Metadata: read           | GitHub secret on the harness repo                              |

Also on the API in both Railway environments: `FACILITATOR_EMAILS`, `DEPLOY_PASSPHRASE`, `STAGING_WEB_URL=https://web-staging-52c0.up.railway.app`, `PRODUCTION_WEB_URL=https://web-production-7ef71.up.railway.app`. The existing `GITHUB_TOKEN` (issue filing) and `ASSEMBLY_LINE_TOKEN` (staging label) are untouched. The plan's first task in each repo is a probe script that exercises every call the feature makes, including a merge and a push on a disposable branch, and prints which one is denied **(review)**.

## Error handling summary

| Failure                                   | What the room sees                                                                                                       |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| GitHub rate limit or outage               | Last-good snapshot with its age and "GitHub unreachable"; buttons disabled.                                              |
| Staging or production unreachable         | That card shows "unreachable"; nothing else changes.                                                                     |
| Wrong passphrase                          | Field error; after five, "Too many attempts, try again at HH:MM".                                                        |
| A PR moved or turned red between poll and press | `CONFLICT` naming the PR; the row shows the current badge.                                                          |
| Staging merge succeeds in api, fails in web | Response lists `merged` and `remaining`; the row shows one merged badge and one open; the next press finishes it.      |
| Ship fails mid-way                        | Badge "Ship failed at <step>" with the run link; issue comments; "Retry ship <version>" reruns with the marker's version. |
| Second facilitator presses during a ship  | `CONFLICT` "another deploy is in progress"; the workflow's concurrency group is the backstop.                            |
| Dispatch accepted, response lost          | The next snapshot finds the run by request id; no second dispatch.                                                      |

## Testing

- API: integration tests with the fake port for the snapshot (stage derivation, PR matching across three repos, green definition, `onStaging` by compare, next-version rules including the three `CONFLICT` cases, cache and last-good fallback, `canDeploy` outside the cache), for both POSTs (allowlist, passphrase, lockout order and fail-closed, action lock, moved-head conflict, partial merge response, stale-click conflict, dispatch payload and request id correlation), and for the feature flag. No network.
- Web: component tests with MSW for the four screen states, viewer versus facilitator rendering, each Action variant, the dialog's error states, the stale banner, and the header link toggling on the health flag. Screenshots in both themes.
- Workflow: `actionlint` in the harness `ci`; `dry_run: true` from the Actions tab; then rehearsals of the failure paths, not only success **(review)**: failure after the api release merge, failure after the api promotion, a duplicate click, a lost dispatch response, and a Railway deploy failure, each followed by a retry that completes.
- Runbook: the Ship segment becomes "press Deploy to production, narrate the run", with the manual sequence kept in an appendix as the fallback, and a timed rehearsal that fits the ten-minute slot or moves the slot.

## Sequencing

1. Issue #22 (request-page list) through `/triage-requests` and `/implement-issue`: it adds `GET /feature-requests`, which the pipeline reuses for issue listing. Done: triaged 2026-09-11.
2. `ship.yml` in the harness repo, dry-run tested, then one real run shipping #22 to production.
3. API: config, the pipeline port, `GET /pipeline`, the two POSTs and the retry, the health flag, the probe script.
4. Web: the page, the link, the dialog, screenshots.
5. Runbook and playbook updates; the failure rehearsals; the timed rehearsal.

Each of 2, 3 and 4 is its own plan and its own pull requests, API before web as always.

## Open risks

- Token scoping is easy to get slightly wrong; the probe task exists for that.
- GitHub's check-runs API can lag a merge by a minute; the page shows "checks running" rather than a stale colour, and every POST recomputes fresh.
- Between the api and web promotions production serves a new API with the old web for a minute or two; this release train has no contract change, and the runbook keeps the two clicks close together. A release with a contract change is rehearsed in that order before it is shipped live.
- Automation removes the typing, not the CI and deploy minutes: a full ship is about eight to twelve minutes end to end, so the runbook's Ship slot is measured in the rehearsal.
