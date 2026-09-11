# Context-Aware Interview (#31) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the in-app feature request interviewer know the product (API endpoints, web screens, UI conventions), open by confirming what it understood and pre-filling the draft, recommend an answer to every question, let the PM finish at any point, and run on Fable through its own `INTERVIEW_MODEL`.

**Architecture:** The API's interview adapter gains a third cached system block built from three markdown documents (its own product map from disk, the web repo's product map and UI conventions fetched from GitHub raw and refreshed on a timer). The `report_turn` tool contract gains `recommended`; the messages route gains `finish`. The adapter moves to `client.beta.messages.stream` with `output_config.effort` and server-side fallbacks. The web app pulls the contract, shows the recommended chip first with a badge, and adds a "Finish with what we have" chip.

**Tech Stack:** Node 24, Express 5, zod 4, `@anthropic-ai/sdk` 0.124.0, vitest, drizzle (no migration needed: `messages` is jsonb). Web: React 19, Vite, TanStack Query, shadcn/ui, MSW, vitest, Testing Library.

**Spec:** `docs/superpowers/specs/2026-09-12-context-aware-interview-design.md` (harness repo). Read it first; every task below argues from it.

## Global Constraints

- Branch name in all three repos: `feat/31-context-aware-feature-request-interview`, off `develop`. Never push to `develop` or `main`; open pull requests and stop.
- API first, web second: the web repo pulls the contract from the API branch (`cd frontend && scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types`) before any web code changes.
- Every task is test-first: the failing test output is shown before the implementation, the passing output after.
- Every commit ends with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Run `nvm use` inside `backend/` and `frontend/` before any npm command.
- Before each repo's pull request: `npm run product-map`, `npm test`, `npm run typecheck`, `npm run lint`, then `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci` whose last line must be `docs-check: OK`. Never `npm run docs:check` (that is the Stop-hook mode).
- `src/agent/prompts/**` (API) and `src/api/**` (web) are architectural files: each repo needs one ADR in this branch (Tasks 8 and 9).
- **No version bump in either repo.** The pipeline's `ship.yml` cuts 1.6.0 at promotion time. (The spec's "release 1.6.0" is the ship, not a commit here.)
- Copy rules: chips are real `Button`s named by their visible text; the smoke test drives the app by role and name, so the recommended chip's accessible name stays its option text (the badge is `aria-hidden`).
- Model constants, verbatim: `INTERVIEW_MODEL` default `claude-fable-5-1`; `INTERVIEW_EFFORT` enum `low|medium|high|xhigh|max` default `medium`; `PRODUCT_CONTEXT_REF` default `develop`; `PRODUCT_CONTEXT_REFRESH_MINUTES` default `10`; `INTERVIEW_MAX_OUTPUT_TOKENS = 16_000`; `INTERVIEW_TIMEOUT_MS = 90_000`; beta `server-side-fallback-2026-07-01` with `fallbacks: "default"`.
- Fixed strings, verbatim: `FINISHED_CONTENT = "Finish with what we have"` (stored user message and chip label); `FINISH_TURN_CONTENT = "The PM asked to finish the interview with what you have."` (what the model sees); unavailable lines `Web product map: unavailable (fetch failed)` and `UI conventions: unavailable (fetch failed)`.

---

## File structure

**API (`backend/`)**

| File | Responsibility |
| --- | --- |
| `src/schemas/feature-request-conversations.ts` (modify) | contract: `recommended`, `finished`, `finish` |
| `src/lib/interview-constants.ts` (modify) | `FINISHED_CONTENT` beside `SKIPPED_CONTENT` |
| `src/config.ts` (modify) | four new variables |
| `src/agent/interview/product-context.ts` (create) | `ProductContextLoader`: disk read, GitHub fetch, trim, refresh |
| `src/agent/interview/prompt.ts` (modify) | `systemBlocks(context)` three blocks, `FINISH_TURN_CONTENT`, finish mapping |
| `src/agent/prompts/interview.system.md` (modify) | the instructions |
| `src/agent/interview/anthropic-interview-model.ts` (modify) | beta stream, effort, fallbacks, context getter, recommended check |
| `src/agent/interview/fake-interview-model.ts` (modify) | `recommended`, finish turn |
| `src/agent/interview/model.ts` (modify) | `createInterviewModel` selection gains `effort` and `context` |
| `src/services/feature-request-conversations.ts` (modify) | finish turn, `recommended` persisted, refinement lines, 90 s default |
| `src/server.ts` (modify) | build and start the loader, pass it in, stop on shutdown |
| `docs/adr/0007-product-context-fetched-at-runtime.md` (create), `docs/ARCHITECTURE.md`, `README.md`, `CHANGELOG.md`, `.env.example` (modify) | docs |

**Web (`frontend/`)**

| File | Responsibility |
| --- | --- |
| `src/api/openapi.json`, `src/api/types.ts` (regenerated) | contract copy |
| `docs/adr/0011-contract-pull-recommended-answer-and-finish.md` (create) | ADR for the pull |
| `src/features/feature-request/hooks.ts` (modify) | `finish` on `SendTurnVariables`, pending label |
| `src/features/feature-request/components/ConversationPanel.tsx` (modify) | recommended chip first with badge, finish chip |
| `tests/msw/db.ts`, `tests/msw/fixtures.ts` (modify) | fixtures carry `recommended`; `advanceTurn` handles `finish` |
| `README.md`, `CHANGELOG.md` (modify) | selector row, notes |

**Harness (this repo)**: `docs/PRD.md`, the spec, this plan; Railway variable on production.

---

## Task 1: Contract first (API schemas and OpenAPI)

**Files:**
- Modify: `backend/src/schemas/feature-request-conversations.ts`
- Modify: `backend/src/lib/interview-constants.ts`
- Test: `backend/src/schemas/feature-request-conversations.test.ts`
- Regenerated: `backend/openapi.json`, `backend/docs/API.md`

**Interfaces:**
- Produces: `InterviewQuestionSchema = { text: string; options: string[] (1..4); recommended: string }`; `ConversationMessageSchema` gains `recommended?: string`, `finished?: boolean`; `ConversationTurnBody` gains `finish?: boolean`, and `skip` with `finish` together fails validation; `FINISHED_CONTENT` exported from `src/lib/interview-constants.ts` and re-exported from the schema module like `SKIPPED_CONTENT`.

- [ ] **Step 1: Branch**

```bash
cd backend && nvm use
git fetch origin && git switch -c feat/31-context-aware-feature-request-interview origin/develop
```

- [ ] **Step 2: Write the failing tests**

Append to `src/schemas/feature-request-conversations.test.ts` (inside the existing `describe("ConversationTurnBody")`, and a new describe):

```ts
  it("takes an optional finish flag and rejects finish together with skip", () => {
    expect(ConversationTurnBody.parse({ content: FINISHED_CONTENT, finish: true }).finish).toBe(true);
    expect(
      ConversationTurnBody.safeParse({ content: FINISHED_CONTENT, finish: true, skip: true }).success,
    ).toBe(false);
  });
```

```ts
describe("InterviewQuestionSchema", () => {
  it("requires a recommended answer alongside the options", () => {
    expect(
      InterviewQuestionSchema.safeParse({ text: "Who?", options: ["A", "B"], recommended: "A" })
        .success,
    ).toBe(true);
    expect(InterviewQuestionSchema.safeParse({ text: "Who?", options: ["A", "B"] }).success).toBe(
      false,
    );
  });
});

describe("ConversationMessageSchema", () => {
  it("parses rows stored before recommended and finished existed", () => {
    const old = { id: randomUUID(), role: "assistant", content: "Who?", at: ISO, options: ["A"] };
    expect(ConversationMessageSchema.parse(old).recommended).toBeUndefined();
    const finished = { id: randomUUID(), role: "user", content: FINISHED_CONTENT, at: ISO, finished: true };
    expect(ConversationMessageSchema.parse(finished).finished).toBe(true);
  });
});
```

Add to the test file's imports: `FINISHED_CONTENT`, `InterviewQuestionSchema`, `ConversationMessageSchema` from `./feature-request-conversations.js`, `randomUUID` from `node:crypto`, and `const ISO = "2026-09-10T09:00:00.000Z";` if not already present.

- [ ] **Step 3: Run the tests to see them fail**

Run: `npx vitest run src/schemas/feature-request-conversations.test.ts`
Expected: FAIL, `FINISHED_CONTENT` is not exported; `recommended` missing does not fail parse.

- [ ] **Step 4: Implement**

`src/lib/interview-constants.ts`, after `SKIPPED_CONTENT`:

```ts
/** Recorded as the user message's content when the PM presses "Finish with what we have" (spec 3.5). */
export const FINISHED_CONTENT = "Finish with what we have";
```

`src/schemas/feature-request-conversations.ts`:

```ts
import { EMPTY_DRAFT, FINISHED_CONTENT, SKIPPED_CONTENT } from "../lib/interview-constants.js";
export { EMPTY_DRAFT, FINISHED_CONTENT, SKIPPED_CONTENT };
```

In `ConversationMessageSchema`, after `options`:

```ts
    /** Present on an assistant message that asked a question: the option the assistant recommends. */
    recommended: z.string().optional(),
    /** Present on the user message that ended the interview early (spec 3.5). */
    finished: z.boolean().optional(),
```

Replace `ConversationTurnBody`:

```ts
export const ConversationTurnBody = z
  .object({
    content: z.string().trim().min(1).max(MAX_TURN_CONTENT),
    skip: z.boolean().optional(),
    /** Ends the interview with the draft as it stands; content is ignored (spec 3.5). */
    finish: z.boolean().optional(),
  })
  .refine((body) => !(body.skip === true && body.finish === true), {
    message: "skip and finish cannot both be true",
    path: ["finish"],
  })
  .openapi("ConversationTurnBody");
```

`InterviewQuestionSchema`:

```ts
export const InterviewQuestionSchema = z.object({
  text: z.string(),
  options: z.array(z.string()).min(1).max(4),
  /** The answer the assistant would give; must be one of `options` word for word (checked by the adapter). */
  recommended: z.string(),
});
```

- [ ] **Step 5: Run the tests to see them pass, then the whole suite**

Run: `npx vitest run src/schemas/feature-request-conversations.test.ts` then `npm test`
Expected: the new tests PASS. Expect failures elsewhere that reference `InterviewQuestion` without `recommended` (fake model, adapter tests): note them, they are fixed in Tasks 5 and 6. If `npm run typecheck` fails only for those, that is expected at this point.

- [ ] **Step 6: Regenerate the contract and commit**

```bash
npm run openapi
git add src/schemas/feature-request-conversations.ts src/schemas/feature-request-conversations.test.ts src/lib/interview-constants.ts openapi.json docs/API.md
git commit -m "feat: interview contract gains recommended answer and finish turn (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/31-context-aware-feature-request-interview
```

Milestone **A1**: the web lane may start Task 9 from this branch.

---

## Task 2: Config variables

**Files:**
- Modify: `backend/src/config.ts`, `backend/.env.example`
- Test: `backend/src/config.test.ts`

**Interfaces:**
- Produces: `config.INTERVIEW_MODEL: string`, `config.INTERVIEW_EFFORT: InterviewEffort`, `config.PRODUCT_CONTEXT_REF: string`, `config.PRODUCT_CONTEXT_REFRESH_MINUTES: number`; exported type `InterviewEffort = "low" | "medium" | "high" | "xhigh" | "max"`.

- [ ] **Step 1: Write the failing tests** (in `src/config.test.ts`, inside `describe("loadConfig")`)

```ts
  it("gives the interview its own model, effort and product-context settings", () => {
    const config = loadConfig(valid);
    expect(config.INTERVIEW_MODEL).toBe("claude-fable-5-1");
    expect(config.INTERVIEW_EFFORT).toBe("medium");
    expect(config.PRODUCT_CONTEXT_REF).toBe("develop");
    expect(config.PRODUCT_CONTEXT_REFRESH_MINUTES).toBe(10);
    expect(loadConfig({ ...valid, INTERVIEW_MODEL: "claude-opus-5" }).INTERVIEW_MODEL).toBe("claude-opus-5");
    expect(loadConfig({ ...valid, INTERVIEW_EFFORT: "high" }).INTERVIEW_EFFORT).toBe("high");
    expect(() => loadConfig({ ...valid, INTERVIEW_EFFORT: "turbo" })).toThrow(ConfigError);
    expect(() => loadConfig({ ...valid, PRODUCT_CONTEXT_REFRESH_MINUTES: "0" })).toThrow(ConfigError);
  });
```

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/config.test.ts`
Expected: FAIL, `INTERVIEW_MODEL` undefined.

- [ ] **Step 3: Implement** (in `configSchema`, after `INTERVIEW_HOURLY_LIMIT`)

```ts
    /** The interview's own model and effort (spec 3.1). AI_MODEL stays the breakdown's. */
    INTERVIEW_MODEL: z.string().min(1).default("claude-fable-5-1"),
    INTERVIEW_EFFORT: z.enum(["low", "medium", "high", "xhigh", "max"]).default("medium"),
    /** Git ref of kpnemo/kaizen-tasks-web the product context is fetched from; production sets main. */
    PRODUCT_CONTEXT_REF: z.string().min(1).default("develop"),
    PRODUCT_CONTEXT_REFRESH_MINUTES: int.positive().default(10),
```

After `export type Config`, add:

```ts
export type InterviewEffort = Config["INTERVIEW_EFFORT"];
```

`.env.example`, after `INTERVIEW_HOURLY_LIMIT=60`:

```
INTERVIEW_MODEL=claude-fable-5-1
INTERVIEW_EFFORT=medium
PRODUCT_CONTEXT_REF=develop
PRODUCT_CONTEXT_REFRESH_MINUTES=10
```

- [ ] **Step 4: Run to see it pass**

Run: `npx vitest run src/config.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/config.ts src/config.test.ts .env.example
git commit -m "feat: INTERVIEW_MODEL, INTERVIEW_EFFORT and product-context settings (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 3: Product context loader

**Files:**
- Create: `backend/src/agent/interview/product-context.ts`
- Test: `backend/src/agent/interview/product-context.test.ts`

**Interfaces:**
- Produces:

```ts
export interface ProductContext {
  api: string;
  web: string | null;
  conventions: string | null;
  fetchedAt: string | null;
}
export interface ProductContextSource {
  readApiMap(): string;
  fetchWebDoc(path: "docs/product-map.md" | "docs/ui-conventions.md"): Promise<string>;
}
export function trimHistory(markdown: string): string;
export function githubRawSource(ref: string, fetchImpl?: typeof fetch): ProductContextSource;
export class ProductContextLoader {
  constructor(source: ProductContextSource, options: { refreshMs: number; log: Logger });
  start(): Promise<void>;
  refresh(): Promise<void>;
  stop(): void;
  current(): ProductContext;
}
```

- [ ] **Step 1: Write the failing tests**

```ts
import { describe, expect, it, vi } from "vitest";
import type { Logger } from "../../lib/logger.js";
import { ProductContextLoader, trimHistory, type ProductContextSource } from "./product-context.js";

const API_MAP = `# Product map: Kaizen Tasks API

Prose header.

## Endpoints (\`openapi.json\`)

| Tag | Method | Path | Summary |
| --- | --- | --- | --- |
| tasks | GET | \`/tasks\` | List tasks |

## Unreleased changes (\`CHANGELOG.md\`)

- something pending

## Recent releases (history, not current behavior)

- 1.5.0
`;

const WEB_MAP = "# Product map: kaizen-tasks-web\n\n## Screens\n\n| Path | Renders |\n| --- | --- |\n| `/tasks` | `TaskListPage` |\n\n## Recent releases (history, not current behavior)\n\n- 1.5.0\n";
const CONVENTIONS = "# UI conventions\n\n## shadcn first\n\nUse the primitives.\n";

function log(): Logger {
  return { warn: vi.fn(), info: vi.fn(), error: vi.fn(), debug: vi.fn() } as unknown as Logger;
}

function source(overrides: Partial<ProductContextSource> = {}): ProductContextSource {
  return {
    readApiMap: () => API_MAP,
    fetchWebDoc: async (path) => (path === "docs/product-map.md" ? WEB_MAP : CONVENTIONS),
    ...overrides,
  };
}

describe("trimHistory", () => {
  it("drops the Recent releases and Unreleased changes sections and keeps everything else", () => {
    const trimmed = trimHistory(API_MAP);
    expect(trimmed).toContain("## Endpoints");
    expect(trimmed).toContain("| tasks | GET |");
    expect(trimmed).toContain("Prose header.");
    expect(trimmed).not.toContain("Recent releases");
    expect(trimmed).not.toContain("Unreleased changes");
    expect(trimmed).not.toContain("1.5.0");
  });
});

describe("ProductContextLoader", () => {
  it("reads the API map from disk and the web documents from the source", async () => {
    const loader = new ProductContextLoader(source(), { refreshMs: 60_000, log: log() });
    await loader.start();
    const context = loader.current();
    expect(context.api).toContain("## Endpoints");
    expect(context.web).toContain("## Screens");
    expect(context.web).not.toContain("Recent releases");
    expect(context.conventions).toBe(CONVENTIONS);
    expect(context.fetchedAt).not.toBeNull();
    loader.stop();
  });

  it("keeps null web fields and logs once when the first fetch fails, and never throws", async () => {
    const logger = log();
    const loader = new ProductContextLoader(
      source({ fetchWebDoc: async () => { throw new Error("boom"); } }),
      { refreshMs: 60_000, log: logger },
    );
    await expect(loader.start()).resolves.toBeUndefined();
    expect(loader.current()).toMatchObject({ web: null, conventions: null, fetchedAt: null });
    expect(loader.current().api).toContain("## Endpoints");
    expect(logger.warn).toHaveBeenCalledTimes(1);
    loader.stop();
  });

  it("keeps the previous good pair when a refresh fails", async () => {
    let fail = false;
    const loader = new ProductContextLoader(
      source({
        fetchWebDoc: async (path) => {
          if (fail) throw new Error("boom");
          return path === "docs/product-map.md" ? WEB_MAP : CONVENTIONS;
        },
      }),
      { refreshMs: 60_000, log: log() },
    );
    await loader.start();
    fail = true;
    await loader.refresh();
    expect(loader.current().web).toContain("## Screens");
    loader.stop();
  });

  it("refreshes on the timer and stops cleanly", async () => {
    vi.useFakeTimers();
    try {
      const fetchWebDoc = vi.fn(async (path: string) => (path === "docs/product-map.md" ? WEB_MAP : CONVENTIONS));
      const loader = new ProductContextLoader(source({ fetchWebDoc }), { refreshMs: 1_000, log: log() });
      await loader.start();
      expect(fetchWebDoc).toHaveBeenCalledTimes(2);
      await vi.advanceTimersByTimeAsync(1_000);
      expect(fetchWebDoc).toHaveBeenCalledTimes(4);
      loader.stop();
      await vi.advanceTimersByTimeAsync(5_000);
      expect(fetchWebDoc).toHaveBeenCalledTimes(4);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("the real API map on disk", () => {
  it("is found three levels above the interview module", async () => {
    const { diskApiMapPath } = await import("./product-context.js");
    expect(diskApiMapPath()).toMatch(/docs[/\\]product-map\.md$/);
  });
});
```

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/agent/interview/product-context.test.ts`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement** `src/agent/interview/product-context.ts`

```ts
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { Logger } from "../../lib/logger.js";

/** Spec 3.2: what the interviewer knows about the product, as three markdown documents. */
export interface ProductContext {
  /** This repo's docs/product-map.md, history sections removed. */
  api: string;
  /** kpnemo/kaizen-tasks-web docs/product-map.md, history sections removed; null until a fetch succeeds. */
  web: string | null;
  /** kpnemo/kaizen-tasks-web docs/ui-conventions.md, whole; null until a fetch succeeds. */
  conventions: string | null;
  fetchedAt: string | null;
}

export type WebDocPath = "docs/product-map.md" | "docs/ui-conventions.md";

export interface ProductContextSource {
  readApiMap(): string;
  fetchWebDoc(path: WebDocPath): Promise<string>;
}

/** Three levels above src/agent/interview/ (and dist/agent/interview/) is the package root. */
export const API_MAP_URL = new URL("../../../docs/product-map.md", import.meta.url);

export function diskApiMapPath(): string {
  return fileURLToPath(API_MAP_URL);
}

const HISTORY_HEADINGS = ["## Recent releases", "## Unreleased changes"];

/** Drops the history sections: from a matching `## ` heading to the next `## ` heading or the end. */
export function trimHistory(markdown: string): string {
  const lines = markdown.split("\n");
  const kept: string[] = [];
  let dropping = false;
  for (const line of lines) {
    if (line.startsWith("## ")) {
      dropping = HISTORY_HEADINGS.some((heading) => line.startsWith(heading));
    }
    if (!dropping) kept.push(line);
  }
  return kept.join("\n").replace(/\n{3,}/g, "\n\n").trimEnd() + "\n";
}

const FETCH_TIMEOUT_MS = 10_000;

/** GitHub raw, no token: both repos are public (spec 3.2). */
export function githubRawSource(ref: string, fetchImpl: typeof fetch = fetch): ProductContextSource {
  return {
    readApiMap: () => readFileSync(API_MAP_URL, "utf8"),
    async fetchWebDoc(path) {
      const url = `https://raw.githubusercontent.com/kpnemo/kaizen-tasks-web/${ref}/${path}`;
      const response = await fetchImpl(url, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
      if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
      return response.text();
    },
  };
}

export class ProductContextLoader {
  private context: ProductContext;
  private timer: ReturnType<typeof setInterval> | undefined;

  constructor(
    private readonly source: ProductContextSource,
    private readonly options: { refreshMs: number; log: Logger },
  ) {
    this.context = { api: trimHistory(source.readApiMap()), web: null, conventions: null, fetchedAt: null };
  }

  /** First load, then the timer. Resolves after the first fetch attempt, success or not. */
  async start(): Promise<void> {
    await this.refresh();
    this.timer = setInterval(() => void this.refresh(), this.options.refreshMs);
    this.timer.unref();
  }

  /** Fetches both web documents together; a failure of either keeps the previous pair. */
  async refresh(): Promise<void> {
    try {
      const [web, conventions] = await Promise.all([
        this.source.fetchWebDoc("docs/product-map.md"),
        this.source.fetchWebDoc("docs/ui-conventions.md"),
      ]);
      this.context = {
        ...this.context,
        web: trimHistory(web),
        conventions,
        fetchedAt: new Date().toISOString(),
      };
    } catch (err) {
      this.options.log.warn(
        { reason: err instanceof Error ? err.message : String(err) },
        "product context: web documents not fetched, keeping the previous ones",
      );
    }
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
  }

  current(): ProductContext {
    return this.context;
  }
}
```

- [ ] **Step 4: Run to see it pass**

Run: `npx vitest run src/agent/interview/product-context.test.ts` → PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/agent/interview/product-context.ts src/agent/interview/product-context.test.ts
git commit -m "feat: product context loader for the interview (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 4: Prompt: three system blocks, finish marker, rewritten instructions

**Files:**
- Modify: `backend/src/agent/interview/prompt.ts`
- Modify: `backend/src/agent/prompts/interview.system.md`
- Test: `backend/src/agent/interview/prompt.test.ts`

**Interfaces:**
- Consumes: `ProductContext` from Task 3.
- Produces: `systemBlocks(context: ProductContext): CachedSystemBlock[]` (three blocks); `renderProductContext(context: ProductContext): string`; `FINISH_TURN_CONTENT`; `transcriptMessages(input)` maps a user message with `finished: true` (or `input.finishedLast`) to `FINISH_TURN_CONTENT`. `InterviewInput` gains `finishedLast: boolean` (Task 6 updates `model.ts`; do it here so the prompt test compiles: add `finishedLast: boolean;` to `InterviewInput` in `model.ts` now).

- [ ] **Step 1: Write the failing tests** (replace the existing `describe("the interview system prompt")` phrase list and add blocks tests)

```ts
import type { ProductContext } from "./product-context.js";
import { FINISH_TURN_CONTENT, renderProductContext, /* existing imports */ } from "./prompt.js";

const context: ProductContext = {
  api: "## Endpoints\n\n| tasks | GET | `/tasks` | List tasks |\n",
  web: "## Screens\n\n| `/tasks` | `TaskListPage` |\n\n## App shell\n\n| `ThemeToggle` | header |\n",
  conventions: "## shadcn first\n\nUse the primitives.\n",
  fetchedAt: "2026-09-12T00:00:00.000Z",
};

describe("systemBlocks", () => {
  it("returns three cached blocks: instructions, rubric, product context", () => {
    const blocks = systemBlocks(context);
    expect(blocks).toHaveLength(3);
    for (const block of blocks) expect(block.cache_control).toEqual({ type: "ephemeral" });
    expect(blocks[0]!.text).toBe(loadInterviewSystemPrompt());
    expect(blocks[1]!.text).toBe(loadRubric());
    expect(blocks[2]!.text).toContain("# Product context (what exists today)");
    expect(blocks[2]!.text).toContain("## API: kpnemo/kaizen-tasks-api");
    expect(blocks[2]!.text).toContain("| tasks | GET |");
    expect(blocks[2]!.text).toContain("## Web app: kpnemo/kaizen-tasks-web");
    expect(blocks[2]!.text).toContain("`TaskListPage`");
    expect(blocks[2]!.text).toContain("## UI conventions");
    expect(blocks[2]!.text).toContain("Use the primitives.");
  });

  it("says when the web documents are unavailable", () => {
    const text = renderProductContext({ ...context, web: null, conventions: null, fetchedAt: null });
    expect(text).toContain("Web product map: unavailable (fetch failed)");
    expect(text).toContain("UI conventions: unavailable (fetch failed)");
    expect(text).toContain("| tasks | GET |");
  });
});

describe("transcriptMessages", () => {
  it("maps a finished turn to the finish marker the prompt names", () => {
    const messages = transcriptMessages({
      ...input([message("assistant", "Who?"), message("user", "Finish with what we have")]),
      finishedLast: true,
    });
    expect(messages.at(-2)).toEqual({ role: "user", content: FINISH_TURN_CONTENT });
  });
});
```

Update the existing prompt phrase test to the new instructions:

```ts
  it("states the turn contract, the opening turn, question choice, finishing and the draft rules", () => {
    for (const phrase of [
      "report_turn",
      "exactly one question",
      "The cap is eight",
      "Questions asked so far: N of 8.",
      "you must not ask a ninth question",
      "`stillMissing` is EMPTY when the request is ready",
      "Whenever `done` is true, `question` must be null",
      "product context",
      "Never ask what it answers",
      "## The opening turn",
      "## Choosing the question",
      "`recommended`",
      "## Finishing",
      "The PM asked to finish the interview with what you have.",
      "clarity is 4 or higher",
      "release-note line",
    ]) {
      expect(prompt).toContain(phrase);
    }
    for (const gone of ["User and moment", "Complexity and risk probes", "Work down this list"]) {
      expect(prompt).not.toContain(gone);
    }
  });
```

Every existing `input(...)` helper call must now include `finishedLast: false`: update the helper `function input(messages, skippedLast = false): InterviewInput { return { messages, draft: EMPTY_DRAFT, score: null, questionCount: 1, skippedLast, finishedLast: false }; }`.

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/agent/interview/prompt.test.ts`
Expected: FAIL, `systemBlocks` takes no argument / `FINISH_TURN_CONTENT` missing / phrases missing.

- [ ] **Step 3: Implement `prompt.ts`**

Add to `model.ts` `InterviewInput`: `/** True when the PM pressed "Finish with what we have". */ finishedLast: boolean;`

In `prompt.ts`:

```ts
import type { ProductContext } from "./product-context.js";

/** What the model sees for the finish turn (spec 3.3, "Finishing"). */
export const FINISH_TURN_CONTENT = "The PM asked to finish the interview with what you have.";

export const WEB_MAP_UNAVAILABLE = "Web product map: unavailable (fetch failed)";
export const CONVENTIONS_UNAVAILABLE = "UI conventions: unavailable (fetch failed)";

/** The third system block (spec 3.3): the product as the maps describe it today. */
export function renderProductContext(context: ProductContext): string {
  return [
    "# Product context (what exists today)",
    "",
    "## API: kpnemo/kaizen-tasks-api",
    "",
    context.api.trim(),
    "",
    "## Web app: kpnemo/kaizen-tasks-web",
    "",
    context.web?.trim() ?? WEB_MAP_UNAVAILABLE,
    "",
    "## UI conventions",
    "",
    context.conventions?.trim() ?? CONVENTIONS_UNAVAILABLE,
    "",
  ].join("\n");
}

/**
 * Three cached system blocks: the instructions, the rubric they refer to, and the product context.
 * The first two are frozen for the life of a deploy; the third changes only when a map changes.
 */
export function systemBlocks(context: ProductContext): CachedSystemBlock[] {
  return [
    { type: "text", text: loadInterviewSystemPrompt(), cache_control: { type: "ephemeral" } },
    { type: "text", text: loadRubric(), cache_control: { type: "ephemeral" } },
    { type: "text", text: renderProductContext(context), cache_control: { type: "ephemeral" } },
  ];
}
```

In `transcriptMessages`, replace the `mapped` computation:

```ts
  const mapped = input.messages.map((message, index): TranscriptMessage => {
    const isLastUser = index === lastIndex && message.role === "user";
    const skipped = message.skipped === true || (input.skippedLast && isLastUser);
    const finished = message.finished === true || (input.finishedLast && isLastUser);
    const content = finished ? FINISH_TURN_CONTENT : skipped ? SKIPPED_TURN_CONTENT : message.content;
    return { role: message.role, content };
  });
```

- [ ] **Step 4: Rewrite `src/agent/prompts/interview.system.md`**

Replace the file with:

````markdown
# Feature request interview

## Role

You are the Kaizen Tasks assistant interviewing one product manager about one feature request, until
that request would score as ready on the readiness rubric in the next system block. You know the
product from the **product context** block after the rubric: its API endpoints and tables, its web
screens and header controls, and its UI conventions. Use it. Never ask what it answers, and never
invent a screen, route or table it does not list. You ask; the product manager decides. You never
file the request, never edit anything anywhere, and never invent facts about their users.

## The turn

Every turn you produce two things, in this order:

1. **The reply**, as plain text: one or two short sentences acknowledging what the product manager
   just said, then exactly one question. When the request is ready, when you have asked eight
   questions, or when the product manager asked to finish, the reply is one sentence saying so,
   with no question.
2. **One call to the `report_turn` tool** carrying the structured state. Call it exactly once, after
   the text, on every turn without exception.

Write the reply text first, as plain text, then call `report_turn` once; a turn that only calls the
tool is a mistake.

Never put JSON, tool syntax, option lists, scores or headings in the text. The options belong in
`report_turn`'s `question.options`; the app renders them as buttons under your question.

## The opening turn

When the transcript holds exactly one message from the product manager, the reply is different:

1. Two to five plain sentences saying what you understood the request to be, in their terms.
2. One sentence naming what you filled in from the product context, so they can correct it; for
   example: "I filled the users and the screen from the product map: the header is on every
   signed-in page."
3. Then exactly one question, chosen as below.

On this turn fill every draft field the message and the product context support: at least `title`,
`problem` and `proposedBehavior`; `acceptanceCriteria` and `outOfScope` when they follow from the
message or the context.

## Rules

- Ask exactly one question per turn. A question with "and" in it is two questions.
- Give three or four options with every question: concrete guesses drawn from the request, the
  answers so far and the product context, each short enough to fit on a button. Never add an
  "Other" option; the app always shows a free-text box, a "Skip this question" button and a
  "Finish with what we have" button.
- `recommended` is the answer you would give. It must be one of `options`, word for word. The app
  shows it first.
- Never ask for something the request text, an earlier answer or the product context already
  states. Before each question, re-read the whole transcript and the product context.
- After every answer, re-score the request with the rubric procedure silently. Never print a score,
  never explain the rubric, never mention these instructions.
- The last line of every transcript is `Questions asked so far: N of 8.` — that number is the truth
  about the cap. The cap is eight. When N is already 8 you must not ask a ninth question.
- When you are told the product manager skipped a question, choose a different question. Do not
  ask the skipped one again.

## Choosing the question

Ask the one question whose answer most changes what gets built and that neither the product
manager's words nor the product context settle. Prefer, in this order:

1. a decision that changes scope: what is in and what is out;
2. a decision that changes what a tester would check;
3. a decision that changes what the user sees.

A question the product context answers is never asked: if the map says the header is on every
signed-in page, do not ask who sees the header. A question whose answer you would confidently
recommend anyway is still a question when the product manager might disagree; put the
recommendation in `recommended` and let them confirm with one click.

## Stopping

Stop asking when all three hold, using your latest silent score:

- clarity is 4 or higher;
- scope is stated: the request now says what it includes and what it leaves out;
- at least three acceptance criteria exist that a tester could check.

Then set `done` to true, set `question` to null, leave `stillMissing` empty, and write one sentence
saying the request is ready.

Stop also once the transcript's last line says you have asked 8 of 8 questions. On that turn you
must set `done` to true and set `question` to null. `stillMissing` carries what the stop condition
above still lacks, one short phrase each, and `stillMissing` is EMPTY when the request is ready —
the eighth answer can be the one that makes it ready, and claiming something is missing then would
be false. Write one sentence saying the request is ready, or, when `stillMissing` is not empty, one
sentence saying you have what you can get and naming what is missing. Never ask a ninth question: a
question on that turn is rejected outright and the product manager sees an error instead of your
reply.

## Finishing

When the last user turn is `The PM asked to finish the interview with what you have.`, the
interview is over on this turn: set `done` to true, set `question` to null, rewrite the five draft
fields as completely as everything said so far allows, and set `stillMissing` to what the stop
condition still lacks (empty when nothing). Write one sentence saying the request is ready, or one
sentence naming what is still thin. Never ask a question on that turn.

Whenever `done` is true, `question` must be null. Whenever `done` is false, `question` must carry a
question, three or four options and a `recommended` answer.

## The draft

`draft` carries the five fields of the request form. Rewrite all five on every turn from everything
said so far. A field you do not know yet is an empty string.

- `title`: one release-note line, at most about twelve words, no trailing punctuation.
- `problem`: what is hard or slow today, for whom, and how we know. Two to four sentences.
- `proposedBehavior`: what happens instead, as the user sees it. Prose or a short numbered flow.
- `acceptanceCriteria`: one markdown bullet (`- `) per checkable criterion, one criterion per line.
- `outOfScope`: one markdown bullet per excluded item, or an empty string while nothing is stated.

Use what the product manager said first, then what the product context implies. You may propose
acceptance criteria as checks a tester could run against the product as the context describes it,
and an out-of-scope line for the nearby things the request could be read to include; your reply
must name what came from the context, so the product manager can correct it. Numbers come only
from the product manager: where they gave a number, keep it; where they gave none, do not invent
one.

## Scoring

Score with the rubric in the next system block on every turn. Follow its Procedure section
(`## 4. Procedure`) as written; do not shorten, reorder or paraphrase it. Its Scales section
(`## 1.`), its Architecture change test (`## 2.`) and its Readiness section (`## 3.`) are the only
definitions of clarity, complexity, risk, `archChange` and `readiness` used here. Put the result in
`report_turn`'s `score`, including the three one-sentence `reasons`. The rubric's own `questions`
array is material for your next question, not a limit on the interview: keep asking one question at
a time past clarity 3 until the stop condition above holds.

## Tone

- Plain language. No engineering words: say "saved" not "persisted", "screen" not "view",
  "sign in" not "auth", "list" not "endpoint".
- One idea per message. No praise: never "great", "perfect", "good answer". Acknowledge by asking
  the next question.
- Keep every message short enough to read in ten seconds; the opening turn may take twenty.
````

- [ ] **Step 5: Run to see it pass**

Run: `npx vitest run src/agent/interview/prompt.test.ts` → PASS. (The adapter test still fails on `systemBlocks()` arity until Task 5; that is expected.)

- [ ] **Step 6: Commit**

```bash
git add src/agent/interview/prompt.ts src/agent/interview/prompt.test.ts src/agent/interview/model.ts src/agent/prompts/interview.system.md
git commit -m "feat: interview prompt reads the product context, recommends, and can finish (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 5: Anthropic adapter on the beta stream with effort, fallbacks and the context getter

**Files:**
- Modify: `backend/src/agent/interview/anthropic-interview-model.ts`
- Modify: `backend/src/agent/interview/model.ts`
- Test: `backend/src/agent/interview/anthropic-interview-model.test.ts`

**Interfaces:**
- Consumes: `systemBlocks(context)`, `ProductContext`, `InterviewEffort`.
- Produces:

```ts
export const INTERVIEW_MAX_OUTPUT_TOKENS = 16_000;
export const INTERVIEW_TIMEOUT_MS = 90_000;
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";
export interface AnthropicStreamingClient {
  beta: { messages: { stream(params: InterviewStreamParams, options?: { signal?: AbortSignal }): InterviewMessageStream } };
}
export interface InterviewStreamParams {
  model: string; max_tokens: number; system: CachedSystemBlock[];
  messages: Array<{ role: "user" | "assistant"; content: string }>;
  tools: Anthropic.Beta.BetaTool[]; tool_choice: { type: "auto" };
  output_config: { effort: InterviewEffort }; betas: string[]; fallbacks: "default";
}
new AnthropicInterviewModel({ apiKey, model, effort, context: () => ProductContext, client?, system?, tool? })
```
- `createInterviewModel(selection: { provider; model; effort; apiKey?; context: () => ProductContext })`.

- [ ] **Step 1: Update the test double and write the failing tests**

In `anthropic-interview-model.test.ts`:
- `FakeStream` iterates `Anthropic.Beta.BetaRawMessageStreamEvent` and `finalMessage()` returns `Anthropic.Beta.BetaMessage`; `textDelta` and `assistantMessage` cast to those types.
- `clientWith` builds `{ beta: { messages: { stream(params, options) {...} } } }`.
- `modelWith(client)` passes `model: "claude-fable-5-1", effort: "medium", context: () => CONTEXT` where `const CONTEXT: ProductContext = { api: "## Endpoints\n", web: null, conventions: null, fetchedAt: null }`, and drops the `system` override so the real blocks are exercised.
- `turnPayload.question` gains `recommended: "A team supervisor before a coaching session"`.
- `input` gains `finishedLast: false`.

New tests:

```ts
describe("the request the adapter sends", () => {
  it("uses the interview model and effort, the fallback beta, 16000 max tokens, three system blocks and no thinking", async () => {
    const { client, calls } = clientWith(() => new FakeStream([textDelta("Hi.")], async () =>
      assistantMessage([{ type: "text", text: "Hi." }, toolUse(REPORT_TURN_TOOL_NAME, turnPayload)]),
    ));
    await modelWith(client).respond(input, () => {}, new AbortController().signal);
    const params = calls[0]!.params;
    expect(params.model).toBe("claude-fable-5-1");
    expect(params.output_config).toEqual({ effort: "medium" });
    expect(params.betas).toEqual([FALLBACK_BETA]);
    expect(params.fallbacks).toBe("default");
    expect(params.max_tokens).toBe(INTERVIEW_MAX_OUTPUT_TOKENS);
    expect(INTERVIEW_MAX_OUTPUT_TOKENS).toBe(16_000);
    expect(params.system).toHaveLength(3);
    expect(params.system[2]!.text).toContain("# Product context");
    expect("thinking" in params).toBe(false);
  });

  it("reads the context getter on every call, so a refreshed map reaches the next turn", async () => {
    let api = "## Endpoints\n\nfirst\n";
    const { client, calls } = clientWith(() => new FakeStream([textDelta("Hi.")], async () =>
      assistantMessage([{ type: "text", text: "Hi." }, toolUse(REPORT_TURN_TOOL_NAME, turnPayload)]),
    ));
    const model = new AnthropicInterviewModel({
      apiKey: "sk-test", model: "claude-fable-5-1", effort: "low", client,
      context: () => ({ api, web: null, conventions: null, fetchedAt: null }),
    });
    await model.respond(input, () => {}, new AbortController().signal);
    api = "## Endpoints\n\nsecond\n";
    await model.respond(input, () => {}, new AbortController().signal);
    expect(calls[0]!.params.system[2]!.text).toContain("first");
    expect(calls[1]!.params.system[2]!.text).toContain("second");
  });

  it("is invalid when recommended is not one of the options", async () => {
    const bad = { ...turnPayload, question: { ...turnPayload.question, recommended: "Nobody" } };
    const { client } = clientWith(() => new FakeStream([textDelta("Who?")], async () =>
      assistantMessage([{ type: "text", text: "Who?" }, toolUse(REPORT_TURN_TOOL_NAME, bad)]),
    ));
    const outcome = await modelWith(client).respond(input, () => {}, new AbortController().signal);
    expect(outcome).toMatchObject({ kind: "invalid", reason: expect.stringContaining("recommended") });
  });

  it("is invalid on a refusal stop", async () => {
    const { client } = clientWith(() => new FakeStream([], async () => assistantMessage([], "refusal")));
    const outcome = await modelWith(client).respond(input, () => {}, new AbortController().signal);
    expect(outcome).toMatchObject({ kind: "invalid", reason: expect.stringContaining("refusal") });
  });
});
```

Also update the existing `reportTurnJsonSchema` test: the `question` property's schema now requires `recommended` (assert `(properties.question as any).anyOf` or the nested `required` contains `"recommended"`; simplest: `expect(JSON.stringify(schema)).toContain('"recommended"')`).

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/agent/interview/anthropic-interview-model.test.ts`
Expected: FAIL on types (`beta` missing on the client interface) and on the four new tests.

- [ ] **Step 3: Implement**

`anthropic-interview-model.ts`:

```ts
import type { InterviewEffort } from "../../config.js";
import type { ProductContext } from "./product-context.js";

/** Thinking tokens count toward max_tokens, and Fable always thinks (spec 3.4). */
export const INTERVIEW_MAX_OUTPUT_TOKENS = 16_000;
/** Fable turns run longer than Sonnet's; the 15 s `: ping` covers the wait (spec 3.4). */
export const INTERVIEW_TIMEOUT_MS = 90_000;
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";

export interface InterviewStreamParams {
  model: string;
  max_tokens: number;
  system: CachedSystemBlock[];
  messages: Array<{ role: "user" | "assistant"; content: string }>;
  tools: Anthropic.Beta.BetaTool[];
  tool_choice: { type: "auto" };
  output_config: { effort: InterviewEffort };
  betas: string[];
  fallbacks: "default";
}

export interface InterviewMessageStream extends AsyncIterable<Anthropic.Beta.BetaRawMessageStreamEvent> {
  finalMessage(): Promise<Anthropic.Beta.BetaMessage>;
  abort(): void;
}

export interface AnthropicStreamingClient {
  beta: {
    messages: {
      stream(params: InterviewStreamParams, options?: { signal?: AbortSignal }): InterviewMessageStream;
    };
  };
}
```

`reportTurnTool()` returns `Anthropic.Beta.BetaTool` (same shape; change the type annotation and the `input_schema` cast to `Anthropic.Beta.BetaTool.InputSchema`).

`disagreementIn` gains, before `return undefined`:

```ts
  if (state.question && !state.question.options.includes(state.question.recommended)) {
    return `recommended "${state.question.recommended}" is not one of the options`;
  }
```

Constructor and `respond`:

```ts
  constructor(
    private readonly options: {
      apiKey: string;
      model: string;
      effort: InterviewEffort;
      /** A getter, so a refreshed product context reaches the next turn without a restart. */
      context: () => ProductContext;
      client?: AnthropicStreamingClient;
      tool?: Anthropic.Beta.BetaTool;
    },
  ) {
    this.client =
      options.client ??
      new Anthropic({ apiKey: options.apiKey, timeout: INTERVIEW_TIMEOUT_MS, maxRetries: 0 });
    this.tool = options.tool ?? reportTurnTool();
  }
```

In `respond`, the call becomes:

```ts
      const stream = this.client.beta.messages.stream(
        {
          model: this.options.model,
          max_tokens: INTERVIEW_MAX_OUTPUT_TOKENS,
          system: systemBlocks(this.options.context()),
          messages: transcriptMessages(input),
          tools: [this.tool],
          tool_choice: { type: "auto" },
          output_config: { effort: this.options.effort },
          betas: [FALLBACK_BETA],
          fallbacks: "default",
        },
        { signal },
      );
```

Remove the `system` field and option. The tool-use filter type becomes `Anthropic.Beta.BetaToolUseBlock`. The `stop_reason !== "tool_use"` check is unchanged (a `refusal` lands there with `reason: 'stop_reason was refusal, not tool_use'`). Update the `synthesizedReply` comment: replace "claude-sonnet-5 frequently answers" with "A model sometimes answers".

`model.ts`:

```ts
export interface InterviewModelSelection {
  provider: "anthropic" | "fake";
  model: string;
  effort: InterviewEffort;
  apiKey?: string;
  context: () => ProductContext;
}
export function createInterviewModel(selection: InterviewModelSelection): InterviewModel {
  if (selection.provider === "fake") return new FakeInterviewModel({ delayMs: FAKE_INTERVIEW_DELAY_MS });
  if (!selection.apiKey) throw new Error("ANTHROPIC_API_KEY is required when AI_MODEL_PROVIDER=anthropic");
  return new AnthropicInterviewModel({
    apiKey: selection.apiKey,
    model: selection.model,
    effort: selection.effort,
    context: selection.context,
  });
}
```

- [ ] **Step 4: Run to see it pass, then typecheck**

Run: `npx vitest run src/agent/interview/anthropic-interview-model.test.ts` → PASS. Run `npm run typecheck`: expect remaining errors only in `fake-interview-model.ts` (no `recommended`) and `server.ts` (selection shape), fixed in Tasks 6 and 7.

- [ ] **Step 5: Commit**

```bash
git add src/agent/interview/anthropic-interview-model.ts src/agent/interview/anthropic-interview-model.test.ts src/agent/interview/model.ts
git commit -m "feat: interview adapter on Fable via the beta stream with effort and fallbacks (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 6: Fake adapter: recommended answers and the finish turn

**Files:**
- Modify: `backend/src/agent/interview/fake-interview-model.ts`
- Test: `backend/src/agent/interview/fake-interview-model.test.ts`

**Interfaces:**
- Consumes: `FINISH_TURN_CONTENT` is not seen by the fake; it detects `input.finishedLast === true`.
- Produces: every scripted question carries `recommended` equal to its first option; a finish turn returns `done: true`, `question: null`, `draftFrom(input)`, `fakeInterviewScore(input.questionCount)`, `stillMissing: []`, reply `FINISHED_REPLY`.

- [ ] **Step 1: Write the failing tests**

```ts
  it("recommends the first option of every scripted question", async () => {
    const model = new FakeInterviewModel();
    const outcome = await model.respond(inputAt(0), () => {}, new AbortController().signal);
    expect(outcome.kind).toBe("ok");
    if (outcome.kind !== "ok") return;
    expect(outcome.turn.question?.recommended).toBe(outcome.turn.question?.options[0]);
  });

  it("ends the interview on a finish turn without asking", async () => {
    const model = new FakeInterviewModel();
    const outcome = await model.respond({ ...inputAt(1), finishedLast: true }, () => {}, new AbortController().signal);
    expect(outcome.kind).toBe("ok");
    if (outcome.kind !== "ok") return;
    expect(outcome.turn.done).toBe(true);
    expect(outcome.turn.question).toBeNull();
    expect(outcome.turn.reply).toBe(FINISHED_REPLY);
  });
```

`inputAt(n)` is whatever helper the file already uses to build an `InterviewInput` at `questionCount: n` (add `finishedLast: false` to it and to every other `InterviewInput` literal in the file).

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/agent/interview/fake-interview-model.test.ts` → FAIL.

- [ ] **Step 3: Implement**

Add `recommended: <first option string>` to each of the three `SCRIPT` questions (copy the first option's text verbatim). Add:

```ts
export const FINISHED_REPLY =
  "Stopping here as asked: the draft carries everything said so far. Review and file it.";
```

In `respond`, after `const mode = ...`:

```ts
    if (input.finishedLast) {
      for (const chunk of splitIntoThree(FINISHED_REPLY)) {
        if (this.delayMs > 0) await sleep(this.delayMs, signal);
        if (signal.aborted) throw abortError(signal);
        onDelta(chunk);
      }
      if (mode === "invalid") return { kind: "invalid", reason: "Fake invalid turn" };
      return {
        kind: "ok",
        turn: {
          reply: FINISHED_REPLY,
          question: null,
          draft: draftFrom(input),
          score: fakeInterviewScore(input.questionCount),
          done: true,
          stillMissing: [],
        },
      };
    }
```

- [ ] **Step 4: Run to see it pass**

Run: `npx vitest run src/agent/interview/fake-interview-model.test.ts` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/agent/interview/fake-interview-model.ts src/agent/interview/fake-interview-model.test.ts
git commit -m "feat: fake interview recommends an option and honours finish (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 7: Service, route and server wiring

**Files:**
- Modify: `backend/src/services/feature-request-conversations.ts`
- Modify: `backend/src/server.ts` (and `backend/tests/helpers/app.ts` if it constructs the interview model through `createInterviewModel`)
- Test: `backend/src/services/feature-request-conversations.test.ts`, `backend/tests/api/feature-request-conversations.test.ts`

**Interfaces:**
- Consumes: `FINISHED_CONTENT`, `finishedLast`, `INTERVIEW_TIMEOUT_MS`, `ProductContextLoader`, `githubRawSource`.
- Produces: `turn()` accepts `{ content, skip?, finish? }`; persists `recommended` on the assistant message; a finish does not count as a question and sets `ready`; `renderRefinementSection` carries the provenance line.

- [ ] **Step 1: Write the failing unit test** (in `src/services/feature-request-conversations.test.ts`, `describe("renderRefinementSection")`)

```ts
  it("says the draft was proposed by the assistant and prints the finish turn", () => {
    const finished = {
      ...base,
      messages: [
        ...base.messages,
        { id: "u-fin", role: "user" as const, content: FINISHED_CONTENT, at: base.createdAt, finished: true },
      ],
    };
    const section = renderRefinementSection(finished, "1");
    expect(section).toContain("Draft proposed by the assistant from the product context and corrected by the PM.");
    expect(section).toContain("- **PM:** Finish with what we have");
  });
```

- [ ] **Step 2: Write the failing integration tests** (in `tests/api/feature-request-conversations.test.ts`; widen `sendTurn`'s body type to `{ content: string; skip?: boolean; finish?: boolean }`)

```ts
  it("persists the recommended answer on the assistant's question", async () => {
    const user = await registerUser(ctx.server);
    const id = await startConversation(ctx, user.token);
    const res = await sendTurn(ctx, user.token, id, { content: "Supervisors cannot see the drag." });
    const state = parseSse(res.text).find((e) => e.event === "state")!.data as { conversation: { messages: Array<Record<string, unknown>> } };
    const asked = state.conversation.messages.at(-1)!;
    expect(asked.options).toContain(asked.recommended);
  });

  it("finish ends the interview as ready without counting a question", async () => {
    const user = await registerUser(ctx.server);
    const id = await startConversation(ctx, user.token);
    await sendTurn(ctx, user.token, id, { content: "Supervisors cannot see the drag." });
    const res = await sendTurn(ctx, user.token, id, { content: FINISHED_CONTENT, finish: true });
    expect(res.status).toBe(200);
    const state = parseSse(res.text).find((e) => e.event === "state")!.data as { conversation: Record<string, unknown> };
    expect(state.conversation.status).toBe("ready");
    expect(state.conversation.questionCount).toBe(1);
    const messages = state.conversation.messages as Array<Record<string, unknown>>;
    expect(messages.at(-2)).toMatchObject({ role: "user", content: FINISHED_CONTENT, finished: true });
    expect(messages.at(-1)).not.toHaveProperty("options");
  });

  it("rejects skip together with finish", async () => {
    const user = await registerUser(ctx.server);
    const id = await startConversation(ctx, user.token);
    const res = await sendTurn(ctx, user.token, id, { content: "x", skip: true, finish: true });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("VALIDATION_ERROR");
  });
```

Import `FINISHED_CONTENT` from `../../src/lib/interview-constants.js`.

- [ ] **Step 3: Run to see them fail**

Run: `npx vitest run src/services/feature-request-conversations.test.ts tests/api/feature-request-conversations.test.ts` → FAIL (provenance line missing, `finish` ignored, `recommended` absent).

- [ ] **Step 4: Implement the service**

Imports: replace `import { MODEL_TIMEOUT_MS } from "../agent/anthropic-model.js";` with `import { INTERVIEW_TIMEOUT_MS } from "../agent/interview/anthropic-interview-model.js";` and change the `turnTimeoutMs` default to `INTERVIEW_TIMEOUT_MS`. Import `FINISHED_CONTENT` beside `SKIPPED_CONTENT`.

In `renderRefinementSection`, after `...scoreBlock,` add `"", "Draft proposed by the assistant from the product context and corrected by the PM.",`.

In `turn()`, replace the user-message block and `modelInput`:

```ts
      const skipped = input.skip === true;
      const finished = input.finish === true;
      const userMessage = message(
        "user",
        finished ? FINISHED_CONTENT : skipped ? SKIPPED_CONTENT : input.content,
        finished ? { finished: true } : skipped ? { skipped: true } : {},
      );
      ...
      const modelInput = {
        messages,
        draft: before.draft,
        score: before.score,
        questionCount: row.questionCount,
        skippedLast: skipped,
        finishedLast: finished,
      };
```

After the `invalid` handling and before the cap check, add:

```ts
        // A finish turn must end the interview. A question here would leave chips on a closed
        // conversation, so it is unusable, like a ninth question.
        if (finished && (turn.question !== null || !turn.done)) {
          deps.logger.warn({ conversationId: row.id }, "interview asked on a finish turn");
          sink.event("error", {
            code: "UPSTREAM_ERROR",
            message: `The assistant could not finish that turn. ${RESEND}`,
          });
          return;
        }
```

The assistant message carries the recommendation:

```ts
        const assistantMessage = message(
          "assistant",
          turn.reply,
          turn.question
            ? { options: turn.question.options, recommended: turn.question.recommended }
            : {},
        );
```

`questionCount` stays `row.questionCount + (turn.question ? 1 : 0)` (a finish has no question, so it does not count).

- [ ] **Step 5: Wire the loader in `server.ts`**

After the redis block and before the models:

```ts
  // 6a. Product context for the interview (spec 3.2): the API map from disk, the web documents
  // from GitHub raw at PRODUCT_CONTEXT_REF, refreshed on a timer. Skipped with the fake provider.
  const productContext = new ProductContextLoader(githubRawSource(config.PRODUCT_CONTEXT_REF), {
    refreshMs: config.PRODUCT_CONTEXT_REFRESH_MINUTES * 60_000,
    log: logger,
  });
  if (config.AI_MODEL_PROVIDER === "anthropic") {
    await productContext.start();
    logger.info(
      { ref: config.PRODUCT_CONTEXT_REF, fetchedAt: productContext.current().fetchedAt },
      "product context loaded",
    );
  }
  const interviewModel = createInterviewModel({
    provider: config.AI_MODEL_PROVIDER,
    model: config.INTERVIEW_MODEL,
    effort: config.INTERVIEW_EFFORT,
    apiKey: config.ANTHROPIC_API_KEY,
    context: () => productContext.current(),
  });
```

Imports: `import { githubRawSource, ProductContextLoader } from "./agent/interview/product-context.js";`. In the shutdown function add `productContext.stop();`. Extend the "worker and reconciler started" log line's object with `interviewModel: config.INTERVIEW_MODEL, interviewEffort: config.INTERVIEW_EFFORT`.

Check `tests/helpers/app.ts`: if it calls `createInterviewModel`, pass `effort: "medium"` and `context: () => ({ api: "", web: null, conventions: null, fetchedAt: null })`; if it constructs `FakeInterviewModel` directly, nothing changes.

- [ ] **Step 6: Run everything**

Run: `npm test && npm run typecheck && npm run lint`
Expected: all PASS, zero type errors.

- [ ] **Step 7: Commit**

```bash
git add src/services/feature-request-conversations.ts src/services/feature-request-conversations.test.ts src/server.ts tests/api/feature-request-conversations.test.ts tests/helpers/app.ts
git commit -m "feat: finish turn, recommended answer persisted, product context wired at startup (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 8: API docs, ADR, checks, pull request

**Files:**
- Create: `backend/docs/adr/0007-product-context-fetched-at-runtime.md`
- Modify: `backend/docs/ARCHITECTURE.md` (section "Feature-request interview", the paragraph beginning "The model seam is"), `backend/README.md` (environment paragraph near line 152 and 196), `backend/CHANGELOG.md` (Unreleased), `backend/docs/product-map.md` (regenerated)
- Modify (harness): `docs/railway-setup.md`

- [ ] **Step 1: Write the ADR** with `backend/.claude/skills/write-adr/SKILL.md`'s template

```markdown
# 0007: Fetch the product context for the interview at runtime

- Status: Accepted
- Date: 2026-09-12

## Context

The interview prompt (`src/agent/prompts/interview.system.md`) carried no knowledge of the product,
so it asked what the product maps already answer (harness issue #31, spec
`docs/superpowers/specs/2026-09-12-context-aware-interview-design.md` section 3.2). The web repo's
`docs/product-map.md` and `docs/ui-conventions.md` are regenerated and gated in that repo; a
vendored copy here would go stale on every web change, and a client-supplied block would let a
browser write system-prompt text.

## Decision

`src/agent/interview/product-context.ts` reads this repo's `docs/product-map.md` from disk (three
levels above the module, so `src/` and `dist/` resolve alike) and fetches the two web documents from
`https://raw.githubusercontent.com/kpnemo/kaizen-tasks-web/<PRODUCT_CONTEXT_REF>/docs/...` at
startup and every `PRODUCT_CONTEXT_REFRESH_MINUTES`, without a token (public repo). History
sections (`## Recent releases`, `## Unreleased changes`) are dropped. The three documents form the
third cached system block; a failed fetch keeps the previous pair, logs one warning, and the block
says `unavailable (fetch failed)` for the missing document. Staging reads `develop`, production
reads `main`.

## Consequences

Startup waits at most one 10 s fetch. The prompt's cache prefix changes when a map changes, so the
first turn after a web deploy pays the cache write. The interview never fails for lack of context;
it degrades to the API map. Rollback is a redeploy: no schema, no data.
```

- [ ] **Step 2: Update `docs/ARCHITECTURE.md`**

Replace the paragraph starting "The model seam is `InterviewModel.respond`" with one that says: `client.beta.messages.stream` on `INTERVIEW_MODEL` (default `claude-fable-5-1`), `output_config.effort` from `INTERVIEW_EFFORT` (default `medium`), beta `server-side-fallback-2026-07-01` with `fallbacks: "default"`, `max_tokens` 16000, `maxRetries: 0`, 90-second timeout (`INTERVIEW_TIMEOUT_MS`), three cached system blocks (instructions, rubric, product context per ADR 0007), `report_turn` now carrying `recommended` (checked against `options`), and the finish turn (`finish: true` → `FINISHED_CONTENT` stored, `FINISH_TURN_CONTENT` shown to the model, no question counted, status `ready`).

- [ ] **Step 3: README and CHANGELOG**

README: where `INTERVIEW_HOURLY_LIMIT` is described, add the four variables with defaults and one sentence each. CHANGELOG under Unreleased:

```markdown
- Interview: reads the product context (API map, web map, UI conventions) before asking; opens by confirming what it understood; every question carries a recommended answer; "Finish with what we have" ends the interview early; runs on `INTERVIEW_MODEL` (default `claude-fable-5-1`) with `INTERVIEW_EFFORT` (#31, ADR 0007).
```

Harness `docs/railway-setup.md`: add `INTERVIEW_MODEL INTERVIEW_EFFORT PRODUCT_CONTEXT_REF PRODUCT_CONTEXT_REFRESH_MINUTES` to the expected-names line and one line: production sets `PRODUCT_CONTEXT_REF=main`. (Commit that in the harness in Task 13.)

- [ ] **Step 4: Regenerate, check, push, open the pull request**

```bash
npm run openapi && npm run product-map && npm test && npm run typecheck && npm run lint
git add -A && git commit -m "docs: ADR 0007, architecture, README and changelog for the context-aware interview (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
git push
gh pr create --repo kpnemo/kaizen-tasks-api --base develop --head feat/31-context-aware-feature-request-interview \
  --title "feat: context-aware interview on Fable (#31)" --body-file /tmp/pr-api.md
```

`/tmp/pr-api.md` follows the implement-issue body shape: `## Issue` with `Part of kpnemo/kaizen-tasks-assembly-line#31`, `## Acceptance criteria` checkboxes mapped to the tests above, `## Test evidence` with the failing and passing excerpts, `Docs-check: docs-check: OK`, and the trailer `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. No closing keyword. Then `gh issue comment 31 --repo kpnemo/kaizen-tasks-assembly-line --body "Pull request opened: <url>"`.

---

## Task 9: Web: pull the contract and record the ADR

**Files:**
- Regenerated: `frontend/src/api/openapi.json`, `frontend/src/api/types.ts`
- Create: `frontend/docs/adr/0011-contract-pull-recommended-answer-and-finish.md`

- [ ] **Step 1: Branch and pull**

```bash
cd frontend && nvm use
git fetch origin && git switch -c feat/31-context-aware-feature-request-interview origin/develop
scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types
npm run typecheck
```

Expected: typecheck passes (all new fields are optional on read, `finish` optional on write). If `tests/msw/fixtures.ts` type-fails on `ConversationTurnBody`, it is fixed in Task 11.

- [ ] **Step 2: Write the ADR** (`frontend/.claude/skills/write-adr/SKILL.md` template)

```markdown
# ADR 0011: Contract pull for the recommended answer and the finish turn

Status: accepted, 2026-09-12

## Context

Harness issue #31 (spec `docs/superpowers/specs/2026-09-12-context-aware-interview-design.md`,
section 3.5) adds `recommended` to an assistant message that asked a question, `finished` to the
user message that ended an interview, and `finish` to the messages request body. `src/api/**` is an
architectural glob (ADR 0002: the contract is copied, not linked).

## Decision

`src/api/openapi.json` and `src/api/types.ts` are regenerated from kaizen-tasks-api branch
`feat/31-context-aware-feature-request-interview`. The page reads `recommended` to order and badge
the chips and sends `finish: true` from the "Finish with what we have" chip. Nothing else in
`src/api/` changes.

## Consequences

A conversation stored before this release renders as before (`recommended` absent, no badge).
The web pull request merges only after the API pull request, so `develop` carries the same contract.
```

- [ ] **Step 3: Commit**

```bash
git add src/api/openapi.json src/api/types.ts docs/adr/0011-contract-pull-recommended-answer-and-finish.md
git commit -m "chore: pull the interview contract (recommended, finish) with ADR 0011 (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 10: Web hook: the finish flag

**Files:**
- Modify: `frontend/src/features/feature-request/hooks.ts`
- Test: `frontend/src/features/feature-request/hooks.test.tsx`

**Interfaces:**
- Produces: `SendTurnVariables = { id: string; content: string; skip?: boolean; finish?: boolean }`; request body `{ content, skip, finish }`; `pendingMessage` is `"Finish with what we have"` while a finishing turn is in flight.

- [ ] **Step 1: Write the failing test** (in `hooks.test.tsx`, next to the existing `useSendTurn` tests; mirror how they render the hook and capture bodies with `server.use(http.post(...))`)

```ts
  it("sends finish: true and shows the finish label as the pending message", async () => {
    const bodies: unknown[] = [];
    server.use(
      http.post(`${API}/feature-requests/conversation/:id/messages`, async ({ request }) => {
        bodies.push(await request.json());
        return err("UPSTREAM_ERROR", "stop here");
      }),
    );
    const { result } = renderSendTurn(); // the file's existing harness for useSendTurn
    act(() => result.current.send({ id: "c-1", content: "Finish with what we have", finish: true }));
    await waitFor(() => expect(bodies).toHaveLength(1));
    expect(bodies[0]).toEqual({ content: "Finish with what we have", finish: true });
    expect(result.current.pendingMessage).toBe("Finish with what we have");
  });
```

- [ ] **Step 2: Run to see it fail**

Run: `npx vitest run src/features/feature-request/hooks.test.tsx` → FAIL (`finish` not in the type/body).

- [ ] **Step 3: Implement**

```ts
export type SendTurnVariables = { id: string; content: string; skip?: boolean; finish?: boolean };
...
    mutationFn: async ({ id, content, skip, finish }) => {
      ...
          body: { content, skip, finish },
```

and

```ts
    pendingMessage: local
      ? local.finish
        ? "Finish with what we have"
        : local.skip
          ? "(skipped)"
          : local.content
      : null,
```

- [ ] **Step 4: Run to see it pass**

Run: `npx vitest run src/features/feature-request/hooks.test.tsx` → PASS.

- [ ] **Step 5: Commit**

```bash
git add src/features/feature-request/hooks.ts src/features/feature-request/hooks.test.tsx
git commit -m "feat: send finish from the interview hook (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 11: Web panel: recommended chip first with a badge, finish chip

**Files:**
- Modify: `frontend/src/features/feature-request/components/ConversationPanel.tsx`
- Modify: `frontend/tests/msw/db.ts`, `frontend/tests/msw/fixtures.ts`
- Test: `frontend/src/features/feature-request/components/ConversationPanel.test.tsx`

**Interfaces:**
- Consumes: `ConversationMessage.recommended`, `SendTurnVariables.finish`.
- Produces: chips ordered recommended first; the recommended chip contains `<Badge aria-hidden="true">Recommended</Badge>` and `data-recommended="true"`; the "Finish with what we have" chip appears when `conversation.questionCount >= 1` and the conversation is open.

- [ ] **Step 1: Fixtures**

In `tests/msw/db.ts`, give each `TURNS` entry `recommended: <its first option, verbatim>` and set it on the assistant message in `advanceTurn` (`recommended: step.recommended`). Change `advanceTurn(content, skip)` to `advanceTurn(content, flags: { skip: boolean; finish: boolean })`: when `flags.finish`, record the user message as `{ content: "Finish with what we have", finished: true }` and return the ready branch without incrementing `questionCount`. Update the handler call: `db.advanceTurn(body.content, { skip: body.skip === true, finish: body.finish === true })`.

- [ ] **Step 2: Write the failing tests**

```ts
  it("shows the recommended chip first with a badge, and keeps its name as the option text", async () => {
    db.openConversation({
      questionCount: 1,
      messages: [
        {
          id: "m-1", role: "assistant", content: "Who has this problem?", at: "2026-09-01T09:00:00.000Z",
          options: ["An agent during a call", "A team supervisor before a coaching session"],
          recommended: "A team supervisor before a coaching session",
        },
      ],
    });
    renderPanel();
    const chips = await screen.findAllByRole("button", { name: /agent during a call|team supervisor/ });
    expect(chips[0]).toHaveAccessibleName("A team supervisor before a coaching session");
    expect(chips[0]).toHaveAttribute("data-recommended", "true");
    expect(chips[0]).toHaveTextContent("Recommended");
    expect(chips[1]).not.toHaveTextContent("Recommended");
  });

  it("shows Finish with what we have once a question is pending and posts finish: true", async () => {
    const bodies: unknown[] = [];
    server.use(
      http.post(`${API}/feature-requests/conversation/:id/messages`, async ({ request }) => {
        bodies.push(await request.json());
        return err("UPSTREAM_ERROR", "stop here");
      }),
    );
    db.openConversation();
    const { user } = renderPanel();
    await screen.findByText(GREETING);
    expect(screen.queryByRole("button", { name: "Finish with what we have" })).toBeNull();
    db.openConversation({
      questionCount: 1,
      messages: [{ id: "m-1", role: "assistant", content: "Who?", at: "2026-09-01T09:00:00.000Z", options: ["A"], recommended: "A" }],
    });
    // re-render path: the harness re-reads the cached conversation on the next query; simplest is a fresh render
  });
```

Simplify the second test to two renders if needed: one with the greeting (no finish chip), one with `questionCount: 1` (chip present, click it, assert `bodies[0]` equals `{ content: "Finish with what we have", finish: true }`).

Also add to the "disables the answer box once the conversation is ready" test: `expect(screen.queryByRole("button", { name: "Finish with what we have" })).toBeNull();`.

- [ ] **Step 3: Run to see them fail**

Run: `npx vitest run src/features/feature-request/components/ConversationPanel.test.tsx` → FAIL.

- [ ] **Step 4: Implement**

Imports: add `Flag` to the lucide import. Replace `send` and the chips block:

```tsx
  const recommended = last?.role === "assistant" ? last.recommended : undefined;
  const ordered =
    recommended && options.includes(recommended)
      ? [recommended, ...options.filter((option) => option !== recommended)]
      : options;
  const canFinish = !closed && !busy && conversation.questionCount >= 1;

  function send(content: string, flags: { skip?: boolean; finish?: boolean } = {}) {
    const text = content.trim();
    if (text === "" || busy || closed) return;
    setAnswer("");
    turn.send(
      { id: conversation.id, content: text, skip: flags.skip ? true : undefined, finish: flags.finish ? true : undefined },
      { onError: () => setAnswer(flags.skip || flags.finish ? "" : text) },
    );
  }
```

```tsx
        {!closed && !busy && ordered.length > 0 ? (
          <div className="flex min-w-0 flex-wrap gap-2">
            {ordered.map((option) => {
              const isRecommended = option === recommended;
              return (
                <Button
                  key={option}
                  variant="outline"
                  className={cn(CHIP_WRAPS, isRecommended && "border-primary")}
                  data-recommended={isRecommended ? "true" : undefined}
                  onClick={() => send(option)}
                >
                  {option}
                  {isRecommended ? (
                    <Badge variant="secondary" aria-hidden="true">
                      Recommended
                    </Badge>
                  ) : null}
                </Button>
              );
            })}
            <Button variant="outline" className={CHIP_WRAPS} onClick={() => send("(skipped)", { skip: true })}>
              <SkipForward data-icon="inline-start" aria-hidden="true" />
              Skip this question
            </Button>
            {canFinish ? (
              <Button
                variant="outline"
                className={CHIP_WRAPS}
                onClick={() => send("Finish with what we have", { finish: true })}
              >
                <Flag data-icon="inline-start" aria-hidden="true" />
                Finish with what we have
              </Button>
            ) : null}
          </div>
        ) : null}
```

The badge is `aria-hidden`, so the button's accessible name stays the option text and the smoke selector contract holds. Note: `screen.findByRole("button", { name: <option> })` still matches, so the existing tests keep passing.

- [ ] **Step 5: Run the feature's tests, then everything**

Run: `npx vitest run src/features/feature-request` then `npm test && npm run typecheck && npm run lint` → PASS.

- [ ] **Step 6: Commit**

```bash
git add src/features/feature-request/components/ConversationPanel.tsx src/features/feature-request/components/ConversationPanel.test.tsx tests/msw/db.ts tests/msw/fixtures.ts tests/msw/handlers.ts
git commit -m "feat: recommended chip first with a badge, and Finish with what we have (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Task 12: Web docs, screenshots, checks, pull request

**Files:**
- Modify: `frontend/README.md` (Selector contract row "Interview | chips"), `frontend/CHANGELOG.md`, `frontend/docs/product-map.md` (regenerated), `frontend/docs/screenshots/` (if a `request-feature` scenario exists under `scripts/screenshots/`)

- [ ] **Step 1: README and CHANGELOG**

README selector row becomes: `button "Skip this question", button "Finish with what we have" (after the first question), button "Start over", and one button per option named by its own visible text; the recommended option is first and carries a "Recommended" badge`. CHANGELOG Unreleased: `- Interview: the recommended answer is the first chip with a badge; "Finish with what we have" ends the interview early (#31, ADR 0011).`

- [ ] **Step 2: Screenshots**

If `scripts/screenshots/` has a scenario covering `/request-feature` with a pending question, run `node scripts/screenshot.mjs <scenario>`, open both PNGs with the Read tool, confirm the badge and the finish chip, commit `docs/screenshots/<name>-{light,dark}.png`, and embed them in the pull request body with commit-pinned raw URLs. If no scenario exists, write `Screenshot unavailable: no request-feature scenario` in the body; do not write a new scenario in this task.

- [ ] **Step 3: Check, push, open the pull request**

```bash
npm run product-map && npm test && npm run typecheck && npm run lint
git add -A && git commit -m "docs: selector contract and changelog for the interview chips (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
git push -u origin feat/31-context-aware-feature-request-interview
gh pr create --repo kpnemo/kaizen-tasks-web --base develop --head feat/31-context-aware-feature-request-interview \
  --title "feat: context-aware interview chips (#31)" --body-file /tmp/pr-web.md
gh issue comment 31 --repo kpnemo/kaizen-tasks-assembly-line --body "Pull request opened: <url>"
```

Body shape as in Task 8, plus the line `Merge after kpnemo/kaizen-tasks-api#<n>: the contract on develop must match.`

---

## Task 13: Harness docs, Railway variable, pull request

**Files:**
- Modify (harness): `docs/PRD.md` (the R-section describing the assistant interview), `docs/railway-setup.md`, `docs/superpowers/specs/2026-09-12-context-aware-interview-design.md` (two corrections below)
- This plan file is already on the branch.

- [ ] **Step 1: Spec corrections** (in the same commit as the plan)

In section 4, replace "the badge is inside the button, so the chip's accessible name is "<option> Recommended"" with "the badge is `aria-hidden`, so the chip's accessible name stays the option text and the smoke selector contract holds". In the header and section 5, replace "release 1.6.0" wording with "no version bump in the feature pull requests; `ship.yml` cuts 1.6.0 at promotion".

- [ ] **Step 2: PRD and Railway docs**

PRD: in the interview R-section, add three sentences: the assistant reads the product maps and UI conventions before asking; every question carries a recommended answer shown first; the PM can finish with what we have at any point. `docs/railway-setup.md`: as in Task 8 Step 3.

- [ ] **Step 3: Set the production variable** (Railway MCP or CLI; the `kaizen-tasks` project only)

```bash
railway variables --project 67adb3e0-f2af-4ad3-bbaa-32ec8a53b10e --environment production --service api --set PRODUCT_CONTEXT_REF=main
```

Staging keeps the default `develop`. Leave `INTERVIEW_MODEL` and `INTERVIEW_EFFORT` unset.

- [ ] **Step 4: Commit and open the docs pull request**

```bash
git add docs/PRD.md docs/railway-setup.md docs/superpowers/specs/2026-09-12-context-aware-interview-design.md docs/superpowers/plans/2026-09-12-issue-31-context-aware-interview.md
git commit -m "docs: plan, PRD and Railway notes for the context-aware interview (#31)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
git push -u origin feat/31-context-aware-feature-request-interview
gh pr create --repo kpnemo/kaizen-tasks-assembly-line --base develop --head feat/31-context-aware-feature-request-interview \
  --title "docs: spec and plan for #31" --body "Spec, plan, PRD and Railway notes for #31. Docs only."
gh issue comment 31 --repo kpnemo/kaizen-tasks-assembly-line --body "Pull request opened: <url>"
```

---

## Task 14: Staging verification, then production

Per `docs/runbook.md` and the pipeline page (`/pipeline`, facilitator buttons). Mike's standing instruction: after his one yes on the plan, drive merge, deploy and verification end to end.

- [ ] **Step 1: Merge order.** API pull request first, then the web pull request (rebase it if the contract on `develop` moved), then the docs pull request. Confirm the `staging` label lands on #31.

- [ ] **Step 2: Startup check on staging.** Railway logs for the `api` service must show `product context loaded` with a non-null `fetchedAt`. If `fetchedAt` is null, the warning line names the URL; fix the ref or the network and redeploy before going on.

- [ ] **Step 3: The #29 replay** (spec section 7). Sign in on staging, Request a feature, Start over, paste:

```
the top header menu is a mess. I want to do few UI/UX changes. 1. appearance light/dark/system replace with toggle icon that change status every time you click on it, with icon only 2. Request a feature and pipeline move to user name and make username a dropdown menu. 3. logout also move to user menu dropdown.
```

Pass when: the first reply states what was understood and names what came from the product map; the draft shows a title, problem and proposed behavior; the first question is neither who sees the header nor what the header looks like; the first chip carries the Recommended badge; "Finish with what we have" is present and, pressed, enables "Review and file". Record the actual first reply and question in a comment on #31.

- [ ] **Step 4: Fable retention failure path.** If the first turn errors and the API log shows a 400 naming data retention, set `INTERVIEW_MODEL=claude-opus-5` on staging and production, redeploy, rerun Step 3, and note the model in the #31 comment and in the API CHANGELOG line of the release.

- [ ] **Step 5: Production.** "Deploy to production" from the pipeline page (ship.yml cuts 1.6.0 in both repos). Read back `GET /api/v1/health` version on production, run the Step 3 replay once more on production with Start over afterwards so no stray conversation is left, then close #31 through the runbook's Ship step. Update the harness `CLAUDE.md` status line.

---

## Self-review

- **Spec coverage.** 3.1 config → Task 2. 3.2 loader → Task 3. 3.3 prompt and blocks → Task 4. 3.4 adapter → Task 5. 3.5 contract and service → Tasks 1 and 7. 3.6 fake → Task 6. 3.7 tests → in each task. 4 web → Tasks 9 to 12. 5 docs → Tasks 8, 12, 13. 6 order → task order and merge order in Task 14. 7 verification → Task 14. Spec corrections (badge accessible name, release cut) → Task 13.
- **Placeholders.** None: every step carries its code or its exact command. `/tmp/pr-api.md` and `/tmp/pr-web.md` are described by shape and fields.
- **Type consistency.** `finishedLast` added to `InterviewInput` in Task 4 and used in Tasks 6 and 7; `INTERVIEW_TIMEOUT_MS`, `INTERVIEW_MAX_OUTPUT_TOKENS`, `FALLBACK_BETA` defined in Task 5 and referenced in Task 7 and Task 8; `FINISHED_CONTENT` (lib, Task 1), `FINISH_TURN_CONTENT` (prompt, Task 4); `ProductContext`, `ProductContextLoader`, `githubRawSource`, `trimHistory`, `diskApiMapPath` (Task 3) used in Tasks 4, 5, 7; `InterviewEffort` (Task 2) used in Task 5; `SendTurnVariables.finish` (Task 10) used in Task 11; `advanceTurn(content, { skip, finish })` (Task 11) used by the MSW handler in the same task.
