# Pipeline API (pipeline, part 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `GET /pipeline` gives the page one cached snapshot (environments, branches, issues with PRs, next version, ship state, `canDeploy`); `POST /pipeline/issues/{n}/deploy-staging`, `POST /pipeline/ship` and `POST /pipeline/ship/retry` perform the two facilitator clicks behind the allowlist, the passphrase, the lockout and the action lock; `/health` reports `features.pipeline`.

**Architecture:** A new slice beside feature-requests: `src/services/pipeline.ts` (snapshot builder, derivations, guards, actions) over a second GitHub port `PipelineGitHub` (`src/services/pipeline-github.ts`, Octokit with a per-call deadline) and a small Redis-backed `src/lib/pipeline-locks.ts` (snapshot cache, last-good, refresh lock, action lock, passphrase lockout). Routes in `src/routes/pipeline.ts`, schemas in `src/schemas/pipeline.ts`. Mounted only when the five settings are present. Tests inject a fake port and use the real test Redis.

**Tech Stack:** Express 5, zod + OpenAPI registry, Octokit, ioredis, Vitest + supertest. Node 24 via `nvm use`.

**Spec:** `docs/superpowers/specs/2026-09-11-pipeline-control-room-design.md` (sections "Definitions the API and the workflow share" and "The API"). The ship workflow's contract (run name `ship <request_id> <version>`, the `<!-- kaizen-ship {…} -->` marker, step names) is `.github/workflows/ship.yml` on `develop` after harness PR #24.

## Global Constraints

- Branch `feat/pipeline-api` in `backend/` off `develop`; one pull request; `add-api-endpoint` skill for every route (restate, failing integration test, schemas registered, service, route with `validate` and the envelope, `npm run openapi`, README routes table, changelog, docs gate). Contract changes ripple to the web in part 4, not here.
- Settings: `PIPELINE_GITHUB_TOKEN`, `FACILITATOR_EMAILS`, `DEPLOY_PASSPHRASE` (min 12), `STAGING_WEB_URL`, `PRODUCTION_WEB_URL`. Repos are constants: harness `kpnemo/kaizen-tasks-assembly-line`, api `kpnemo/kaizen-tasks-api`, web `kpnemo/kaizen-tasks-web`. No fallback to `GITHUB_TOKEN`.
- Every GitHub call carries `AbortSignal.timeout(10_000)`; environment reads use `fetch` with a 5 s `AbortSignal.timeout`.
- Error codes: `FORBIDDEN` (not allowlisted, or wrong passphrase with `details.reason: "passphrase"`), `RATE_LIMITED` (`details.resetAt`), `CONFLICT` (stale click, moved head, red check, action in progress, versions differ, nothing to release), `UNAVAILABLE` (Redis down: fail closed), `UPSTREAM_ERROR` (GitHub failed and no last-good snapshot).
- Passphrase comparison with `crypto.timingSafeEqual` on equal-length buffers; never logged. Lockout checked before the comparison; five failures per user in ten minutes.
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Docs gate: `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci`.

---

### Task 1: Settings, the pipeline GitHub port, the health flag

**Files:**
- Modify: `src/config.ts` (five settings), `src/routes/health.ts` (`HealthFeatures.pipeline`), `src/schemas/health.ts` (`pipeline: z.boolean()`), `src/app.ts` (`pipelineConfigOf`, `features.pipeline`, port construction, mount)
- Create: `src/services/pipeline-github.ts`
- Test: `tests/api/health.test.ts` (flag false by default, true with the five settings), `tests/api/pipeline.test.ts` (created here with the mount tests; grows in later tasks)

**Interfaces:**
- Produces: `pipelineConfigOf(config): PipelineConfig | undefined` with `{ token, facilitatorEmails: Set<string>, passphrase, stagingUrl, productionUrl }`; `PipelineGitHub` port:

```ts
export interface PipelineGitHub {
  listIssues(p: { repo: string; labels: string; state: "all"; perPage: number }): Promise<IssueItem[]>;
  listPulls(p: { repo: string; state: "all"; perPage: number }): Promise<PullItem[]>;
  getPull(p: { repo: string; number: number }): Promise<PullItem>;
  checkRuns(p: { repo: string; ref: string }): Promise<CheckRun[]>;                 // name, status, conclusion
  compare(p: { repo: string; base: string; head: string }): Promise<"identical" | "behind" | "ahead" | "diverged">;
  branchHead(p: { repo: string; branch: string }): Promise<string>;
  fileText(p: { repo: string; path: string; ref: string }): Promise<string>;
  mergePull(p: { repo: string; number: number; sha: string; method: "squash" | "merge" }): Promise<{ sha: string }>;
  commentIssue(p: { repo: string; number: number; body: string }): Promise<void>;
  dispatchWorkflow(p: { repo: string; workflow: string; ref: string; inputs: Record<string, string> }): Promise<void>;
  listRuns(p: { repo: string; workflow: string; perPage: number }): Promise<RunItem[]>;   // id, name (run-name), status, conclusion, url, createdAt
  runJobs(p: { repo: string; runId: number }): Promise<JobItem[]>;                          // steps: name, status, conclusion
}
```

- [ ] **Step 1: Failing tests** in `tests/api/health.test.ts`: `features.pipeline` is `false` on `createTestApp()` and `true` on `createTestApp({ PIPELINE_GITHUB_TOKEN: "t", FACILITATOR_EMAILS: "mike@example.com", DEPLOY_PASSPHRASE: "correct-horse-battery", STAGING_WEB_URL: "https://s.test", PRODUCTION_WEB_URL: "https://p.test" }, { pipelineGithub: fake, fetchImpl: fakeFetch })`; in `tests/api/pipeline.test.ts`: `GET /api/v1/pipeline` is 404 `NOT_FOUND` on the plain app and 401 without a session on the configured one.
- [ ] **Step 2: Run, watch them fail** (`features.pipeline` undefined; route 404 on both apps).
- [ ] **Step 3: Implement** the settings (`FACILITATOR_EMAILS` lower-cased and split on commas at parse time with a zod `transform`), `pipelineConfigOf`, the port with Octokit (`request: { signal: AbortSignal.timeout(10_000) }` on every call, like feature-requests), `AppDeps.pipelineGithub?` and `AppDeps.fetchImpl?` (tests inject a fake `fetch` for the environment reads), the health flag, and an empty `pipelineRouter` mounted behind `requireAuth` when the config exists.
- [ ] **Step 4: Green, docs** (`npm run openapi` for the health schema change, changelog bullet), commit `feat: pipeline settings, GitHub port and health flag`.

---

### Task 2: `GET /pipeline`, the snapshot

**Files:**
- Create: `src/services/pipeline.ts`, `src/lib/pipeline-locks.ts`, `src/schemas/pipeline.ts`
- Modify: `src/routes/pipeline.ts`, `src/schemas/index.ts` (side-effect import), `tests/api/pipeline.test.ts`

**Interfaces:**
- Produces: `createPipelineService(deps: { github: PipelineGitHub; redis: Redis; fetchImpl: typeof fetch; config: PipelineConfig; logger })` with `snapshot(callerEmail): Promise<Snapshot>`; `Snapshot` exactly as the spec's JSON (`generatedAt, stale, staleReason?, canDeploy, nextVersion | null, nextVersionError?, ship, environments, branches, issues[]`).
- Pure helpers exported for unit tests: `stageOf(labels, state)` (reuse from feature-requests), `readinessOf(labels)` (reuse), `nextVersionOf({ apiVersion, webVersion, apiUnreleased, webUnreleased })`, `isGreen(pull, checkRuns, base)`, `matchPullsToIssue(pulls, n)`.

- [ ] **Step 1: Failing tests**

```ts
describe("GET /pipeline", () => {
  it("builds the snapshot: environments, branches, issues with PRs, stage, readiness, next version", …);
    // fake: two issues (22 open with labels staging+scores, 19 closed shipped 2 days ago), pulls in three repos
    // (web feat/22-… merged, api feat/22-… merged, harness feat/22-… merged, web release/1.3.0 merged),
    // check runs green, compare "behind" for merge SHAs vs served commits, branch heads, package.json 1.3.0 both,
    // changelogs with ### Added bullets → nextVersion "1.4.0"; fakeFetch answers health/version.json for both URLs.
    // asserts: issues[0].number 22, stage "staging", onStaging true, productionReady true, pullRequests length 3,
    // environments.staging.api.version "1.3.0", branches.web.develop, nextVersion "1.4.0", canDeploy false for a
    // non-facilitator, ship.active false.
  it("marks canDeploy for an allowlisted email, outside the cache", …);   // two users, one snapshot generation (fake counts calls)
  it("serves the last-good snapshot with stale=true when GitHub fails after a success", …);
  it("answers UPSTREAM_ERROR when GitHub fails and nothing is cached", …);
  it("shows an unreachable environment without failing the snapshot", …);
  it("derives production readiness from served commits, not from the staging label", …);  // compare returns "ahead" → onStaging false
  it("reports the active ship run and its current step", …);   // listRuns has "ship <id> 1.4.0" in_progress; runJobs step "Promote api" in_progress
  it("computes the next version: minor for Added/Changed, patch for Fixed only, errors for empty or unequal", …);  // unit-level over nextVersionOf
});
```

- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement.** `pipeline-locks.ts`: `readSnapshot()` (`GET pipeline:snapshot`), `readLastGood()`, `writeSnapshot(json)` (`SET … EX 10` and `SET pipeline:last-good … EX 3600`), `tryRefreshLock()` (`SET pipeline:refreshing 1 NX EX 20`), `releaseRefreshLock()`, `invalidate()`. `pipeline.ts`: `buildShared()` gathers in parallel: issues (two label queries), pulls once per repo, branch heads (four), package.json and CHANGELOG.md from both `develop`s, environment reads via `fetchImpl` with 5 s timeouts, ship runs (newest 10) and the jobs of the newest queued or running one; then derives per issue: PRs by head prefix `feat/<n>-` / `fix/<n>-` (harness docs branches included), `checks` from the check runs of open heads (`green` when every required check for the base has a successful completed run, `red` when any completed run failed, else `pending`), `onStaging` (all merged and each app-repo merge SHA `identical|behind` the served commit), `productionReady` (`onStaging` and no unfinished marker for another version: read the newest `kaizen-ship` marker from the issue's comments, `done: true` clears it). `snapshot(email)`: fresh → return; else refresh under the lock or wait 500 ms and re-read up to 4 times; on failure serve last-good with `stale: true`; then set `canDeploy`. The 14-day shipped window filters `state=closed` issues by `closedAt`.
- [ ] **Step 4: Schemas and route.** `PipelineSnapshot` zod schema mirroring the JSON, registered `get /pipeline` with `UNAUTHORIZED`, `UPSTREAM_ERROR`; `router.get("/", …)`.
- [ ] **Step 5: Green, docs, commit** `feat: GET /pipeline snapshot`.

---

### Task 3: The guards and `POST /pipeline/issues/{number}/deploy-staging`

**Files:**
- Modify: `src/services/pipeline.ts` (guards, `deployStaging`), `src/lib/pipeline-locks.ts` (lockout, action lock), `src/schemas/pipeline.ts`, `src/routes/pipeline.ts`, `tests/api/pipeline.test.ts`

**Interfaces:**
- Produces: `authorize(user, passphrase)` throwing `FORBIDDEN` / `RATE_LIMITED` / `UNAVAILABLE`; `withActionLock(requestId, fn)`; `deployStaging(user, n, passphrase) → { merged: [{repo, number, sha}], remaining: [{repo, number, reason}] }`.

- [ ] **Step 1: Failing tests**

```ts
describe("POST /pipeline/issues/:n/deploy-staging", () => {
  it("is FORBIDDEN for a non-facilitator, before any GitHub call", …);
  it("is FORBIDDEN with details.reason passphrase on a wrong passphrase, and RATE_LIMITED after five", …);  // resetAt present; checks lockout is read before compare (a locked user with the right passphrase is still RATE_LIMITED)
  it("is UNAVAILABLE when Redis is down", …);   // inject a redis whose get rejects
  it("merges every green PR api → web → harness with the inspected head sha, and invalidates the snapshot", …);
  it("refuses with CONFLICT naming the first PR that is not green", …);
  it("reports partial completion when the second merge fails", …);   // fake mergePull throws on web → 200 with merged [api], remaining [web, harness]
  it("refuses with CONFLICT while a ship run is active or another action holds the lock", …);
});
```

- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement.** Lockout keys `pipeline:lockout:<userId>` (`INCR` + `EXPIRE 600` on failure; `GET` before compare; `TTL` for `resetAt`); action lock `SET pipeline:action <requestId> NX EX 60`, released in `finally`; `deployStaging`: fresh `listPulls` per repo (no cache), match to the issue, order api, web, harness, each must be open, not draft, base `develop`, `mergeable_state` not `dirty|blocked`, `ci` green on the current head; merge with the inspected head SHA (`squash`); collect `merged`/`remaining`; invalidate the snapshot; log `{ userId, issue, action: "deploy-staging", requestId }`.
- [ ] **Step 4: Schemas** (`DeployBody { passphrase }`, `DeployStagingResponse`), route with `validate`, registered with `FORBIDDEN`, `RATE_LIMITED`, `CONFLICT`, `UNAVAILABLE`, `UPSTREAM_ERROR`.
- [ ] **Step 5: Green, docs, commit** `feat: deploy to staging from the pipeline`.

---

### Task 4: `POST /pipeline/ship` and `POST /pipeline/ship/retry`

**Files:**
- Modify: `src/services/pipeline.ts` (`ship`, `retryShip`), `src/schemas/pipeline.ts`, `src/routes/pipeline.ts`, `tests/api/pipeline.test.ts`

**Interfaces:**
- Produces: `ship(user, { passphrase, version, issues }) → { requestId, version, issues, run: { id, url } | null }`; `retryShip(user, { passphrase, issue })` with the marker's version and issue set.

- [ ] **Step 1: Failing tests**

```ts
describe("POST /pipeline/ship", () => {
  it("dispatches ship.yml with request_id, version and the issue set, and returns the run found by run name", …);
  it("refuses with CONFLICT when the body's version or issue set differs from the fresh computation", …);
  it("refuses with CONFLICT when an issue carries an unfinished marker for another version", …);
  it("does not dispatch twice for the same requestId when the first response was lost", …);   // pipeline:ship:<id> exists and a run carries it
  it("returns run null when the run is not visible within the poll window, and the next snapshot reconciles it", …);
});
describe("POST /pipeline/ship/retry", () => {
  it("re-dispatches with the marker's version and issue set for a failed or cancelled run", …);
  it("refuses while the marker's run is still queued or running", …);
});
```

- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Implement.** Same guards and lock; recompute production-ready issues and `nextVersion` fresh; `requestId = randomUUID()`; `SET pipeline:ship:<requestId> <json> EX 600`; `dispatchWorkflow({ repo: harness, workflow: "ship.yml", ref: "develop", inputs: { request_id, version, issues: "22,23" } })`; poll `listRuns` every 2 s for up to 20 s for `name === "ship <requestId> <version>"`; invalidate the snapshot; `retryShip` reads the issue's newest marker (`done` false, run concluded failure/cancelled/timed_out) and dispatches with `request_id = marker.requestId + "-r" + attempt`, the marker's version and issues.
- [ ] **Step 4: Schemas** (`ShipBody { passphrase, version, issues }`, `ShipResponse`, `ShipRetryBody { passphrase, issue }`), routes, registration.
- [ ] **Step 5: Green, docs, commit** `feat: ship to production from the pipeline`.

---

### Task 5: Docs, README, probe, pull request

- [ ] `README.md` routes table (four rows), settings table (five variables), `docs/API.md` regenerated, `CHANGELOG.md` `### Added` bullet, `npm run product-map`, `docs/ARCHITECTURE.md` one paragraph (the pipeline slice and why the API dispatches rather than orchestrates). No architectural file changes (no schema, queue, auth, prompt): no ADR.
- [ ] `scripts/pipeline-probe.mjs`: with `PIPELINE_GITHUB_TOKEN` set, calls each read the snapshot needs and one dry-run dispatch, printing `ok`/`denied` per call (Codex review item).
- [ ] Full checks, docs gate, push `feat/pipeline-api`, PR to `develop` with the criteria checklist, failing/passing evidence, and the Railway variables to set on `api` in both environments.

## Self-review

- Spec coverage: settings and flag (T1), snapshot with cache/last-good/`canDeploy` outside the cache/bounded GitHub work/readiness by compare/ship run state (T2), guards with lockout order and fail-closed, action lock, green definition, head-SHA merges, partial completion (T3), ship with stale-click conflict, request id correlation, no double dispatch, retry (T4), docs and probe (T5).
- Placeholders: test bodies are named and their fixtures described; the executor writes them from the descriptions (the spec fixes every shape).
- Consistency: `PipelineGitHub`, `pipelineConfigOf`, `createPipelineService`, key names `pipeline:snapshot|last-good|refreshing|action|lockout:<userId>|ship:<requestId>`, and the run name `ship <requestId> <version>` match the spec and `ship.yml`.
