# Spec: #22 Show existing requests at the bottom of the Request a feature page

Context: docs/superpowers/briefs/2026-09-11-issue-22-show-existing-requests-at-the-bottom-of.md

## What

A "Requests so far" section at the bottom of `/request-feature`, under whichever mode the page is in, listing every issue labelled `feature-request` in the harness repository: open first, then closed, newest first within each group, at most 50 per group. Each row shows the number, the title, a stage chip, the readiness score with its three score labels, and a link to the issue on GitHub. The API fetches the list through the GitHub port it already uses to file requests. Approach A from the round: extend the existing feature-request slice in both repos.

## Who

Anyone signed in who opens the Request page: a participant checking that their request exists and where it is, and the facilitator pointing at the app instead of GitHub.

## Behavior

- `GET /api/v1/feature-requests` (mounted with the POST, behind the session, only when `GITHUB_TOKEN` and `GITHUB_REPO` are set) returns `{ data: FeatureRequestSummary[] }`. Each item: `number`, `title`, `state` (`open` | `closed`), `stage` (`new` | `triaged` | `implementing` | `staging` | `shipped` | `closed`), `readiness` (number or null), `labels` (string[]), `url`, `createdAt`, `closedAt` (string or null).
- Ordering: the open group (GitHub `state=open`, `sort=created`, `direction=desc`, `per_page=50`) followed by the closed group (`state=closed`, same). Two GitHub calls, no cache.
- Stage: first match of `shipped`, `staging`, `implementing`, `triaged` among the labels; else `closed` for a closed issue, `new` for an open one.
- Readiness: from labels `clarity:<c>`, `complexity:<x>`, `risk:<r>` with the rubric formula `c*2 + (6-x) + (6-r)`; null when any of the three is missing. (Mike, design round 2026-09-11: "you have labels on issues", so the rows show them.)
- A GitHub failure logs status and message and answers `UPSTREAM_ERROR` (502), as the POST does.
- Web: `useFeatureRequests()` (query key `["feature-request", "list"]`) feeds `RequestsSoFar`; `useSubmitFeatureRequest` invalidates that key on success so the new issue appears at the top of the open group. The section renders under all three page modes.

## Acceptance criteria as tests

Effective criteria are the issue's, with criterion 4 amended by the requester in the round (labels shown).

1. Shape, ordering, cap, mount, auth — `backend/tests/api/feature-requests.test.ts` › "lists requests open first then closed, newest first, with the summary fields" (fake returns a mixed set; asserts field set, order and that `per_page: 50` was requested per state) and "GET requires a session" (401 envelope).
2. Stage derivation — › "derives the stage from labels in priority order" (six fixtures: shipped+staging → shipped, staging+implementing → staging, implementing → implementing, triaged → triaged, closed without → closed, open without → new).
3. GitHub failure — › "answers 502 UPSTREAM_ERROR when GitHub fails to list" (a fake that throws; asserts the envelope and that the log line carries no raw body).
4. Heading, rows, chips, labels, link name — `frontend/src/features/feature-request/components/RequestsSoFar.test.tsx` › "shows requests open first with stage chips, readiness and GitHub links" (three issues; asserts row order, chip text, "Readiness 17", the score chips, and links named "Open #<n> on GitHub" with `target="_blank"` and `rel="noreferrer"`).
5. States — › "shows the loading, empty and error states without breaking the page" (status text "Loading requests"; empty sentence "No requests yet. Yours can be the first."; on `err("UPSTREAM_ERROR", …)` an alert with that message while the "Request a feature" heading is still on the page).
6. Refresh after filing — `RequestFeaturePage.test.tsx` › "refreshes the requests list after filing" (file through the form; the MSW list handler returns the new issue on the second call; assert it appears first without navigation).
7. Docs and contract — `npm run openapi` regenerates `openapi.json` and `docs/API.md`; the web pulls it and regenerates `types.ts`; changelog bullets in both repos; the docs gate prints OK in both.

No API error-state test is needed beyond 3; the web feature has its happy path (4) and error state (5).

## Looks

Below the page's current content, separated by a `Separator`: an `h2` "Requests so far" in the display face, then a list (`ul`, one `li` per issue, 44 px minimum height, `text-base`). Each row: `#<number>` in the muted colour, the title as plain text, a stage `Badge` (Shipped default, Staging secondary, Implementing outline, Triaged and New ghost, Closed ghost with muted text), then "Readiness <n>" and three small ghost badges `clarity 5`, `complexity 3`, `risk 2` when present, then a `Button variant="link"` rendered as an anchor with the `ExternalLink` icon and the accessible name "Open #<number> on GitHub". A muted divider line "Closed" precedes the closed group when both groups exist. Light and dark follow the tokens; screenshots by `scripts/screenshot.mjs request-feature` (new scenario: route `/request-feature`, ready on the "Requests so far" heading).

## Out of scope

- Filtering, search or pagination beyond the 50-per-group cap.
- Pull requests, environments or deploy buttons (the pipeline page).
- Editing or closing issues from the app.
- Bug issues (the pipeline page lists them).
- Server-side caching of the list (the pipeline snapshot adds one).

## Repos and files

API, `kaizen-tasks-api`, branch `feat/22-show-existing-requests-at-the-bottom-of`: `src/services/feature-requests.ts` (port `list`, `summarize`, stage and readiness helpers), `src/routes/feature-requests.ts` (`GET /`), `src/schemas/feature-requests.ts` (`FeatureRequestSummary`, path registration), `tests/api/feature-requests.test.ts` (fake gains `list`), `openapi.json`, `docs/API.md`, `README.md` routes table, `CHANGELOG.md`, `docs/product-map.md`. No schema, queue, auth or prompt change: no ADR.

Web, `kaizen-tasks-web`, same branch name: `src/api/openapi.json`, `src/api/types.ts` (pulled), `src/api/models.ts` (alias `FeatureRequestSummary`), `src/features/feature-request/hooks.ts`, `src/features/feature-request/components/RequestsSoFar.tsx` and its test, `RequestFeaturePage.tsx` and its test, `tests/msw/handlers.ts` (default list handler, factory), `README.md` feature list, `CHANGELOG.md`, `docs/product-map.md`, `docs/adr/0008-…` (the contract pull touches `src/api/**`), `scripts/screenshots/request-feature.mjs`, `docs/screenshots/request-feature-{light,dark}.png`.
