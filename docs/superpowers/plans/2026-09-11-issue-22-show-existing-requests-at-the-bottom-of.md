# Requests so far on the Request page (#22) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `GET /api/v1/feature-requests` lists the harness repo's feature requests with a derived stage and readiness, and the Request page shows them in a "Requests so far" section that refreshes after filing.

**Architecture:** The API's existing feature-request slice grows one read path: the GitHub port gains `list`, the service derives stage and readiness from labels and orders open-then-closed newest-first, the router exposes `GET /`, and the schema registers the summary in the OpenAPI registry. The web pulls the new contract, adds a `useFeatureRequests` query that the submit mutation invalidates, and a `RequestsSoFar` component rendered under every mode of the Request page.

**Tech Stack:** Express 5, zod + OpenAPI registry, Octokit, Vitest + supertest (API); React 19, TanStack Query, shadcn `Badge`/`Button`/`Separator`, MSW, Vitest + Testing Library (web). Node 24 via `nvm use`.

**Spec:** `docs/superpowers/specs/2026-09-11-issue-22-show-existing-requests-at-the-bottom-of.md`

## Global Constraints

- Branch `feat/22-show-existing-requests-at-the-bottom-of` in `backend/` and `frontend/` (already checked out, linked to the issue). API first; the web pulls the contract from `../backend/openapi.json`.
- Order: open group then closed group, newest `createdAt` first inside each; at most 50 per group (`per_page: 50`, `sort: created`, `direction: desc`, two GitHub calls, no cache).
- Stage order: `shipped`, `staging`, `implementing`, `triaged`; else `closed` (closed issue) or `new` (open issue). Readiness `c*2 + (6-x) + (6-r)` from `clarity:c`, `complexity:x`, `risk:r`; `null` when any is missing or outside 1..5.
- GitHub failure → `UPSTREAM_ERROR` (502); log status and message only, never the raw body.
- Copy, exact: heading "Requests so far"; status "Loading requests"; empty "No requests yet. Yours can be the first."; link name "Open #<n> on GitHub"; divider "Closed".
- Every commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Every npm command runs inside the repo after `nvm use`. Docs gate: `BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci`, last line `docs-check: OK`; never `npm run docs:check`.
- Follow `backend/.claude/skills/add-api-endpoint/SKILL.md` for Task 1 and `frontend/.claude/skills/add-frontend-feature/SKILL.md` for Task 2 (docs before the green run, `npm run product-map`, screenshots for a visible change).

---

### Task 1: `GET /feature-requests` on the API

**Files:**
- Modify: `backend/src/services/feature-requests.ts` (port `list`, `GitHubIssueListItem`, `stageOf`, `readinessOf`, `FeatureRequestSummary`, service `list()`)
- Modify: `backend/src/schemas/feature-requests.ts` (`FeatureRequestSummary` schema, `registerPath` for `get /feature-requests`)
- Modify: `backend/src/routes/feature-requests.ts` (`router.get("/")`)
- Modify: `backend/tests/api/feature-requests.test.ts` (fakes gain `list`; four tests)
- Modify: `backend/README.md` (routes table), `backend/CHANGELOG.md` (`[Unreleased]` → `### Added`)
- Regenerate: `backend/openapi.json`, `backend/docs/API.md` (`npm run openapi`), `backend/docs/product-map.md` (`npm run product-map`)

**Interfaces:**
- Produces: `GET /api/v1/feature-requests` → `{ data: FeatureRequestSummary[] }`, `FeatureRequestSummary = { number, title, state, stage, readiness, labels, url, createdAt, closedAt }`; port method `GitHubIssues.list(params)`.

- [ ] **Step 1: Write the failing tests**

In `backend/tests/api/feature-requests.test.ts`, extend the fakes (TypeScript requires `list` once the port has it) and add a fixture helper and a `describe`:

```ts
import type { GitHubIssueListItem, GitHubIssues } from "../../src/services/feature-requests.js";

function fixture(over: Partial<GitHubIssueListItem> & { number: number }): GitHubIssueListItem {
  return {
    title: `Issue ${over.number}`,
    state: "open",
    html_url: `https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/${over.number}`,
    created_at: "2026-09-01T00:00:00Z",
    closed_at: null,
    labels: ["feature-request"],
    ...over,
  };
}

class FakeIssues implements GitHubIssues {
  calls: Parameters<GitHubIssues["create"]>[0][] = [];
  listCalls: Parameters<GitHubIssues["list"]>[0][] = [];
  open: GitHubIssueListItem[] = [];
  closed: GitHubIssueListItem[] = [];
  fail = false;
  async create(params: Parameters<GitHubIssues["create"]>[0]) { /* unchanged */ }
  async list(params: Parameters<GitHubIssues["list"]>[0]) {
    this.listCalls.push(params);
    if (this.fail) throw new Error("GitHub is down");
    return params.state === "open" ? this.open : this.closed;
  }
}

class LeakyIssues implements GitHubIssues {
  private boom(): never {
    throw Object.assign(new Error("Validation Failed"), {
      status: 422,
      response: { data: { message: "secret-marker" } },
    });
  }
  async create(): ReturnType<GitHubIssues["create"]> { this.boom(); }
  async list(): ReturnType<GitHubIssues["list"]> { this.boom(); }
}

describe("GET /feature-requests", () => {
  it("requires a session", async () => {
    expect((await request(configured.server).get(URL)).status).toBe(401);
  });

  it("lists requests open first then closed, newest first, with the summary fields", async () => {
    const user = await registerUser(configured.server);
    issues.listCalls = [];
    issues.open = [
      fixture({ number: 5, created_at: "2026-09-09T13:09:53Z",
        labels: ["feature-request", "clarity:5", "complexity:3", "risk:3", "triaged"] }),
      fixture({ number: 22, created_at: "2026-09-11T08:28:47Z", labels: ["feature-request", "implementing"] }),
    ];
    issues.closed = [
      fixture({ number: 19, state: "closed", created_at: "2026-09-10T15:12:50Z",
        closed_at: "2026-09-11T07:24:21Z", labels: ["feature-request", "shipped"] }),
    ];
    const res = await request(configured.server).get(URL).set(auth(user.token));
    expect(res.status).toBe(200);
    expect(res.body.data.map((i: { number: number }) => i.number)).toEqual([22, 5, 19]);
    expect(res.body.data[1]).toEqual({
      number: 5, title: "Issue 5", state: "open", stage: "triaged", readiness: 16,
      labels: ["feature-request", "clarity:5", "complexity:3", "risk:3", "triaged"],
      url: "https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/5",
      createdAt: "2026-09-09T13:09:53Z", closedAt: null,
    });
    expect(res.body.data[0].readiness).toBeNull();
    expect(issues.listCalls.map((c) => [c.state, c.per_page, c.sort, c.direction, c.labels])).toEqual([
      ["open", 50, "created", "desc", "feature-request"],
      ["closed", 50, "created", "desc", "feature-request"],
    ]);
  });

  it("derives the stage from labels in priority order", async () => {
    const user = await registerUser(configured.server);
    issues.open = [
      fixture({ number: 1, labels: ["feature-request", "staging", "shipped"] }),
      fixture({ number: 2, labels: ["feature-request", "implementing", "staging"] }),
      fixture({ number: 3, labels: ["feature-request", "triaged", "implementing"] }),
      fixture({ number: 4, labels: ["feature-request", "triaged"] }),
      fixture({ number: 5, labels: ["feature-request"] }),
    ];
    issues.closed = [fixture({ number: 6, state: "closed", labels: ["feature-request"] })];
    const res = await request(configured.server).get(URL).set(auth(user.token));
    const stages = Object.fromEntries(res.body.data.map((i: { number: number; stage: string }) => [i.number, i.stage]));
    expect(stages).toEqual({ 1: "shipped", 2: "staging", 3: "implementing", 4: "triaged", 5: "new", 6: "closed" });
  });

  it("answers 502 UPSTREAM_ERROR when GitHub fails to list", async () => {
    const user = await registerUser(leaky.server);
    const res = await request(leaky.server).get(URL).set(auth(user.token));
    expect(res.status).toBe(502);
    expect(res.body.error.code).toBe("UPSTREAM_ERROR");
    expect(leakyLog.text).not.toContain("secret-marker");
  });
});
```

- [ ] **Step 2: Run them and watch them fail for the right reason**

Run: `npx vitest run tests/api/feature-requests.test.ts`
Expected: the file fails to compile until `GitHubIssueListItem` and `list` exist on the port; after Step 3's port change alone, the four new tests fail with 404 `NOT_FOUND` (route missing) and the existing POST tests still pass.

- [ ] **Step 3: The port, the derivations and the service method**

In `backend/src/services/feature-requests.ts`:

```ts
export interface GitHubIssueListItem {
  number: number;
  title: string;
  state: "open" | "closed";
  html_url: string;
  created_at: string;
  closed_at: string | null;
  labels: string[];
}

export interface GitHubIssues {
  create(params: { owner: string; repo: string; title: string; body: string; labels: string[] }): Promise<{ number: number; html_url: string }>;
  list(params: {
    owner: string; repo: string; labels: string; state: "open" | "closed";
    per_page: number; sort: "created"; direction: "desc";
  }): Promise<GitHubIssueListItem[]>;
}

// in createOctokitIssues:
    async list(params) {
      const { data } = await octokit.rest.issues.listForRepo(params);
      // The issues API returns pull requests too; they carry `pull_request`.
      return data
        .filter((issue) => !issue.pull_request)
        .map((issue) => ({
          number: issue.number,
          title: issue.title,
          state: issue.state === "closed" ? "closed" : "open",
          html_url: issue.html_url,
          created_at: issue.created_at,
          closed_at: issue.closed_at ?? null,
          labels: issue.labels
            .map((label) => (typeof label === "string" ? label : (label.name ?? "")))
            .filter((name) => name.length > 0),
        }));
    },

export type FeatureRequestStage = "new" | "triaged" | "implementing" | "staging" | "shipped" | "closed";

export interface FeatureRequestSummary {
  number: number; title: string; state: "open" | "closed"; stage: FeatureRequestStage;
  readiness: number | null; labels: string[]; url: string; createdAt: string; closedAt: string | null;
}

const STAGE_LABELS = ["shipped", "staging", "implementing", "triaged"] as const;

/** First lifecycle label in priority order; `closed` or `new` when none is present. */
export function stageOf(labels: string[], state: "open" | "closed"): FeatureRequestStage {
  for (const stage of STAGE_LABELS) if (labels.includes(stage)) return stage;
  return state === "closed" ? "closed" : "new";
}

/** The rubric formula over the triage labels; null unless all three scores are present and 1..5. */
export function readinessOf(labels: string[]): number | null {
  const score = (name: string): number | null => {
    const label = labels.find((l) => l.startsWith(`${name}:`));
    const n = label ? Number(label.slice(name.length + 1)) : NaN;
    return Number.isInteger(n) && n >= 1 && n <= 5 ? n : null;
  };
  const c = score("clarity"); const x = score("complexity"); const r = score("risk");
  return c === null || x === null || r === null ? null : c * 2 + (6 - x) + (6 - r);
}

function summarize(issue: GitHubIssueListItem): FeatureRequestSummary {
  return {
    number: issue.number, title: issue.title, state: issue.state,
    stage: stageOf(issue.labels, issue.state), readiness: readinessOf(issue.labels),
    labels: issue.labels, url: issue.html_url, createdAt: issue.created_at, closedAt: issue.closed_at,
  };
}

const newestFirst = (a: GitHubIssueListItem, b: GitHubIssueListItem): number =>
  b.created_at.localeCompare(a.created_at);
```

Extend `FeatureRequestsService` with `list(): Promise<FeatureRequestSummary[]>` and implement it in `createFeatureRequestsService`, reusing the existing logging discipline (extract the catch block into `function githubFailure(err, what)` used by both `createIssue` and the new call):

```ts
    async list() {
      const fetchState = async (state: "open" | "closed") => {
        try {
          return await deps.issues.list({ owner, repo, labels: FEATURE_REQUEST_LABEL, state, per_page: 50, sort: "created", direction: "desc" });
        } catch (err) {
          throw githubFailure(err, "github issue listing failed", "Could not list the GitHub issues");
        }
      };
      const [open, closed] = await Promise.all([fetchState("open"), fetchState("closed")]);
      return [...open.sort(newestFirst), ...closed.sort(newestFirst)].map(summarize);
    },
```

- [ ] **Step 4: Schema and route**

`backend/src/schemas/feature-requests.ts`:

```ts
export const FeatureRequestSummary = z
  .object({
    number: z.number().int(),
    title: z.string(),
    state: z.enum(["open", "closed"]),
    stage: z.enum(["new", "triaged", "implementing", "staging", "shipped", "closed"]),
    readiness: z.number().int().nullable(),
    labels: z.array(z.string()),
    url: z.url(),
    createdAt: z.string(),
    closedAt: z.string().nullable(),
  })
  .openapi("FeatureRequestSummary");

registry.registerPath({
  method: "get",
  path: `/feature-requests`,
  tags: ["feature-requests"],
  summary: "List the feature requests filed to GitHub",
  description:
    "Mounted only when GITHUB_TOKEN and GITHUB_REPO are configured. Issues labelled `feature-request`, open first then closed, newest first within each group, at most 50 per group. `stage` is the first lifecycle label in the order shipped, staging, implementing, triaged, else `closed` or `new`; `readiness` is the rubric score from the clarity, complexity and risk labels, null when any is missing.",
  security: bearerAuth,
  responses: {
    200: jsonResponse("Feature requests", envelope(z.array(FeatureRequestSummary))),
    ...errorResponses("UNAUTHORIZED", "UPSTREAM_ERROR"),
  },
});
```

`backend/src/routes/feature-requests.ts`, before the POST:

```ts
  router.get("/", async (_req, res) => {
    sendData(res, await service.list());
  });
```

- [ ] **Step 5: Run the tests and watch them pass**

Run: `npx vitest run tests/api/feature-requests.test.ts`
Expected: all tests in the file pass, the four new ones included.

- [ ] **Step 6: Docs before the green run**

`npm run openapi` (regenerates `openapi.json` and `docs/API.md`). `backend/README.md` routes table, after the `POST /feature-requests` row:

```markdown
| `GET /feature-requests`                             | bearer | The requests filed so far, open first then closed, with stage and readiness |
```

`backend/CHANGELOG.md`, under `## [Unreleased]`, `### Added`:

```markdown
- `GET /feature-requests`: the requests filed to GitHub, open first then closed and newest first within each group (at most 50 per group), each with a `stage` derived from the lifecycle labels (shipped, staging, implementing, triaged, else closed or new) and a `readiness` computed from the triage labels. The GitHub port gains `list`; a GitHub failure is `UPSTREAM_ERROR` as for filing. (#22)
```

Then `npm run product-map`.

- [ ] **Step 7: Green run, commit, gate**

```bash
npm test && npm run typecheck && npm run lint
git add -A && git commit -m "feat: list the feature requests filed to GitHub (#22)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected: all green; last line `docs-check: OK`.

---

### Task 2: "Requests so far" on the Request page

**Files:**
- Regenerate: `frontend/src/api/openapi.json`, `frontend/src/api/types.ts` (`npm run api:pull -- --local ../backend/openapi.json`)
- Modify: `frontend/src/api/models.ts` (alias), `frontend/src/features/feature-request/hooks.ts` (`featureRequestsKey`, `useFeatureRequests`, invalidation in `useSubmitFeatureRequest`), `frontend/src/features/feature-request/RequestFeaturePage.tsx` (section under every mode), `frontend/tests/msw/handlers.ts` (default list handler and `featureRequestSummary` factory)
- Create: `frontend/src/features/feature-request/components/RequestsSoFar.tsx`, `frontend/src/features/feature-request/components/RequestsSoFar.test.tsx`, `frontend/docs/adr/0008-feature-request-list-contract-pull.md`, `frontend/scripts/screenshots/request-feature.mjs`, `frontend/docs/screenshots/request-feature-{light,dark}.png`
- Modify: `frontend/src/features/feature-request/RequestFeaturePage.test.tsx` (refresh test), `frontend/README.md` (feature list), `frontend/CHANGELOG.md`, `frontend/docs/product-map.md`

**Interfaces:**
- Consumes: `GET /feature-requests` from Task 1 through the pulled contract; `FeatureRequestSummary = JsonBody<paths["/feature-requests"]["get"]["responses"][200]>["data"][number]`.

- [ ] **Step 1: Pull the contract and write the ADR**

```bash
npm run api:pull -- --local ../backend/openapi.json && npm run api:types
```

`src/api/models.ts`: `export type FeatureRequestSummary = JsonBody<paths["/feature-requests"]["get"]["responses"][200]>["data"][number];`

ADR `docs/adr/0008-feature-request-list-contract-pull.md`, following `frontend/.claude/skills/write-adr/SKILL.md`: context (the Request page needs the list; the browser must not hold a GitHub token), decision (pull the contract that adds `GET /feature-requests`, read it through the typed client, derive nothing about stages in the web), consequences (one more query key, the submit mutation invalidates it).

- [ ] **Step 2: MSW default handler and factory**

`tests/msw/handlers.ts`, in `featureRequestHandlers`:

```ts
export function featureRequestSummary(over: Partial<FeatureRequestSummary> & { number: number }): FeatureRequestSummary {
  return {
    title: `Request ${over.number}`, state: "open", stage: "triaged", readiness: 16,
    labels: ["feature-request", "clarity:5", "complexity:3", "risk:3", "triaged"],
    url: `https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/${over.number}`,
    createdAt: "2026-09-09T13:09:53Z", closedAt: null, ...over,
  };
}
export let featureRequestList: FeatureRequestSummary[] = [];
export function setFeatureRequestList(items: FeatureRequestSummary[]) { featureRequestList = items; }
// handler:
  http.get(`${API}/feature-requests`, () => ok(featureRequestList)),
```

Reset `featureRequestList` to `[]` in `tests/setup.ts`'s `afterEach` alongside the db reset.

- [ ] **Step 3: Write the failing component tests**

`src/features/feature-request/components/RequestsSoFar.test.tsx`:

```tsx
import { screen, within } from "@testing-library/react";
import { http } from "msw";
import { describe, expect, it } from "vitest";
import { API, err, featureRequestSummary, setFeatureRequestList } from "../../../../tests/msw/handlers";
import { renderApp } from "../../../../tests/render";
import { server } from "../../../../tests/msw/server";

const ROUTE = "/request-feature?mode=form";

describe("Requests so far", () => {
  it("shows requests open first with stage chips, readiness and GitHub links", async () => {
    setFeatureRequestList([
      featureRequestSummary({ number: 22, title: "Show existing requests", stage: "implementing", readiness: null, labels: ["feature-request", "implementing"] }),
      featureRequestSummary({ number: 5, title: "Regenerate suggestions with a hint" }),
      featureRequestSummary({ number: 19, title: "Change app accent color", state: "closed", stage: "shipped", readiness: 17,
        labels: ["feature-request", "clarity:4", "complexity:2", "risk:1", "shipped"], closedAt: "2026-09-11T07:24:21Z" }),
    ]);
    renderApp({ route: ROUTE });
    const section = await screen.findByRole("region", { name: "Requests so far" });
    const rows = within(section).getAllByRole("listitem");
    expect(rows.map((r) => r.textContent)).toEqual([
      expect.stringContaining("#22"), expect.stringContaining("#5"), expect.stringContaining("#19"),
    ]);
    expect(within(rows[0]).getByText("Implementing")).toBeInTheDocument();
    expect(within(rows[1]).getByText("Readiness 16")).toBeInTheDocument();
    expect(within(rows[1]).getByText("clarity 5")).toBeInTheDocument();
    expect(within(rows[2]).getByText("Shipped")).toBeInTheDocument();
    expect(within(section).getByText("Closed")).toBeInTheDocument();
    const link = within(rows[0]).getByRole("link", { name: "Open #22 on GitHub" });
    expect(link).toHaveAttribute("href", "https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/22");
    expect(link).toHaveAttribute("target", "_blank");
    expect(link).toHaveAttribute("rel", "noreferrer");
  });

  it("shows the loading, empty and error states without breaking the page", async () => {
    renderApp({ route: ROUTE });
    expect(await screen.findByRole("status", { name: "" })).toHaveTextContent("Loading requests");
    expect(await screen.findByText("No requests yet. Yours can be the first.")).toBeInTheDocument();

    server.use(http.get(`${API}/feature-requests`, () => err("UPSTREAM_ERROR", "Could not list the GitHub issues")));
    renderApp({ route: ROUTE });
    expect(await screen.findByRole("alert")).toHaveTextContent("Could not list the GitHub issues");
    expect(screen.getByRole("heading", { name: "Request a feature" })).toBeInTheDocument();
  });
});
```

`RequestFeaturePage.test.tsx`, one more test next to the existing filing test:

```tsx
  it("refreshes the requests list after filing", async () => {
    let calls = 0;
    server.use(http.get(`${API}/feature-requests`, () => {
      calls += 1;
      return ok(calls === 1 ? [] : [featureRequestSummary({ number: 43, title: "Bulk accept", stage: "new", readiness: null, labels: ["feature-request"] })]);
    }));
    renderApp({ route: "/request-feature?mode=form" });
    expect(await screen.findByText("No requests yet. Yours can be the first.")).toBeInTheDocument();
    // fill and submit the form exactly as the existing "files a request" test does
    ...
    expect(await screen.findByRole("heading", { name: /Request #\d+ filed/ })).toBeInTheDocument();
    expect(await screen.findByText("#43")).toBeInTheDocument();
  });
```

- [ ] **Step 4: Run them and watch them fail**

Run: `npx vitest run src/features/feature-request`
Expected: the three new tests fail (no region "Requests so far"; `featureRequestSummary` exists but the page renders nothing new); existing tests pass.

- [ ] **Step 5: Hook, component, page**

`hooks.ts`:

```ts
export const featureRequestsKey = ["feature-request", "list"] as const;

/** GET /feature-requests: the requests filed so far, open first then closed. */
export function useFeatureRequests() {
  return useQuery({
    queryKey: featureRequestsKey,
    queryFn: async (): Promise<FeatureRequestSummary[]> =>
      unwrap(await client.GET("/feature-requests")).data,
    staleTime: 10_000,
  });
}
```

In `useSubmitFeatureRequest`'s `onSuccess`, add `void queryClient.invalidateQueries({ queryKey: featureRequestsKey });` (keep whatever it does today).

`components/RequestsSoFar.tsx`:

```tsx
import { ExternalLink } from "lucide-react";
import type { FeatureRequestSummary } from "@/api/models";
import { toApiError } from "@/api/errors";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { useFeatureRequests } from "../hooks";

const STAGE: Record<FeatureRequestSummary["stage"], { label: string; variant: "default" | "secondary" | "outline" | "ghost" }> = {
  shipped: { label: "Shipped", variant: "default" },
  staging: { label: "Staging", variant: "secondary" },
  implementing: { label: "Implementing", variant: "outline" },
  triaged: { label: "Triaged", variant: "ghost" },
  new: { label: "New", variant: "ghost" },
  closed: { label: "Closed", variant: "ghost" },
};

const SCORE_LABELS = ["clarity", "complexity", "risk"] as const;

function Row({ item }: { item: FeatureRequestSummary }) {
  const stage = STAGE[item.stage];
  const scores = SCORE_LABELS.flatMap((name) => {
    const label = item.labels.find((l) => l.startsWith(`${name}:`));
    return label ? [`${name} ${label.slice(name.length + 1)}`] : [];
  });
  return (
    <li className="flex min-h-11 flex-wrap items-center gap-x-3 gap-y-1 text-base">
      <span className="text-muted-foreground">#{item.number}</span>
      <span className="font-medium">{item.title}</span>
      <Badge variant={stage.variant}>{stage.label}</Badge>
      {item.readiness !== null && <span className="text-muted-foreground">Readiness {item.readiness}</span>}
      {scores.map((s) => <Badge key={s} variant="ghost" className="text-muted-foreground">{s}</Badge>)}
      <Button asChild variant="link" className="ml-auto h-auto min-h-11">
        <a href={item.url} target="_blank" rel="noreferrer" aria-label={`Open #${item.number} on GitHub`}>
          GitHub <ExternalLink aria-hidden="true" />
        </a>
      </Button>
    </li>
  );
}

/** Every feature request filed so far, open first then closed (issue #22). */
export function RequestsSoFar() {
  const requests = useFeatureRequests();
  const open = requests.data?.filter((r) => r.state === "open") ?? [];
  const closed = requests.data?.filter((r) => r.state === "closed") ?? [];
  return (
    <section aria-labelledby="requests-so-far" className="space-y-4">
      <Separator />
      <h2 id="requests-so-far">Requests so far</h2>
      {requests.isPending ? (
        <p role="status" className="text-muted-foreground">Loading requests</p>
      ) : requests.isError ? (
        <div role="alert" className="text-destructive">{toApiError(requests.error).message}</div>
      ) : requests.data.length === 0 ? (
        <p className="text-muted-foreground">No requests yet. Yours can be the first.</p>
      ) : (
        <ul className="divide-y">
          {open.map((item) => <Row key={item.number} item={item} />)}
          {open.length > 0 && closed.length > 0 && (
            <li className="py-2 text-sm text-muted-foreground uppercase tracking-wide" aria-hidden="true">Closed</li>
          )}
          {closed.map((item) => <Row key={item.number} item={item} />)}
        </ul>
      )}
    </section>
  );
}
```

(If `Separator` or a `ghost` Badge variant is missing, check `src/components/ui/`: `separator.tsx` exists; `badge.tsx` has `ghost`.) The "Closed" divider `li` must not count as a row in the test: give it `role="presentation"` instead of `aria-hidden` if `getAllByRole("listitem")` picks it up.

`RequestFeaturePage.tsx`: rename the current component body to `function RequestFeatureBody()` (everything from the `available` checks to the final form return, unchanged) and make the page:

```tsx
export function RequestFeaturePage() {
  const { available } = useFeatureRequestAvailable();
  return (
    <div className="space-y-10">
      <RequestFeatureBody />
      {available === true && <RequestsSoFar />}
    </div>
  );
}
```

(`RequestFeatureBody` keeps its own `useFeatureRequestAvailable()` call; the health query is shared and cached.)

- [ ] **Step 6: Run the tests and watch them pass**

Run: `npx vitest run src/features/feature-request`
Expected: all pass.

- [ ] **Step 7: Docs before the green run**

`README.md` Features list, after the "Request a feature, refined" bullet:

```markdown
- Requests so far: the Request page lists every request filed to GitHub, open first then closed, with its stage (New, Triaged, Implementing, Staging, Shipped), its readiness and score labels, and a link to the issue; filing one adds it to the top
```

`CHANGELOG.md` `[Unreleased]` → `### Added`:

```markdown
- "Requests so far" at the bottom of the Request page: every feature request filed to GitHub through `GET /feature-requests`, open first then closed and newest first, each with a stage chip derived from the lifecycle labels, the readiness score and score labels from triage, and an "Open #n on GitHub" link; filing a request refreshes the list. Contract pulled for the new route (ADR 0008). (#22)
```

Then `npm run product-map`.

- [ ] **Step 8: Green run, commit, gate**

```bash
npm test && npm run typecheck && npm run lint
git add -A && git commit -m "feat: requests so far on the Request page (#22)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci
```

Expected: green; `docs-check: OK`.

- [ ] **Step 9: Screenshots**

Scenario `scripts/screenshots/request-feature.mjs`:

```js
// The Request page in form mode with the "Requests so far" list under it.
export const route = "/request-feature?mode=form";
export async function ready(page) {
  await page.getByRole("heading", { name: "Request a feature", level: 1 }).waitFor({ timeout: 15_000 });
  await page.getByRole("heading", { name: "Requests so far", level: 2 }).waitFor({ timeout: 15_000 });
  await page.getByRole("listitem").first().waitFor({ timeout: 20_000 });
}
```

Local stack: Postgres and Redis are running; start the API with the feature on, reading the real harness repo through your own GitHub CLI token (read access is enough for listing):

```bash
cd backend && nvm use && GITHUB_TOKEN=$(gh auth token) GITHUB_REPO=kpnemo/kaizen-tasks-assembly-line npm run dev   # background
cd frontend && nvm use && VITE_PROXY_TARGET=http://localhost:3000 npm run dev                                   # background
node scripts/screenshot.mjs request-feature
```

Open both PNGs with the Read tool, compare with the spec's Looks, commit `docs: screenshots of the requests list (#22)`, note the SHA for the PR body, stop the dev servers.

---

After Task 2: push both branches, open the API PR then the web PR (`Part of kpnemo/kaizen-tasks-assembly-line#22`, the criteria checklist, failing and passing output, commit-pinned screenshot URLs), then the docs PR in the harness repo with the briefing, spec and plan; comment each on the issue. That is `/implement-issue` Step 8, not a plan task.

## Self-review

- Spec coverage: criteria 1 to 3 → Task 1 steps 1 to 5; criteria 4 to 6 → Task 2 steps 3 to 5; criterion 7 → Task 1 step 6, Task 2 steps 1, 7, 8; Looks → Task 2 steps 5 and 9.
- Placeholders: the refresh test's form-filling lines are marked to be copied from the existing filing test in the same file; nothing else is elided.
- Consistency: `featureRequestsKey`, `useFeatureRequests`, `featureRequestSummary`, `setFeatureRequestList`, `FeatureRequestSummary`, `stageOf`, `readinessOf` are named the same everywhere above.
