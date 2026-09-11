# Briefing: #22 Show existing requests at the bottom of the Request a feature page

- Summary: People file a request in the app and never see it again there. The facilitator wants the Request page itself to show every request filed so far, open first then closed, each with a stage chip and a link to GitHub, fetched by the API with the token it already holds. The browser never talks to GitHub.
- Triage: readiness 17, clarity 5, complexity 3, risk 2
- UI: visible
- Repos: kaizen-tasks-api, kaizen-tasks-web

## What exists today

The API files a request with `POST /feature-requests` (`backend/src/routes/feature-requests.ts`), validated by zod schemas registered in the OpenAPI registry (`src/schemas/feature-requests.ts`, side-effect-imported from `src/schemas/index.ts`), through `createFeatureRequestsService` (`src/services/feature-requests.ts`). That service owns the GitHub port, `interface GitHubIssues { create(...) }`, with a real Octokit implementation (`createOctokitIssues`, 10 s timeout) and a `FakeIssues` in `tests/api/feature-requests.test.ts` injected through `createTestApp(config, { github })`. `GITHUB_REPO` is split into owner and repo. A GitHub failure is logged as status and message only and thrown as `upstreamError(...)`, code `UPSTREAM_ERROR`, HTTP 502. The router is mounted under `requireAuth` and only when `GITHUB_TOKEN` and `GITHUB_REPO` are set; `/health` reports that as `features.featureRequests`.

The web page `frontend/src/features/feature-request/RequestFeaturePage.tsx` has three modes (interview, plain form, "Request #N filed"), each ending the page; `hooks.ts` holds `useConversation`, `useStartConversation`, `useSendTurn`, `useSubmitFeatureRequest` (which updates the conversation cache with `setQueryData`, not invalidation) and `useFeatureRequestAvailable()` reading the health query. Tests use `renderApp({ route })`, MSW `server.use`, the `ok`/`err` envelope helpers and `healthBody(featureRequests)` from `tests/msw/handlers.ts`; unhandled requests fail, so a new endpoint needs a default handler.

There is no issue listing anywhere, no label-to-stage mapping, and no list call on the port. `FEATURE_REQUEST_LABEL = "feature-request"` is the only label constant.

## Touched areas

- API: `src/services/feature-requests.ts` (port method `list`, stage derivation, ordering), `src/routes/feature-requests.ts` (`GET /`), `src/schemas/feature-requests.ts` (summary schema, path registration), `tests/api/feature-requests.test.ts` (fake gains `list`), `openapi.json` and `docs/API.md` via `npm run openapi`, `README.md` routes table, `CHANGELOG.md`, `docs/product-map.md`.
- Web: `src/api/openapi.json` and `src/api/types.ts` via `npm run api:pull -- --local ../backend/openapi.json`, `src/api/models.ts` alias, `src/features/feature-request/hooks.ts` (`useFeatureRequests`, invalidation in `useSubmitFeatureRequest`), a new `components/RequestsSoFar.tsx`, `RequestFeaturePage.tsx` (section under every mode), `tests/msw/handlers.ts` (default handler and factory), `RequestFeaturePage.test.tsx`, `README.md` feature list, `CHANGELOG.md`, `docs/product-map.md`, an ADR (the contract pull touches `src/api/**`, an architectural glob), screenshots.

## Mockups seen

none

## Unknowns

none

## Open questions

none. Decisions taken from the issue text and the conventions: the section renders under all three page modes, because the request says "at the bottom of /request-feature"; only issues labelled `feature-request` are listed (bugs come with the pipeline page); two GitHub calls per request (`state=open`, `state=closed`, `per_page=50`, sorted by `created` descending), no server-side cache in this issue (the pipeline snapshot adds one later); `UPSTREAM_ERROR` (502) is reused for a GitHub failure; the section's own error never blocks the interview or the form.
