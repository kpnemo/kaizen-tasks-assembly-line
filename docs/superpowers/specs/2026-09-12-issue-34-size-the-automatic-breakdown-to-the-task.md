# Spec: #34 Size the automatic breakdown to the task, up to fifty steps

Context: docs/superpowers/briefs/2026-09-12-issue-34-size-the-automatic-breakdown-to-the-task.md

Decision record: kaizen-tasks-api ADR 0008 (`docs/adr/0008-size-the-breakdown-to-the-task.md`).

## What

The AI breakdown proposes as many steps as the task needs instead of a fixed three to seven: none for a task small enough to do as it is, a handful for a small one, up to fifty for a large one. A result over fifty is asked for once more with a limit of fifty; whatever the second answer holds is shown in full. A task judged to need no steps is shown as skipped with the reason "Small enough to do as is". Accepting, editing and dismissing steps do not change.

## Who

The signed-in person who creates a task (the breakdown runs on its own) or presses Regenerate on the task detail (the same breakdown, by hand). Both paths share one behaviour (round answer Q4).

## Behaviour

1. **Before the model.** Unchanged: a title under three words with no description is skipped as `too_short` without a model call (round answer Q3). The hourly limit, the session budget and `AI_ENABLED` are checked as today and count breakdown requests, not model calls.
2. **The prompt sizes the breakdown.** In `backend/src/agent/prompts/breakdown.system.md` the size judgement becomes the first reasoning step and gates the rest: judge first how much work the task is; when it is small enough to do as it is, return no steps and stop there; otherwise work through the remaining steps and return only the steps the task needs, never more than fifty. When the input carries `maxSteps`, return at most that many. The output contract says "zero to fifty objects". The other reasoning steps and every constraint stay, renumbered. (Final review 2026-09-12: the judgement was first placed at step 5, behind two unconditional instructions to produce a first step; it leads instead so a real model can actually answer with none.)
3. **The model may answer at any size.** `backend/src/schemas/breakdown.ts`: `MIN_STEPS` is removed, `MAX_STEPS` becomes `50` (the soft ceiling), and the zod `steps` array is `.max(200)` with no minimum so an oversize answer parses and is counted instead of failing schema validation. `BreakdownInput` in `backend/src/agent/model.ts` gains `maxSteps?: number`, and `AnthropicBreakdownModel` puts it in the user message JSON when set.
4. **Clean without cutting.** `postValidate` in `backend/src/agent/breakdown.ts` trims, drops empties and deduplicates as today, keeps every distinct step (no truncation, no minimum), and caps tag suggestions at three as today.
5. **One re-ask, then take what comes.** `breakdownTask` calls the model once; if the cleaned result has more than `MAX_STEPS` steps it calls the model once more with `{ ...input, maxSteps: MAX_STEPS }` and uses that answer, cleaned, whatever its size. If the second call is refused, invalid or throws a retryable error, or comes back with no steps at all (a task the assistant just proposed sixty steps for is not "small enough to do as is"), the first answer is kept in full (the user gets steps rather than a failure). A result of fifty or fewer is never re-asked. The re-ask is inside the same job attempt; BullMQ retries only on thrown retryable errors, as today.
6. **No steps is a skip.** When the final cleaned result has zero steps, `processBreakdownJob` in `backend/src/jobs/processors/breakdown.ts` writes `aiStatus = 'skipped'`, `aiSkipReason = 'no_steps_needed'` and the filtered tag suggestions, and creates no suggested steps; any previous suggested steps of this generation's predecessor are replaced as they are today. `aiSkipReasonEnum` in `backend/src/db/schema.ts` gains the additive value `no_steps_needed` with a `drizzle/` migration (`ALTER TYPE ... ADD VALUE`); `AiSkipReasonSchema` in `backend/src/schemas/tasks.ts` follows and the contract is regenerated.
7. **Web.** After the contract pull, `SKIP_LABELS` in `frontend/src/lib/format.ts` gains `no_steps_needed: "Small enough to do as is"`. `AiBanner` and `AiChip` render the new reason through the existing skipped state; `StepList` renders every suggested step and gains no cap. Nothing structural changes.
8. **Fake model.** `FakeBreakdownModel` gains a scripted form: a queue of outcomes consumed one per call, so tests can drive "sixty then fifty", "sixty then sixty", "sixty then invalid" and "no steps". The default four-step fixture stays valid.

## Acceptance criteria as tests

No comment on the issue overrides the form's criteria; these are the six as written.

1. Creating a clearly small task shows the skipped banner with a reason and no suggested steps. `backend/src/jobs/processors/breakdown.test.ts::marks the task skipped with no_steps_needed when the assistant returns no steps` (aiStatus skipped, aiSkipReason no_steps_needed, zero suggested children, tag suggestions kept); `frontend/src/lib/format.test.ts::labels no_steps_needed as Small enough to do as is` and `frontend/src/features/tasks/components/AiBanner.test.tsx::shows the skipped banner with Small enough to do as is`.
2. Creating a clearly large task produces more than seven suggested steps. `backend/src/agent/breakdown.test.ts::keeps twenty distinct steps` (replaces "caps steps at seven").
3. Different task sizes produce different step counts; the count is not fixed at seven. `backend/src/agent/prompt.test.ts::asks the assistant to size the breakdown, zero to fifty, and no longer says stop at seven`; `backend/src/schemas/schemas.test.ts::BreakdownSchema accepts zero steps and fifty-one steps`.
4. No breakdown proposes more than fifty on the first attempt; over fifty is retried once with a limit of fifty. `backend/src/agent/breakdown.test.ts::re-asks once with maxSteps fifty when the first answer has more than fifty steps` (two calls, the second input carries `maxSteps: 50`, the result is the second answer) and `::does not re-ask when the first answer has fifty steps`.
5. If the retry still returns more than fifty, every returned step is shown. `backend/src/agent/breakdown.test.ts::keeps every step when the second answer is still over fifty` (sixty in, sixty out, two calls) and `::keeps the first answer when the re-ask fails`; `frontend/src/features/tasks/components/StepList.test.tsx::renders sixty suggested steps without a cap`.
6. Each suggested step can still be accepted, edited or dismissed, and accept-all and dismiss-all still work. Existing `backend/tests/api/tasks.test.ts` suggestion tests and existing web `StepRow` and `BulkBar` tests stay green, unchanged.

Also: `backend/src/schemas/schemas.test.ts` asserts the enum list `too_short, rate_limited, ai_disabled, no_steps_needed`; `backend/tests/live/breakdown.live.test.ts` drops `MIN_STEPS` and asserts `1..MAX_STEPS` for its realistic task.

## Out of scope

- A setting to turn the automatic breakdown on or off, or to request it manually.
- Changes to how steps are accepted, edited or dismissed.
- Changes to the hourly limit, session budget or the `AI_ENABLED` kill switch.
- A model-written skip reason (round answer Q2: the reason is fixed).
- Removing the pre-model title rule (round answer Q3).
- `docs/PRD.md` sections 5.2 still say three to seven; a separate docs pull request in the assembly-line repo updates it.

## Looks

The existing skipped `Alert` on the task detail (`AiBanner`, title "The assistant skipped this task") with the reason line "Small enough to do as is", and the same words in the task-list `AiChip`. The look came from the request and was confirmed in the round (Q1). No new control, icon or placement; both themes render as the existing skipped state does. The web pull request carries the task-detail screenshot in both themes with this reason showing.

## Repos and files touched

kaizen-tasks-api (`backend/`), first:

- `src/agent/prompts/breakdown.system.md`, `src/agent/prompt.test.ts`
- `src/schemas/breakdown.ts`, `src/schemas/tasks.ts`, `src/schemas/schemas.test.ts`
- `src/agent/model.ts`, `src/agent/anthropic-model.ts`, `src/agent/anthropic-model.test.ts` (comment), `src/agent/fake-model.ts`
- `src/agent/breakdown.ts`, `src/agent/breakdown.test.ts`
- `src/jobs/processors/breakdown.ts`, its test
- `src/db/schema.ts`, new `drizzle/` migration
- `openapi.json`, `docs/API.md` (regenerated), `docs/product-map.md` (regenerated, header prose "three to seven" fixed by hand), `CHANGELOG.md`, `docs/adr/0008-size-the-breakdown-to-the-task.md` (status to Accepted), `tests/live/breakdown.live.test.ts`

kaizen-tasks-web (`frontend/`), after pulling the contract:

- `src/api/openapi.json`, `src/api/types.ts` (pulled and regenerated), new `docs/adr/0012-*.md` for the contract pull
- `src/lib/format.ts`, its test; `AiBanner.test.tsx`, `StepList.test.tsx`
- `docs/product-map.md` header prose, `CHANGELOG.md`, `docs/screenshots/` task-detail skipped in both themes
