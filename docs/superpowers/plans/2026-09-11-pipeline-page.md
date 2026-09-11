# Pipeline page (pipeline, part 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/pipeline` in the web app: the flow diagram, the two environment cards, the issues table with one action per row, and the passphrase dialog behind the two facilitator buttons, composed from shadcn and fed by `GET /pipeline`.

**Architecture:** A new feature folder `src/features/pipeline/` (page, `hooks.ts`, `components/`), a route under the app shell and a header link gated on `health.features.pipeline`, one polling query for the snapshot and three mutations. Everything visible is shadcn: `Card` for environments, `Table` for issues, `Badge` for stages and PR checks, `Button` for actions, `AlertDialog` + `Field` for the passphrase, `Alert`/`Empty`/`Skeleton` for the non-content states. The diagram is one inline SVG component.

**Tech Stack:** React 19, TanStack Query, react-router 7, shadcn (new-york-v4, Radix), lucide, Vitest + Testing Library + MSW.

**Spec:** `docs/superpowers/specs/2026-09-11-pipeline-control-room-design.md`, sections "The page: /pipeline" and "The API". Contract: the API PR from `docs/superpowers/plans/2026-09-11-pipeline-api.md` (pull it with `npm run api:pull -- --local ../backend/openapi.json`).

## Global Constraints

- Branch `feat/pipeline-page` in `frontend/`, off `develop` **after** the shell rework (`feat/ui-shell`) and the API PR have merged: the page needs Table, Alert, Skeleton, Empty, Spinner and the contract. If the shell PR is not merged yet, branch from `origin/feat/ui-shell` and say so in the PR.
- `add-frontend-feature` skill in full: contract pull first (ADR: the pull touches `src/api/**`), failing component tests, the shadcn skill and the frontend-design skill loaded before the first visible change, docs before the green run, screenshots in both themes (`scripts/screenshots/pipeline.mjs`), the docs gate `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci`.
- Selector contract in `README.md` is frozen; the new page adds names, it changes none. New accessible names the smoke test may adopt later: link "Pipeline", heading "Pipeline", table "Issues", buttons "Deploy to staging" and "Deploy <version> to production", dialog "Deploy passphrase" field.
- Poll every 10 s while mounted (`refetchInterval: 10_000`, `refetchIntervalInBackground: false`).
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

### Task 1: Contract, route, link, hooks, and the four screen states

**Files:**
- Regenerate: `src/api/openapi.json`, `src/api/types.ts`; Modify: `src/api/models.ts` (`PipelineSnapshot`, `PipelineIssue`, `PipelineEnvironment`, `DeployBody`, `ShipBody`, `ShipRetryBody` aliases), `src/api/health-query.ts` if the flag helper lives there
- Create: `docs/adr/0009-pipeline-contract-pull.md`, `src/features/pipeline/hooks.ts`, `src/features/pipeline/PipelinePage.tsx`, `src/features/pipeline/PipelineLink.tsx`, `src/features/pipeline/PipelinePage.test.tsx`
- Modify: `src/app/router.tsx` (`/pipeline` under `RequireAuth` + `AppShell`), `src/app/layout.tsx` (`<PipelineLink />` after Tags, same `NavButton` the shell rework introduced), `tests/msw/handlers.ts` (`pipelineHandlers`, `pipelineSnapshot()` factory with overrides, `healthBody({ pipeline })`)

**Interfaces:**
- Produces: `usePipelineAvailable()` (health flag), `usePipeline()` (key `["pipeline"]`, 10 s poll), `useDeployStaging()`, `useShip()`, `useRetryShip()` (mutations; `onSuccess` invalidates `["pipeline"]`; errors are returned to the dialog, not toasted, except network errors).

- [ ] **Step 1: Failing tests** in `PipelinePage.test.tsx`: link hidden when `features.pipeline` is false and shown when true; `/pipeline` renders heading "Pipeline"; loading shows `role="status"` "Loading pipeline" with skeletons; `err("UPSTREAM_ERROR", …)` shows an `Alert` with the message; a snapshot with no issues shows `Empty` "No requests yet".
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement** the pull, the ADR, the aliases, the MSW factory (a realistic default snapshot: two environments at 1.4.0, three issues at stages implementing / staging / shipped with PRs), the hooks, the link, the route, and the page skeleton with the four states.
- [ ] **Step 4: Green, docs** (README feature bullet, CHANGELOG, product map), commit `feat: pipeline page shell, contract and states`.

---

### Task 2: The flow diagram and the environment cards

**Files:**
- Create: `src/features/pipeline/components/FlowDiagram.tsx`, `src/features/pipeline/components/EnvironmentCard.tsx`, `src/features/pipeline/components/EnvironmentCard.test.tsx`

- [ ] **Step 1: Failing tests**: `EnvironmentCard` renders "Staging" with api and web version and short commit, "db ok" and "redis ok" as badges, and the state line ("serving develop's head" / "deploying" / "unreachable" as a destructive badge); the snapshot's age line renders "as of HH:MM:SS" and, when `stale` is true, the destructive "GitHub unreachable" badge.
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement.** `FlowDiagram`: an inline `<svg role="img" aria-labelledby="flow-title">` with eight nodes (Request, Triage, Implement, Pull requests, Develop, Staging, Production, Shipped) laid out in one row on wide screens and two rows under 900 px (two `<g>` layouts switched by a CSS class), semantic tokens only (`stroke-border`, `fill-card`, the brand accent on the two click arrows labelled "Deploy to staging" and "Deploy to production"), one line of caption under each node naming the actor. `EnvironmentCard`: full `Card` composition (`CardHeader` with `CardTitle` and `CardDescription`, `CardContent` a two-column definition list, `CardFooter` with the state badge).
- [ ] **Step 4: Green, commit** `feat: pipeline flow diagram and environment cards`.

---

### Task 3: The issues table and the action column

**Files:**
- Create: `src/features/pipeline/components/IssuesTable.tsx`, `src/features/pipeline/components/IssueAction.tsx`, `src/features/pipeline/components/IssuesTable.test.tsx`

- [ ] **Step 1: Failing tests**: table `aria-label="Issues"` with headers Issue, Stage, Readiness, Pull requests, Action; rows in snapshot order; stage `Badge` per stage (Shipped default, Staging secondary, Implementing outline, Triaged/New outline muted); PR badges with the repo short name and number and one icon per state (pending `CircleDashed`, green `CircleCheck`, red `CircleX`, merged `GitMerge`); the action cell shows exactly one of: "Deploy to staging" (implementing, all open PRs green, `canDeploy`), "Deploy 1.5.0 to production" (productionReady, no active ship, `canDeploy`), "Shipping: <step>" badge linking to the run, "Ship failed at <step>" badge plus "Retry ship 1.5.0", or a muted hint; nothing renders for a viewer without `canDeploy` except the badges and hints.
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement** with shadcn `Table`; the action column is the last, `whitespace-nowrap`; every button carries a lucide icon (`Rocket` staging, `Ship` production, `RotateCcw` retry); the run links are `Button asChild variant="link"` with `ExternalLink data-icon="inline-end"`.
- [ ] **Step 4: Green, commit** `feat: pipeline issues table`.

---

### Task 4: The passphrase dialog and the mutations

**Files:**
- Create: `src/features/pipeline/components/DeployDialog.tsx`, `src/features/pipeline/components/DeployDialog.test.tsx`

- [ ] **Step 1: Failing tests**: clicking "Deploy to staging" opens an `AlertDialog` titled "Deploy #22 to staging" whose description lists the PRs that will merge; the `Field` "Deploy passphrase" is a password input; "Deploy to staging" posts `{ passphrase }` to `/pipeline/issues/22/deploy-staging` and closes on 200, invalidating the snapshot; a `FORBIDDEN` with `details.reason: "passphrase"` shows the field error "Wrong passphrase"; a `RATE_LIMITED` with `details.resetAt` shows "Too many attempts, try again at HH:MM"; a `CONFLICT` shows the API message inline as an `Alert`; the production variant is titled "Deploy 1.5.0 to production", its description names every staged issue ("Ships #22 and #23"), and it posts `{ passphrase, version, issues }` to `/pipeline/ship`; "Retry ship" posts to `/pipeline/ship/retry`.
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement**: one `DeployDialog` component with a `kind` prop (`staging | production | retry`), `AlertDialogTitle`, `AlertDialogDescription`, a `Field` with `FieldLabel`, `Input type="password" autoComplete="off"`, `FieldError`, `AlertDialogCancel` and `AlertDialogAction` rendered as the verb button with `Spinner data-icon="inline-start"` while pending and `disabled` when the passphrase is empty; errors mapped from `ApiError` (`toApiError`).
- [ ] **Step 4: Green, commit** `feat: pipeline deploy dialog`.

---

### Task 5: Screenshots, docs, pull request

- [ ] `scripts/screenshots/pipeline.mjs`: route `/pipeline`, ready on heading "Pipeline" and table "Issues"; the local API needs the five pipeline settings (`PIPELINE_GITHUB_TOKEN=$(gh auth token)`, `FACILITATOR_EMAILS=<the throwaway user's email pattern is unknown>`: for the capture set `FACILITATOR_EMAILS` to the screenshot runner's generated email domain if it is deterministic, else capture the viewer variant and add `act` that logs in as a facilitator account created for the run; `DEPLOY_PASSPHRASE`, `STAGING_WEB_URL`, `PRODUCTION_WEB_URL`). Capture both themes; a second scenario `pipeline-dialog.mjs` opens the production dialog when a row is ready.
- [ ] README feature bullet, CHANGELOG bullet, `npm run product-map`, the docs gate; `README.md` "Selector contract" gains the new names as *available*, not required.
- [ ] Push, PR to `develop`: what changed, the criteria checklist per task, screenshots table, failing-then-passing evidence, `Docs-check: docs-check: OK`, and the note that the page shows buttons only to facilitators (so a reviewer with a non-facilitator account sees none).

## Self-review

- Spec coverage: blocks 1 to 4 of "The page" map to Tasks 2, 2, 3, 4; the four screen states and the poll to Task 1; the stale banner to Task 2; the action rules and the `canDeploy` gating to Task 3; the dialog's three error shapes to Task 4; screenshots and docs to Task 5.
- Placeholders: the facilitator email for the screenshot run is an open question resolved in Task 5 by the executor (it depends on the runner's throwaway account); everything else is concrete.
- Consistency: hook names, query key `["pipeline"]`, endpoint paths and body shapes match the API plan; component names are used identically across tasks.
