# Size the automatic breakdown to the task (#34) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The breakdown proposes as many steps as the task needs (none to fifty, one re-ask above fifty, then everything is kept), and a task needing no steps is shown as skipped with the reason "Small enough to do as is".

**Architecture:** The prompt does the sizing; the zod output schema stops bounding the count so the code can count; `breakdownTask` re-asks once with `maxSteps: 50`; the worker turns an empty result into `aiStatus = 'skipped'` with the new additive enum value `no_steps_needed`; the web pulls the contract and adds one label. API first, web after the pull. ADR 0008 in the API repo records the decision.

**Tech Stack:** Express 5, zod, Drizzle (Postgres enum, additive migration), BullMQ, Anthropic SDK structured output, vitest; React 19, MSW, Playwright screenshots.

**Spec:** `docs/superpowers/specs/2026-09-12-issue-34-size-the-automatic-breakdown-to-the-task.md`

## Global Constraints

- Branch `feat/34-size-the-automatic-breakdown-to-the-task` in every repo; base `develop`. Never merge, never push to `develop`.
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Skip reason value is exactly `no_steps_needed`; its label is exactly `Small enough to do as is`.
- `MAX_STEPS = 50` is a soft ceiling: one re-ask, no truncation after it. `MIN_STEPS` no longer exists.
- The pre-model rule `shouldSkipBreakdown` (under three words, no description → `too_short`) is unchanged.
- Hourly limit, session budget, `AI_ENABLED`: unchanged. No `package.json` version bump.
- Test first: show the failing run, then the passing run. Run every npm command inside the repo after `nvm use`.
- Docs gate: `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci` must end with `docs-check: OK`. Never `npm run docs:check` (that is the hook mode).

---

## API: `backend/` (kpnemo/kaizen-tasks-api)

Skill: `backend/.claude/skills/add-api-endpoint/SKILL.md` (no new endpoint, but the same order: failing test, schema, service, contract, changelog, ADR, product map, checks, commit).

### Task 1: The model may answer at any size

**Files:**
- Modify: `src/schemas/breakdown.ts`
- Modify: `src/agent/model.ts` (`BreakdownInput.maxSteps`)
- Modify: `src/agent/prompts/breakdown.system.md` (rule 5, output contract, input section)
- Modify: `src/agent/fake-model.ts` (scripted answers)
- Modify: `src/agent/breakdown.ts` (`postValidate` no longer truncates or requires a minimum)
- Test: `src/agent/prompt.test.ts`, `src/schemas/schemas.test.ts`, `src/agent/breakdown.test.ts`, `tests/live/breakdown.live.test.ts`

**Interfaces:**
- Produces: `MAX_STEPS = 50`; `BreakdownSchema.steps` is `z.array(...).max(200)`; `BreakdownInput` gains `maxSteps?: number`; `FakeBreakdownModel` gains `script?: BreakdownOutcome[]` consumed one per call before falling back to `mode`; `postValidate(raw): BreakdownResult` returns every distinct step.

- [ ] **Step 1: Write the failing tests**

`src/agent/prompt.test.ts`: replace `expect(prompt).toContain("Stop at seven");` with

```ts
    expect(prompt).not.toContain("Stop at seven");
    expect(prompt).toContain("small enough to do as it is");
    expect(prompt).toContain("never more than fifty");
    expect(prompt).toContain("maxSteps");
```

`src/schemas/schemas.test.ts`: add, importing `BreakdownSchema` from `./breakdown.js`:

```ts
describe("BreakdownSchema", () => {
  const step = { title: "Do a thing", rationale: "because" };
  it("accepts zero steps and fifty-one steps", () => {
    expect(BreakdownSchema.safeParse({ steps: [], tagSuggestions: [] }).success).toBe(true);
    const many = Array.from({ length: 51 }, () => step);
    expect(BreakdownSchema.safeParse({ steps: many, tagSuggestions: [] }).success).toBe(true);
  });
});
```

`src/agent/breakdown.test.ts`: replace the two `postValidate` tests "drops empty titles and rejects fewer than three distinct steps" and "caps steps at seven and tag suggestions at three" with

```ts
  it("drops empty titles and keeps a result with no steps", () => {
    const result = postValidate({ steps: [step("   "), step("One"), step("one")], tagSuggestions: [] });
    expect(result.steps.map((s) => s.title)).toEqual(["One"]);
    expect(postValidate({ steps: [], tagSuggestions: ["a"] })).toEqual({ steps: [], tagSuggestions: ["a"] });
  });

  it("keeps twenty distinct steps and caps tag suggestions at three", () => {
    const many = Array.from({ length: 20 }, (_, i) => step(`Step ${i + 1}`));
    const result = postValidate({ steps: many, tagSuggestions: ["a", "b", "c", "d"] });
    expect(result.steps).toHaveLength(20);
    expect(result.steps[19]?.title).toBe("Step 20");
    expect(result.tagSuggestions).toEqual(["a", "b", "c"]);
  });
```

Remove the now-unused `BreakdownInvalid` import only if nothing else in the file uses it (the "breakdownTask outcomes" test still does; keep it).

- [ ] **Step 2: Run them and watch them fail**

Run: `npx vitest run --project unit src/agent/prompt.test.ts src/schemas/schemas.test.ts src/agent/breakdown.test.ts`
Expected: FAIL. Prompt still contains "Stop at seven"; `BreakdownSchema` rejects 0 and 51 steps; `postValidate` throws below three and returns 7 of 20.

- [ ] **Step 3: Implement**

`src/schemas/breakdown.ts`:

```ts
import { z } from "zod";

/** Soft ceiling: above it the model is asked once more with this limit, then the answer is kept as is. */
export const MAX_STEPS = 50;
/** Loose parse bound so an oversize answer is counted by the code instead of failing schema validation. */
export const PARSE_MAX_STEPS = 200;
export const MAX_TAG_SUGGESTIONS = 3;

export const BreakdownSchema = z.object({
  steps: z.array(z.object({ title: z.string(), rationale: z.string() })).max(PARSE_MAX_STEPS),
  tagSuggestions: z.array(z.string()).max(MAX_TAG_SUGGESTIONS),
});

export type BreakdownResult = z.infer<typeof BreakdownSchema>;
```

`src/agent/model.ts`, in `BreakdownInput` add after `openTasks`:

```ts
  /** Set on the one re-ask: the model must return at most this many steps. */
  maxSteps?: number;
```

`src/agent/prompts/breakdown.system.md`: rule 5 becomes

```
5. Judge first how much work the task is. If the task is small enough to do as it is, one sitting with nothing to plan, return no steps at all. Otherwise return only the steps the task needs: two for a small task, twenty for a large one, never more than fifty. Never pad a short list and never squeeze a long one. When the input carries `maxSteps`, return at most that many steps and fold the remainder into the last step.
```

Output contract: `an ordered list of zero to fifty objects`. Input section: add `\`maxSteps\` is present only when a previous answer was too long; it is the most steps you may return.`

`src/agent/fake-model.ts`: add scripted answers.

```ts
export class FakeBreakdownModel implements BreakdownModel {
  mode: FakeMode;
  result: BreakdownResult;
  /** Outcomes consumed one per call, in order, before `mode` applies. */
  readonly script: BreakdownOutcome[];
  readonly calls: BreakdownInput[] = [];

  constructor(options: { mode?: FakeMode; result?: BreakdownResult; script?: BreakdownOutcome[] } = {}) {
    this.mode = options.mode ?? "ok";
    this.result = options.result ?? FAKE_BREAKDOWN_RESULT;
    this.script = [...(options.script ?? [])];
  }

  async complete(input: BreakdownInput): Promise<BreakdownOutcome> {
    this.calls.push(input);
    const scripted = this.script.shift();
    if (scripted) return structuredClone(scripted);
    switch (this.mode) { /* unchanged */ }
  }
}
```

`src/agent/breakdown.ts` `postValidate`: drop the `MIN_STEPS` import and the `if (steps.length === MAX_STEPS) break;` line and the `if (steps.length < MIN_STEPS) throw` block; update the doc comment to "Trim, drop empties, deduplicate case-insensitively, keep every distinct step, cap tag suggestions at three." Keep the `MAX_STEPS` import for Task 2.

`tests/live/breakdown.live.test.ts`: drop `MIN_STEPS`; assert `toBeGreaterThanOrEqual(1)` and `toBeLessThanOrEqual(MAX_STEPS)`; rename the test "returns a sized list of steps with rationales and at most three tags for a realistic task".

`src/agent/anthropic-model.test.ts` line 113 comment: "e.g. a step without a title" instead of the MIN_STEPS wording.

- [ ] **Step 4: Run to green**

Run: `npx vitest run --project unit src/agent src/schemas`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: let the breakdown answer at any size (#34)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 2: One re-ask above fifty, then take what comes

**Files:**
- Modify: `src/agent/breakdown.ts` (`breakdownTask`)
- Test: `src/agent/breakdown.test.ts`

**Interfaces:**
- Consumes: `MAX_STEPS`, `FakeBreakdownModel({ script })`, `postValidate` from Task 1.
- Produces: `breakdownTask(input, model): Promise<BreakdownResult>` with the re-ask rule below; the worker keeps calling it unchanged.

- [ ] **Step 1: Write the failing tests** (append to `src/agent/breakdown.test.ts`)

```ts
const manySteps = (n: number) => Array.from({ length: n }, (_, i) => step(`Step ${i + 1}`));
const ok = (n: number) => ({ kind: "ok" as const, result: { steps: manySteps(n), tagSuggestions: [] } });

describe("breakdownTask re-ask", () => {
  it("re-asks once with maxSteps fifty when the first answer has more than fifty steps", async () => {
    const model = new FakeBreakdownModel({ script: [ok(60), ok(45)] });
    const result = await breakdownTask(input, model);
    expect(model.calls).toHaveLength(2);
    expect(model.calls[0]).toEqual(input);
    expect(model.calls[1]).toEqual({ ...input, maxSteps: 50 });
    expect(result.steps).toHaveLength(45);
  });

  it("does not re-ask when the first answer has fifty steps", async () => {
    const model = new FakeBreakdownModel({ script: [ok(50)] });
    expect((await breakdownTask(input, model)).steps).toHaveLength(50);
    expect(model.calls).toHaveLength(1);
  });

  it("keeps every step when the second answer is still over fifty", async () => {
    const model = new FakeBreakdownModel({ script: [ok(60), ok(60)] });
    expect((await breakdownTask(input, model)).steps).toHaveLength(60);
    expect(model.calls).toHaveLength(2);
  });

  it("keeps the first answer when the re-ask fails", async () => {
    const invalid = { kind: "invalid" as const, reason: "garbage" };
    const model = new FakeBreakdownModel({ script: [ok(60), invalid] });
    expect((await breakdownTask(input, model)).steps).toHaveLength(60);
    const outage = new FakeBreakdownModel({ script: [ok(60)], mode: "retryable-error" });
    expect((await breakdownTask(input, outage)).steps).toHaveLength(60);
  });

  it("returns no steps when the model returns none", async () => {
    const model = new FakeBreakdownModel({ script: [ok(0)] });
    expect(await breakdownTask(input, model)).toEqual({ steps: [], tagSuggestions: [] });
  });
});
```

- [ ] **Step 2: Run and watch it fail**

Run: `npx vitest run --project unit src/agent/breakdown.test.ts`
Expected: FAIL. One call only, 60 steps returned where 45 is expected; the failure cases throw.

- [ ] **Step 3: Implement** (`src/agent/breakdown.ts`, replace `breakdownTask`)

```ts
async function askOnce(input: BreakdownInput, model: BreakdownModel): Promise<BreakdownResult> {
  const outcome = await model.complete(input);
  if (outcome.kind === "refused") throw new BreakdownRefused(outcome.reason);
  if (outcome.kind === "invalid") throw new BreakdownInvalid(outcome.reason);
  return postValidate(outcome.result);
}

/**
 * Pure orchestration (ADR 0008): call the model; above MAX_STEPS ask once more with that limit
 * and keep whatever comes back, the first answer when the re-ask fails. No truncation.
 */
export async function breakdownTask(
  input: BreakdownInput,
  model: BreakdownModel,
): Promise<BreakdownResult> {
  const first = await askOnce(input, model);
  if (first.steps.length <= MAX_STEPS) return first;
  try {
    return await askOnce({ ...input, maxSteps: MAX_STEPS }, model);
  } catch {
    return first;
  }
}
```

- [ ] **Step 4: Run to green**

Run: `npx vitest run --project unit src/agent`
Expected: PASS, including the existing "maps refused and invalid outcomes" test (a failing first call still throws).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: re-ask once above fifty steps, then keep the answer (#34)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

### Task 3: No steps is a skip, the enum, the contract and the docs

**Files:**
- Modify: `src/db/schema.ts` (`aiSkipReasonEnum`), create `drizzle/0003_no_steps_needed.sql` via `npm run db:generate`
- Modify: `src/schemas/tasks.ts` (`AiSkipReasonSchema`), `src/schemas/schemas.test.ts` (enum list)
- Modify: `src/jobs/processors/breakdown.ts` (zero-step result)
- Test: `tests/jobs/breakdown.test.ts`
- Docs: `openapi.json` and `docs/API.md` (`npm run openapi`), `CHANGELOG.md`, `docs/product-map.md` header, `docs/adr/0008-size-the-breakdown-to-the-task.md` status → Accepted

**Interfaces:**
- Produces: `AiSkipReason` gains `no_steps_needed` in the contract; the web pulls it in Task 4.

- [ ] **Step 1: Write the failing tests**

`src/schemas/schemas.test.ts` line 25: `["ai_skip_reason", AiSkipReasonSchema, ["too_short", "rate_limited", "ai_disabled", "no_steps_needed"]],`

`tests/jobs/breakdown.test.ts`, after "marks a refused breakdown failed with a message":

```ts
  it("marks the task skipped with no_steps_needed when the assistant returns no steps", async () => {
    const user = await registerUser(ctx.server);
    model.script.push({ kind: "ok", result: { steps: [], tagSuggestions: ["errands"] } });
    startWorker();
    const task = await service.create(user.userId, { title: "Water the office plants" });
    const skipped = await waitFor(row(task.id, user.userId), (t) => t?.aiStatus === "skipped");
    expect(skipped?.aiSkipReason).toBe("no_steps_needed");
    expect(skipped?.aiTagSuggestions).toEqual(["errands"]);
    expect(await listChildren(ctx.db, task.id)).toHaveLength(0);
  });
```

(`model` is the suite's shared `FakeBreakdownModel`; `script` is the array from Task 1. If the suite recreates `model` in `beforeEach`, push in the test as shown.)

- [ ] **Step 2: Run and watch them fail**

Run: `npx vitest run --project unit src/schemas/schemas.test.ts && npx vitest run --project integration tests/jobs/breakdown.test.ts`
Expected: FAIL. Enum list mismatch; the worker writes `done` with zero children, never `skipped`.

- [ ] **Step 3: Implement**

`src/db/schema.ts`: add `"no_steps_needed",` to `aiSkipReasonEnum`. Then `npm run db:generate` and check the new `drizzle/0003_*.sql` is exactly `ALTER TYPE "public"."ai_skip_reason" ADD VALUE 'no_steps_needed';` (additive, ADR 0004). Rename the file to `0003_no_steps_needed.sql` and fix the tag in `drizzle/meta/_journal.json` to match.

`src/schemas/tasks.ts`: `.enum(["too_short", "rate_limited", "ai_disabled", "no_steps_needed"])`.

`src/jobs/processors/breakdown.ts`, between step 4 and step 5 (after the `try/catch` around `breakdownTask`):

```ts
  // 4b. No steps needed (ADR 0008): a skip, not a failure. Tag suggestions are still kept.
  if (result.steps.length === 0) {
    const onTaskNow = new Set((taskTagMap.get(task.id) ?? []).map((t) => t.name.toLowerCase()));
    const kept = result.tagSuggestions.filter((name) => !onTaskNow.has(name.toLowerCase()));
    await db.transaction(async (tx) => {
      await replaceSuggestedChildren(tx, {
        taskId: task.id, userId: data.userId, generationId: data.generationId, steps: [], tagSuggestions: kept,
      });
      await updateAiState(tx, task.id, data.generationId, {
        aiStatus: "skipped",
        aiSkipReason: "no_steps_needed",
      });
    });
    log.info({ tagSuggestions: kept.length }, "skipped: no steps needed");
    return;
  }
```

Check `replaceSuggestedChildren` sets `aiStatus: "done"` inside; if it does, the `updateAiState` call after it in the same transaction overrides it, which is the intent. If `AiStatePatch` does not accept `aiSkipReason` with `aiStatus: "skipped"` in one patch, look at how the `too_short` branch does it and copy that shape.

- [ ] **Step 4: Contract, docs, checks**

```bash
npm run openapi          # openapi.json and docs/API.md
```

`CHANGELOG.md` under `## [Unreleased]`:

```markdown
### Changed

- The breakdown proposes as many steps as the task needs, from none to fifty, instead of a fixed three to seven; a result over fifty is asked for once more with a limit of fifty and the second answer is kept in full. A task the assistant judges small enough to do as it is is skipped with the new reason `no_steps_needed` (#34, ADR 0008).
```

`docs/product-map.md` header prose: "an AI assistant proposes three to seven small steps" → "an AI assistant proposes as many small steps as the task needs, none to fifty". `docs/adr/0008-size-the-breakdown-to-the-task.md`: `Status: Accepted`. Check `docs/ARCHITECTURE.md` and `README.md` for "three to seven" (`grep -n "three to seven" docs README.md`) and fix any hit.

```bash
npm run product-map
npm test
npm run typecheck
npm run lint
```

Expected: every command exits 0, the new integration test passes.

- [ ] **Step 5: Commit and gate**

```bash
git add -A && git commit -m "feat: no steps needed is a skip; enum, contract and docs (#34)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected last line: `docs-check: OK`. If it fails, fix the docs and amend.

---

## Web: `frontend/` (kpnemo/kaizen-tasks-web)

Skill: `frontend/.claude/skills/add-frontend-feature/SKILL.md`.

### Task 4: The label, the contract pull, the tests and the screenshot

**Files:**
- Pull: `src/api/openapi.json`, `src/api/types.ts`
- Create: `docs/adr/0012-contract-pull-no-steps-needed.md`
- Modify: `src/lib/format.ts`, `src/lib/format.test.ts`, `src/features/tasks/TaskDetailPage.test.tsx`, `tests/msw/db.ts` (a `T_NO_STEPS` fixture row), `CHANGELOG.md`, `docs/product-map.md` header
- Create: `scripts/screenshots/task-detail-no-steps.mjs`; commit `docs/screenshots/task-detail-no-steps-{light,dark}.png`

**Interfaces:**
- Consumes: the API contract from Task 3 (`AiSkipReason` with `no_steps_needed`).

- [ ] **Step 1: Pull the contract and write the ADR**

```bash
scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types
```

`docs/adr/0012-contract-pull-no-steps-needed.md` (format of `docs/adr/0011-*.md`): Status Accepted, Date 2026-09-12. Context: kaizen-tasks-api ADR 0008 adds the skip reason `no_steps_needed` and the breakdown may return up to fifty steps or none. Decision: `src/api/openapi.json` and `src/api/types.ts` are pulled from the API branch `feat/34-size-the-automatic-breakdown-to-the-task`; the only web change is the label `Small enough to do as is` in `src/lib/format.ts`; the step list is not capped. Consequences: `SKIP_LABELS` is `Record<AiSkipReason, string>`, so the build fails until the label exists; long lists render as they are.

- [ ] **Step 2: Write the failing tests**

`src/lib/format.test.ts`, inside "labels every skip reason in words": `expect(skipReasonLabel("no_steps_needed")).toBe("Small enough to do as is");`

`tests/msw/db.ts`: add `export const T_NO_STEPS = "t-4";` and a row next to the `T_SKIPPED` one: `makeTask({ id: T_NO_STEPS, title: "Water the office plants", aiStatus: "skipped", aiSkipReason: "no_steps_needed" })` with no children.

`src/features/tasks/TaskDetailPage.test.tsx`, append:

```ts
  it("shows the skipped banner with Small enough to do as is when the assistant needed no steps", async () => {
    renderApp({ route: `/tasks/${T_NO_STEPS}` });
    const banner = await screen.findByRole("status", { name: "Assistant" });
    expect(within(banner).getByText("The assistant skipped this task")).toBeInTheDocument();
    expect(within(banner).getByText("Small enough to do as is")).toBeInTheDocument();
    expect(screen.getByText("No steps yet.")).toBeInTheDocument();
  });

  it("renders sixty suggested steps without a cap", async () => {
    const parent = db.find(T_SUGGESTED)!;
    db.rows.push(...Array.from({ length: 60 }, (_, i) =>
      makeStep({ id: `big-${i}`, parentId: parent.id, title: `Big step ${i + 1}`, origin: "ai", suggestionState: "suggested" }),
    ));
    renderApp({ route });
    await screen.findByRole("listitem", { name: "Big step 60" });
    expect(screen.getAllByRole("listitem", { name: /Big step/ })).toHaveLength(60);
  });
```

(Import `T_NO_STEPS` and `makeStep` from `tests/msw/db`. If `db.rows` is not the array's name, use the collection `db.detail` reads from; if `T_SUGGESTED` already has suggested children, the count stays 60 because of the name filter.)

- [ ] **Step 3: Run and watch them fail**

Run: `npx vitest run src/lib/format.test.ts src/features/tasks/TaskDetailPage.test.tsx`
Expected: FAIL. `skipReasonLabel("no_steps_needed")` is a type error and returns `undefined`; the banner test finds no `T_NO_STEPS` row until the fixture exists (add the fixture in this step so the test fails on the label, not the fixture).

- [ ] **Step 4: Implement**

`src/lib/format.ts`: add `no_steps_needed: "Small enough to do as is",` to `SKIP_LABELS`.

`CHANGELOG.md` under `## [Unreleased]`: `- **Changed** — The assistant's breakdown is sized to the task, none to fifty steps; a task judged small enough shows the skipped banner with "Small enough to do as is" (#34).`

`docs/product-map.md` header: "breaks it into three to seven steps" → "breaks it into as many steps as it needs, none to fifty".

```bash
npm run product-map && npm test && npm run lint && npm run typecheck
```

Expected: all green.

- [ ] **Step 5: Commit, then screenshot**

```bash
git add -A && git commit -m "feat: label the no_steps_needed skip reason (#34)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

`scripts/screenshots/task-detail-no-steps.mjs` (pattern of `task-detail-skipped.mjs`; the fake model cannot return zero steps on demand, so the detail response is rewritten in the browser):

```js
// A task the assistant judged small enough to do as it is: the "Assistant" status banner with
// "Small enough to do as is", an outline Regenerate, then the Empty steps state. The API's fake
// model always answers with steps, so the task detail response is rewritten to the skipped state.
import { bringUnderHeader, openNewTask, parkPointer } from "./lib/task.mjs";

export const route = "/tasks";
export { readyOnList as ready } from "./lib/task.mjs";

export async function act(page) {
  await page.route(/\/api\/v1\/tasks\/[0-9a-f-]{36}$/, async (route) => {
    if (route.request().method() !== "GET") return route.continue();
    const response = await route.fetch();
    const body = await response.json();
    body.data = { ...body.data, aiStatus: "skipped", aiSkipReason: "no_steps_needed", children: [] };
    await route.fulfill({ response, json: body });
  });
  await openNewTask(page, "Water the office plants");
  await page.getByText("Small enough to do as is").waitFor({ timeout: 20_000 });
  await page.getByText("No steps yet.").waitFor({ timeout: 5_000 });
  await bringUnderHeader(page, page.getByRole("status", { name: "Assistant" }));
  await parkPointer(page);
}
```

```bash
node scripts/screenshot.mjs task-detail-no-steps
```

Open `docs/screenshots/task-detail-no-steps-light.png` and `-dark.png` with the Read tool; check against the spec's Looks: the existing skipped Alert, title "The assistant skipped this task", reason "Small enough to do as is", Regenerate, both themes. Then:

```bash
git add scripts/screenshots/task-detail-no-steps.mjs docs/screenshots/task-detail-no-steps-*.png
git commit -m "docs: screenshots of the no-steps skipped state (#34)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected last line: `docs-check: OK`. The pull request embeds the PNGs with commit-pinned raw URLs (`https://raw.githubusercontent.com/kpnemo/kaizen-tasks-web/<sha of this commit>/docs/screenshots/task-detail-no-steps-light.png`). If `screenshot.mjs` exits 2, the pull request body carries `Screenshot unavailable: <its reason>` and no images.

---

## Pull requests (implement-issue Step 8)

API first, then web, then the docs pull request in the assembly-line repo with the briefing, the spec and this plan. Every body says `Part of kpnemo/kaizen-tasks-assembly-line#34`, never a closing keyword, and checks off the six criteria with the failing and passing test output.
