# Kaizen Tasks Assembly Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the cross-repo harness and facilitator kit in `kpnemo/kaizen-tasks-assembly-line` (folder `webapp/`): workspace files, the readiness rubric, the issue form and labels, the four seeded requests, the smoke package, the root hooks, the three Claude Code skills, the branch-protection and CI files, the Railway setup procedure, and the runbook.

**Architecture:** One repository that owns no application code. It holds the two app repos as git-ignored nested checkouts (`backend/`, `frontend/`), so one Claude Code session at the root can work across both by reading the nested repos' skills as files. A root Stop hook delegates docs-check to each nested repo with changes, because nested hooks do not fire in a root session. Everything that writes to GitHub is idempotent (labels replaced, comments edited in place, board rewritten) and nothing here ever merges a pull request.

**Tech Stack:** Bash scripts (macOS bash 3.2 compatible), GitHub CLI `gh` 2.100, GitHub issue forms, Claude Code skills and hooks (`.claude/settings.json`), Playwright 1.63 with Chromium on Node 24, TypeScript 5.9, ESLint 10 flat config, Prettier 3.9, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-kaizen-tasks-assembly-line-design.md`. Master plan with cross-lane interfaces: `docs/superpowers/plans/2026-09-08-master-plan.md`. Upstream: `docs/PRD.md` sections 8, 11, 7, 13; API spec `backend/docs/superpowers/specs/2026-09-08-kaizen-tasks-api-design.md` sections 4.4 and 8; web spec `frontend/docs/superpowers/specs/2026-09-08-kaizen-tasks-web-design.md` sections 2.3, 2.4, 7, 8.

## Global Constraints

Every lane plan inherits these. They are copied from the specs and from Mike's standing rules.

- Node 24 LTS everywhere, pinned by `.nvmrc` containing `24`; `engines.node` is `>=24 <25`. Run `nvm use` before any npm command.
- Branching: work on `develop`. Feature branches come off `develop` and merge by pull request. `main` receives only `develop` by pull request after staging verification. Nothing is ever pushed to `main` directly. `develop` is the default branch on GitHub.
- Secrets never enter a repository. `ANTHROPIC_API_KEY`, `JWT_SECRET`, `ADMIN_TOKEN`, `SEED_DEMO_PASSWORD`, and any GitHub token live only in Railway variables and in git-ignored local `.env` files. Mike pastes them.
- Railway: only the new project `kaizen-tasks`. Never link to, modify, or redeploy any other project in the account. Railway operations follow the official `use-railway` skill.
- GitHub: repos `kpnemo/kaizen-tasks-api`, `kpnemo/kaizen-tasks-web`, `kpnemo/kaizen-tasks-assembly-line`, `kpnemo/kaizen-tasks-product-skills`, all public.
- TypeScript strict in every repo. ESM. Prettier formatting. ESLint flat config.
- Test first: every task shows a failing test before implementation. Tests that hit external services are opt-in and excluded from CI.
- Docs are part of every change: `CHANGELOG.md` `[Unreleased]` bullet, regenerated OpenAPI or types where applicable, ADR when an architectural file changes. The docs-check script enforces it locally and in CI.
- Migrations are additive only (ADR 0004 in the API repo).
- The API service pins `PORT=3000`; the web service proxies `/api/*` to `http://api.railway.internal:3000`.
- The workshop root folder is not a repository. `webapp/` is `kaizen-tasks-assembly-line`; `webapp/backend/` and `webapp/frontend/` are nested, git-ignored repositories; `product-skills/` is at the root.

Lane-specific constraints, from the assembly-line spec:

- This repository never merges pull requests and never pushes to `develop` or `main` of any repo directly. Its skills open pull requests and stop.
- All shell scripts run on macOS `/bin/bash` 3.2 (no associative arrays, no `mapfile`, no `${var,,}`) and on GitHub `ubuntu-latest`.
- Every script has a `--dry-run` mode or accepts a fixture root, so it can be tested before the GitHub repos and Railway project exist.
- Labels, the rubric `version:` line, the smoke env names (`SMOKE_BASE_URL`, `SMOKE_AI_TIMEOUT_MS`, `SMOKE_FAST`), and the `smoke/` path are cross-lane interfaces (master plan section 4). Do not rename them.

---

## Working directory and conventions used by every task

- All paths below are relative to `/Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp` unless absolute. Every task starts with `cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp && git switch develop`.
- The commit trailer, used verbatim in every commit step:

```bash
TRAILER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- Shell state does not persist between tool calls. Prepend this preamble to every command block that uses `$SCRATCH` or `$TRAILER` (it is omitted from the listings for brevity):

```bash
SCRATCH=/private/tmp/claude-502/-Users-Mike-Bogdanovsky-Projects-nice-product-workshop-Sep-2026/b173ad22-2840-489c-891e-760f2df96511/scratchpad; mkdir -p "$SCRATCH"
TRAILER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
- Scripts are tested with `--dry-run` or a fixture root, never against GitHub or Railway from this lane. The real runs against GitHub happen in the CI/CD lane (`docs/superpowers/plans/2026-09-08-kaizen-tasks-cicd.md`) and at integration.
- Facts that already hold on 2026-09-08 (master plan section 2, L3-M0 status), which no task may contradict:
  - The four GitHub repos `kpnemo/kaizen-tasks-api`, `kpnemo/kaizen-tasks-web`, `kpnemo/kaizen-tasks-assembly-line`, `kpnemo/kaizen-tasks-product-skills` exist, public, with `develop` as the default branch. `backend/` and `frontend/` are already checkouts of the two app repos (HTTPS remotes) on `develop`.
  - Railway project `kaizen-tasks` (id `67adb3e0-f2af-4ad3-bbaa-32ec8a53b10e`) has `staging` and `production`, each with `Postgres`, `Redis`, `api` from `kaizen-tasks-api`, and `web` from `kaizen-tasks-web` on that environment's branch (`develop`, `main`). Wait-for-CI is on for `api` and `web` in both environments through the service config field `source.checkSuites`; healthchecks are set; `web` has `PORT=8080`; `ANTHROPIC_API_KEY` is the placeholder `REPLACE_ME_WITH_REAL_KEY` until Mike replaces it.
  - Web domains: staging `https://web-staging-52c0.up.railway.app`, production `https://web-production-7ef71.up.railway.app`. Every document written by this plan uses these values; they are facts, not placeholders.
  - Still open in L3-M0: the label set (this plan's Task 4 script, run for real by the CI/CD lane's Task 3) and the real Anthropic key.

## File structure

| Path | Responsibility | Task |
|---|---|---|
| `.gitignore`, `.nvmrc`, `package.json`, `.prettierrc.json`, `.prettierignore` | Workspace hygiene and the root tooling (prettier for the format hook, `yaml` for the issue-form check) | 1 |
| `CLAUDE.md` | Workspace map and conventions for a root Claude Code session | 1 |
| `README.md` | What the repo is, setup, the three skills, the runbook | 1 |
| `rubric/readiness.md` | The versioned readiness rubric (cross-lane interface with L5) | 2 |
| `.github/ISSUE_TEMPLATE/feature-request.yml`, `config.yml`, `scripts/check-issue-form.mjs` | Intake form, blank issues off, CI validator | 3 |
| `scripts/setup-labels.sh` | Label set and the pinned Triage board | 4 |
| `seeds/requests/*.md`, `scripts/seed-requests.sh` | Four seeded requests and the filing script | 5 |
| `scripts/setup-workspace.sh` | Clone, Node 24, Postgres and Redis, databases, `npm ci` | 6 |
| `smoke/` | Playwright smoke package (cross-lane interface with L1 and L2 promote workflows) | 7 |
| `.claude/settings.json`, `scripts/docs-check-all.sh`, `scripts/format-file.sh` | Root hooks | 8 |
| `.claude/skills/triage-requests/SKILL.md` | Triage skill | 9 |
| `.claude/skills/implement-issue/SKILL.md` | Implement skill | 10 |
| `.claude/skills/seed-requests/SKILL.md` | Seed skill | 11 |
| `scripts/protect-branches.sh` | Branch protection for both app repos | 12 |
| `.github/workflows/ci.yml` | CI for this repo | 13 |
| `docs/railway-setup.md` | Railway procedure followed by the CI/CD lane | 14 |
| `docs/runbook.md` | Facilitator runbook | 15 |
| `triage/.gitkeep` | Folder for dated triage reports | 9 |

**Milestone L4-M1** (rubric, issue form, labels script, seeds, workspace `CLAUDE.md`) is Tasks 1 to 5. It ends at the end of Task 5's commit step; at that point L5 may vendor the rubric and the CI/CD lane may run `scripts/setup-labels.sh`. **Milestone L4-M2** is Tasks 6 to 16.

---

### Task 1: Workspace files: gitignore, Node pin, root tooling, CLAUDE.md, README

**Files:**

- Modify: `.gitignore`
- Create: `.nvmrc`, `package.json`, `.prettierrc.json`, `.prettierignore`, `CLAUDE.md`, `README.md`

**Interfaces:**

- Consumes: nothing.
- Produces: root `npx prettier` (used by `scripts/format-file.sh` in Task 8), root `npm run check:issue-form` (Task 3 creates the script it runs, Task 13's CI calls it), `.nvmrc` read by `actions/setup-node` in Task 13. `CLAUDE.md` names the per-repo skill paths that Task 10's skill reads.

- [ ] **Step 1: Replace `.gitignore`**

Write `.gitignore` with exactly:

```gitignore
# nested application repos, each pushed to its own GitHub repository
/backend/
/frontend/

node_modules/
smoke/test-results/
smoke/playwright-report/

.env
.env.*
!.env.example
.DS_Store
```

- [ ] **Step 2: Pin Node and add the root tooling**

Write `.nvmrc`:

```
24
```

Write `package.json`:

```json
{
  "name": "kaizen-tasks-assembly-line",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=24 <25"
  },
  "scripts": {
    "check:issue-form": "node scripts/check-issue-form.mjs",
    "check:rubric": "grep -E '^version: [0-9]+$' rubric/readiness.md",
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  },
  "devDependencies": {
    "prettier": "3.9.6",
    "yaml": "2.9.0"
  }
}
```

Write `.prettierrc.json`:

```json
{
  "printWidth": 100,
  "proseWrap": "preserve",
  "singleQuote": false,
  "trailingComma": "all"
}
```

Write `.prettierignore`:

```
backend/
frontend/
node_modules/
smoke/node_modules/
smoke/test-results/
smoke/playwright-report/
docs/superpowers/
package-lock.json
```

- [ ] **Step 3: Install and produce the lockfile**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
source "$HOME/.nvm/nvm.sh" && nvm install 24 >/dev/null && nvm use 24
node --version
npm install
ls package-lock.json && npx prettier --version
```

Expected: `v24.x.y`, `package-lock.json` listed, `3.9.6`.

- [ ] **Step 4: Write `CLAUDE.md`**

```markdown
# kaizen-tasks-assembly-line

The workspace and cross-repo harness for the Kaizen Tasks workshop. This repository owns no application code. A Claude Code session started here can work in both app repos at once.

## Layout

| Path | What it is |
|---|---|
| `backend/` | Nested repo `kpnemo/kaizen-tasks-api`, git-ignored here. Express 5 API on port 3000, Postgres, Redis and BullMQ, Anthropic SDK breakdown agent. Owns the API contract `openapi.json`. |
| `frontend/` | Nested repo `kpnemo/kaizen-tasks-web`, git-ignored here. React 19 and Vite app on port 5173 in development, typed client generated from the API contract, Caddy proxy for `/api/*` in production. |
| `rubric/readiness.md` | The readiness rubric. Versioned by its `version:` front-matter line; the product-skills repo vendors a copy. |
| `.claude/skills/` | `triage-requests`, `implement-issue`, `seed-requests`. |
| `smoke/` | Playwright smoke package, run by both app repos' `promote` workflows against staging. |
| `seeds/requests/` | Four seeded feature requests. `triage/` holds dated triage reports. |
| `scripts/` | Workspace setup, labels, seeds, branch protection, root hooks. |
| `docs/` | PRD, runbook, Railway setup, specs and plans. |

## Run both apps locally

1. Once: `scripts/setup-workspace.sh` (clones the nested repos, selects Node 24, checks Postgres and Redis, creates `kaizen_dev` and `kaizen_test`, runs `npm ci` in both).
2. Terminal 1: `cd backend && nvm use && npm run dev` (API on http://localhost:3000).
3. Terminal 2: `cd frontend && nvm use && VITE_PROXY_TARGET=http://localhost:3000 npm run dev` (web on http://localhost:5173, proxies `/api` to the API).

## Conventions shared by both app repos

1. Envelopes: success is `{ "data", "meta" }`, error is `{ "error": { "code", "message", "details", "requestId" } }`; codes are a closed enum.
2. TDD: write the failing test first and show it failing in the transcript before the implementation.
3. Docs-check: each repo's Stop hook runs `scripts/docs-check.sh --hook`; the root Stop hook runs it in every nested repo that has changes; CI runs the same script.
4. Migrations are additive only (API ADR 0004).
5. Contract copy: the web repo commits `src/api/openapi.json` and its generated types; when the API contract changes, pull it (`scripts/pull-openapi.sh --local ../backend/openapi.json` then `npm run api:types`) before touching web code.

## Per-repo skills, read by path from a root session

- `backend/.claude/skills/add-api-endpoint/SKILL.md`
- `frontend/.claude/skills/add-frontend-feature/SKILL.md`
- `backend/.claude/skills/write-adr/SKILL.md` and `frontend/.claude/skills/write-adr/SKILL.md`
- `backend/.claude/skills/release-notes/SKILL.md` and `frontend/.claude/skills/release-notes/SKILL.md`

## Rules

- When a change touches both repos, the API changes first; the web follows after pulling the contract.
- Nothing in this repository merges pull requests. Skills open pull requests and stop. Mike merges.
- Never push to `develop` or `main` directly. Feature branches and pull requests only, in every repo.
- Secrets never enter any repository.
- Root hooks: Stop runs `scripts/docs-check-all.sh --hook`; PostToolUse on Edit or Write runs `scripts/format-file.sh`.
```

- [ ] **Step 5: Write `README.md`**

```markdown
# kaizen-tasks-assembly-line

The cross-repo harness and facilitator kit for the Kaizen Tasks workshop. It holds the workspace that contains the two application repos, the feature-request intake, the readiness rubric, the triage and implement skills, the smoke package that gates promotion in both app repos, the seeded requests, and the runbook. It owns no application code.

Related repositories: [kaizen-tasks-api](https://github.com/kpnemo/kaizen-tasks-api), [kaizen-tasks-web](https://github.com/kpnemo/kaizen-tasks-web), [kaizen-tasks-product-skills](https://github.com/kpnemo/kaizen-tasks-product-skills).

## Set up the workspace

```bash
gh repo clone kpnemo/kaizen-tasks-assembly-line webapp
cd webapp
scripts/setup-workspace.sh
```

The script clones `backend/` and `frontend/` (both git-ignored here), selects Node 24 through nvm, checks that Postgres and Redis answer, creates the `kaizen_dev` and `kaizen_test` databases, runs `npm ci` in both repos, and prints the commands to start each app. Run it again any time; every step is idempotent.

## The three skills

Open Claude Code at the workspace root (`claude` in this folder). The skills are in `.claude/skills/`.

| Skill | What it does |
|---|---|
| `/seed-requests` | Files `seeds/requests/*.md` as `feature-request` issues, skipping titles that already exist. |
| `/triage-requests` | Scores every open `feature-request` issue with `rubric/readiness.md`, writes `triage/<date>.md`, applies score labels, upserts one comment per issue, rewrites the pinned Triage board. `--score-only <n | file>` scores one request and writes nothing; `--dry-run` scores everything and writes nothing to GitHub. |
| `/implement-issue <n>` | Implements one request end to end across both repos with TDD, opens one pull request per affected repo, and stops. It never merges. |

## Other scripts

| Script | Purpose |
|---|---|
| `scripts/setup-labels.sh [--dry-run]` | Create or update the label set and the pinned Triage board issue. |
| `scripts/seed-requests.sh [--dry-run]` | Same as the seed skill, from a shell. |
| `scripts/protect-branches.sh <owner/repo> [--dry-run]` | Apply branch protection to `develop` and `main` of an app repo. |
| `scripts/docs-check-all.sh --hook` | Root Stop hook: run each nested repo's docs-check when it has changes. |
| `scripts/format-file.sh` | Root PostToolUse hook: format an edited file with the owning repo's prettier. |

## Smoke package

`smoke/` is a Playwright test that registers a user, creates a task, waits for the assistant, accepts a suggestion, and logs out. Both app repos check this repository out at `main` and run it against staging in their `promote` workflow. See `smoke/README.md`.

## Docs

- `docs/PRD.md`: the product requirements.
- `docs/runbook.md`: the facilitator runbook, minute by minute, with the failure page and rollback.
- `docs/railway-setup.md`: how the Railway project `kaizen-tasks` is set up.
- `docs/superpowers/specs/` and `docs/superpowers/plans/`: design specs and implementation plans.
```

- [ ] **Step 6: Check formatting and commit**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
npx prettier --check CLAUDE.md README.md package.json .prettierrc.json
git add .gitignore .nvmrc package.json package-lock.json .prettierrc.json .prettierignore CLAUDE.md README.md
git commit -m "chore: workspace files, Node pin, root tooling, CLAUDE.md and README" -m "$TRAILER"
```

Expected: prettier prints `All matched files use Prettier code style!`; the commit succeeds on `develop`.

---

### Task 2: The readiness rubric

**Files:**

- Create: `rubric/readiness.md`

**Interfaces:**

- Consumes: nothing.
- Produces: `rubric/readiness.md` with a front-matter `version: 1` line (L5 copies the file to the same relative path and compares the `version:` line), the fixed output shape `{ clarity, complexity, risk, archChange, readiness, reasons: { clarity, complexity, risk }, questions: [] }` used by Task 9's skill and by L5's `refine-request`.

- [ ] **Step 1: Write the failing check**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
npm run check:rubric; echo "exit=$?"
```

Expected: `grep` reports `rubric/readiness.md: No such file or directory` (npm adds its own error block after it) and `exit=2`, grep's exit code for a missing file, passed through by `npm run`.

- [ ] **Step 2: Write `rubric/readiness.md`**

```markdown
---
version: 1
owner: kpnemo/kaizen-tasks-assembly-line
---

# Readiness rubric

This document is written for a model to follow. It scores one feature request on three scales, decides whether the request implies an architecture change, computes a readiness score, and, when the request is unclear, produces two or three clarifying questions. The `triage-requests` skill in the assembly-line repository and the `refine-request` skill in the product-skills repository both follow it, so a product manager's local score and the engineering triage score agree for the same text. The `version:` line above changes whenever an anchor, the formula, or the output shape changes.

## 1. Scales

Score each scale as an integer from 1 to 5. Pick the highest anchor whose every condition is met by the text as written, not by what the reader can infer.

### Clarity

| Score | Anchor |
|---|---|
| 1 | A wish with no user and no outcome. The reader cannot say who benefits or what would be different. |
| 2 | A goal with no observable behavior. The reader knows what the requester wants to be true, but not what a user would see or do. |
| 3 | Behavior is described, but acceptance criteria are missing or untestable. A tester could not write a pass-or-fail check from the text. |
| 4 | Testable acceptance criteria and a stated scope. Every criterion can be checked by a tester with a yes or a no. |
| 5 | Everything in 4, and the request also names what is out of scope and at least one edge case. |

### Complexity

| Score | Anchor |
|---|---|
| 1 | One file in one repo. |
| 2 | One repo, a few files, no schema change. |
| 3 | Both repos, or a schema-additive change (a new column with a default, a new table, a new index). |
| 4 | A new subsystem or an external integration (a new queue, a new third-party API, a new background process, a new page that talks to a new service). |
| 5 | Restructures existing flows: changes how existing screens, endpoints, or jobs relate to each other. |

### Risk

| Score | Anchor |
|---|---|
| 1 | Cosmetic: copy, layout, color, ordering. |
| 2 | Isolated behavior: a new control or rule that cannot affect other features or stored data. |
| 3 | Touches authentication, stored data, or the AI prompt or its inputs. |
| 4 | Could lose or expose data. |
| 5 | Changes security or multi-user boundaries. |

## 2. Architecture change test

`archChange` is true when the request implies touching any of the following. Otherwise it is false.

- The database schema beyond additive columns: dropping, renaming, or retyping a column, or changing a constraint.
- Authentication or session handling.
- The queue: job shape, worker topology, retry policy.
- The agent's system prompt or the agent's output schema.
- The proxy between the web service and the API.
- The API contract in a breaking way: removing or renaming a field, changing a status code, changing an envelope.
- Multi-user data sharing of any kind.

When the request is too vague to know what would change (clarity 1 or 2), set `archChange` to false and let the clarifying questions surface it. Do not infer an architecture change from a wish.

## 3. Readiness

```
readiness = clarity * 2 + (6 - complexity) + (6 - risk)
```

Range 4 to 20. Sort descending. Every request with `archChange` true sorts after every request with `archChange` false, regardless of score. Ties break by creation date ascending, oldest first.

## 4. Procedure

1. Read the whole request: problem, proposed behavior, acceptance criteria, out of scope, and the requester's role when given.
2. Score clarity first, from the acceptance criteria alone. A well-written problem statement does not raise clarity; only checkable criteria do. Bullets that a tester can answer yes or no are criteria; adjectives ("faster", "better", "intuitive") are not.
3. Score complexity and risk by naming the files or areas that would change, using the repo layouts below. Write those names into the reasons.
4. Apply the architecture change test.
5. Compute readiness with the formula.
6. If clarity is below 3, write clarifying questions following section 5. Otherwise `questions` is an empty array.
7. Output exactly this shape. When asked for the score alone, output the JSON and nothing else.

```json
{
  "clarity": 4,
  "complexity": 2,
  "risk": 1,
  "archChange": false,
  "readiness": 17,
  "reasons": {
    "clarity": "one sentence on the acceptance criteria",
    "complexity": "one sentence naming the files or areas that change",
    "risk": "one sentence naming what the change can affect"
  },
  "questions": []
}
```

### Repo layouts used for scoring

API, `kaizen-tasks-api` (`backend/`): `src/routes/` (Express routers, one per resource), `src/schemas/` (zod request and response schemas, OpenAPI registry), `src/services/` (business rules, ownership checks), `src/repositories/` (Drizzle queries), `src/db/schema.ts` and `drizzle/` (schema and migrations), `src/agent/` (breakdown module, `prompts/breakdown.system.md`), `src/jobs/` (BullMQ queue, worker, reconciler), `src/lib/auth.ts` (JWT and refresh cookie), `openapi.json` (generated contract). Architectural files: `src/db/schema.ts`, `drizzle/**`, `src/jobs/**`, `src/lib/auth.ts`, `src/agent/prompts/**`, `.railway/**`.

Web, `kaizen-tasks-web` (`frontend/`): `src/features/<domain>/` (tasks, tags, auth, feature-request: pages, components, hooks, tests), `src/components/ui/` (shadcn primitives), `src/api/` (committed contract copy, generated types, client with auth middleware), `src/app/router.tsx` (routes), `Caddyfile` (static serving and the `/api/*` proxy). Architectural files: `src/api/**`, `Caddyfile`, `.railway/**`, `src/app/router.tsx`, `src/main.tsx`.

A change confined to one feature folder in the web is complexity 2. A change that adds an endpoint and a screen is complexity 3. A change that adds a column with a default is complexity 3. A change to the prompt file is risk 3 and, when the prompt's instructions change, `archChange` true.

## 5. Clarifying questions

Only when clarity is below 3. Write two or three questions, each answerable in one sentence, drawn from these patterns and phrased for the requester's role when given:

- Who is the user and when does this happen?
- What does the user see when it works?
- What would make you say it is done?
- What should explicitly not change?

Do not ask about implementation. Do not ask more than three questions.
```

- [ ] **Step 3: Run the check**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
npm run check:rubric; echo "exit=$?"
node -e 'const s=require("fs").readFileSync("rubric/readiness.md","utf8"); const m=s.match(/^---\n([\s\S]*?)\n---/); if(!m) process.exit(1); console.log(m[1])'
```

Expected: `version: 1` printed twice (once by grep, once from the front matter), `exit=0`.

- [ ] **Step 4: Commit**

```bash
git add rubric/readiness.md
git commit -m "feat: readiness rubric v1" -m "$TRAILER"
```

---

### Task 3: Issue form, config, and the form validator

**Files:**

- Create: `.github/ISSUE_TEMPLATE/feature-request.yml`, `.github/ISSUE_TEMPLATE/config.yml`, `scripts/check-issue-form.mjs`

**Interfaces:**

- Consumes: root `yaml` dependency from Task 1.
- Produces: the form's field labels `Problem`, `Proposed behavior`, `Acceptance criteria`, `Out of scope`, `Your role`. GitHub renders a submitted form as `### <label>` sections in the issue body; Task 5's seeds use the same headings and Task 9's skill reads the `### Acceptance criteria` section. `npm run check:issue-form` is called by Task 13's CI.

- [ ] **Step 1: Write the validator first and see it fail**

Write `scripts/check-issue-form.mjs`:

```js
#!/usr/bin/env node
// Validates .github/ISSUE_TEMPLATE/feature-request.yml: it parses as YAML, is named "Feature request",
// applies the feature-request label, and has exactly the five fields in order with the required ones required.
import { readFileSync } from "node:fs";
import { parse } from "yaml";

const path = new URL("../.github/ISSUE_TEMPLATE/feature-request.yml", import.meta.url);
let doc;
try {
  doc = parse(readFileSync(path, "utf8"));
} catch (error) {
  console.error(`feature-request.yml: FAILED to read or parse: ${error.message}`);
  process.exit(1);
}

const expectedIds = ["problem", "behavior", "acceptance", "out_of_scope", "role"];
const requiredIds = ["problem", "behavior", "acceptance"];
const fields = (doc.body ?? []).filter((block) => block.type !== "markdown");
const ids = fields.map((block) => block.id);
const problems = [];

if (doc.name !== "Feature request") {
  problems.push(`name is ${JSON.stringify(doc.name)}, expected "Feature request"`);
}
if (!Array.isArray(doc.labels) || !doc.labels.includes("feature-request")) {
  problems.push(`labels must include "feature-request", got ${JSON.stringify(doc.labels)}`);
}
if (JSON.stringify(ids) !== JSON.stringify(expectedIds)) {
  problems.push(`field ids are ${JSON.stringify(ids)}, expected ${JSON.stringify(expectedIds)}`);
}
for (const field of fields) {
  const required = Boolean(field.validations?.required);
  const shouldBeRequired = requiredIds.includes(field.id);
  if (required !== shouldBeRequired) {
    problems.push(`${field.id} required=${required}, expected ${shouldBeRequired}`);
  }
  if (!field.attributes?.label) {
    problems.push(`${field.id} has no label`);
  }
}
const roleField = fields.find((field) => field.id === "role");
if (roleField && roleField.type !== "input") {
  problems.push(`role must be an input, got ${roleField.type}`);
}
for (const field of fields.filter((f) => f.id !== "role")) {
  if (field.type !== "textarea") {
    problems.push(`${field.id} must be a textarea, got ${field.type}`);
  }
}

if (problems.length > 0) {
  console.error("feature-request.yml: FAILED");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(`feature-request.yml: OK (${ids.join(", ")})`);
```

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
npm run check:issue-form; echo "exit=$?"
```

Expected: `feature-request.yml: FAILED to read or parse: ENOENT ...` and `exit=1`.

- [ ] **Step 2: Write the form**

Write `.github/ISSUE_TEMPLATE/feature-request.yml`:

```yaml
name: Feature request
description: Ask for a change to Kaizen Tasks. Every request is scored with the readiness rubric.
labels: ["feature-request"]
body:
  - type: markdown
    attributes:
      value: |
        Write for a tester, not for a developer. Checkable acceptance criteria are what move a request up the ranking.
  - type: textarea
    id: problem
    attributes:
      label: Problem
      description: What is hard or slow today, for whom, and how do you know
      placeholder: When I ..., I have to ..., which costs ... I know because ...
    validations:
      required: true
  - type: textarea
    id: behavior
    attributes:
      label: Proposed behavior
      description: What should happen instead, as the user would see it
      placeholder: On the task detail page, a button labeled ... that ...
    validations:
      required: true
  - type: textarea
    id: acceptance
    attributes:
      label: Acceptance criteria
      description: "How we will know it is done: bullet points a tester could check"
      placeholder: |
        - Given ..., when ..., then ...
        - ...
    validations:
      required: true
  - type: textarea
    id: out_of_scope
    attributes:
      label: Out of scope
      description: What this request deliberately does not include
    validations:
      required: false
  - type: input
    id: role
    attributes:
      label: Your role
      description: Your role, so the assistant can phrase questions for you
      placeholder: Product manager, contact-center analytics
    validations:
      required: false
```

Write `.github/ISSUE_TEMPLATE/config.yml`:

```yaml
blank_issues_enabled: false
contact_links:
  - name: Feature request form
    url: https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/new?template=feature-request.yml
    about: Every request goes through the form so the triage skill can score it.
```

- [ ] **Step 3: Run the validator**

Run:

```bash
npm run check:issue-form; echo "exit=$?"
```

Expected: `feature-request.yml: OK (problem, behavior, acceptance, out_of_scope, role)` and `exit=0`.

Then prove the validator catches drift:

```bash
sed -i.bak 's/id: role/id: persona/' .github/ISSUE_TEMPLATE/feature-request.yml
npm run check:issue-form; echo "exit=$?"
mv .github/ISSUE_TEMPLATE/feature-request.yml.bak .github/ISSUE_TEMPLATE/feature-request.yml
npm run check:issue-form
```

Expected: the middle run prints `field ids are [...,"persona"], expected [...,"role"]` with `exit=1`; the last run prints `OK`.

- [ ] **Step 4: Commit**

```bash
npx prettier --write .github/ISSUE_TEMPLATE/*.yml scripts/check-issue-form.mjs
git add .github/ISSUE_TEMPLATE/feature-request.yml .github/ISSUE_TEMPLATE/config.yml scripts/check-issue-form.mjs
git commit -m "feat: feature request issue form with validator" -m "$TRAILER"
```

---

### Task 4: Labels script with the Triage board

**Files:**

- Create: `scripts/setup-labels.sh`

**Interfaces:**

- Consumes: `gh` authenticated as `kpnemo`. The repo `kpnemo/kaizen-tasks-assembly-line` exists on GitHub since 2026-09-08 (CI/CD lane Task 2, done), but this task still tests only with `--dry-run`; the real run against GitHub is the CI/CD lane's Task 3 (Labels), the one step of L3-M0 still open.
- Produces: labels `feature-request`, `clarity:1..5`, `complexity:1..5`, `risk:1..5`, `arch-change`, `triaged`, `implementing`, `shipped`, `triage-board` (master plan interface "Labels"); one pinned open issue titled `Triage board` labeled `triage-board` whose body starts with `<!-- kaizen-triage-board -->` (rewritten by Task 9's skill).

- [ ] **Step 1: Write the script**

Write `scripts/setup-labels.sh`:

```bash
#!/usr/bin/env bash
# Create or update the label set in the assembly-line repo and create the pinned "Triage board" issue if missing.
# Usage: scripts/setup-labels.sh [--dry-run]
#   REPO=<owner/name> overrides the target (default kpnemo/kaizen-tasks-assembly-line).
# Idempotent: gh label create --force updates color and description; the board is created only when no open
# issue carries the triage-board label.
set -euo pipefail

REPO="${REPO:-kpnemo/kaizen-tasks-assembly-line}"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

label() { # name color description
  run gh label create "$1" --repo "$REPO" --force --color "$2" --description "$3"
}

label feature-request 1D76DB "A request filed through the feature request form"

# One gray-to-green gradient per scale, index 1..5.
GRADIENT="BFBFBF A9CBA4 8FC48A 5FB35A 2EA043"
for scale in clarity complexity risk; do
  i=1
  for color in $GRADIENT; do
    label "$scale:$i" "$color" "Rubric $scale score $i of 5"
    i=$((i + 1))
  done
done

label arch-change B60205 "Implies an architecture change; sorts after every other request"
label triaged D4C5F9 "Scored by triage-requests"
label implementing 9B6FE0 "implement-issue has opened pull requests"
label shipped 5319E7 "Merged to main and live in production"
label triage-board FBCA04 "The pinned Triage board issue; carried by exactly one issue"

# Triage board: one open issue, pinned, body rewritten by the triage skill.
if [ "$DRY_RUN" = 1 ]; then
  echo "DRY-RUN: would create and pin the 'Triage board' issue if no open issue carries the triage-board label"
  exit 0
fi

existing="$(gh issue list --repo "$REPO" --label triage-board --state open --json number --jq '.[0].number // empty')"
if [ -n "$existing" ]; then
  echo "Triage board exists: #$existing"
  exit 0
fi

body="$(mktemp)"
cat >"$body" <<'EOF'
<!-- kaizen-triage-board -->
# Triage board

No triage run yet. The `triage-requests` skill rewrites this body with the current ranking.
EOF
url="$(gh issue create --repo "$REPO" --title "Triage board" --label triage-board --body-file "$body")"
number="${url##*/}"
gh issue pin "$number" --repo "$REPO"
rm -f "$body"
echo "Triage board created and pinned: #$number ($url)"
```

- [ ] **Step 2: Make it executable and dry-run it**

Run:

```bash
chmod +x scripts/setup-labels.sh
scripts/setup-labels.sh --dry-run | tee "$SCRATCH/labels-dry-run.txt"
grep -c '^DRY-RUN: gh label create' "$SCRATCH/labels-dry-run.txt"
grep 'clarity:5' "$SCRATCH/labels-dry-run.txt"
bash -n scripts/setup-labels.sh && echo "syntax ok"
```

Expected: 21 lines counted (1 + 15 + 5 labels); the `clarity:5` line contains `--color 2EA043`; the final line is `DRY-RUN: would create and pin the 'Triage board' issue ...`; `syntax ok`.

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-labels.sh
git commit -m "feat: labels script with Triage board creation" -m "$TRAILER"
```

---

### Task 5: The four seeds and the seed script (end of L4-M1)

**Files:**

- Create: `seeds/requests/01-mark-all-done.md`, `seeds/requests/02-smarter-ai.md`, `seeds/requests/03-share-task.md`, `seeds/requests/04-regenerate-with-hint.md`, `scripts/seed-requests.sh`

**Interfaces:**

- Consumes: the form headings from Task 3; label `feature-request` from Task 4.
- Produces: seed files with front matter `title:` and the form's five `###` sections; `scripts/seed-requests.sh [--dry-run]` whose logic Task 11's skill reuses. Expected triage outcome (Task 9 and integration): 01 first with readiness 19, 04 second with 14, 02 receives questions, 03 is `arch-change` and sorts last.

- [ ] **Step 1: Write the seeds**

`seeds/requests/01-mark-all-done.md`:

```markdown
---
title: Add a "Mark all steps done" button on the task detail
---

### Problem

When I finish a task that has five or six steps I tick each checkbox one by one. On a laptop in a meeting that is five clicks and five list re-renders for one outcome. I do this several times a day, and two colleagues in the pilot asked for the same thing.

### Proposed behavior

On the task detail page, in the bulk bar, a button labeled "Mark all steps done". Clicking it sets every accepted or user-created step to done and the progress label updates to `N/N`. Suggested and dismissed steps are left as they are. No API change is needed: the web app updates each counted step through the existing update endpoint.

### Acceptance criteria

- On a task with at least one accepted or user-created step that is not done, the task detail shows a button labeled "Mark all steps done".
- Clicking it sets the status of every accepted or user-created step to done using the existing `PATCH /api/v1/tasks/:id` endpoint (one request per step is acceptable), and the progress label reads `N/N` where N is the number of those steps.
- Steps in the suggested or dismissed state keep their state and status.
- When every counted step is already done, the button is disabled.
- The web app has component tests for the happy path (three steps become done, label reads `3/3`) and for the disabled state; `CHANGELOG.md` has an `[Unreleased]` bullet.

### Out of scope

- Undo of the bulk action.
- Marking the parent task itself as done automatically.
- A keyboard shortcut.

### Your role

Product manager, contact-center analytics
```

`seeds/requests/02-smarter-ai.md`:

```markdown
---
title: Make the AI smarter
---

### Problem

Sometimes the suggested steps are not that useful for my kind of work.

### Proposed behavior

The AI should be smarter and give steps I would actually do.

### Acceptance criteria

- The suggestions are better.

### Out of scope

_No response_

### Your role

_No response_
```

`seeds/requests/03-share-task.md`:

```markdown
---
title: Share a task with a teammate
---

### Problem

Half of my tasks are really joint tasks with one teammate. Today we each keep a copy and they drift apart within a day; last week we both did the same step. There is no way to see a task someone else owns.

### Proposed behavior

On the task detail page, a "Share" control where I type a teammate's email. When they log in, the task appears in their list with a "shared by <name>" badge. Both of us can check steps, edit titles, and accept suggestions, and both see the other's changes on the next poll.

### Acceptance criteria

- The owner can share a task with another registered user by email from the task detail page.
- The shared task appears in the other user's task list with a "shared by <display name>" badge and opens in their task detail.
- Both users can change step status, edit step titles, and accept or dismiss suggestions; a change by one is visible to the other within five seconds.
- Sharing with an unknown email shows the error "No user with that email".
- The owner can unshare; the task then disappears from the other user's list.
- Tags remain the owner's; the other user sees them but cannot edit them.

### Out of scope

- Sharing with more than one person.
- Comments or activity history.
- Notifications by email.

### Your role

Product lead, workforce management
```

`seeds/requests/04-regenerate-with-hint.md`:

```markdown
---
title: Regenerate suggestions with a hint
---

### Problem

When the assistant's first breakdown misses the point, my only option is to regenerate blind and hope. For a task like "Prepare the QBR deck" I usually know what is missing ("the deck is for finance, not engineering") and I cannot say so. I regenerate two or three times a week and it rarely gets closer.

### Proposed behavior

The Regenerate button on the task detail opens a small text field, "Anything the assistant should know?", with a Regenerate button. The hint is sent with the regenerate request and passed to the assistant as part of the task input, next to the title and description. The system prompt and the output shape do not change. The hint is not stored on the task.

### Acceptance criteria

- On the task detail, Regenerate opens an optional single-line hint field (maximum 300 characters) and a Regenerate button; submitting with an empty hint behaves exactly like today.
- `POST /api/v1/tasks/:id/breakdown` accepts an optional JSON body `{ "hint": string }`; a hint longer than 300 characters returns `VALIDATION_ERROR` with the path `body.hint`.
- The hint reaches the breakdown model as a `hint` field of the task input; the API has a test that the fake model receives it.
- The task detail shows the thinking state after submitting and the new suggestions replace the previous suggested steps; accepted steps are kept.
- The API's `openapi.json` and the web's generated types include the new body; `CHANGELOG.md` in both repos has an `[Unreleased]` bullet.

### Out of scope

- Storing hint history on the task.
- Suggesting hints automatically.
- Changing the system prompt or the number of steps.

### Your role

Product manager, agent desktop
```

- [ ] **Step 2: Write the seed script**

Write `scripts/seed-requests.sh`:

```bash
#!/usr/bin/env bash
# File seeds/requests/*.md as feature-request issues. Skips a seed whose title already exists as an open issue.
# Usage: scripts/seed-requests.sh [--dry-run]
#   REPO=<owner/name> overrides the target (default kpnemo/kaizen-tasks-assembly-line).
# Seed format: a front matter block with a `title:` line (plain or quoted; one layer of surrounding quotes is
# stripped so a YAML formatter cannot change the issue title), then the body in the issue form's section
# structure (### Problem, ### Proposed behavior, ### Acceptance criteria, ### Out of scope, ### Your role).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-kpnemo/kaizen-tasks-assembly-line}"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

# Titles of open issues, one per line. Empty when gh cannot reach the repo (dry run before the repo exists).
open_titles=""
if gh auth status >/dev/null 2>&1; then
  open_titles="$(gh issue list --repo "$REPO" --state open --limit 200 --json title --jq '.[].title' 2>/dev/null || true)"
fi

created=0
skipped=0
for seed in "$ROOT"/seeds/requests/*.md; do
  name="$(basename "$seed")"
  # Front matter is between the first line (---) and the next --- line.
  title="$(sed -n '2,/^---$/p' "$seed" | sed -n 's/^title:[[:space:]]*//p' | head -1)"
  case "$title" in
    \"*\") title="${title#\"}"; title="${title%\"}" ;;
    \'*\') title="${title#\'}"; title="${title%\'}" ;;
  esac
  if [ -z "$title" ]; then
    echo "SKIP     $name: no title: line in the front matter" >&2
    continue
  fi
  body="$(mktemp)"
  # Everything after the second --- line is the body.
  awk 'f >= 2 { print } /^---$/ { f++ }' "$seed" | sed '1{/^$/d;}' >"$body"

  if printf '%s\n' "$open_titles" | grep -Fxq -- "$title"; then
    echo "SKIP     $title (an open issue with this title exists)"
    skipped=$((skipped + 1))
    rm -f "$body"
    continue
  fi
  if [ "$DRY_RUN" = 1 ]; then
    echo "WOULD CREATE  $title  [$name, $(wc -l <"$body" | tr -d ' ') body lines]"
    rm -f "$body"
    continue
  fi
  url="$(gh issue create --repo "$REPO" --label feature-request --title "$title" --body-file "$body")"
  echo "CREATED  $title  $url"
  created=$((created + 1))
  rm -f "$body"
done

if [ "$DRY_RUN" = 0 ]; then
  echo "Done: $created created, $skipped skipped."
fi
```

- [ ] **Step 3: Dry-run and inspect the parsed pieces**

Run:

```bash
chmod +x scripts/seed-requests.sh
bash -n scripts/seed-requests.sh && echo "syntax ok"
scripts/seed-requests.sh --dry-run
sed -n '2,/^---$/p' seeds/requests/01-mark-all-done.md | sed -n 's/^title:[[:space:]]*//p'
awk 'f >= 2 { print } /^---$/ { f++ }' seeds/requests/02-smarter-ai.md | sed '1{/^$/d;}' | head -3
```

Expected: `syntax ok`; four lines in file order, each `WOULD CREATE` (or `SKIP     <title> (an open issue with this title exists)` for a seed that has already been filed, since the repo exists and `gh` is logged in), the first being `WOULD CREATE  Add a "Mark all steps done" button on the task detail  [01-mark-all-done.md, 25 body lines]` (the count may differ by one); the title line printed alone, without surrounding quotes; the body preview starts with `### Problem`.

- [ ] **Step 4: Prove the skip logic with a fake `gh`**

Run:

```bash
mkdir -p "$SCRATCH/fakebin"
cat >"$SCRATCH/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list") printf '%s\n' "Make the AI smarter" ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SCRATCH/fakebin/gh"
PATH="$SCRATCH/fakebin:$PATH" scripts/seed-requests.sh --dry-run
```

Expected: three `WOULD CREATE` lines and one `SKIP     Make the AI smarter (an open issue with this title exists)`.

- [ ] **Step 5: Commit (L4-M1 ends here)**

```bash
npx prettier --write seeds/requests/*.md
scripts/seed-requests.sh --dry-run | grep -c 'Add a "Mark all steps done" button on the task detail'
git add seeds/requests scripts/seed-requests.sh
git commit -m "feat: four seeded requests and the seed script" -m "$TRAILER"
git log --oneline -6
```

Expected: the grep prints `1` (the title survives formatting without quotes); five new commits on `develop` since the review-fixes commit. **L4-M1 is complete**: `rubric/readiness.md` with `version: 1`, the issue form, `scripts/setup-labels.sh`, four seeds, and root `CLAUDE.md` are committed on `develop`. Tell the orchestrator so L5 can vendor the rubric and the CI/CD lane can run the labels script (its Task 3; the GitHub repo already exists).

---

### Task 6: Workspace setup script

**Files:**

- Create: `scripts/setup-workspace.sh`

**Interfaces:**

- Consumes: GitHub repos `kpnemo/kaizen-tasks-api` and `kpnemo/kaizen-tasks-web` (exist since 2026-09-08, CI/CD lane Task 2). Locally both are already checked out (`backend/` and `frontend/` are git checkouts with HTTPS remotes), so the clone branch is exercised only in a fixture root in dry-run.
- Produces: `backend/` and `frontend/` checkouts, Node 24 active, databases `kaizen_dev` and `kaizen_test`, `node_modules` in both.

- [ ] **Step 1: Write the script**

Write `scripts/setup-workspace.sh`:

```bash
#!/usr/bin/env bash
# Prepare the workspace: clone the two app repos if missing, select Node 24 with nvm, check Postgres and Redis,
# create the local databases, run npm ci in both repos, print the next commands.
# Usage: scripts/setup-workspace.sh [--dry-run]
# Every step is idempotent. In --dry-run, mutations are printed and missing services are reported as WARN.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}
problem() {
  if [ "$DRY_RUN" = 1 ]; then echo "WARN  $*"; else echo "ERROR $*" >&2; exit 1; fi
}

echo "== 1. Nested repos"
for dir in backend frontend; do
  case "$dir" in
    backend) repo="kpnemo/kaizen-tasks-api" ;;
    frontend) repo="kpnemo/kaizen-tasks-web" ;;
  esac
  if [ -d "$ROOT/$dir/.git" ]; then
    echo "OK    $dir is a git checkout"
  else
    # gh honours the user's configured git protocol (HTTPS with the CLI's credential helper on this machine)
    run gh repo clone "$repo" "$ROOT/$dir"
  fi
done

echo "== 2. Node 24 through nvm"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
set +u
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
elif [ -s /opt/homebrew/opt/nvm/nvm.sh ]; then
  . /opt/homebrew/opt/nvm/nvm.sh
else
  problem "nvm not found; install it from https://github.com/nvm-sh/nvm and rerun"
fi
if command -v nvm >/dev/null 2>&1; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN: nvm install 24 && nvm use 24"
  else
    nvm install 24 >/dev/null
    nvm use 24 >/dev/null
  fi
  echo "OK    node $(node --version 2>/dev/null || echo '?')"
fi
set -u

echo "== 3. Postgres and Redis"
if pg_isready -q 2>/dev/null; then
  echo "OK    Postgres answers"
else
  problem "Postgres is not answering; run: brew services start postgresql@17"
fi
if [ "$(redis-cli ping 2>/dev/null || true)" = "PONG" ]; then
  echo "OK    Redis answers"
else
  problem "Redis is not answering; run: brew services start redis"
fi

echo "== 4. Databases"
for db in kaizen_dev kaizen_test; do
  if psql -lqt 2>/dev/null | cut -d '|' -f 1 | tr -d ' ' | grep -qx "$db"; then
    echo "OK    database $db exists"
  else
    run createdb "$db"
  fi
done

echo "== 5. Dependencies"
for dir in backend frontend; do
  if [ -f "$ROOT/$dir/package.json" ]; then
    (cd "$ROOT/$dir" && run npm ci)
  else
    echo "SKIP  $dir has no package.json yet"
  fi
done

cat <<EOF
== Next
  API:  cd backend  && nvm use && cp -n .env.example .env; npm run dev            # http://localhost:3000
  Web:  cd frontend && nvm use && VITE_PROXY_TARGET=http://localhost:3000 npm run dev   # http://localhost:5173
  Both test suites: (cd backend && npm test) && (cd frontend && npm test)
EOF
```

- [ ] **Step 2: Dry-run it**

Run:

```bash
chmod +x scripts/setup-workspace.sh
bash -n scripts/setup-workspace.sh && echo "syntax ok"
scripts/setup-workspace.sh --dry-run
```

Expected: `syntax ok`; `OK    backend is a git checkout` and `OK    frontend is a git checkout` (both exist locally); `DRY-RUN: nvm install 24 && nvm use 24`; `OK    Postgres answers`, `OK    Redis answers` (or `WARN` lines if a service is stopped); `DRY-RUN: createdb kaizen_dev` and `DRY-RUN: createdb kaizen_test` or `OK` lines if they exist; `SKIP  backend has no package.json yet` (or `DRY-RUN: npm ci` once L1-M1 has landed), the same for `frontend`; the `== Next` block. The `OK    node` line shows whatever `node` is on the PATH, since a dry run does not switch versions.

Then prove the clone branch with a fixture root:

```bash
mkdir -p "$SCRATCH/ws-empty/scripts" && cp scripts/setup-workspace.sh "$SCRATCH/ws-empty/scripts/"
"$SCRATCH/ws-empty/scripts/setup-workspace.sh" --dry-run | grep 'DRY-RUN: gh repo clone'
```

Expected: two lines, `DRY-RUN: gh repo clone kpnemo/kaizen-tasks-api .../ws-empty/backend` and the web one.

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-workspace.sh
git commit -m "feat: workspace setup script" -m "$TRAILER"
```

---

### Task 7: The smoke package

**Files:**

- Create: `smoke/package.json`, `smoke/tsconfig.json`, `smoke/eslint.config.js`, `smoke/playwright.config.ts`, `smoke/tests/smoke.spec.ts`, `smoke/README.md`

**Interfaces:**

- Consumes: a deployed or local web URL. Locally, the frontend dev server (`http://localhost:5173`) with the API running, once L1-M2 and L2-M3 exist; until then the test is verified by typecheck, lint, and a run against any URL that fails at step 1 with a trace.
- Produces: the master plan interface "Smoke package": `kaizen-tasks-assembly-line` at `main`, folder `smoke/`, `npm ci && SMOKE_BASE_URL=<url> npm test`; env `SMOKE_AI_TIMEOUT_MS` (default 90000), `SMOKE_FAST` (`1` skips the AI wait). The selector contract in `smoke/README.md` is the only assumption made about the web app's markup; the frontend lane reads it (flagged to the orchestrator as an addition to the master plan's section 4).

- [ ] **Step 1: Package, TypeScript, and ESLint files**

Write `smoke/package.json`:

```json
{
  "name": "kaizen-tasks-smoke",
  "private": true,
  "type": "module",
  "description": "Playwright smoke test for Kaizen Tasks, run against staging by the promote workflows",
  "engines": {
    "node": ">=24 <25"
  },
  "scripts": {
    "test": "playwright test",
    "test:headed": "playwright test --headed",
    "lint": "eslint . && prettier --check .",
    "typecheck": "tsc --noEmit",
    "format": "prettier --write ."
  },
  "devDependencies": {
    "@eslint/js": "10.0.1",
    "@playwright/test": "1.63.0",
    "@types/node": "24.13.3",
    "eslint": "10.10.0",
    "prettier": "3.9.6",
    "typescript": "5.9.3",
    "typescript-eslint": "8.70.0"
  }
}
```

Write `smoke/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noEmit": true,
    "types": ["node"],
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["playwright.config.ts", "tests/**/*.ts"]
}
```

Write `smoke/eslint.config.js`:

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["node_modules/", "test-results/", "playwright-report/"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
);
```

Write `smoke/.prettierignore` (prettier reads the ignore file from its own working directory, so the root one does not apply when `npm run lint` runs inside `smoke/`; without this, failure artifacts under `test-results/` would fail `prettier --check`):

```
node_modules/
test-results/
playwright-report/
package-lock.json
```

- [ ] **Step 2: Install and prove the test file is missing**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/smoke
source "$HOME/.nvm/nvm.sh" && nvm use 24
npm install
npx playwright install --with-deps chromium
npx playwright --version
SMOKE_BASE_URL=http://localhost:9 npx playwright test; echo "exit=$?"
```

Expected: `Version 1.63.0`; the test run reports `Error: No tests found` (or an equivalent "no tests" message) and a non-zero exit. On macOS `--with-deps` installs nothing beyond the browser; the flag matters on `ubuntu-latest` in CI.

- [ ] **Step 3: Playwright config**

Write `smoke/playwright.config.ts`:

```ts
import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.SMOKE_BASE_URL;
if (!baseURL) {
  throw new Error("SMOKE_BASE_URL is required, for example SMOKE_BASE_URL=https://web-staging-52c0.up.railway.app");
}
const aiTimeoutMs = Number(process.env.SMOKE_AI_TIMEOUT_MS ?? "90000");
if (!Number.isFinite(aiTimeoutMs) || aiTimeoutMs <= 0) {
  throw new Error(`SMOKE_AI_TIMEOUT_MS must be a positive number of milliseconds, got ${process.env.SMOKE_AI_TIMEOUT_MS}`);
}

export default defineConfig({
  testDir: "./tests",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  // The single test waits up to aiTimeoutMs for the assistant plus about two minutes of navigation.
  timeout: aiTimeoutMs + 120_000,
  expect: { timeout: 15_000 },
  outputDir: "test-results",
  reporter: [["list"], ["html", { open: "never", outputFolder: "playwright-report" }]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    video: "off",
    actionTimeout: 15_000,
    navigationTimeout: 30_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
```

- [ ] **Step 4: The smoke test**

Write `smoke/tests/smoke.spec.ts`:

```ts
import { expect, test, type Locator, type Page } from "@playwright/test";

const AI_TIMEOUT_MS = Number(process.env.SMOKE_AI_TIMEOUT_MS ?? "90000");
const FAST = process.env.SMOKE_FAST === "1";
const PASSWORD = "smoke-pass-2026";
const DISPLAY_NAME = "Smoke";
const TASK_TITLE = "Prepare the quarterly business review deck for the leadership team";
const TASK_DESCRIPTION =
  "Collect last quarter's numbers from finance and product and turn them into a twelve-slide story. The deck is presented to the leadership team on Thursday and must run under twenty minutes.";

type AiState = "thinking" | "suggestions" | "failed" | "skipped" | "none";

// The chip inside a task row states the AI status in words. These patterns are the contract with the web app
// (see README.md, "Selector contract").
const CHIP = {
  thinking: /thinking/i,
  suggestions: /\d+ suggestions?/i,
  failed: /failed/i,
  skipped: /too short to break down|hourly limit reached|assistant paused/i,
};

function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}

async function aiState(row: Locator): Promise<AiState> {
  const text = oneLine(await row.innerText());
  if (CHIP.thinking.test(text)) return "thinking";
  if (CHIP.failed.test(text)) return "failed";
  if (CHIP.skipped.test(text)) return "skipped";
  if (CHIP.suggestions.test(text)) return "suggestions";
  return "none";
}

async function expectLoginPage(page: Page): Promise<void> {
  await expect(page).toHaveURL(/\/login(\?.*)?$/);
  await expect(page.getByRole("heading", { name: /log in/i })).toBeVisible();
}

test("register, create a task, wait for the assistant, accept a suggestion, log out", async ({ page }) => {
  const email = `smoke+${Date.now()}@kaizen.local`;
  const row = page.getByRole("listitem").filter({ hasText: TASK_TITLE });

  await test.step("1. open the base URL and expect the login page", async () => {
    await page.goto("/");
    await expectLoginPage(page);
  });

  await test.step("2. register a fresh user", async () => {
    await page.getByRole("link", { name: /register|create an account/i }).click();
    await expect(page).toHaveURL(/\/register$/);
    await page.getByLabel(/email/i).fill(email);
    await page.getByLabel(/^password$/i).fill(PASSWORD);
    await page.getByLabel(/display name/i).fill(DISPLAY_NAME);
    await page.getByRole("button", { name: /create account|register/i }).click();
    await expect(page).toHaveURL(/\/tasks$/);
  });

  await test.step("3. create the task from the task list", async () => {
    const title = page.getByRole("textbox", { name: /task title/i });
    await expect(title).toBeVisible();
    await title.fill(TASK_TITLE);
    const description = page.getByRole("textbox", { name: /description/i });
    if (!(await description.isVisible())) {
      await page.getByRole("button", { name: /description/i }).click();
    }
    await description.fill(TASK_DESCRIPTION);
    await title.press("Enter");
    await expect(row).toBeVisible();
  });

  await test.step("4. wait for the assistant", async () => {
    let state = await aiState(row);
    if (state === "thinking") {
      if (FAST) {
        console.log("SMOKE_FAST=1: not waiting for the assistant");
      } else {
        await expect
          .poll(async () => (await aiState(row)) !== "thinking", {
            timeout: AI_TIMEOUT_MS,
            intervals: [2_000],
            message: `the AI chip was still thinking after ${AI_TIMEOUT_MS} ms`,
          })
          .toBe(true);
        state = await aiState(row);
      }
    }
    const rowText = oneLine(await row.innerText());
    if (state === "failed") {
      throw new Error(`AI breakdown failed: ${rowText}`);
    }
    if (state === "skipped") {
      console.log(`AI breakdown skipped, accepted as a pass: ${rowText}`);
    }
    if (state === "none") {
      console.log(`AI chip absent, the breakdown finished with no suggestions: ${rowText}`);
    }
  });

  await test.step("5. open the detail and accept the first suggestion when there is one", async () => {
    await row.getByRole("link", { name: TASK_TITLE }).click();
    await expect(page).toHaveURL(/\/tasks\/[0-9a-f-]{36}$/);
    await expect(page.getByRole("heading", { name: TASK_TITLE })).toBeVisible();
    const accept = page.getByRole("button", { name: /^accept$/i }).first();
    if ((await accept.count()) > 0) {
      await accept.click();
      await expect(page.getByText(/\b\d+\/[1-9]\d*\b/).first()).toBeVisible();
    } else {
      console.log("No suggestion to accept on the detail page");
    }
  });

  await test.step("6. log out and expect the login page", async () => {
    const directLogout = page.getByRole("button", { name: /log out/i });
    if ((await directLogout.count()) > 0) {
      await directLogout.click();
    } else {
      await page.getByRole("button", { name: DISPLAY_NAME }).click();
      await page.getByRole("menuitem", { name: /log out/i }).click();
    }
    await expectLoginPage(page);
  });
});
```

- [ ] **Step 5: Typecheck, lint, and run against a dead URL to see the failure artifacts**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/smoke
npm run typecheck && npm run lint
SMOKE_BASE_URL=http://127.0.0.1:9 npm test; echo "exit=$?"
ls test-results/*/ | head
```

Expected: typecheck and lint pass (prettier may ask for `npm run format` first; run it and re-check); the test fails in step 1 with `net::ERR_CONNECTION_REFUSED`, `exit=1`, and `test-results/` contains a folder with `trace.zip` and a screenshot. This proves traces are kept on failure.

Also prove the config guard:

```bash
npx playwright test 2>&1 | grep 'SMOKE_BASE_URL is required'
```

Expected: the error line is printed.

- [ ] **Step 6: Smoke README**

Write `smoke/README.md`:

```markdown
# Kaizen Tasks smoke test

One Playwright test, Chromium only, run against a deployed Kaizen Tasks web URL. Both app repos check this repository out at `main` in their `promote` workflow and run it against staging before a pull request into `main` may merge.

## What it does, in order

1. Opens the base URL and expects the login page.
2. Registers `smoke+<timestamp>@kaizen.local` with a fixed password and the display name "Smoke".
3. Expects the task list and creates the task "Prepare the quarterly business review deck for the leadership team" with a two-sentence description.
4. Expects the row with a thinking chip. Unless fast mode, polls the row until the chip leaves thinking, within the AI timeout. Fails on a failed chip or on timeout. Accepts a skipped chip as a pass with a console note.
5. Opens the detail. If suggestions exist, accepts the first one and expects the progress label to read `0/1` or higher.
6. Logs out and expects the login page.

## Run it

```bash
nvm use
npm ci
npx playwright install --with-deps chromium
SMOKE_BASE_URL=https://<web domain> npm test          # headless
SMOKE_BASE_URL=http://localhost:5173 npm run test:headed   # rehearsal, watch it
```

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `SMOKE_BASE_URL` | yes | none | The web app origin |
| `SMOKE_AI_TIMEOUT_MS` | no | `90000` | How long to wait for the assistant to finish |
| `SMOKE_FAST` | no | unset | `1` skips the AI wait (step 4) |

Traces and screenshots are written under `test-results/` on failure, plus an HTML report under `playwright-report/`. Open a trace with `npx playwright show-trace test-results/<folder>/trace.zip`.

## Selector contract

The test finds elements by accessible role and name, never by CSS class. The web app must satisfy:

| Screen | Element | Locator used |
|---|---|---|
| Login | heading | role heading, name matches `/log in/i`; URL ends in `/login` |
| Login | link to register | role link, name matches `/register|create an account/i` |
| Register | inputs | labels matching `/email/i`, `/^password$/i`, `/display name/i` |
| Register | submit | role button, name matches `/create account|register/i`; success lands on `/tasks` |
| Task list | create bar | role textbox named `Task title`; role textbox named `Description` (a button whose name contains "description" reveals it when collapsed); Enter in the title submits |
| Task list | row | role listitem containing the task title; the title is a link to the detail |
| Task list | AI chip text | `Thinking` while pending or running; `N suggestions` when done with suggestions; contains `failed` on failure; one of `too short to break down`, `hourly limit reached`, `assistant paused` when skipped |
| Detail | heading | role heading with the task title; URL `/tasks/<uuid>` |
| Detail | accept | role button named exactly `Accept` on each suggested step |
| Detail | progress | text matching `done/total`, for example `0/1` |
| Anywhere | log out | role button named `Log out`, or a role button named after the display name that opens a menu with a menuitem `Log out` |

## How the app repos call it

```yaml
- uses: actions/checkout@v5
  with:
    repository: kpnemo/kaizen-tasks-assembly-line
    ref: main
    path: assembly-line
- uses: actions/setup-node@v5
  with:
    node-version-file: .nvmrc
- run: npm ci
  working-directory: assembly-line/smoke
- run: npx playwright install --with-deps chromium
  working-directory: assembly-line/smoke
- run: npm test
  working-directory: assembly-line/smoke
  env:
    SMOKE_BASE_URL: https://web-staging-52c0.up.railway.app
    SMOKE_AI_TIMEOUT_MS: "90000"
- uses: actions/upload-artifact@v5
  if: failure()
  with:
    name: smoke-results
    path: assembly-line/smoke/test-results/
```

The repository is public, so the checkout needs no token (verification item L3 in the assembly-line spec, proven by the first `promote` run; fallback: pass `token: ${{ github.token }}` with read scope).
```

- [ ] **Step 7: Commit**

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
(cd smoke && npm run format && npm run lint && npm run typecheck)
git add smoke/package.json smoke/package-lock.json smoke/.prettierignore smoke/tsconfig.json smoke/eslint.config.js smoke/playwright.config.ts smoke/tests/smoke.spec.ts smoke/README.md
git status --short smoke
git commit -m "feat: playwright smoke package" -m "$TRAILER"
```

Expected: `git status` shows nothing untracked under `smoke/` except ignored `node_modules`, `test-results`, `playwright-report`.

---

### Task 8: Root hooks: settings, docs-check-all, format-file (proves L2)

**Files:**

- Create: `.claude/settings.json`, `scripts/docs-check-all.sh`, `scripts/format-file.sh`

**Interfaces:**

- Consumes: master plan interface "Docs-check": each nested repo has `scripts/docs-check.sh --hook` that exits 2 on failure with the fix list on stdout, owns its three-strike counter `.claude/.docs-check-blocks` and marker `.claude/DOCS-CHECK-FAILED`, and after the third consecutive block stops blocking but never exits 0 while printing FAILED (API spec section 8.2: it prints `DOCS CHECK FAILED, human intervention required`, writes the marker, and exits non-zero but not 2). Claude Code hook facts from the official hooks reference: the Stop hook's stdin JSON carries `stop_hook_active`, true when Claude Code is already continuing because a Stop hook blocked; exit 2 blocks the stop and feeds stderr to the model; any other non-zero exit is non-blocking; `timeout` is in seconds; hook events sit under a top-level `hooks` key in `.claude/settings.json`. Root prettier from Task 1. `jq` (present at `/usr/bin/jq`).
- Produces: a Stop hook that blocks the root session (exit 2) when any nested repo with changes fails its docs-check, passes a nested escape hatch through as non-blocking (exit 1), and can never loop on a repo that has already given up; a PostToolUse hook that formats edited files with the owning repo's prettier. `KAIZEN_WORKSPACE_ROOT` env override for fixture tests.

- [ ] **Step 1: Build a fixture workspace and the failing test**

Run:

```bash
FX="$SCRATCH/hooks-fixture"; rm -rf "$FX"; mkdir -p "$FX/backend/scripts" "$FX/frontend"
git -C "$FX/backend" init -q -b develop
printf '.claude/\n' > "$FX/backend/.gitignore"    # the nested counter and marker live in .claude/; ignored so run 8 below sees a clean tree
cat >"$FX/backend/scripts/docs-check.sh" <<'EOF'
#!/usr/bin/env bash
# Fixture stand-in for a nested repo's scripts/docs-check.sh. DOCS_CHECK_FIXTURE_RESULT selects the outcome:
#   fail  (default) a rule fails: fix list on stdout, exit 2 (blocking)
#   pass  everything is fine: marker removed, exit 0
#   hatch the nested three-strike escape hatch has fired: banner, marker written, exit 1 (non-blocking)
#   stuck a misbehaving nested script: marker written but still exit 2
input="$(cat)"
echo "cwd=$(pwd)"
echo "stop_hook_active=$(printf '%s' "$input" | jq -r '.stop_hook_active')"
mkdir -p .claude
case "${DOCS_CHECK_FIXTURE_RESULT:-fail}" in
  pass)  rm -f .claude/DOCS-CHECK-FAILED; echo "docs-check OK"; exit 0 ;;
  hatch) echo "Rule A" > .claude/DOCS-CHECK-FAILED; echo "DOCS CHECK FAILED, human intervention required"; exit 1 ;;
  stuck) echo "Rule A" > .claude/DOCS-CHECK-FAILED; echo "Rule A: add a bullet under [Unreleased] in CHANGELOG.md"; exit 2 ;;
  *)     echo "Rule A: add a bullet under [Unreleased] in CHANGELOG.md"; exit 2 ;;
esac
EOF
chmod +x "$FX/backend/scripts/docs-check.sh"
git -C "$FX/backend" add -A && git -C "$FX/backend" -c user.email=t@t -c user.name=t commit -qm init
echo "change" > "$FX/backend/src.txt"      # uncommitted change → the repo "has changes"
git -C "$FX/frontend" init -q -b develop && git -C "$FX/frontend" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
echo '{"hook_event_name":"Stop","stop_hook_active":false}' | KAIZEN_WORKSPACE_ROOT="$FX" bash scripts/docs-check-all.sh --hook; echo "exit=$?"
```

Expected: `bash: scripts/docs-check-all.sh: No such file or directory` and `exit=127`.

- [ ] **Step 2: Write `scripts/docs-check-all.sh`**

```bash
#!/usr/bin/env bash
# Root Stop hook: run each nested repo's docs-check when that repo has changes.
# Usage: scripts/docs-check-all.sh --hook
#   stdin: the Stop hook JSON from Claude Code, for example
#          {"hook_event_name":"Stop","stop_hook_active":false,"session_id":"...","cwd":"..."}.
#          It is forwarded unchanged to each nested script.
#   KAIZEN_WORKSPACE_ROOT=<dir> overrides the workspace root (used by the fixture test).
#
# Exit code, mapped from the nested scripts (master plan section 4, "Docs-check"):
#   every nested exit 0, or no nested repo with changes  -> exit 0, report on stdout
#   any nested exit 2                                    -> exit 2, report on stderr: Claude Code blocks the stop
#                                                           and feeds stderr back to the model
#   otherwise (a nested exit that is neither 0 nor 2)    -> exit 1, report on stderr, non-blocking. This is the
#                                                           nested escape hatch: after three consecutive blocks a
#                                                           nested docs-check stops blocking, prints its banner
#                                                           "DOCS CHECK FAILED, human intervention required",
#                                                           writes .claude/DOCS-CHECK-FAILED, and exits non-zero
#                                                           without exiting 2. A failure is never turned into
#                                                           exit 0 here.
#
# stop_hook_active is true when Claude Code is already continuing because a Stop hook blocked. This script keeps
# checking when it is true (skipping would let a real failure through on the second attempt); the nested
# three-strike counter is the loop guard. As a safety net it reads the flag and, when it is true and a nested
# repo carries the marker .claude/DOCS-CHECK-FAILED after its run, treats that repo as escape-hatched (exit 1,
# not 2) even if the nested script exited 2, so a root session can never loop on a repo that has already given
# up. This script adds no docs rules of its own.
set -uo pipefail

if [ "${1:-}" != "--hook" ]; then
  echo "usage: $0 --hook   (reads the Stop hook JSON on stdin)" >&2
  exit 1
fi

ROOT="${KAIZEN_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
HOOK_INPUT="$(cat 2>/dev/null || true)"
STOP_HOOK_ACTIVE="$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
if [ "$STOP_HOOK_ACTIVE" != "true" ]; then STOP_HOOK_ACTIVE=false; fi

# A repo "has changes" when the working tree is dirty or HEAD has commits beyond its base
# (merge-base with origin/develop, else local develop).
has_changes() {
  local repo="$1" base=""
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then return 0; fi
  if git -C "$repo" rev-parse --verify -q origin/develop >/dev/null 2>&1; then
    base="$(git -C "$repo" merge-base HEAD origin/develop 2>/dev/null || true)"
  elif git -C "$repo" rev-parse --verify -q develop >/dev/null 2>&1; then
    base="$(git -C "$repo" merge-base HEAD develop 2>/dev/null || true)"
  fi
  if [ -n "$base" ] && [ -n "$(git -C "$repo" rev-list "$base"..HEAD 2>/dev/null)" ]; then return 0; fi
  return 1
}

blocked=0
hatched=0
report="stop_hook_active=$STOP_HOOK_ACTIVE"$'\n'
for name in backend frontend; do
  repo="$ROOT/$name"
  if [ ! -d "$repo/.git" ]; then continue; fi
  if [ ! -f "$repo/scripts/docs-check.sh" ]; then
    report="$report[$name] scripts/docs-check.sh not found, skipped"$'\n'
    continue
  fi
  if ! has_changes "$repo"; then
    report="$report[$name] no changes, docs-check skipped"$'\n'
    continue
  fi
  output="$(cd "$repo" && printf '%s' "$HOOK_INPUT" | bash scripts/docs-check.sh --hook 2>&1)"
  code=$?
  report="$report$(printf '%s\n' "$output" | sed "s/^/[$name] /")"$'\n'
  if [ "$code" -eq 0 ]; then
    continue
  fi
  if [ "$code" -eq 2 ] && [ "$STOP_HOOK_ACTIVE" = true ] && [ -f "$repo/.claude/DOCS-CHECK-FAILED" ]; then
    report="$report[$name] exit 2 with the marker .claude/DOCS-CHECK-FAILED present while stop_hook_active is true: treated as the escape hatch, not blocking again"$'\n'
    code=1
  fi
  if [ "$code" -eq 2 ]; then
    blocked=1
    report="$report[$name] docs-check exit 2, blocking the stop"$'\n'
  else
    hatched=1
    report="$report[$name] docs-check exit $code, escape hatch, not blocking"$'\n'
  fi
done

if [ "$blocked" -ne 0 ]; then
  printf '%s' "$report" >&2
  exit 2
fi
if [ "$hatched" -ne 0 ]; then
  printf '%s' "$report" >&2
  exit 1
fi
printf '%s' "$report"
exit 0
```

- [ ] **Step 3: Run the fixture sequence (verification item L2 and the exit-code contract)**

Run (one tool call, so `$FX` is defined):

```bash
FX="$SCRATCH/hooks-fixture"
chmod +x scripts/docs-check-all.sh
J0='{"hook_event_name":"Stop","stop_hook_active":false}'
J1='{"hook_event_name":"Stop","stop_hook_active":true}'
run() { echo "-- $1"; shift; "$@"; echo "exit=$?"; }
run "1 fail, first attempt"                 env KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J0' | bash scripts/docs-check-all.sh --hook"
run "2 fail again, stop_hook_active true"   env KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J1' | bash scripts/docs-check-all.sh --hook"
run "3 nested escape hatch"                 env DOCS_CHECK_FIXTURE_RESULT=hatch KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J1' | bash scripts/docs-check-all.sh --hook"
run "4 stuck nested, stop_hook_active true" env DOCS_CHECK_FIXTURE_RESULT=stuck KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J1' | bash scripts/docs-check-all.sh --hook"
run "5 stuck nested, fresh stop"            env DOCS_CHECK_FIXTURE_RESULT=stuck KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J0' | bash scripts/docs-check-all.sh --hook"
run "6 pass clears the marker"              env DOCS_CHECK_FIXTURE_RESULT=pass KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '$J1' | bash scripts/docs-check-all.sh --hook"
ls "$FX/backend/.claude/"
run "7 stdin is not JSON"                   env KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo 'not json' | bash scripts/docs-check-all.sh --hook"
rm "$FX/backend/src.txt"
run "8 no changes"                          env KAIZEN_WORKSPACE_ROOT="$FX" bash -c "echo '{}' | bash scripts/docs-check-all.sh --hook"
run "9 without --hook"                      bash scripts/docs-check-all.sh
```

Expected, in order. Every report starts with a `stop_hook_active=<value>` line and ends with `[frontend] scripts/docs-check.sh not found, skipped`; reports for exit 1 and 2 go to stderr, for exit 0 to stdout.

1. `[backend] cwd=<...>/hooks-fixture/backend`, `[backend] stop_hook_active=false`, `[backend] Rule A: add a bullet under [Unreleased] in CHANGELOG.md`, `[backend] docs-check exit 2, blocking the stop`; `exit=2`. The `cwd=` line ending in `/backend` proves L2: the nested script runs with the nested repo as its working directory, so its counter and marker files land in the nested `.claude/`.
2. The same with `stop_hook_active=true`; `exit=2`. A real failure still blocks on the second attempt; the flag alone never disarms the hook.
3. `[backend] DOCS CHECK FAILED, human intervention required`, `[backend] docs-check exit 1, escape hatch, not blocking`; `exit=1`. Non-blocking: the session may stop and the banner reaches the user.
4. `[backend] exit 2 with the marker .claude/DOCS-CHECK-FAILED present while stop_hook_active is true: treated as the escape hatch, not blocking again`, then `[backend] docs-check exit 1, escape hatch, not blocking`; `exit=1`.
5. `[backend] docs-check exit 2, blocking the stop`; `exit=2`. The marker alone does not disarm a fresh stop.
6. `[backend] docs-check OK`; `exit=0`; the `ls` prints nothing because the marker is gone.
7. `stop_hook_active=false` (invalid JSON defaults to false), one `[backend] jq: parse error` line from the fixture, `[backend] docs-check exit 2, blocking the stop`; `exit=2`.
8. `[backend] no changes, docs-check skipped`; `exit=0`.
9. The usage line on stderr; `exit=1`.

Record in the task report: "L2 verified by fixture; fallback `--repo <path>` not needed."

- [ ] **Step 4: Write `scripts/format-file.sh` and its failing test**

Run first:

```bash
printf '# x\n\n\n\n* a\n' > "$SCRATCH/note.md"
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRATCH/note.md\"}}" | bash scripts/format-file.sh; echo "exit=$?"
```

Expected: `No such file or directory`, `exit=127`.

Write `scripts/format-file.sh`:

```bash
#!/usr/bin/env bash
# Root PostToolUse hook for Edit|Write: format the edited file with the owning repo's prettier.
# stdin: the hook JSON ({"tool_name":"Edit","tool_input":{"file_path":"..."}}).
#   KAIZEN_WORKSPACE_ROOT=<dir> overrides the workspace root (used by the fixture test).
# Files under backend/ or frontend/ are formatted by that repo's prettier (any extension prettier knows).
# Files elsewhere are formatted by the root prettier only when they are markdown, JSON, or YAML.
# Never blocks: always exits 0.
set -uo pipefail

ROOT="${KAIZEN_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
input="$(cat 2>/dev/null || true)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
if [ -z "$file" ]; then exit 0; fi
case "$file" in
  /*) ;;
  *) file="$ROOT/$file" ;;
esac
if [ ! -f "$file" ]; then exit 0; fi

format_in() { # repo file
  local repo="$1" target="$2"
  if [ ! -x "$repo/node_modules/.bin/prettier" ]; then
    echo "format-file: prettier is not installed in $repo, skipped $target"
    return 0
  fi
  if (cd "$repo" && ./node_modules/.bin/prettier --write --ignore-unknown --log-level warn "$target"); then
    echo "format-file: formatted $target with $repo/node_modules/.bin/prettier"
  else
    echo "format-file: prettier failed on $target"
  fi
}

case "$file" in
  "$ROOT/backend/"*) format_in "$ROOT/backend" "$file" ;;
  "$ROOT/frontend/"*) format_in "$ROOT/frontend" "$file" ;;
  *.md | *.json | *.yml | *.yaml) format_in "$ROOT" "$file" ;;
  *) echo "format-file: $file is outside both repos and not markdown, JSON, or YAML; skipped" ;;
esac
exit 0
```

- [ ] **Step 5: Test format-file against the root and a fixture nested repo**

Run:

```bash
FX="$SCRATCH/hooks-fixture"
chmod +x scripts/format-file.sh
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRATCH/note.md\"}}" | bash scripts/format-file.sh; echo "exit=$?"
cat "$SCRATCH/note.md"
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRATCH/note.sh\"}}" | bash scripts/format-file.sh; echo "exit=$?"
echo '{"a":1}' > "$FX/backend/x.json"
echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FX/backend/x.json\"}}" | KAIZEN_WORKSPACE_ROOT="$FX" bash scripts/format-file.sh; echo "exit=$?"
echo 'not json' | bash scripts/format-file.sh; echo "exit=$?"
```

Expected: first run prints `format-file: formatted .../note.md with .../webapp/node_modules/.bin/prettier`, `exit=0`, and `cat` shows the blank lines collapsed and `* a` rewritten as `- a`; second run (file does not exist) prints nothing, `exit=0`; third run prints `format-file: prettier is not installed in .../hooks-fixture/backend, skipped ...`, `exit=0`; fourth run prints nothing, `exit=0`.

- [ ] **Step 6: Write `.claude/settings.json`**

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/docs-check-all.sh\" --hook",
            "timeout": 600
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/format-file.sh\"",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

The shape is the settings format from the official hooks reference: events under a top-level `hooks` key, `timeout` in seconds, and no `matcher` on the Stop entry because Stop ignores matchers.

Validate the file and run each hook command exactly as Claude Code will, with `$CLAUDE_PROJECT_DIR` set:

```bash
FX="$SCRATCH/hooks-fixture"
jq -e '.hooks.Stop[0].hooks[0].type == "command" and .hooks.PostToolUse[0].matcher == "Edit|Write"' .claude/settings.json && echo "settings shape ok"
echo "change" > "$FX/backend/src.txt"
echo '{"hook_event_name":"Stop","stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$PWD" KAIZEN_WORKSPACE_ROOT="$FX" bash -c "$(jq -r '.hooks.Stop[0].hooks[0].command' .claude/settings.json)"; echo "exit=$?"
echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRATCH/note.md\"}}" | CLAUDE_PROJECT_DIR="$PWD" bash -c "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' .claude/settings.json)"; echo "exit=$?"
```

Expected: `true` then `settings shape ok`; the Stop command prints the `[backend] ... blocking the stop` report on stderr and `exit=2`; the PostToolUse command prints `format-file: formatted .../note.md ...` and `exit=0`. This proves the command strings in the file resolve through `$CLAUDE_PROJECT_DIR`. Note for the executor: hooks load at session start, so a running Claude Code session must be restarted to pick them up; `/hooks` lists what loaded.

- [ ] **Step 7: Commit**

```bash
npx prettier --write .claude/settings.json
git add .claude/settings.json scripts/docs-check-all.sh scripts/format-file.sh
git commit -m "feat: root Stop and PostToolUse hooks delegating to the nested repos" -m "$TRAILER"
```

---

### Task 9: The triage-requests skill

**Files:**

- Create: `.claude/skills/triage-requests/SKILL.md`, `triage/.gitkeep`

**Interfaces:**

- Consumes: `rubric/readiness.md` (Task 2), labels and the board (Task 4), the form's `### Acceptance criteria` heading (Task 3), `gh` authenticated as `kpnemo`.
- Produces: `triage/<YYYY-MM-DD>.md` reports committed as `triage: <date>`; labels `clarity:*`, `complexity:*`, `risk:*`, `triaged`, `arch-change` on each issue; one comment per issue carrying `<!-- kaizen-triage -->`; the board body starting with `<!-- kaizen-triage-board -->`. The `--score-only` mode is what L5's `refine-request` describes as the engineering score.

- [ ] **Step 1: Write the skill**

Write `.claude/skills/triage-requests/SKILL.md`:

````markdown
---
name: triage-requests
description: Rank open feature requests by readiness and write scores back to GitHub
argument-hint: "[--score-only <issue number | file>] [--dry-run]"
---

# triage-requests

Score every open `feature-request` issue with `rubric/readiness.md`, rank them, write a dated report under `triage/`, and write the scores back to GitHub as labels, one upserted comment per issue, and the pinned Triage board. Every write is a replacement, so running the skill twice leaves the same state.

Constants:

- `REPO=kpnemo/kaizen-tasks-assembly-line`
- Comment marker: `<!-- kaizen-triage -->`
- Board marker: `<!-- kaizen-triage-board -->`
- Working directory: the workspace root (the folder containing `rubric/`, `triage/`, `.claude/`).

## Modes

| Invocation | Effect |
|---|---|
| `/triage-requests` | Full mode: score, report, labels, comments, board, summary |
| `/triage-requests --dry-run` | Score and write the report file (uncommitted); print what would change on GitHub; write nothing to GitHub; no commit |
| `/triage-requests --score-only 12` | Score issue 12 and print the result; write nothing anywhere |
| `/triage-requests --score-only seeds/requests/02-smarter-ai.md` | Score a file; write nothing anywhere |

## Step 1: Read the rubric

Read `rubric/readiness.md` in full. Print `Rubric version: <n>` from its front matter. Follow its procedure section literally for every score: clarity from the acceptance criteria alone, complexity and risk by naming files or areas, the architecture change test, the formula, questions only when clarity is below 3.

## Step 2: Score-only mode

Applies when `--score-only` is given. No writes of any kind: no labels, no comments, no report, no commit.

1. Load the request text.
   - A number: `gh issue view <n> --repo $REPO --json title,body --jq '"# " + .title + "\n\n" + .body'`
   - A file path: read the file; the front matter `title:` line is the title, everything after the second `---` is the body.
2. Apply the rubric procedure.
3. Print the fixed output shape as a JSON block, then the three reasons and the questions as prose. Stop.

## Step 3: Full mode, fetch the open requests

```bash
gh issue list --repo $REPO --label feature-request --state open \
  --json number,title,body,createdAt,labels --limit 100
```

The Triage board carries `triage-board`, not `feature-request`, so it never appears here. If the list is empty, print "No open feature requests" and stop.

## Step 4: Score and rank

Score every issue with the rubric procedure. Rank by readiness descending; every issue with `archChange: true` after every issue with `archChange: false`, regardless of score; ties by `createdAt` ascending.

## Step 5: Write the report

Write `triage/<YYYY-MM-DD>.md` with today's UTC date (`date -u +%F`):

```markdown
# Triage <YYYY-MM-DD>

Rubric version <n>. <count> issues scored at <ISO timestamp, date -u +%FT%TZ>.

| Rank | Issue | Title | Readiness | Clarity | Complexity | Risk | Arch |
|---|---|---|---|---|---|---|---|
| 1 | #<n> | <title> | 19 | 5 | 2 | 1 | no |

## #<n> <title>

- Clarity <c>: <reason>
- Complexity <x>: <reason>
- Risk <r>: <reason>
- Architecture change: <yes | no>
- Questions: none | 1. ... 2. ... 3. ...
```

Unless `--dry-run`, commit it:

```bash
git add triage/<YYYY-MM-DD>.md
git commit -m "triage: <YYYY-MM-DD>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

In `--dry-run`, leave the file uncommitted and say so.

## Step 6: Labels and the triage comment, per issue

Skip this step entirely in `--dry-run`; instead print, per issue, the labels that would be set and whether the comment would be created or edited.

For each issue `<n>` with scores `<c>`, `<x>`, `<r>` and `archChange`:

1. Remove the score labels currently present:

```bash
current="$(gh issue view <n> --repo $REPO --json labels \
  --jq '[.labels[].name | select(test("^(clarity|complexity|risk):"))] | join(",")')"
if [ -n "$current" ]; then gh issue edit <n> --repo $REPO --remove-label "$current"; fi
```

2. Add the new ones and `triaged`:

```bash
gh issue edit <n> --repo $REPO --add-label "clarity:<c>,complexity:<x>,risk:<r>,triaged"
```

3. Architecture flag: when `archChange` is true, `gh issue edit <n> --repo $REPO --add-label arch-change`. When false and the fetched labels include `arch-change`, `gh issue edit <n> --repo $REPO --remove-label arch-change`.

4. Write the comment to a temp file:

```markdown
<!-- kaizen-triage -->
**Triage** (rubric v<n>, <YYYY-MM-DD>): readiness **<score>**. Clarity <c>, complexity <x>, risk <r><, architecture change>.

- Clarity: <one-line reason>
- Complexity: <one-line reason>
- Risk: <one-line reason>

**Questions** (only when clarity is below 3; omit the heading otherwise)
1. <question>
2. <question>
```

5. Upsert: find the existing comment by the marker, edit it if found, create it otherwise.

```bash
cid="$(gh api "repos/$REPO/issues/<n>/comments" --paginate \
  --jq '[.[] | select(.body | contains("<!-- kaizen-triage -->"))][0].id // empty' | head -1)"
if [ -n "$cid" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$cid" -F body=@<tempfile> --jq .html_url
else
  gh issue comment <n> --repo $REPO --body-file <tempfile>
fi
```

## Step 7: Rewrite the Triage board

Skip in `--dry-run` (print the table instead).

```bash
board="$(gh issue list --repo $REPO --label triage-board --state open --json number --jq '.[0].number // empty')"
```

If empty, run `scripts/setup-labels.sh` (it creates and pins the board) and read the number again. Write the body to a temp file:

```markdown
<!-- kaizen-triage-board -->
# Triage board

| Rank | Issue | Title | Readiness | Clarity | Complexity | Risk | Arch | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | #<n> | <title> | 19 | 5 | 2 | 1 | no | triaged |

Status is `shipped` when the issue carries `shipped`, else `implementing` when it carries `implementing`, else `triaged`.
Last run: <ISO timestamp>. Report: `triage/<YYYY-MM-DD>.md`. Rubric version <n>.
```

Then `gh issue edit $board --repo $REPO --body-file <tempfile>`.

## Step 8: Summary

Print the top three as `#<n> <title> (readiness <score>)`, then `Recommended to implement next: #<n> <title>`, which is the first ranked issue with `archChange: false`. If every issue is an architecture change, say so and recommend none.

## Rules

- Never merge, never close issues, never edit an issue's title or body. The only body this skill rewrites is the Triage board's.
- Never post a second triage comment on an issue; always upsert by the marker.
- Score from the text as written. Do not read linked pull requests or other issues.
````

- [ ] **Step 2: Create the triage folder and check the skill loads**

Run:

```bash
mkdir -p triage && touch triage/.gitkeep
head -5 .claude/skills/triage-requests/SKILL.md
node -e 'const s=require("fs").readFileSync(".claude/skills/triage-requests/SKILL.md","utf8"); const fm=s.split("---")[1]; for (const k of ["name:","description:","argument-hint:"]) if(!fm.includes(k)) {console.error("missing "+k); process.exit(1)}; console.log("frontmatter ok")'
```

Expected: the front matter with `name: triage-requests`, and `frontmatter ok`.

- [ ] **Step 3: Dry-run the skill against the seeds as files (no GitHub)**

Start Claude Code at the workspace root (`claude`) and run, one at a time:

```
/triage-requests --score-only seeds/requests/01-mark-all-done.md
/triage-requests --score-only seeds/requests/02-smarter-ai.md
/triage-requests --score-only seeds/requests/03-share-task.md
/triage-requests --score-only seeds/requests/04-regenerate-with-hint.md
```

Expected: each prints `Rubric version: 1` and a JSON block. 01: `clarity: 5, complexity: 2, risk: 1, archChange: false, readiness: 19, questions: []`. 02: `clarity: 1`, `archChange: false`, two or three questions drawn from the four patterns. 03: `archChange: true`, risk 5. 04: `clarity: 4, complexity: 3, risk: 3, archChange: false, readiness: 14`. If 01 or 04 deviate by more than one point on any scale, tighten the seed text (Task 5) rather than the rubric, and re-run. Paste the four JSON blocks into the task report as evidence.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/triage-requests/SKILL.md triage/.gitkeep
git commit -m "feat: triage-requests skill" -m "$TRAILER"
```

---

### Task 10: The implement-issue skill (ties to L1)

**Files:**

- Create: `.claude/skills/implement-issue/SKILL.md`

**Interfaces:**

- Consumes: master plan interface "Per-repo skills": `backend/.claude/skills/add-api-endpoint/SKILL.md`, `frontend/.claude/skills/add-frontend-feature/SKILL.md`, `write-adr` in both; scripts `frontend/scripts/pull-openapi.sh --local <path>`, `npm run api:types`, `npm run openapi`, `npm run docs:check`, `npm test` in both repos (L1-M2, L2-M2).
- Produces: one pull request per affected repo with base `develop`, body containing `Closes kpnemo/kaizen-tasks-assembly-line#<n>` (verification item L1, proven at integration when Mike merges the first one; fallback recorded in the runbook), label `implementing` and a PR-links comment on the issue.

- [ ] **Step 1: Write the skill**

Write `.claude/skills/implement-issue/SKILL.md`:

````markdown
---
name: implement-issue
description: Implement one feature request end to end across both repos with TDD, open pull requests, never merge
argument-hint: "<issue number>"
---

# implement-issue

Take one issue from `kpnemo/kaizen-tasks-assembly-line`, restate its acceptance criteria, implement it test-first in the affected nested repos using their own skills, run their full checks, open one pull request per affected repo, and stop.

Constants:

- `REPO=kpnemo/kaizen-tasks-assembly-line`
- Nested repos: `backend/` is `kpnemo/kaizen-tasks-api`; `frontend/` is `kpnemo/kaizen-tasks-web`. Base branch `develop` in both.
- Branch name: `feat/<n>-<slug>` where `<slug>` is the issue title lowercased, non-alphanumerics replaced by `-`, at most 40 characters.
- Working directory: the workspace root. Run every npm command inside the nested repo after `nvm use`.

## Hard rules

- Never run `gh pr merge`. Never push to `develop` or `main`. Never edit files outside `backend/` and `frontend/`. Never commit in the workspace repo.
- Never guess at an untestable criterion; stop and ask.
- Show the failing test output in the transcript before writing implementation code, and the passing output after. The transcript is what the room sees.
- Every commit ends with the two trailer lines:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
```

## Step 1: Restate the acceptance criteria

```bash
gh issue view <n> --repo $REPO --json title,body,labels
```

Print a numbered checklist copied from the `### Acceptance criteria` section, one line per bullet, and under each the test that will prove it (file and test name). If any criterion cannot be turned into a test (an adjective with no observable behavior, a number nobody stated), print `Untestable criterion: <text>` and `Question: <one sentence the requester can answer>` and stop. Do not continue with a guess.

## Step 2: Architecture change

If the labels include `arch-change`:

1. Decide the affected repo from the request (schema, queue, auth, prompt, proxy: `backend/`; router, client, Caddyfile: `frontend/`).
2. Create the feature branch there (the branch command from Step 5 or Step 6).
3. Read that repo's `.claude/skills/write-adr/SKILL.md` and write the ADR exactly as it says; commit it on the feature branch.
4. Stop with the sentence `ADR written, confirm to continue`.

Resume from Step 3 only when told to continue.

## Step 3: Decide the slice

State which repos change and why, in two sentences. State the smallest slice that satisfies every criterion in the checklist. Target: finished in 25 minutes. If both repos change, the API changes first and the web follows after pulling the contract.

## Step 4: Time box

Print `Start: $(date +%H:%M)`. Check the clock at each step boundary. At 20 minutes after the start, if Step 7 has not begun, stop and report: what is done, what remains, which branch holds the commits, and the exact next command.

## Step 5: API, when affected

```bash
git -C backend fetch origin
git -C backend switch -c feat/<n>-<slug> origin/develop
```

Read `backend/.claude/skills/add-api-endpoint/SKILL.md` and follow it exactly: restate the endpoint, write the failing integration test, run it and show the failure, add or extend the schemas and register them, add the service method with the ownership check, the repository query, the route with `validate` and the envelope, run the tests and show them green, regenerate OpenAPI, add the changelog bullet, add an ADR if an architectural file changed, run docs-check.

Then, in `backend/`:

```bash
cd backend && nvm use
npm test
npm run openapi
npm run docs:check
git add -A && git commit -m "feat: <short title> (#<n>)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
cd ..
```

All three commands must exit 0 before the commit.

## Step 6: Web, when affected

```bash
git -C frontend fetch origin
git -C frontend switch -c feat/<n>-<slug> origin/develop
```

If the contract changed in Step 5:

```bash
cd frontend && scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types && cd ..
```

Read `frontend/.claude/skills/add-frontend-feature/SKILL.md` and follow it exactly: restate the criteria, write the failing component test and show the failure, add or extend the feature folder, add the hook, wire the route and nav, run the tests green, update the README feature list and the changelog, ADR if an architectural file changed, run docs-check.

Then, in `frontend/`:

```bash
cd frontend && nvm use
npm test
npm run docs:check
git add -A && git commit -m "feat: <short title> (#<n>)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
cd ..
```

## Step 7: Push and open the pull requests

For each affected repo (`backend` with `kpnemo/kaizen-tasks-api`, `frontend` with `kpnemo/kaizen-tasks-web`):

```bash
git -C <dir> push -u origin feat/<n>-<slug>
gh pr create --repo kpnemo/<repo> --base develop --head feat/<n>-<slug> \
  --title "feat: <issue title> (#<n>)" --body-file <tempfile>
```

Pull request body:

```markdown
## Issue

Closes kpnemo/kaizen-tasks-assembly-line#<n>

## Acceptance criteria

- [x] <criterion 1>: <test file and name>
- [x] <criterion 2>: ...

## Test evidence

Failing run before the implementation:

```
<the relevant lines of the failing test output>
```

Passing run after:

```
<the relevant lines of the passing test output>
```

Docs-check: `<the last line of npm run docs:check>`
```

Print the pull request URLs. The API pull request is listed first.

## Step 8: Mark the issue

```bash
gh issue edit <n> --repo $REPO --add-label implementing
gh issue comment <n> --repo $REPO --body "Pull requests: <api url> <web url>"
```

## Step 9: Stop

Print the pull request URLs and the sentence `Ready for review and merge`. Do nothing else. Merging, promotion, and closing the issue are done by the facilitator following `docs/runbook.md`.

## Note on issue closing across repos

> **Superseded 2026-09-10.** No pull request carries a closing keyword any more: `develop` is the app repos' default branch, so a keyword
> closes the issue on the merge to staging. Bodies say `Part of ...#<n>`, the facilitator labels `shipped` and closes the issue after the
> production read-back, and `.github/workflows/issue-lifecycle.yml` retires the in-work labels and reopens anything closed too early.
> The paragraph below is kept as the historical record.

`Closes kpnemo/kaizen-tasks-assembly-line#<n>` closes the issue when the pull request merges because the author has write access to the assembly-line repo (verification item L1 in the assembly-line spec). The runbook checks `gh issue view <n> --repo $REPO --json state` after the merge; if the issue is still open, the facilitator runs `gh issue close <n> --repo $REPO --comment "Shipped in <pr url>"`.
````

- [ ] **Step 2: Check the front matter and the never-merge rule**

Run:

```bash
node -e 'const s=require("fs").readFileSync(".claude/skills/implement-issue/SKILL.md","utf8"); const fm=s.split("---")[1]; for (const k of ["name: implement-issue","description:","argument-hint:"]) if(!fm.includes(k)) {console.error("missing "+k); process.exit(1)}; if(!/Never run `gh pr merge`/.test(s)) {console.error("never-merge rule missing"); process.exit(1)}; if(!/Part of kpnemo\/kaizen-tasks-assembly-line#<n>/.test(s)) {console.error("Part of line missing"); process.exit(1)}; if(/\bCloses kpnemo\/kaizen-tasks-assembly-line#<n>`?\s*$/m.test(s)) {console.error("a closing keyword is back in the PR template"); process.exit(1)}; console.log("skill ok")'
grep -c 'gh pr merge' .claude/skills/implement-issue/SKILL.md
```

Expected: `skill ok`; the grep count is `1` (the rule that forbids it, no command that runs it).

- [ ] **Step 3: Dry rehearsal of Steps 1 to 4 against a seed as a file (no repos needed)**

In Claude Code at the workspace root, run `/implement-issue` with the instruction "Treat `seeds/requests/01-mark-all-done.md` as issue 1 and stop after Step 4; do not create branches." Expected transcript: a five-item numbered checklist naming component tests in `frontend/src/features/tasks/`, "Affected repos: frontend only" with the reason that the request explicitly uses the existing PATCH endpoint, the slice statement, and `Start: HH:MM`. The full run (Steps 5 to 9) is exercised at integration once L1-M2 and L2-M3 exist; that run is where L1 is verified.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/implement-issue/SKILL.md
git commit -m "feat: implement-issue skill" -m "$TRAILER"
```

---

### Task 11: The seed-requests skill

**Files:**

- Create: `.claude/skills/seed-requests/SKILL.md`

**Interfaces:**

- Consumes: `scripts/seed-requests.sh` from Task 5.
- Produces: the same issues the script creates, runnable as `/seed-requests` from Claude Code.

- [ ] **Step 1: Write the skill**

Write `.claude/skills/seed-requests/SKILL.md`:

````markdown
---
name: seed-requests
description: File the seeded feature requests in seeds/requests as GitHub issues, skipping titles that already exist
argument-hint: "[--dry-run]"
---

# seed-requests

File every `seeds/requests/*.md` as a `feature-request` issue in `kpnemo/kaizen-tasks-assembly-line`. A seed whose title already exists as an open issue is skipped, so the skill can run again safely. The logic lives in `scripts/seed-requests.sh`; this skill runs it and reports.

Seed format: a front matter block with a `title:` line, then the body in the issue form's section structure (`### Problem`, `### Proposed behavior`, `### Acceptance criteria`, `### Out of scope`, `### Your role`).

## Steps

1. Confirm the target and the login:

```bash
gh auth status
gh repo view kpnemo/kaizen-tasks-assembly-line --json nameWithOwner --jq .nameWithOwner
```

Stop if either fails; report the error.

2. Preview:

```bash
scripts/seed-requests.sh --dry-run
```

Print the `WOULD CREATE` and `SKIP` lines. If the argument was `--dry-run`, stop here.

3. File:

```bash
scripts/seed-requests.sh
```

4. Verify and report:

```bash
gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label feature-request --state open --json number,title \
  --jq '.[] | "#\(.number) \(.title)"'
```

Print the created issue URLs, the skipped titles, and the sentence `Run /triage-requests to score them`.

## Rules

- Never edit or close existing issues. Never file a seed twice.
- Do not change the seed files from this skill; edits to seeds are ordinary commits.
````

- [ ] **Step 2: Check and commit**

Run:

```bash
node -e 'const s=require("fs").readFileSync(".claude/skills/seed-requests/SKILL.md","utf8"); const fm=s.split("---")[1]; for (const k of ["name: seed-requests","description:","argument-hint:"]) if(!fm.includes(k)) {console.error("missing "+k); process.exit(1)}; console.log("skill ok")'
git add .claude/skills/seed-requests/SKILL.md
git commit -m "feat: seed-requests skill" -m "$TRAILER"
```

Expected: `skill ok`, commit succeeds.

---

### Task 12: Branch protection script

**Files:**

- Create: `scripts/protect-branches.sh`

**Interfaces:**

- Consumes: master plan interface "Check names": workflow and job ids `ci` and `promote` in both app repos. `gh` authenticated as `kpnemo` with admin on the repos. Run for real by the CI/CD lane's branch-protection task after `ci` has run once and `promote` exists.
- Produces: protection on `develop` (required check `ci`) and `main` (required checks `ci` and `promote`) with pull request required, zero approvals, no force pushes, no deletions, enforce-admins off.

- [ ] **Step 1: Write the script**

Write `scripts/protect-branches.sh`:

```bash
#!/usr/bin/env bash
# Apply branch protection to develop and main of one app repo.
# Usage: scripts/protect-branches.sh <owner/repo> [--dry-run]
#   develop: required status check ci.  main: required status checks ci and promote.
#   Both: a pull request is required with zero required approvals, no force pushes, no deletions,
#   enforce_admins off so the facilitator can merge as soon as the checks are green.
# Replayable: PUT replaces the whole protection object.
set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "usage: $0 <owner/repo> [--dry-run]" >&2
  exit 1
fi
DRY_RUN=0
if [ "${2:-}" = "--dry-run" ]; then DRY_RUN=1; fi

payload() { # branch
  local contexts='["ci"]'
  if [ "$1" = "main" ]; then contexts='["ci", "promote"]'; fi
  cat <<EOF
{
  "required_status_checks": { "strict": false, "contexts": $contexts },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false,
  "required_conversation_resolution": false
}
EOF
}

for branch in develop main; do
  body="$(payload "$branch")"
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN: gh api -X PUT -H 'Accept: application/vnd.github+json' repos/$REPO/branches/$branch/protection --input - <<'JSON'"
    echo "$body"
    echo "JSON"
    continue
  fi
  printf '%s' "$body" | gh api -X PUT -H "Accept: application/vnd.github+json" \
    "repos/$REPO/branches/$branch/protection" --input - \
    --jq "{branch: \"$branch\", checks: .required_status_checks.contexts, enforce_admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count, force_pushes: .allow_force_pushes.enabled, deletions: .allow_deletions.enabled}"
done
```

- [ ] **Step 2: Dry-run and validate the JSON payloads**

Run:

```bash
chmod +x scripts/protect-branches.sh
bash -n scripts/protect-branches.sh && echo "syntax ok"
scripts/protect-branches.sh kpnemo/kaizen-tasks-api --dry-run | tee "$SCRATCH/protect.txt"
awk '/<<.JSON./{f=1;next} /^JSON$/{f=0} f' "$SCRATCH/protect.txt" | jq -s '.[0].required_status_checks.contexts, .[1].required_status_checks.contexts, .[1].enforce_admins, .[1].required_pull_request_reviews.required_approving_review_count'
scripts/protect-branches.sh; echo "exit=$?"
```

Expected: `syntax ok`; two `DRY-RUN` blocks; jq prints `["ci"]`, `["ci","promote"]`, `false`, `0`; the last call prints the usage line and `exit=1`.

- [ ] **Step 3: Commit**

```bash
git add scripts/protect-branches.sh
git commit -m "feat: branch protection script for the app repos" -m "$TRAILER"
```

---

### Task 13: CI workflow for this repo

**Files:**

- Create: `.github/workflows/ci.yml`

**Interfaces:**

- Consumes: `smoke/` scripts `lint` and `typecheck` (Task 7), `npm run check:issue-form` (Tasks 1 and 3), `rubric/readiness.md` (Task 2), `.nvmrc` (Task 1), both lockfiles.
- Produces: a workflow named `ci` with job id `ci` on pull requests and pushes to `main`. No deploys.

- [ ] **Step 1: Write the workflow**

Write `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [develop, main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - uses: actions/setup-node@v5
        with:
          node-version-file: .nvmrc
          cache: npm
          cache-dependency-path: |
            package-lock.json
            smoke/package-lock.json

      - name: Install root tooling
        run: npm ci

      - name: Install the smoke package
        run: npm ci
        working-directory: smoke

      - name: Install Chromium
        run: npx playwright install --with-deps chromium
        working-directory: smoke

      - name: Lint the smoke package
        run: npm run lint
        working-directory: smoke

      - name: Typecheck the smoke package
        run: npm run typecheck
        working-directory: smoke

      - name: Validate the feature request form
        run: npm run check:issue-form

      - name: Assert the rubric has a version line
        run: grep -E '^version: [0-9]+$' rubric/readiness.md
```

- [ ] **Step 2: Run every step locally in the same order**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp
source "$HOME/.nvm/nvm.sh" && nvm use
node -e 'const y=require("yaml"); const d=y.parse(require("fs").readFileSync(".github/workflows/ci.yml","utf8")); console.log(d.name, Object.keys(d.jobs), d.jobs.ci.steps.length)'
npm ci && (cd smoke && npm ci && npm run lint && npm run typecheck) && npm run check:issue-form && grep -E '^version: [0-9]+$' rubric/readiness.md && echo "ALL CI STEPS PASS LOCALLY"
```

Expected: `ci [ 'ci' ] 9`, then `ALL CI STEPS PASS LOCALLY`. The repo exists on GitHub; the workflow runs there on the first pull request or push to `main` (it does not run on pushes to `develop`, by the spec), and its first green run is recorded by the CI/CD lane.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: lint and typecheck the smoke package, validate the form and the rubric" -m "$TRAILER"
```

---

### Task 14: Railway setup procedure

**Files:**

- Create: `docs/railway-setup.md`

**Interfaces:**

- Consumes: API spec section 2.4 (variable names) and 10.3, web spec section 2.3, 2.4, 8; master plan section 4 "Railway services" and section 5 (Mike's inputs); the `use-railway` skill's command surface (`railway init`, `environment new --duplicate`, `add --database`, `add --service --repo --branch`, `variable set`, `config plan/apply`, `domain`).
- Produces: the procedure of record for the CI/CD lane (`docs/superpowers/plans/2026-09-08-kaizen-tasks-cicd.md`). That lane had executed most of it by the evening of 2026-09-08 (the state block at the top of the document says what is done and what is open), so the document is written to match the live project: the two known web domains are in it, wait-for-CI is the `source.checkSuites` config field with the dashboard as verification only, and `web` carries `PORT=8080`.

- [ ] **Step 1: Write the document**

Write `docs/railway-setup.md`:

```markdown
# Railway setup for Kaizen Tasks

**Scope rule.** The workshop touches exactly one Railway project, the new project `kaizen-tasks`, created by `railway init` from `backend/`. Never `railway link` to, modify, redeploy, or delete any other project in the account. Before any command that changes state, `railway status --json | jq -r .name` must print `kaizen-tasks`. Railway work follows the official `use-railway` skill (`railway setup agent`); its preflight is `railway whoami --json` and `railway status --json`.

**State on 2026-09-08 evening** (master plan section 2, L3-M0 status). Sections 1 to 3, 5, and 6 below have been executed: project `kaizen-tasks` (id `67adb3e0-f2af-4ad3-bbaa-32ec8a53b10e`) exists with `staging` and `production`; each has `Postgres`, `Redis`, `api` from `kpnemo/kaizen-tasks-api`, and `web` from `kpnemo/kaizen-tasks-web` on that environment's branch; the variable set is in place with `PORT=3000` on `api` and `PORT=8080` on `web`; wait-for-CI is on through `source.checkSuites`; healthchecks are set (`/api/v1/health` on `api`, `/version.json` on `web`); the `web` domains are generated. Still open: `ANTHROPIC_API_KEY` is the placeholder `REPLACE_ME_WITH_REAL_KEY` in both environments until Mike replaces it (the paste command is in section 2), and section 4 (IaC apply) waits for L1-M1 and L2-M1. Everything below stays the procedure of record: each step is safe to repeat, and together they rebuild the project if it is ever deleted.

## Target state

| Environment | Services | Source branch | Public domain |
|---|---|---|---|
| `production` | `api`, `web`, `Postgres`, `Redis` | `main` | `web` only: `https://web-production-7ef71.up.railway.app` |
| `staging` | `api`, `web`, `Postgres`, `Redis` | `develop` | `web` only: `https://web-staging-52c0.up.railway.app` |

`api` has no public domain. `web` proxies `/api/*` to `http://api.railway.internal:3000`; `api` pins `PORT=3000` and `web` pins `PORT=8080`. Wait-for-CI (`source.checkSuites: true`) is on for `api` and `web` in both environments so a red check suite never deploys.

## 1. Create the project

From `webapp/backend/`:

```bash
railway whoami --json
railway init --name kaizen-tasks --json
railway status --json | jq -r '.name, .environment'
railway list --json | jq -r '.[].name'
```

`init` creates the project with the default `production` environment and links the directory to it. `list` must show `kaizen-tasks` alongside the pre-existing projects, none of which change.

## 2. Build production first

Still linked to `production`:

```bash
railway add --database postgres --json      # service name Postgres
railway add --database redis --json         # service name Redis
railway add --service api --repo kpnemo/kaizen-tasks-api --branch main --json
railway add --service web --repo kpnemo/kaizen-tasks-web --branch main --json
railway service list --json | jq -r '.[].name'
```

If `railway add --repo` reports that the repo is not visible, Mike installs or extends the Railway GitHub App for `kpnemo/kaizen-tasks-api` and `kpnemo/kaizen-tasks-web` (Railway dashboard, Account settings, GitHub, Configure), then the command is repeated. Always pass `--json` to `railway add`; never retry blind, list services first.

Variables on `api` (non-secret; use `--skip-deploys` until the last one so the service does not redeploy for every change):

```bash
railway variable set \
  'DATABASE_URL=${{Postgres.DATABASE_URL}}' 'REDIS_URL=${{Redis.REDIS_URL}}' \
  PORT=3000 APP_ENV=production WORKER_ENABLED=true \
  AI_MODEL=claude-sonnet-5 AI_RATE_LIMIT_PER_HOUR=20 AI_GLOBAL_LIMIT_PER_HOUR=300 \
  AI_ENABLED=true AI_STALE_MINUTES=10 SEED_DEMO_USER=true LOG_LEVEL=info \
  --service api --environment production --skip-deploys
```

Variables on `web`: `PORT=8080` (Caddy binds `:{$PORT}`; a fixed value makes the domain's target port deterministic).

```bash
railway variable set PORT=8080 --service web --environment production --skip-deploys
```

Secrets on `api`, pasted by Mike in his own terminal so they never pass through an agent transcript. `JWT_SECRET` and `ADMIN_TOKEN` are at least 32 characters; `openssl rand -hex 32` produces 64.

```bash
openssl rand -hex 32 | tr -d '\n' | railway variable set JWT_SECRET --stdin --service api --environment production --skip-deploys
openssl rand -hex 32 | tr -d '\n' | railway variable set ADMIN_TOKEN --stdin --service api --environment production --skip-deploys
printf '%s' '<demo password>' | railway variable set SEED_DEMO_PASSWORD --stdin --service api --environment production --skip-deploys
printf '%s' '<anthropic key>'  | railway variable set ANTHROPIC_API_KEY --stdin --service api --environment production
```

Verify the names (values are not printed):

```bash
railway variable list --service api --environment production --json | jq -r 'keys[]' | sort
```

Expected names: `ADMIN_TOKEN AI_ENABLED AI_GLOBAL_LIMIT_PER_HOUR AI_MODEL AI_RATE_LIMIT_PER_HOUR AI_STALE_MINUTES ANTHROPIC_API_KEY APP_ENV DATABASE_URL JWT_SECRET LOG_LEVEL PORT REDIS_URL SEED_DEMO_PASSWORD SEED_DEMO_USER WORKER_ENABLED` plus Railway's own `RAILWAY_*` entries.

Then confirm the key is real, without printing it:

```bash
railway variable list --service api --environment production --json | jq -r '.ANTHROPIC_API_KEY | startswith("REPLACE_ME")'
```

Expected `false`. On 2026-09-08 it prints `true` in both environments: the placeholder `REPLACE_ME_WITH_REAL_KEY` is set and Mike replaces it with the `ANTHROPIC_API_KEY` command above; until then every AI breakdown on Railway fails.

`GITHUB_TOKEN` and `GITHUB_REPO=kpnemo/kaizen-tasks-assembly-line` are added only if the optional feature-request page ships.

## 3. Create staging by duplicating production

```bash
railway environment new staging --duplicate production
railway environment link staging
railway status --json | jq -r '.name, .environment'
railway service list --json | jq -r '.[].name'
```

Duplication copies every service, its configuration, and its variables; the databases are new instances with their own volumes and credentials, and the reference variables `${{Postgres.DATABASE_URL}}` resolve to the staging databases. Then override what differs:

```bash
railway environment edit --service-config api source.branch develop --environment staging -m "staging tracks develop"
railway environment edit --service-config web source.branch develop --environment staging -m "staging tracks develop"
railway variable set APP_ENV=staging --service api --environment staging --skip-deploys
railway environment config --environment staging --json | jq '.services[] | select(.name=="api" or .name=="web") | {name, branch: .source.branch}'
```

Secrets for staging are pasted again by Mike with the same four commands as section 2 with `--environment staging`; staging gets its own `JWT_SECRET` and `ADMIN_TOKEN`, and the same Anthropic key unless Mike prefers a second one.

## 4. Apply each repo's `.railway/railway.ts` per environment

After L1-M1 and L2-M1 (the files exist and are pushed). The IaC file declares the service's build, start, healthcheck, and source branch chosen from the environment name. `railway config` commands act on the linked environment and cannot take `--environment`, so link, plan, review, apply, and repeat.

From `webapp/backend/`:

```bash
railway environment link staging
railway config plan --verbose
# review: only the api service changes; "0 to destroy" is required. If the plan destroys anything, stop.
railway config apply --yes        # only after Mike has read that exact plan and said "apply"
railway environment link production
railway config plan --verbose
railway config apply --yes
```

From `webapp/frontend/` (link the directory first):

```bash
railway link --project kaizen-tasks --environment staging
railway config plan --verbose
railway config apply --yes
railway environment link production
railway config plan --verbose
railway config apply --yes
```

`--yes` only stands in for the interactive confirmation in a non-interactive shell, and only after Mike has read the exact plan. Never pass `--confirm-destructive`; a plan that destroys anything is not applied. After each apply, re-run the wait-for-CI read-back in section 5: the IaC file does not carry `source.checkSuites`, and the field must still read `true` afterwards.

## 5. Wait-for-CI

Wait-for-CI is the per-environment service config field `source.checkSuites` (the `use-railway` skill lists it under Source: `source.checkSuites` (boolean)). It is not declared in `.railway/railway.ts`, so it is set with `railway environment edit` and read back with `railway environment config`. It has been on for `api` and `web` in both environments since 2026-09-08 (master plan section 4, "Wait-for-CI"); the commands below are the procedure of record and are safe to repeat.

```bash
for env in staging production; do
  railway environment edit --service-config api source.checkSuites true --environment $env -m "wait for CI"
  railway environment edit --service-config web source.checkSuites true --environment $env -m "wait for CI"
done
for env in staging production; do
  echo "== $env"
  railway environment config --environment $env --json | jq -c '[.. | objects | select(has("source")) | .source.checkSuites]'
done
```

Expected per environment: `[true,true]` (or `[true,true,null,null]` when the databases are listed too). Re-run the read-back after every `railway config apply` in section 4; if an apply ever resets the field, run the loop above again.

Dashboard, for verification only, never the way the field is set (Mike): project `kaizen-tasks`, environment selector top-left, service `api`, Settings, Source, the toggle named "Wait for CI" (Railway may label it "Check Suites") reads on; the same for `web`; the same in the other environment. The runbook records the exact label seen.

Verification (item V4 in the API spec): push a trivial commit to `develop` in either app repo; `railway deployment list --service api --environment staging --limit 1 --json` shows status `WAITING` while GitHub Actions runs, then `BUILDING`, `DEPLOYING`, `SUCCESS`.

## 6. Public domains for `web`

Generated on 2026-09-08: staging `https://web-staging-52c0.up.railway.app`, production `https://web-production-7ef71.up.railway.app`. `api` never gets a domain. The procedure, for the record; read the existing domains with `railway domain list` before generating anything:

```bash
railway domain list --service web --environment staging --json
railway domain list --service web --environment production --json
railway domain --service web --environment staging --port 8080 --json       # only when the list above is empty
railway domain --service web --environment production --port 8080 --json    # only when the list above is empty
```

Both domains are recorded in `docs/runbook.md` (section "Fixed facts") and are the `SMOKE_BASE_URL` of the app repos' `promote` workflows.

## 7. Verify

```bash
STAGING=https://web-staging-52c0.up.railway.app
curl -fsS "$STAGING/version.json" | jq .
curl -fsS "$STAGING/api/v1/health" | jq .
```

Expected: `version.json` shows `{ "commit": "<sha>", "builtAt": "<iso>" }` where `<sha>` is `git -C frontend rev-parse origin/develop`; health shows `{ "data": { "status": "ok", "commit": "<api sha>", "env": "staging", "checks": { "db": "ok", "redis": "ok" } } }`, proving the proxy and private networking. Repeat with the production domain after the first `main` deploy.

## Changing a variable during the session

`railway variable set AI_GLOBAL_LIMIT_PER_HOUR=600 --service api --environment production` triggers a redeploy of `api` (about two minutes). `AI_ENABLED=false` pauses the assistant the same way. Dashboard path: service `api`, Variables tab, edit, Deploy.

## Rollback

Dashboard: service, Deployments tab, the previous successful deployment, its menu, Redeploy. CLI equivalent for the latest deployment: `railway redeploy --service api --environment production --yes`. Safe because migrations are additive only (API ADR 0004): the previous application runs against the already-migrated database.
```

- [ ] **Step 2: Check that every variable name in the API spec section 2.4 appears**

Run:

```bash
for v in DATABASE_URL REDIS_URL JWT_SECRET ANTHROPIC_API_KEY AI_MODEL AI_RATE_LIMIT_PER_HOUR AI_GLOBAL_LIMIT_PER_HOUR AI_ENABLED AI_STALE_MINUTES ADMIN_TOKEN APP_ENV PORT WORKER_ENABLED SEED_DEMO_USER SEED_DEMO_PASSWORD LOG_LEVEL GITHUB_TOKEN GITHUB_REPO; do grep -q "$v" docs/railway-setup.md || echo "MISSING $v"; done; echo "variable check done"
grep -c 'kaizen-tasks' docs/railway-setup.md
grep -c 'source.checkSuites' docs/railway-setup.md
grep -c 'web-staging-52c0.up.railway.app\|web-production-7ef71.up.railway.app' docs/railway-setup.md
grep -n -i 'dashboard' docs/railway-setup.md
```

Expected: no `MISSING` lines, `variable check done`, a `kaizen-tasks` count above 10, a `source.checkSuites` count of at least 4, a domain count of at least 4, and every `dashboard` line is about verification, the GitHub App, a variable change, or rollback; none says wait-for-CI is switched on there.

- [ ] **Step 3: Commit**

```bash
npx prettier --write docs/railway-setup.md
git add docs/railway-setup.md
git commit -m "docs: Railway setup procedure for the kaizen-tasks project" -m "$TRAILER"
```

---

### Task 15: The facilitator runbook

**Files:**

- Create: `docs/runbook.md`

**Interfaces:**

- Consumes: master plan interfaces "Health", "Web version", "Seed reset" (`POST /api/v1/admin/seed-reset` with header `x-admin-token`, demo user `demo@kaizen.local`); the smoke package (Task 7); the skills (Tasks 9 to 11); `docs/railway-setup.md` (Task 14); the product-skills repo layout (`templates/part3/facilitator-sheet.md`).
- Produces: the runbook. The "Fixed facts" table carries the two web domains, known since 2026-09-08; the only row left open, by design, is the rehearsal timings.

- [ ] **Step 1: Write the runbook**

Write `docs/runbook.md`:

```markdown
# Facilitator runbook: Kaizen Tasks workshop

Three hours: Part 1 live run (75 minutes), Part 2 hands-on (60 minutes), Part 3 planning (45 minutes). Part 1 has no fallback pull request and no recording; the rehearsal is the safety net and the buffer is slack, not a substitute.

## Fixed facts

| Fact | Value |
|---|---|
| Production web | https://web-production-7ef71.up.railway.app |
| Staging web | https://web-staging-52c0.up.railway.app |
| Issue form | https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/new?template=feature-request.yml |
| Triage board | the pinned issue in https://github.com/kpnemo/kaizen-tasks-assembly-line/issues |
| Demo user | `demo@kaizen.local`, password is the `SEED_DEMO_PASSWORD` Railway variable |
| Product skills | `git clone https://github.com/kpnemo/kaizen-tasks-product-skills.git` |
| Rehearsal timings | filled after the rehearsal (section 8) |

Terminals to have open before the session, all at `webapp/`: T1 Claude Code (`claude`), T2 a shell for `gh` and `curl`, T3 `git -C backend log --oneline -3` and the web equivalent for showing SHAs. Browser tabs: production web, staging web, the assembly-line issues page, the two app repos' Actions pages, the Railway project.

## 1. Pre-session checklist

### T minus one day

- [ ] Keys and variables present in both environments: `railway variable list --service api --environment production --json | jq -r 'keys[]'` and the same for `staging` list every name in `docs/railway-setup.md` section 2.
- [ ] The Anthropic key is real, not the placeholder: `railway variable list --service api --environment production --json | jq -r '.ANTHROPIC_API_KEY | startswith("REPLACE_ME")'` prints `false`, and the same for `staging` (the value itself is never printed).
- [ ] Seeds filed: `gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label feature-request --state open` shows the four seed titles (run `/seed-requests` if not).
- [ ] Triage board pinned: `gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label triage-board --json number,isPinned` shows `"isPinned": true`.
- [ ] Triage run today: `/triage-requests`; the board shows 01 first, 04 second, 03 last with `arch-change`.
- [ ] Staging and production healthy with the expected SHAs:

```bash
for env in staging production; do
  case $env in staging) url=https://web-staging-52c0.up.railway.app; ref=origin/develop ;; production) url=https://web-production-7ef71.up.railway.app; ref=origin/main ;; esac
  echo "== $env"; echo "web  $(curl -fsS $url/version.json | jq -r .commit)  expected $(git -C frontend rev-parse $ref)"
  echo "api  $(curl -fsS $url/api/v1/health | jq -r .data.commit)  expected $(git -C backend rev-parse $ref)"
done
```

- [ ] Rehearsal completed within the last three days (section 8 has a dated entry).
- [ ] Anthropic budget: the rehearsal's cost per breakdown times 20 attendees times 3 tasks fits the session budget; set `AI_GLOBAL_LIMIT_PER_HOUR` accordingly (next item).

### T minus one hour

- [ ] Raise the session budget on production: `railway variable set AI_GLOBAL_LIMIT_PER_HOUR=600 --service api --environment production` (redeploys `api`; wait for `SUCCESS` in `railway deployment list --service api --environment production --limit 1 --json`).
- [ ] Reset the demo user on production, in Mike's terminal with his token: `curl -fsS -X POST https://web-production-7ef71.up.railway.app/api/v1/admin/seed-reset -H "x-admin-token: $ADMIN_TOKEN" | jq .` prints `{ "data": { "demoUserId": "<uuid>" } }`.
- [ ] Smoke green against both environments in the last hour: `cd smoke && SMOKE_BASE_URL=https://web-staging-52c0.up.railway.app npm test && SMOKE_BASE_URL=https://web-production-7ef71.up.railway.app npm test`.
- [ ] Log in as the demo user in the production tab; the tour tasks are there.
- [ ] `gh auth status` and `railway whoami` succeed in T2. Claude Code open at `webapp/` in T1 with `/hooks` showing the Stop and PostToolUse hooks.
- [ ] Projector font size checked: terminal at 18pt or larger, browser zoom 125%.

## 2. Part 1, minute by minute (75 minutes)

| Minute | Segment | Facilitator | Room |
|---|---|---|---|
| 0 to 8 | Framing and app tour | State the goal: a request from this room reaches production in the next hour with tests and gates, no slides. Open production as the demo user. Show a task with accepted AI steps, one with pending suggestions and its rationale on hover, one failed with retry. Create a task live and let the thinking chip resolve. | Watches |
| 8 to 20 | The room files requests | Put the issue form URL on screen. Walk the four fields; say that acceptance criteria decide the ranking. Show one seeded request as an example of a clear one. | Registers on production, files requests through the form |
| 20 to 28 | Triage on screen | In T1: `/triage-requests`. Narrate the rubric while it runs. Open the Triage board. Read the top three and the recommended one. Open one low-clarity issue and read the questions the skill posted. | Watches; the authors of unclear requests answer the questions in the issue |
| 28 to 53 | Implement on screen | In T1: `/implement-issue <top request number>`. Narrate the three moments (section 3): the failing test, the docs-check gate, the pull request. Keep the room on what the transcript shows, not on the code. | Watches; questions held to the buffer |
| 53 to 65 | Ship | Open the pull request; checks green; merge to `develop` (Mike). Show Railway staging deployment `WAITING` then building. Show `/version.json` or health on staging with the new SHA. Open the `develop` to `main` pull request; `promote` runs the smoke against staging; show the Playwright steps in the Actions log. Merge to `main`. Show production with the new SHA and the feature. | Watches the pipeline |
| 65 to 75 | Buffer | Absorb CI, provider, or Railway slowness. Cutoff rule: at minute 65 state which live steps are still incomplete and move to Part 2; whatever finishes later is shown at the start of Part 2. | Questions |

Commands used in the Ship segment, in order:

```bash
gh pr view <pr url> --json statusCheckRollup --jq '.statusCheckRollup[] | "\(.name) \(.conclusion)"'
gh pr merge <pr url> --squash --delete-branch                      # Mike, after checks are green
railway deployment list --service web --environment staging --limit 1 --json | jq '.[0].status'
curl -fsS https://web-staging-52c0.up.railway.app/version.json | jq -r .commit
gh pr create --repo kpnemo/kaizen-tasks-web --base main --head develop --title "release: <date>" --body "Promote develop to main"
gh pr checks <promote pr url> --watch
gh pr merge <promote pr url> --merge                                # Mike
curl -fsS https://web-production-7ef71.up.railway.app/version.json | jq -r .commit
gh issue view <n> --repo kpnemo/kaizen-tasks-assembly-line --json state --jq .state   # expect CLOSED (verification L1)
gh issue edit <n> --repo kpnemo/kaizen-tasks-assembly-line --add-label shipped --remove-label implementing
```

If the issue is still `OPEN` after the merge, run `gh issue close <n> --repo kpnemo/kaizen-tasks-assembly-line --comment "Shipped in <pr url>"` and note it in section 8 so the implement skill gains that step. When the API changed too, merge and promote the API pull request first, then the web one.

## 3. What to say at each gate

**The failing test.** "Nothing was written yet. The agent wrote down what done means as a test, ran it, and it fails. That failure is the specification. When it passes, the acceptance criterion you wrote in the form is met, not approximately, exactly."

**The docs-check gate.** "The agent tried to finish and the harness said no. Look at the message: the changelog is missing an entry, or the API contract was not regenerated. This is the same check CI runs, so a shortcut here fails the pull request there. Documentation is part of the change, not a follow-up."

**The pull request.** "Here is the diff, the tests, the evidence, and the link to your issue. The agent stops here. A person merges. In this room that person is me, and I only merge because the checks are green."

**CI on develop.** "Actions runs lint, types, tests against a real database, the docs check, the build. If any fails, nothing deploys."

**Railway waits for CI.** "Railway has already seen the commit. It is holding the deployment until GitHub says the checks passed. A red check never reaches staging."

**Staging health.** "`/version.json` and `/api/v1/health` report the commit hash. The pipeline does not guess whether the build is live; it reads the hash."

**The promote check.** "A browser is registering a user, creating a task, waiting for the assistant, accepting a step, logging out, against staging, right now. Only if that passes may `main` merge."

**Production.** "The same hash, on the production URL. Idea to production, with tests and gates, in under an hour."

## 4. Failure page

| Symptom | Do this | Say this |
|---|---|---|
| API key rejected (tasks stay skipped with "assistant paused" or the breakdown fails with an authentication message in `railway logs --service api --environment production --lines 100 --json`) | In Mike's terminal: `printf '%s' '<new key>' \| railway variable set ANTHROPIC_API_KEY --stdin --service api --environment production`; wait for the redeploy; create a task to prove it. | "The provider rejected the key. Keys live only in Railway variables; I am swapping it and the service redeploys in about two minutes." |
| GitHub Actions slow or queued | Open the Actions tab, show the queue; narrate the gates from section 3 in the meantime; use the buffer. | "This is the queue you would see on a busy afternoon; the gate is the same, the wait is not ours to skip." |
| Railway deployment stuck (`BUILDING` or `DEPLOYING` beyond five minutes) | `railway logs --service <svc> --environment staging --build --lines 200 --json` on screen; if the build is wedged, `railway redeploy --service <svc> --environment staging --yes`; keep the room on the log. | "Here is the build log. I am asking Railway to build again; nothing about the code changes." |
| `implement-issue` stalled or the 20-minute mark passed | Say `stop` in T1; the skill reports what is done; open a pull request with what exists (`gh pr create --draft`); show the branch and the tests that pass. | "Time-boxing is a rule, not a failure. What exists is on a branch with its tests; the rest is a second, smaller request." |
| Staging smoke red in `promote` | Download the `smoke-results` artifact, `npx playwright show-trace <trace.zip>`, show the failing step. Do not promote. | "The gate did its job. This is exactly the bug you do not want in production, caught by a browser, not by a person. We fix, we rerun." |
| Rate limit reached (`hourly limit reached` chips) | `railway variable set AI_GLOBAL_LIMIT_PER_HOUR=1200 --service api --environment production`; two-minute redeploy. | "The session budget is a variable, not a deploy." |
| Cutoff at minute 65 | State what is incomplete, move on, show the rest at the start of Part 2. | "The pipeline keeps running without us." |

## 5. Rollback

Dashboard: open the project `kaizen-tasks`, select the environment, click the service, Deployments tab, find the previous deployment with a green check, open its menu, Redeploy. It is live within about a minute; `/version.json` or health shows the previous commit.

Why it is safe: migrations are additive only (API ADR 0004), so the previous application runs against the already-migrated database, and API changes are additive, so the previous web build keeps working against a newer API. Rollback never touches data.

## 6. Part 2 handoff (60 minutes)

On screen:

```bash
git clone https://github.com/kpnemo/kaizen-tasks-product-skills.git
cd kaizen-tasks-product-skills
claude
```

then `/refine-request` with the issue number each attendee filed in Part 1. The skill interviews them against the same rubric the triage used and rewrites their request; it offers to edit their own issue with `gh` when available. Mike re-runs `/triage-requests` at the end of Part 2 to show the before and after scores on the board.

## 7. Part 3 handoff (45 minutes)

Paper only. Print `templates/part3/agentic-layer-canvas.pdf` and `templates/part3/plan-30-60-90.pdf` from the product-skills repo, one per group of three or four. Follow `templates/part3/facilitator-sheet.md`: 5 framing, 15 canvas, 10 prioritize, 10 plan, 5 share. Close on the plan belonging to the team; no ongoing commitment is promised.

## 8. Rehearsal log

One entry per rehearsal, newest first. Record wall-clock minutes per segment against the table in section 2, what broke, and the change made to this runbook.

| Date | Triage | Implement | Ship | Total | Notes |
|---|---|---|---|---|---|
| (filled at the rehearsal) | | | | | |
```

- [ ] **Step 2: Check the runbook covers every spec section**

Run:

```bash
for h in "Pre-session checklist" "minute by minute" "What to say at each gate" "Failure page" "Rollback" "Part 2 handoff" "Part 3 handoff"; do grep -q "$h" docs/runbook.md || echo "MISSING $h"; done; echo "sections checked"
grep -c '^| [0-9]* to [0-9]* |' docs/runbook.md
grep -n 'seed-reset\|x-admin-token' docs/runbook.md | head -3
grep -c 'web-staging-52c0.up.railway.app\|web-production-7ef71.up.railway.app' docs/runbook.md
grep -c '<[a-z]* web domain>' docs/runbook.md
```

Expected: `sections checked` with no `MISSING`; `6` segment rows; the seed-reset curl found; at least `8` lines carrying a real domain; `0` domain placeholders.

- [ ] **Step 3: Commit**

```bash
npx prettier --write docs/runbook.md
git add docs/runbook.md
git commit -m "docs: facilitator runbook with minute table, gates, failure page, rollback" -m "$TRAILER"
```

---

### Task 16: L4-M2 acceptance: smoke against staging, skills in dry-run against the filed seeds

**Files:**

- Modify: `docs/runbook.md` (section 8 rehearsal log entry only if a rehearsal happens now; otherwise untouched), `triage/<date>.md` (created by the dry run, not committed unless Mike wants the first report kept).

**Interfaces:**

- Consumes: L3-M1 (a staging web domain serving both apps), L3 Task 3 (labels created and the board pinned), the seeds filed by `/seed-requests` (CI/CD lane or Mike).
- Produces: the evidence that closes L4-M2 per the master plan: `smoke/` passes against staging; both skills run end to end against the seeds in dry-run; the runbook and railway-setup docs are complete.

- [ ] **Step 1: Smoke against staging**

Run:

```bash
cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/smoke
source "$HOME/.nvm/nvm.sh" && nvm use
SMOKE_BASE_URL=https://web-staging-52c0.up.railway.app npm test
```

Expected: `1 passed`, with the six steps listed by the `list` reporter. If step 4 times out, rerun with `SMOKE_AI_TIMEOUT_MS=180000` once and report the observed duration so the promote workflows can pick the value. If a step fails on a selector, the selector contract in `smoke/README.md` is the reference: send the failing step and the trace to the frontend lane; do not weaken the test.

- [ ] **Step 2: Seeds and triage in dry-run**

In Claude Code at the workspace root:

```
/seed-requests --dry-run
/triage-requests --dry-run
```

Expected: the seed preview lists four `SKIP` lines (already filed) or `WOULD CREATE` lines; the triage dry run prints `Rubric version: 1`, writes `triage/<today>.md` with the four seeds (plus any room requests filed during rehearsal) ranked 01, 04, then 02, then 03 last with `arch-change`, and prints per issue the labels that would be set and whether the comment would be created or edited.

- [ ] **Step 3: One real triage to seed the board (Mike's call)**

If Mike agrees, run `/triage-requests` for real. Expected: `triage/<today>.md` committed as `triage: <today>`, labels applied, one comment per issue, the board rewritten. Run it a second time and confirm with `gh api repos/kpnemo/kaizen-tasks-assembly-line/issues/<n>/comments --jq 'map(select(.body | contains("<!-- kaizen-triage -->"))) | length'` that each issue still has exactly one triage comment (idempotency).

- [ ] **Step 4: Report L4-M2**

Push `develop` (`git push origin develop`) and report to the orchestrator: smoke duration and result, the triage ranking, confirmation that the domains in `docs/runbook.md` still match `railway domain list --service web --environment <env> --json` for both environments, and the verification status: L2 verified in Task 8; L1 and L3 pending the first merged seed and the first `promote` run (CI/CD plan Tasks 13 and 12).

---

## Verification items from the spec, mapped

| Item | Proven by | Fallback if it fails |
|---|---|---|
| L1 `Closes owner/repo#n` closes an issue in another repo on merge | Task 10 puts the line in every PR body; the runbook (Task 15, section 2) checks `gh issue view <n> --json state` after the first merged seed at integration (CI/CD plan Task 13) | Task 15's runbook step runs `gh issue close <n>`; then add that command to Task 10's Step 8 |
| L2 A root Stop hook can run a nested repo's script with the nested repo as working directory | Task 8, Step 3 fixture sequence: the nested script prints `cwd=.../backend`, its exit 2 blocks the root, and its escape-hatch exit 1 passes through as non-blocking | The nested docs-check scripts accept `--repo <path>` (a change in L1 and L2), and `docs-check-all.sh` passes it |
| L3 `actions/checkout` of a public repo into a subfolder needs no token | Task 7's README documents the checkout; the first `promote` run in the app repos (CI/CD plan Task 12) proves it | Add `token: ${{ github.token }}` to the checkout step in both promote workflows |

## Self-review

**Spec coverage.** Section 2 repo shape: every listed path has a task (`.claude/settings.json` and skills in 8 to 11; `.github` in 3 and 13; `CLAUDE.md`, `README.md`, `.gitignore` in 1; `docs/` in 14 and 15; `rubric/` in 2; `seeds/` in 5; `smoke/` in 7; `triage/` in 9; every script in 4, 5, 6, 8, 12). Section 3 workspace: Task 1 and Task 6. Section 4 intake: Tasks 3 and 4 (form fields in order and required flags validated by `check-issue-form.mjs`; labels with colors; board created and pinned). Section 5 rubric: Task 2 with all anchors, the test, the formula, the procedure with the fixed shape, the question patterns, `version: 1`. Section 6 skills: Tasks 9, 10, 11 with the exact steps, score-only and dry-run modes, the never-merge rule. Section 7 hooks: Task 8. Section 8 smoke: Task 7 with the six steps, the three env vars, Chromium only, traces on failure, the calling snippet. Section 9: seeds with the intended scoring (Task 5), `protect-branches.sh` with the exact payload (Task 12), `ci.yml` (Task 13). Section 10: Task 14. Section 11: Task 15 with all six sections. Section 12: the table above. Section 13 out of scope: no task touches application code, merges, other Railway projects, slides, or the product skills.

**Placeholder scan.** Angle-bracket fields remain only where a value does not exist until runtime: issue numbers and SHAs inside skill and runbook instructions, the secret values Mike pastes, and the rehearsal timings. The two web domains are known (2026-09-08) and written out in Tasks 7, 14, 15, and 16. Every script, YAML, JSON, and markdown file is written in full.

**Type and name consistency.** Env names `SMOKE_BASE_URL`, `SMOKE_AI_TIMEOUT_MS`, `SMOKE_FAST` match between `playwright.config.ts`, `smoke.spec.ts`, the README, the runbook, and the master plan. Label names match between `setup-labels.sh`, the triage skill, the runbook, and the master plan. Markers `<!-- kaizen-triage -->` and `<!-- kaizen-triage-board -->` match between Task 4, Task 9, and Task 16. `KAIZEN_WORKSPACE_ROOT` is the override in both hook scripts. The form headings in Task 3 are the seed headings in Task 5 and the section the skills read in Tasks 9 and 10. `npm run check:issue-form` and `npm run check:rubric` are defined in Task 1 and used in Tasks 3, 2, and 13. The branch name pattern `feat/<n>-<slug>` is the same in Steps 2, 5, 6, and 7 of the implement skill. The docs-check exit contract (0 pass, 2 block, any other non-zero the escape hatch) is the same in the master plan interface, Task 8's root script, and its fixture.

**Cross-lane assumptions not in the master plan's section 4.** The smoke selector contract (Task 7 README) and the web service `PORT=8080` (Task 14). Both are reported to the orchestrator as additions to section 4.
