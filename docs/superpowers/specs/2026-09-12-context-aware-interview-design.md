# Context-aware feature request interview: design

**Status:** approved by Mike on 2026-09-12 00:45 IDT (design presented in chat, one yes).
**Tracking issue:** kpnemo/kaizen-tasks-assembly-line#31.
**Repos:** `kpnemo/kaizen-tasks-api` (contract first) and `kpnemo/kaizen-tasks-web`. Cross-repo docs here.
**Release:** no version bump in the feature pull requests; `ship.yml` cuts 1.7.0 at promotion.
**Supersedes parts of:** `2026-09-10-agentic-feature-request-design.md` sections 2 (Turns), 3.4 (Interview agent) and 3.6 (Config). Everything that spec says and this one does not contradict still holds.

## 1. Goal

Make the in-app interview ask like someone who knows the product. Today the interviewer's system prompt carries no knowledge of Kaizen Tasks, walks a fixed five-step ladder, may not propose anything, and runs on the breakdown's model. On #29 it asked who sees the header and what the header would look like after the change, both answered by the opening message and by the product map. After this change the interviewer reads the product before it asks, opens by confirming what it understood and pre-filling the draft, asks only what is genuinely open, recommends an answer to every question, lets the PM finish at any point, and runs on Fable.

Non-goals: no change to the breakdown agent or `AI_MODEL`; no inline editing of the draft panel (the PM corrects through the chat and the final form); no change to the CLI `/implement-issue` grilling round; no change to filing (`POST /feature-requests` is untouched).

## 2. Experience

Same page, same two panels. What changes:

- **Opening turn.** After the PM's first message the assistant replies in plain prose: two to five sentences saying what it understood, one sentence naming what it filled in from the product context (for example "I filled the users and the screen from the product map: the header is on every signed-in page"), then exactly one question. The right-hand draft fills at the same moment: title, problem and proposed behavior at least, acceptance criteria and out of scope when the message or the product context supports them. The PM corrects by typing a correction in the answer box or by answering the question; either is one turn.
- **Every question** carries three or four option chips as today. One of them is the recommended answer: it renders **first** in the chips row with a small "Recommended" badge inside the chip. Clicking it sends its text like any chip.
- **Finish with what we have.** An outline chip after "Skip this question", shown once at least one question has been asked. Pressing it ends the interview: the assistant writes the final draft and score, the conversation becomes `ready`, "Review and file" enables, and the assistant's last bubble is one sentence saying the request is ready or naming what is still thin. The transcript records the PM's turn as "Finish with what we have".
- **Questions asked** are only the ones neither the opening message, the answers so far, nor the product context settle. The eight-question cap and the rubric stop condition are unchanged.
- **Errors, rate limits, projector rules, Start over, Skip the interview** are unchanged from the 2026-09-10 spec.

## 3. API

### 3.1 Config (`src/config.ts`)

| Variable | Type and default | Purpose |
| --- | --- | --- |
| `INTERVIEW_MODEL` | string, default `claude-fable-5-1` | the interview's model; `AI_MODEL` keeps the breakdown |
| `INTERVIEW_EFFORT` | enum `low\|medium\|high\|xhigh\|max`, default `medium` | `output_config.effort` on every interview turn |
| `PRODUCT_CONTEXT_REF` | string, default `develop` | the git ref of `kpnemo/kaizen-tasks-web` the web documents are fetched from; production sets `main` |
| `PRODUCT_CONTEXT_REFRESH_MINUTES` | positive int, default `10` | how often the web documents are re-fetched |

Existing: `AI_MODEL_PROVIDER=fake` still selects the scripted fake for the interview; `ANTHROPIC_API_KEY` is still required otherwise. Railway: set `PRODUCT_CONTEXT_REF=main` on production, leave the default on staging; `INTERVIEW_MODEL` and `INTERVIEW_EFFORT` unset (defaults) unless a fallback is needed (section 7).

### 3.2 Product context loader (`src/agent/interview/product-context.ts`)

```ts
export interface ProductContext {
  api: string;                 // this repo's docs/product-map.md, trimmed
  web: string | null;          // kaizen-tasks-web docs/product-map.md, trimmed, or null
  conventions: string | null;  // kaizen-tasks-web docs/ui-conventions.md, whole, or null
  fetchedAt: string | null;    // ISO time of the last successful web fetch
}
export interface ProductContextSource {
  readApiMap(): string;                               // disk
  fetchWebDoc(path: string): Promise<string>;         // GitHub raw
}
export class ProductContextLoader {
  constructor(source: ProductContextSource, options: { ref: string; refreshMs: number; log: Logger });
  start(): Promise<void>;      // first load; resolves after the first fetch attempt, success or not
  stop(): void;                // clears the timer
  current(): ProductContext;   // never throws; web fields null until a fetch succeeds
}
```

- **API map from disk.** `new URL("../../../docs/product-map.md", import.meta.url)`: three levels above `src/agent/interview/` and `dist/agent/interview/` alike is the package root, and the repo's `docs/` is present in the Railway build. No change to `scripts/copy-assets.sh`.
- **Web documents from GitHub raw.** `https://raw.githubusercontent.com/kpnemo/kaizen-tasks-web/<ref>/docs/product-map.md` and `.../docs/ui-conventions.md`, `fetch` with a 10 s timeout, no token (the repo is public). Both documents are fetched together; a failure of either keeps the previous good pair (or null on the first load) and logs one `warn` with the URL and the reason. A refresh runs every `PRODUCT_CONTEXT_REFRESH_MINUTES` on a timer that is `unref()`ed so it never holds the process open; `stop()` clears it on shutdown.
- **Trimming.** From each product map, drop the `## Recent releases` and `## Unreleased changes` sections (history, not current behavior): everything from that heading to the next `## ` heading or the end. Keep every other section and the prose header. `ui-conventions.md` is kept whole.
- **In `APP_ENV=test` and with the fake provider** the loader is not started; tests construct it with a fake source. Startup never waits on the network for longer than the fetch timeout.

### 3.3 System prompt (`src/agent/prompts/interview.system.md`) and blocks (`prompt.ts`)

`systemBlocks(context)` returns **three** cached blocks: the instructions, the rubric, then the product context rendered as:

```markdown
# Product context (what exists today)

## API: kpnemo/kaizen-tasks-api
<api map, trimmed>

## Web app: kpnemo/kaizen-tasks-web
<web map, trimmed — or the one line "Web product map: unavailable (fetch failed)">

## UI conventions
<ui-conventions.md — or the one line "UI conventions: unavailable (fetch failed)">
```

Each block carries `cache_control: { type: "ephemeral" }`; three of the four allowed breakpoints. The third block changes only when a map changes, so every turn of every conversation between deploys reads the same cached prefix. `transcriptMessages()` is unchanged except for the finish marker (3.5).

The instructions change as follows; the rest of the file stays.

- **Role** adds: you know the product from the product context block. Use it. Never ask what it answers, and never invent a screen, route or table it does not list.
- **The opening turn** (new section): when the transcript has exactly one PM message, the reply is what you understood in two to five sentences, then one sentence naming what you filled from the product context, then one question. Fill every draft field the message and the context support.
- **Question order** is replaced by **Choosing the question**: ask the one question whose answer most changes what gets built and that neither the PM's words nor the product context settle. Prefer, in this order, a decision that changes scope, then one that changes what a tester would check, then one that changes what the user sees. Never ask what a re-read of the transcript or the context answers. A question with "and" in it is two questions.
- **Options** gain: `recommended` is the answer you would give, and it must be one of `options`, word for word.
- **The draft** replaces "Use only what the product manager said" with: use what the PM said first, then what the product context implies; acceptance criteria may be proposed as checks a tester can run against the product as the context describes it; the reply must name what came from context so the PM can correct it. Numbers still come only from the PM.
- **Finishing** (new section): when the last user turn is `The PM asked to finish the interview with what you have.`, set `done` true, `question` null, `stillMissing` to what the stop condition lacks (empty when nothing), and write one sentence. Never ask a question on that turn.

### 3.4 Anthropic adapter (`anthropic-interview-model.ts`)

- Constructor options gain `effort` and `context: () => ProductContext` (a getter, so a refreshed context reaches the next turn without a restart). `system` is built per call from `systemBlocks(context())`.
- The call moves to `client.beta.messages.stream({ model, max_tokens: 16000, system, messages, tools: [reportTurn], tool_choice: { type: "auto" }, output_config: { effort }, betas: ["server-side-fallback-2026-07-01"], fallbacks: "default" }, { signal })`. No `thinking` parameter: Fable always thinks. If the installed SDK rejects the scalar `fallbacks`, use the array form `fallbacks: [{ model: "claude-opus-5" }]` with beta `server-side-fallback-2026-06-01`; the plan verifies this against the SDK types before writing the test.
- `max_tokens` rises from 4000 to 16000 because thinking tokens count toward it. The interview's own timeout is `INTERVIEW_TIMEOUT_MS = 90_000` (the breakdown keeps 45 s); the 15 s `: ping` comment already covers the wait.
- Validation adds one `disagreementIn` rule: `question.recommended` must be one of `question.options`, otherwise `{ kind: "invalid" }`. A `stop_reason` of `refusal` already falls under "not `tool_use`" and is invalid, so the route emits `error` and persists nothing, as today.
- The client is constructed with `timeout: INTERVIEW_TIMEOUT_MS, maxRetries: 0` as today.

### 3.5 Contract and service

Schemas (`src/schemas/feature-request-conversations.ts`):

- `InterviewQuestionSchema` gains `recommended: z.string()` (required on the model's contract).
- `ConversationMessageSchema` gains `recommended: z.string().optional()` (set on an assistant message that asked a question) and `finished: z.boolean().optional()` (set on the user message that ended the interview). Both optional so rows stored before this release still parse.
- `ConversationTurnBody` gains `finish: z.boolean().optional()`. `skip` and `finish` together is a 400 `VALIDATION_ERROR`. With `finish`, `content` is ignored and the user message is recorded as the constant `FINISHED_CONTENT = "Finish with what we have"` with `finished: true`.
- `npm run openapi` regenerates `openapi.json` and `docs/API.md`; the README route table is unchanged (no new route).

Service (`feature-request-conversations.ts`), `turn()`:

- `finish` runs the same turn as an answer, with the model's last user message replaced by `The PM asked to finish the interview with what you have.` (constant `FINISH_TURN_CONTENT` in `prompt.ts`, beside `SKIPPED_TURN_CONTENT`). The turn must come back `done: true` with `question: null`; if it carries a question the turn is invalid, like a ninth question today. A finish does not increment `question_count`. Status becomes `ready`.
- The assistant message persisted after any turn carries `recommended` from `turn.question`.
- `renderRefinementSection` prints `- **PM:** Finish with what we have` for the finished turn and adds one line under the score table: `Draft proposed by the assistant from the product context and corrected by the PM.`

Startup (`src/server.ts` or wherever `createInterviewModel` is called): build the `ProductContextLoader`, `await start()`, pass `current` as the adapter's context getter, `stop()` on shutdown.

### 3.6 Fake adapter

The scripted fake sets `recommended` to its first option on every question, and answers a finish turn (detected by `FINISH_TURN_CONTENT` as the last user message) with `done: true`, the draft built from the transcript so far, and the fixed score. It ignores the product context.

### 3.7 Tests (API)

- Loader: reads the API map from disk and trims the two history sections; a successful fetch fills `web` and `conventions`; a failed fetch keeps the previous pair and logs once; `current()` never throws; the refresh timer is `unref()`ed and `stop()` clears it.
- Prompt: `systemBlocks()` returns three cached blocks, the third contains the API endpoint table, the web screens table, the app-shell table and the UI conventions headings; the unavailable lines appear when the web fields are null; `transcriptMessages` maps a finished turn to `FINISH_TURN_CONTENT`.
- Adapter: the request carries `model` and `effort` from options, the fallback beta and `fallbacks`, `max_tokens` 16000 and no `thinking`; a `recommended` outside `options` is invalid; a `refusal` stop is invalid.
- Service integration (fake model): a turn's assistant message carries `recommended`; `finish: true` records the finished user message, does not increment `questionCount`, sets `ready`, and the refinement section carries the new lines; `skip` with `finish` is 400.
- Config: defaults for the four variables; an invalid `INTERVIEW_EFFORT` fails startup.
- `npm run openapi -- --check` and docs-check clean.

## 4. Web

Contract pull first (`scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types`), then:

- `hooks.ts`: `SendTurnVariables` gains `finish?: boolean`; the body sends `{ content, skip, finish }`; `pendingMessage` shows "Finish with what we have" for a finishing turn.
- `ConversationPanel.tsx`: the chips row orders `last.recommended` first, rendered as a `Button variant="outline"` whose content is the option text followed by a `Badge variant="secondary"` reading "Recommended" (the badge is `aria-hidden`, so the chip's accessible name stays the option text and the smoke selector contract holds). After "Skip this question", when `conversation.questionCount >= 1` and the conversation is open, an outline chip "Finish with what we have" (lucide `Flag` icon) that calls `send("Finish with what we have", { finish: true })`. Nothing else in the panel changes; the understanding reply is an ordinary assistant bubble.
- `DraftPanel.tsx`: unchanged (`ready` already follows `status === "ready"`).
- README "Selector contract" gains the row for the button "Finish with what we have". ADR 0011 "Contract pull: recommended answer and finish" per the contract-pull rule.

Tests: the recommended chip renders first with the badge and clicking it sends its text; the finish chip is absent before the first question, present after, and posts `finish: true`; a `ready` conversation after a finish enables "Review and file"; every existing interview test stays green.

## 5. Docs and release

- API: ADR 0007 "Product context fetched at runtime for the interview" (why GitHub raw by ref rather than a vendored copy or a client-supplied block; the failure mode; the cache placement); `docs/ARCHITECTURE.md` interview section; README environment table; `docs/railway-setup.md` gains the four variables and the production `PRODUCT_CONTEXT_REF=main`; CHANGELOG; no version bump in the feature pull requests; `ship.yml` cuts 1.7.0 at promotion.
- Web: ADR 0011; README selector row and feature note; CHANGELOG; no version bump in the feature pull requests; `ship.yml` cuts 1.7.0 at promotion.
- Assembly line: this spec; PRD R-section for the interview updated (context, recommended answer, finish); CLAUDE.md status line once shipped.

## 6. Order and milestones

1. **API Task 1 (contract first):** schemas (`recommended`, `finished`, `finish`), `npm run openapi`, commit and push `feat/31-context-aware-feature-request-interview`. Milestone **A1**: the web lane pulls the contract from that branch.
2. API Tasks 2..n: config, loader, prompt and blocks, adapter, service and fake, docs, release cut; each test-first; one pull request to `develop`.
3. Web Tasks 1..n on the same branch name: pull, hooks, panel, docs, release cut; pull request to `develop` after the API pull request merges (the contract on `develop` must match).
4. Deploy to staging from the pipeline page; run the section 7 check; deploy to production.

## 7. Verification on staging, before production

Start a new conversation on staging and paste the #29 opening message verbatim ("the top header menu is a mess. I want to do few UI/UX changes. 1. appearance light/dark/system replace with toggle icon…"). Pass when: the first reply says what was understood and names what came from the product map; the draft shows a title, problem and proposed behavior; the first question is not who sees the header and not what the header looks like; the first chip carries the Recommended badge; "Finish with what we have" appears and, pressed, makes "Review and file" enabled.

If the first turn fails with a 400 naming data retention (Fable requires 30-day retention on the organization), set `INTERVIEW_MODEL=claude-opus-5` on both environments and rerun; the design is otherwise unchanged. Record which model shipped in the release notes.
