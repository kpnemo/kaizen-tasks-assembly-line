# Agentic feature request: design

**Status:** approved by Mike on 2026-09-10 01:10 IDT (grilling rounds in the CI/CD ledger).
**Repos:** `kpnemo/kaizen-tasks-api` (API lane, contract first) and `kpnemo/kaizen-tasks-web` (web lane). Cross-repo docs here.
**Release:** ships as 1.1.0 in both app repos, promoted before the rehearsal.

## 1. Goal

Turn the in-app "Request a feature" form into an interview. An assistant asks the product manager one question at a time, drawn from the readiness rubric, until the request would score as ready; the five request fields fill in live beside the chat; the PM reviews the prefilled form and files it through the existing endpoint. The GitHub issue carries the PM's self-score and the interview transcript, so engineering's triage sees how the request got ready. The in-app agent, the PM's local `refine-request` skill, and engineering's triage all score from the same rubric text.

Non-goals: no new GitHub code path (filing stays `POST /feature-requests`); no editing of existing issues; no multi-user sharing; no change to the breakdown agent; no token streaming library.

## 2. Experience

The page `/request-feature` (nav link "Request a feature", shown only when the API reports `features.featureRequests`) has two panels on a wide screen and stacks on a narrow one:

- **Chat** (left, about 60%): the transcript, the assistant's latest reply streaming word by word, then three or four option chips under the question plus a chip "Skip this question", and a textarea "Your answer" with a "Send" button (Enter sends, Shift+Enter is a newline). While a reply streams, the input is disabled and a "thinking" indicator shows until the first word arrives.
- **Your request** (right): the five fields of the form (Title, Problem, Proposed behavior, Acceptance criteria, Out of scope) as read-only text that fills in and changes after each answer, each with an "empty" placeholder until it has content; above them a readiness chip `Readiness 11 of 20` with the three sub-scores in its title attribute; below them the button "Review and file" (enabled when the assistant says the request is ready, or after the eighth question) and a link "Skip the interview, fill the form".
- **Start**: opening the page resumes the user's open conversation if one exists; otherwise the API creates one whose first assistant message is the fixed greeting `Tell me the idea in a sentence or two: who has the problem and what would be different.` (no model call). The PM types first.
- **Turns**: every PM answer (or skip) is one turn. The assistant replies with one or two short sentences that acknowledge what was said, then exactly one question, and ends the turn with the structured state. Questions follow the `refine-request` ladder: user and moment; observable behavior; done criteria (one criterion per question until at least three exist); out of scope; complexity and risk probes only when implied. The assistant never asks what the request or an earlier answer already states. At most eight questions.
- **Ready**: when the silent score has clarity 4 or higher, scope stated, and at least three checkable criteria, the assistant says the request is ready in one sentence and the state's `done` is true. At the eighth question without that, `done` is true and `stillMissing` lists what is lacking; the assistant says so in one sentence.
- **Review and file**: opens the existing form prefilled from the draft (editable), with a note `Refined with the assistant · readiness 15 of 20`. "File" posts the five fields plus `conversationId`. Success shows the issue link as today; the conversation is marked filed and the next visit starts a new one.
- **Skip the interview**: shows the plain form as today (no `conversationId`).
- **Start over**: a button in the chat header abandons the conversation and starts a new one.
- **Errors**: a failed turn (model error, rate limit) shows a toast through `toastApiError` and re-enables the input; the transcript keeps the PM's message so they can resend. A rate limit error names the hour it resets, as the breakdown limit does.
- **Projector rules** apply: 18px base, 44px chips and buttons, visible focus, no hover-only control.

## 3. API

All routes require auth and are mounted together with the existing feature-request route (same `featureRequestsConfigOf` condition), so the page and the nav link stay hidden when GitHub is not configured.

### 3.1 Data

Additive migration `drizzle/0001_feature_request_conversations.sql` from `src/db/schema.ts`:

```
feature_request_conversations
  id             uuid pk default gen_random_uuid()
  user_id        uuid not null references users(id) on delete cascade
  status         feature_request_conversation_status enum: open | ready | filed | abandoned, default open
  messages       jsonb not null default '[]'      -- ConversationMessage[]
  draft          jsonb not null default '{}'      -- Partial<FeatureRequestDraft>
  score          jsonb null                        -- RubricScore
  question_count integer not null default 0
  still_missing  jsonb not null default '[]'      -- string[]
  issue_number   integer null
  created_at     timestamptz not null default now()
  updated_at     timestamptz not null default now()
  partial unique index (user_id) where status in ('open','ready')
```

`ConversationMessage`: `{ id: string, role: "assistant" | "user", content: string, at: ISO string, options?: string[], skipped?: boolean }`. `FeatureRequestDraft`: the five form fields, every value a string, empty when unknown. `RubricScore`: the rubric's output shape `{ clarity, complexity, risk, archChange, readiness, reasons: { clarity, complexity, risk } }` (the rubric's `questions` array is not stored).

### 3.2 Routes (`src/routes/feature-requests.ts`, service `src/services/feature-request-conversations.ts`)

| Method and path | Body | Response |
| --- | --- | --- |
| `GET /feature-requests/conversation` | | 200 `{ data: Conversation }` for the caller's `open` or `ready` conversation; 404 `NOT_FOUND` otherwise |
| `POST /feature-requests/conversation` | none | 201 `{ data: Conversation }`: abandons any open or ready one, creates a new one with the greeting as its first assistant message |
| `POST /feature-requests/conversation/{id}/messages` | `{ content: string (1..2000, trimmed), skip?: boolean }` | `text/event-stream` (section 3.3); 404 when not the caller's; 409 `CONFLICT` when status is not `open`; 429 `RATE_LIMITED` before the stream starts |
| `POST /feature-requests` | existing five fields plus optional `conversationId: uuid` | unchanged 201; with `conversationId` owned by the caller and status `open` or `ready`, the issue body appends the refinement section (3.5) and the conversation becomes `filed` with `issue_number` |

`Conversation` (response schema): `{ id, status, messages, draft, score, questionCount, stillMissing, issueNumber, createdAt, updatedAt }`. The OpenAPI document describes the messages route with a `text/event-stream` 200 response whose schema is `ConversationEvent` (a discriminated union documented in `components`), so the contract carries the event shapes even though the client parses the stream itself.

`skip: true` records the user message `content: "(skipped)"`, `skipped: true`, and tells the model the PM skipped; it still counts as an answered question.

### 3.3 Stream protocol

Response headers: `Content-Type: text/event-stream; charset=utf-8`, `Cache-Control: no-cache`, `Connection: keep-alive`, `X-Accel-Buffering: no`; headers flushed before the model call. Events, each `event: <name>\ndata: <json>\n\n`:

- `delta` `{ "text": string }`: a piece of the assistant's reply, in order. The client appends.
- `state` `{ "conversation": Conversation }`: once, after the reply is complete and persisted; carries the new assistant message (with `options`), the draft, the score, `questionCount`, `stillMissing`, and `status` (`ready` when done, else `open`).
- `error` `{ "code": ErrorCode, "message": string }`: once, instead of `state`, when the turn failed after the headers were sent (model error, invalid tool output, timeout). The PM's message is NOT persisted in that case, so a resend is a clean retry.
- `done` `{}`: always last.

A comment line `: ping` is written every 15 seconds while waiting on the model. If the client disconnects, the model stream is aborted and nothing is persisted. Per-turn model timeout 45 s (same constant as the breakdown).

### 3.4 Interview agent (`src/agent/interview/`)

Seam, mirroring the breakdown seam:

```ts
export interface InterviewInput {
  messages: ConversationMessage[];   // whole transcript, greeting included
  draft: FeatureRequestDraft;
  score: RubricScore | null;
  questionCount: number;
  skippedLast: boolean;
}
export interface InterviewTurn {
  reply: string;                     // the full text that was streamed
  question: { text: string; options: string[] } | null;  // null when done
  draft: FeatureRequestDraft;
  score: RubricScore;
  done: boolean;
  stillMissing: string[];
}
export interface InterviewModel {
  respond(input: InterviewInput, onDelta: (text: string) => void, signal: AbortSignal): Promise<InterviewOutcome>;
}
export type InterviewOutcome = { kind: "ok"; turn: InterviewTurn } | { kind: "invalid"; reason: string };
```

**Anthropic adapter** (`anthropic-interview-model.ts`): `client.messages.stream(...)` with the same model as the breakdown (`AI_MODEL`), `max_tokens` 4000, a system prompt made of two blocks: `src/agent/prompts/interview.system.md` and the vendored rubric `src/agent/prompts/readiness.md`, both with `cache_control: { type: "ephemeral" }`; the transcript as alternating user/assistant messages (the greeting as the first assistant message; when `skippedLast`, the last user message is `The PM skipped this question.`); one tool `report_turn` whose `input_schema` is generated from the zod schema of `InterviewTurn` minus `reply` (zod 4 `z.toJSONSchema`), `tool_choice: { type: "auto" }`. The system prompt instructs: write the reply as plain text (one or two sentences of acknowledgement, then exactly one question, or the one-sentence ready or cap message), then call `report_turn` exactly once with the structured state; never put JSON in the text. Text deltas go to `onDelta` as they arrive; the tool input is parsed from `finalMessage()`; a missing or invalid tool call is `{ kind: "invalid" }` (no retry; the route emits `error`). `toModelError` and the timeout mirror the breakdown adapter. Invalid classification guard as in the breakdown adapter.

**System prompt** (`interview.system.md`): the role; the `refine-request` skill's Step 4 rules and question order verbatim (one question per turn, options are three or four concrete guesses drawn from the request text, never re-ask, silent re-score after every answer, cap eight); the stop condition; the draft rules (use only what the PM said, keep their numbers, do not invent criteria; Title is a release-note line; Acceptance criteria one bullet per checkable criterion; Out of scope one bullet per item or empty); the rubric procedure reference ("score with the rubric below every turn"); the tool contract. Both the prompt and the rubric copy are architectural files (ADR).

**Rubric copy**: `src/agent/prompts/readiness.md` is a byte-identical copy of the assembly-line rubric. `scripts/sync-rubric.sh` (ported from the product-skills repo) downloads and compares; CI runs `--check` as a warning step; `docs/ARCHITECTURE.md` states that the prompt embeds the rubric.

**Fake adapter** (`fake-interview-model.ts`, used when `AI_MODEL_PROVIDER=fake` and in tests): a scripted interview keyed on `questionCount`: turn 0 asks the user-and-moment question with options `["A team supervisor before a coaching session", "An agent during a call", "A workforce planner on Monday"]`; turn 1 asks observable behavior with three options; turn 2 asks a done criterion; turn 3 (or any `skip` after that) returns `done: true` with a complete draft built from the transcript and a score `{ clarity: 4, complexity: 2, risk: 2, archChange: false, readiness: 16 }`. It streams the reply in three chunks; the delay between chunks is 0 in tests and 150 ms otherwise (constructor option).

### 3.5 Service rules (`feature-request-conversations.ts`)

- `get(userId)`, `create(userId)` (abandon then insert), `abandon(userId, id)`.
- `turn(userId, id, { content, skip }, sink)`: ownership and status checks; rate limit `ratelimit:interview:<userId>:<hourBucket>` with `INTERVIEW_HOURLY_LIMIT` (config, default 60) through the existing limiter shape (a second limiter instance with its own key prefix and limit; the breakdown limiter is untouched); append the user message in memory; call the model with `onDelta` forwarding to the sink; on `ok`, persist in one update: messages (+ user message, + assistant message with `options` from `question`), draft, score, `question_count + 1` when a question was asked, `still_missing`, `status = done ? ready : open`; then `state`. On `invalid` or a thrown error: emit `error` with `UPSTREAM_ERROR` (model) or the mapped code, persist nothing.
- `attachToIssue(userId, conversationId)` used by `submit`: returns the refinement section text and marks `filed` after the issue exists (issue number stored).

Refinement section appended to the issue body:

```markdown
---

<details>
<summary>How this request was refined (assistant interview)</summary>

Rubric version: <version line of the vendored rubric>

| | Clarity | Complexity | Risk | Architecture change | Readiness |
|---|---|---|---|---|---|
| Self-score | 4 | 2 | 2 | no | 16 |

**Interview** (N questions)

- **Assistant:** …
- **PM:** …

</details>
```

### 3.6 Config

`INTERVIEW_HOURLY_LIMIT` (int, default 60) in `src/config.ts` and the Railway IaC variables (`preserve()` is not needed; a default suffices, document it in `docs/railway-setup.md` only if set).

### 3.7 Tests (API)

- Unit: SSE writer (formats events, ping, abort); prompt builder (system blocks, transcript mapping, skipped marker); tool schema JSON; refinement section renderer; fake model script.
- Integration (real Postgres and Redis, fake model): create → get; messages turn streams `delta`s then `state` with `questionCount` 1 and `options`; four turns reach `ready`; skip counts; second `create` abandons the first; another user's conversation is 404; a `filed` or `abandoned` conversation returns 409 on messages; rate limit 429 before headers; `submit` with `conversationId` appends the section and marks `filed`; model `invalid` emits `error` and persists nothing (a fake mode `invalid`).
- `npm run openapi -- --check` clean; docs-check clean.

## 4. Web

`src/features/feature-request/` grows; nothing outside it changes except the contract copy, one ADR, the README and the CHANGELOG. `src/app/router.tsx` is unchanged (`/request-feature` already routes to `RequestFeaturePage`, which becomes the switchboard).

### 4.1 Pieces

- `conversation-stream.ts` (in `src/api/`, shared, no React): `readConversationStream(stream: ReadableStream<Uint8Array>, handlers: { onDelta, onState, onError, onDone })`, a 40-line SSE parser (`TextDecoder`, buffer, split on blank lines, `event:`/`data:` lines, ignore comments). Unit-tested with hand-built streams.
- `hooks.ts` additions: `useConversation()` (query `["feature-request","conversation"]`, `GET`, 404 → `null`), `useStartConversation()` (mutation `POST`, sets the query data), `useSendTurn()`: a mutation that calls `client.POST("/feature-requests/conversation/{id}/messages", { params, body, parseAs: "stream" })`, checks `response.ok` (non-OK is a normal `ApiError` through `toApiError` / `toastApiError`), then `readConversationStream` with `onDelta` appending to a `streamingText` state, `onState` setting the query data to the conversation, `onError` raising an `ApiError`. The token middleware attaches the bearer as for every route; a 401 mid-stream cannot happen (the check is before the stream starts).
- `RequestFeaturePage.tsx` becomes the switchboard: `mode` = `"interview" | "form"`; interview by default when a conversation exists or can be started; the form when the user chose to skip or clicked "Review and file" (then prefilled and carrying `conversationId`).
- `ConversationPanel.tsx`: header ("Kaizen assistant", "Start over" button), `MessageList` (assistant and PM bubbles, the streaming bubble, the thinking indicator), `OptionChips` (buttons 44px tall; clicking sends that text), "Skip this question" chip, `AnswerBox` (textarea `aria-label="Your answer"`, Send button, Enter to send).
- `DraftPanel.tsx`: readiness chip, five read-only fields with placeholders, "Review and file" button, "Skip the interview, fill the form" link.
- The existing form gains `initialValues` and `conversationId` props and the note line.

### 4.2 Tests (web)

MSW handlers: `GET /feature-requests/conversation` (404 or a fixture), `POST` (creates), `POST .../messages` returning a `text/event-stream` body built from an array of events (MSW `HttpResponse` with a `ReadableStream`), `POST /feature-requests` accepting `conversationId`. Tests: the parser; hooks (a turn appends deltas then replaces the conversation; an `error` event raises and keeps the input); page: greeting shows on first visit; sending an answer streams text then shows chips; clicking a chip sends it; skip sends `skip: true`; after `done` the "Review and file" button opens the prefilled form and filing includes `conversationId`; "Skip the interview" shows the plain form; a rate-limit error shows the toast and re-enables the input. Keep the existing form tests green.

### 4.3 Proxy and dev

`Caddyfile`: `reverse_proxy` for `/api/*` gets `flush_interval -1` so streamed responses are not buffered (ADR 0001 amendment). The Vite dev proxy streams as is. `vite.config.ts` unchanged.

### 4.4 Accessibility and selectors

Chips and buttons are real buttons with their visible text as the name. README "Selector contract" gains rows for the page (chat textbox "Your answer", button "Send", button "Skip this question", button "Review and file", link "Skip the interview, fill the form", region "Your request") so a future smoke step can drive it; the smoke test itself is unchanged in this release (filing creates real issues).

## 5. Docs and release

- API: ADR 0005 "Interview agent for feature requests" (streaming over SSE from Express, the tool-call state pattern, the vendored rubric, why no streaming library); `docs/ARCHITECTURE.md` section; README route table; CHANGELOG; release 1.1.0 with the release-notes skill in the same branch (the docs gate accepts a release cut).
- Web: ADR 0005 "Streamed conversation through the typed client" (`parseAs: "stream"`, the SSE parser, the contract's event schema); ADR 0001 amendment (flush); README features and selector rows; CHANGELOG; release 1.1.0.
- Assembly line: runbook Part 1 gains the intake demo with the assistant (script review step), `docs/PRD.md` R-section for the assistant, CHANGELOG; the rubric now has three consumers (assembly line, product-skills, API) and the note about `scripts/sync-rubric.sh` in each.

## 6. Order and milestones

1. **API Task 1 (contract first)**: schemas, the OpenAPI registration for the three routes and the event union, `conversationId` on the existing body, `npm run openapi`, commit and push the branch `feat/interview-agent`. Milestone **A1**: the web lane pulls the contract from that branch (`npm run api:pull -- feat/interview-agent`) and starts.
2. API Tasks 2..n: migration and schema, service, SSE writer, fake model, Anthropic adapter and prompt, routes, submit integration, docs, release cut; each task test-first, reviewed, on the same branch; PR to `develop`; staging. Milestone **A2**: staging serves it with the fake or the real provider.
3. Web Tasks 1..n on `feat/interview-agent`: parser, hooks, panels, switchboard, docs, release cut; PR to `develop` after A2 (the contract on `develop` must match); staging. Milestone **W1**.
4. Both promoted (`develop` to `main`) with the promote gate; production read-backs; Mike's sanity pass of the interview on production.
