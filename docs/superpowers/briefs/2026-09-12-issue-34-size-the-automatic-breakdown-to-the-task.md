# Briefing: #34 Size the automatic breakdown to the task, up to fifty steps

- Summary: The automatic breakdown that runs on task creation always comes back with about seven steps, so small tasks are padded and large ones squeezed. The assistant should judge the size first and propose only the steps the task needs: sometimes twenty, sometimes two, sometimes none, with a ceiling of fifty. A task judged to need no steps shows the existing skipped banner with a reason such as "small enough to do as is"; a result over fifty is re-asked once for at most fifty, and if it is still over fifty every returned step is shown. Accept, edit and dismiss do not change.
- Triage: readiness 16, clarity 5, complexity 3, risk 3 (architecture change)
- UI: visible
- Repos: kaizen-tasks-api, kaizen-tasks-web

## What exists today

- The count is fixed in three places at once. The prompt `backend/src/agent/prompts/breakdown.system.md` says "Stop at seven steps ... Never return fewer than three" (rule 5) and "three to seven" in the output contract. `backend/src/schemas/breakdown.ts` exports `MIN_STEPS = 3`, `MAX_STEPS = 7` and a zod `steps` array with `.min(3).max(7)`; that same zod object is the structured-output format handed to the Anthropic SDK in `backend/src/agent/anthropic-model.ts`, so a model answer outside 3 to 7 fails schema parsing before the code ever counts it. `postValidate` in `backend/src/agent/breakdown.ts` truncates at `MAX_STEPS` and throws `BreakdownInvalid` below `MIN_STEPS`; the worker maps that to `aiStatus = 'failed'` with "The assistant returned an unusable answer, try again".
- There is no in-band re-ask. `anthropic-model.ts` makes one bounded call per job attempt; BullMQ owns retries (ADR 0003: 3 attempts, exponential backoff).
- The model's output has no way to say "no steps": `BreakdownSchema` is `steps` plus `tagSuggestions`, and an empty array is invalid.
- Skipped state: `aiSkipReason` is a Postgres enum with three values, `too_short`, `rate_limited`, `ai_disabled` (`backend/src/db/schema.ts`, `AiSkipReasonSchema` in `backend/src/schemas/tasks.ts`). `rate_limited` and `ai_disabled` are set before enqueueing in `backend/src/services/tasks.ts`; `too_short` is the only skip the worker writes (`backend/src/jobs/processors/breakdown.ts`), from `shouldSkipBreakdown` in `breakdown.ts`: fewer than three words in the title and no description. "Buy milk" is two words, so today it is skipped as `too_short` before any model call.
- Web: `AiBanner.tsx` renders the skipped state generically off `aiSkipReason` with the title "The assistant skipped this task" and the reason in words from `SKIP_LABELS` in `frontend/src/lib/format.ts` (typed `Record<AiSkipReason, string>`, so a new enum value must get a label or the build fails). `AiChip.tsx` shows the same reason. `StepList.tsx` renders every visible step with no cap.
- The fake model `backend/src/agent/fake-model.ts` returns a fixed four-step result and has no call-count or size-dependent behaviour.

## Touched areas

- Prompt: `backend/src/agent/prompts/breakdown.system.md` (rule 5 and the output contract).
- Output schema and constants: `backend/src/schemas/breakdown.ts` (`MIN_STEPS`, `MAX_STEPS`, zod bounds).
- Orchestration: `backend/src/agent/breakdown.ts` (`postValidate`, `breakdownTask`: count check, one re-ask), `backend/src/agent/model.ts` (input shape if the re-ask passes a limit), `backend/src/agent/anthropic-model.ts`, `backend/src/agent/fake-model.ts`.
- Worker: `backend/src/jobs/processors/breakdown.ts` (empty result becomes `skipped` with the new reason instead of `failed`).
- Skip reason enum: `backend/src/db/schema.ts` `aiSkipReasonEnum` plus an additive `drizzle/` migration (`ALTER TYPE ... ADD VALUE`), `AiSkipReasonSchema` in `backend/src/schemas/tasks.ts`, `openapi.json`, `docs/API.md`, `backend/src/schemas/schemas.test.ts` (asserts the exact enum list).
- Tests pinning the numbers: `backend/src/agent/prompt.test.ts` ("Stop at seven"), `backend/src/agent/breakdown.test.ts` ("caps steps at seven"), `backend/src/agent/anthropic-model.test.ts`.
- Web: `frontend/src/api/openapi.json` and `types.ts` (contract pull, ADR), `frontend/src/lib/format.ts` (`SKIP_LABELS`), `AiBanner.tsx` and `AiChip.tsx` render the new reason with no structural change. Screen: `/tasks/:id` (`TaskDetailPage`).
- Prose stating the count: both product-map headers ("three to seven"), `docs/PRD.md` sections 5.2 lines 97-98 in the workspace repo (not editable by this skill; noted below).

## Mockups seen

none

## Unknowns

- Whether the Anthropic structured-output path tolerates a zod array with no upper bound for the model to actually return more than fifty; if the SDK format needs a ceiling, the code counts against fifty after a looser parse (say `.max(200)`).
- `docs/PRD.md` still says three to seven; this skill cannot edit it, so the spec records the divergence for a later docs pull request.

## Open questions

1. Where does the "no steps" reason come from and how is it stored? — suggested answer: a fixed new skip reason `no_steps_needed` (additive enum value) labelled "Small enough to do as is" in the web; the model signals it by returning an empty `steps` array. A model-written sentence would need a new column and free text on the banner, which the request does not ask for.
2. The pre-model title rule (under three words, no description → `too_short`) still catches "Buy milk" before the assistant sees it. Keep it? — suggested answer: keep it as is; it saves a model call and the criterion (a skipped banner with a reason) still passes. Tasks of three words or more that are still small ("Water the office plants") reach the assistant and get the new reason. The alternative is removing the rule so every task is judged by the assistant.
3. Does the manual Regenerate (`POST /tasks/:id/breakdown`) get the same sized behaviour, including the re-ask? — suggested answer: yes, one breakdown behaviour everywhere; the request names creation because that is where it runs on its own, but the same worker serves both.

Decisions taken without asking: the re-ask is a second model call inside the same job attempt (not a BullMQ retry) and does not count as a second breakdown against the hourly limit or session budget, which the request puts out of scope. The ceiling of fifty is a soft one: past the re-ask, no truncation.
