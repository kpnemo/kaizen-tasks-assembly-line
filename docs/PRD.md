# PRD: Kaizen Tasks and the Product Assembly Line Workshop

| Field        | Value                                                                                                                             |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| Owner        | Mike Bogdanovsky, AI Transformation and Enablement, P&T                                                                           |
| Status       | Draft v0.1 for owner review                                                                                                       |
| Written      | 2026-09-08                                                                                                                        |
| Session date | Within two weeks of writing (target on or before 2026-09-22), one rehearsal before                                                |
| Consumers    | Mike (review), then the `superpowers:brainstorming` skill to produce design specs, then `superpowers:writing-plans` and execution |

## 0. How to use this document

This PRD records what we are building and why, and the decisions already taken. It deliberately does not contain designs (data models, file layouts, prompts, exact hook scripts). Those belong to the spec step.

Suggested handoff to the brainstorming skill:

1. Feed this whole file as context.
2. Ask for one design spec per repository, in this order, each spec referencing this PRD by section number: `kaizen-tasks-api` (section 5, 6, 7), `kaizen-tasks-web` (section 5, 6.3, 7), `kaizen-tasks-assembly-line` (section 8, 11), `nice-product-skills` (section 9, 10).
3. Tell brainstorming that everything in the Decision Log (Appendix A) is settled and should not be reopened. It should spend its questions on the items in section 13 (Open questions) and on design choices this PRD leaves to the spec.
4. Each spec goes to writing-plans, and execution runs in the order above, because the web app consumes the API's generated OpenAPI contract and the assembly-line harness needs both apps to exist.

## 1. Background and problem

Mike leads AI transformation and enablement for a Products and Technology organization of about 5,000 engineers, product managers, and DevOps staff. R&D has already moved to an agentic delivery cycle: Claude Code with skills, agents, hooks, TDD, and CI/CD. Product management has not been connected to that cycle yet. PMs still write requests the old way, do not see how their requests are triaged and executed, and have not built any agentic harness for their own work.

The problem to solve in one workshop session:

- PMs do not understand, from experience, how engineering now works. They need to see a request go from idea to production in front of them, with quality gates, not slides.
- PMs' requests are not written for agentic execution. They lack acceptance criteria, clarity, and scope discipline. The engineering harness will expose that in public.
- PMs have Claude Code, Claude Desktop, and Cowork, but no harness of their own. They need one concrete skill they can reuse the next day, and a plan for building more.

## 2. Goals and success criteria

Workshop goals:

- G1. Every attendee sees a feature request they or a colleague wrote get ranked, implemented with TDD, tested in CI, deployed to staging, and promoted to production inside the session.
- G2. Every attendee leaves with a request-refinement skill installed and used once on their own request.
- G3. The room leaves with a prioritized 30/60/90 plan for a product agentic layer, with named owners.

Success criteria for the artifacts:

- S1. The Part 1 flow (file request, rank, implement, PR, CI, merge, staging, smoke, promote, production) completes end to end in a rehearsal in under 40 minutes of wall-clock time for a small, clear request.
- S2. All three application and harness repos have green CI, deployed staging and production URLs, and complete docs on the day.
- S3. The docs-freshness hook and CI drift check block a change that touches the API without updating the OpenAPI spec, verified once in rehearsal.
- S4. A PM with no prior setup runs the request-refinement skill in under 10 minutes including clone.

## 3. Audience and session constraints

| Constraint           | Value                                                                                                             |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Attendees            | 10 to 20 PMs and product leads, mixed hands-on                                                                    |
| Tools attendees have | Claude Code, Claude Desktop, Cowork, GitHub accounts (public repos remove invite friction)                        |
| Format               | One session, 3 hours                                                                                              |
| Split                | Part 1: 75 min. Part 2: 60 min. Part 3: 45 min                                                                    |
| Part 1 mode          | Live run, no fallback PR, no recording. One full rehearsal before the day is the safety net                       |
| Part 2 mode          | Hands-on in Claude Code, skills also usable in Cowork                                                             |
| Part 3 mode          | Facilitated, paper canvas, no laptops required                                                                    |
| Distribution         | Company Claude marketplace and Enterprise connectors exist. Mentioned in the session, not demonstrated            |
| Hosting              | Mike's personal GitHub (public repos) and personal Railway account                                                |
| Secrets              | Anthropic API key lives only in Railway variables and a git-ignored local `.env`. Mike pastes it. Never committed |

## 4. Scope overview

Four repositories, all TypeScript, all public under Mike's GitHub account, all prefixed `kaizen-tasks-`. Layout on disk: the workshop root is a plain folder; `webapp/` is the assembly-line repo and contains `backend/` and `frontend/` as independent, git-ignored nested repos; `product-skills/` sits at the root.

| Repo                          | Purpose                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `kaizen-tasks-api`            | Express API, Postgres, Redis and BullMQ, Anthropic SDK agent. Own `.claude/` harness                                     |
| `kaizen-tasks-web`            | React web app consuming the API's generated OpenAPI contract. Own `.claude/` harness                                     |
| `kaizen-tasks-assembly-line`  | Cross-repo harness: triage and implement agents, workspace layout, issue templates, seeded requests, facilitator runbook |
| `kaizen-tasks-product-skills` | Part 2 product skills packaged as a Claude Code plugin, Part 3 canvas and plan templates, synthetic data                 |

Out of scope: see section 12.

## 5. Product requirements: Kaizen Tasks

Kaizen Tasks is a personal task manager where every big task is broken into small doable steps by an AI assistant, and the human stays in control of what is accepted.

### 5.1 Users and authentication

- R1. Open self-registration with email and password. No email verification. No password reset.
- R2. Login returns a short-lived JWT access token. A refresh token is stored server-side in Redis and delivered as an httpOnly cookie. Logout revokes the refresh token.
- R3. All task, subtask, and tag data is private to the owning user.
- R4. One seeded demo user exists in every environment with a realistic set of tasks, subtasks, and tags for the facilitator's tour. Seed is idempotent.

### 5.2 Tasks, subtasks, and tags

- R5. A task has a title, optional description, status (todo, in progress, done), created and updated timestamps, and an owner.
- R6. A task has zero or more ordered subtasks. A subtask is a task with a parent (decision D30), so it carries the same fields plus an origin flag: created by the user, or suggested by AI. AI-suggested subtasks have a suggestion state: suggested, accepted, dismissed.
- R7. A task has zero or more tags. Tags are user-scoped, have a name and a color, and are the mechanism to connect related tasks. Listing tasks by tag is supported.
- R8. Task list supports filtering by status and tag, and returns subtask progress (accepted or user-created subtasks done over total).
- R9. Full create, read, update, delete for tasks, subtasks, and tags through the API and the web UI.

### 5.3 AI breakdown

- R10. When a task is created, a breakdown job is enqueued automatically. The task carries an AI status: pending, running, done, failed, skipped.
- R11. The breakdown agent uses the Anthropic SDK with Sonnet 5 and structured JSON output. It receives the task title and description, the user's existing tags, and the user's open task titles. It returns three to seven subtasks, each with a title and a one-line rationale, plus zero or more tag suggestions drawn from existing tags or proposed as new.
- R12. The agent's system prompt encodes a reasoning procedure: understand the outcome, identify the first physical action, keep each step under roughly one hour of work, order by dependency, stop at seven. The prompt lives in the repo as a versioned file, not inline code, so it can be reviewed like any other artifact.
- R13. Suggested subtasks land on the task in the suggested state with a visible "suggested by AI" badge and the rationale available on hover or expand. Controls: accept one, accept all, edit then accept, dismiss one, dismiss all.
- R14. The web UI shows a thinking state on the task while AI status is pending or running, and updates without a manual page refresh (polling is acceptable, push is not required).
- R15. Failures are visible, not silent. A failed breakdown shows a retry control. A skipped breakdown carries a reason the UI shows in words: too short to break down, hourly limit reached, or assistant paused. A breakdown stuck for more than ten minutes becomes a retryable failure automatically.
- R16. Rate limits: 20 breakdowns per user per hour and a session budget of 300 per hour across the whole environment, both enforced with Redis and configurable by environment variable. An operator kill switch (`AI_ENABLED=false`) pauses the assistant without a deploy. In every case task creation still succeeds and the task shows a machine-readable skip reason; only the explicit breakdown action returns an error.
- R17. The agent never mutates data directly. It returns a proposal; the API persists it. This separation is part of the story told in the session.

### 5.4 Request a feature (optional, time permitting)

- R18. A "Request a feature" page in the web app with the same fields as the GitHub issue form. Submitting creates a GitHub issue in the assembly-line repo through the API using a server-side token, labeled `feature-request`, with the submitter's display name in the body. This lets PMs without GitHub file requests from inside the product they are shaping.

### 5.5 Non-functional

- R19. `GET /api/v1/health` returns status, git commit SHA, version, and environment name. The smoke test uses the SHA to know the new build is live.
- R20. Structured JSON logging with a request ID on every request and job.
- R21. Basic hardening: helmet, CORS restricted to the web origin per environment, body size limits, password hashing with bcrypt or argon2.
- R22. The web app must be usable on a laptop screen projected in a room: large type, high contrast, no hover-only interactions for critical controls.

## 6. Engineering requirements: conventions the harness enforces

These are requirements on the codebase, and they are also the content of the skills that teach agents how to extend it. The skills are the deliverable. Consistency is the point: two endpoints written by two different agent sessions must be indistinguishable in shape.

### 6.1 API conventions (the "add an API endpoint" skill)

- E1. All routes live under `/api/v1`. JSON only. camelCase keys. ISO 8601 UTC timestamps. UUID identifiers.
- E2. One success envelope for every response: `{ "data": ..., "meta": { ... } }`. `meta` carries pagination and the request ID. Lists are paginated with `limit` and `cursor`; the spec decides cursor encoding.
- E3. One error envelope for every error: `{ "error": { "code": "...", "message": "...", "details": [...], "requestId": "..." } }`. Codes are a closed enum: `VALIDATION_ERROR`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `RATE_LIMITED`, `UPSTREAM_ERROR`, `INTERNAL`. HTTP status is derived from the code by one mapping function. No route constructs an error response by hand.
- E4. Every request's params, query, and body are validated with zod schemas before the handler runs. Validation failures produce `VALIDATION_ERROR` with per-field details. Response bodies are also described by zod schemas.
- E5. The same zod schemas register into an OpenAPI registry. `openapi.json` is generated from the registry and committed. It is the single source of truth for the API reference, and the web app generates its typed client from it.
- E6. Layering: route (HTTP concerns only), service (business rules), repository (Drizzle queries). Handlers never touch the database directly. Services never import Express types.
- E7. Authentication is a single middleware. Authorization checks that a resource belongs to the requesting user happen in services, and failures return `NOT_FOUND`, not `FORBIDDEN`, to avoid leaking existence.
- E8. Every endpoint ships with: a schema file, a route file, a service change if needed, an integration test using Supertest against a real Postgres test database, an OpenAPI registration, and a CHANGELOG entry. The skill's checklist is exactly this list, and the Stop hook verifies it.
- E9. Definition of done for an endpoint change: tests written first and failing, then passing, `openapi.json` regenerated and committed, API reference regenerated, CHANGELOG updated, docs hook passes.

### 6.2 Documentation freshness for every change

- E10. Docs set per app repo: `README.md`, `docs/ARCHITECTURE.md`, `docs/API.md` (generated from `openapi.json`, never edited by hand), `docs/adr/NNNN-title.md`, `CHANGELOG.md` in Keep a Changelog format, and `CLAUDE.md`.
- E11. A blocking Stop hook in each repo runs a docs-drift check before the agent may finish. Rules: if any file under `src/` changed, `CHANGELOG.md` must have an Unreleased entry. If any route or schema file changed, `openapi.json` must regenerate with no diff and `docs/API.md` must be current. If the change touches a file listed as architectural in `CLAUDE.md` (database schema, queue, auth, agent prompt), an ADR must be added or updated. The hook prints exactly what is missing.
- E12. The same drift check runs in CI so a bypassed hook still fails the PR. Local hook and CI share one script.
- E13. The "add an API endpoint" skill and the "add a frontend feature" skill both end with an explicit docs step. Docs are part of the change, not a follow-up task.

### 6.3 Frontend conventions (the "add a frontend feature" skill)

- E14. Vite, React, TypeScript, Tailwind, React Router, TanStack Query for server state. No global state library.
- E15. A typed API client generated from the API's `openapi.json`. The web app cannot call an endpoint the spec does not describe. This is the enforcement mechanism for E5 on the frontend side.
- E16. Feature-folder structure: `src/features/<domain>/` holds components, hooks, and tests for that domain. Shared primitives live in `src/components/ui/`.
- E17. Every feature ships with component tests in Vitest and Testing Library, covering the happy path and the error state. Every user-visible error uses the shared error presentation, sourced from the API error envelope.
- E18. The skill checklist: regenerate the client if the API changed, add or extend a feature folder, write tests first, wire the route, update `README.md` feature list and `CHANGELOG.md`.

### 6.4 Testing standards

- E19. TDD is mandatory for agents: the harness's implementation skill writes a failing test before production code and shows both states in its transcript, because the transcript is what the room sees.
- E20. API: unit tests for services, integration tests for routes against a real Postgres test database and a real Redis, one recorded contract test for the agent's structured output using a fixture, and one opt-in live test against Anthropic that runs only when a key is present.
- E21. Web: component tests with mocked API client. No browser tests in the PR pipeline.
- E22. Smoke: one Playwright script that registers a user, creates a task, waits for AI suggestions, accepts one, and logs out. Runs against staging after each deploy, and gates promotion to `main`.

## 7. Delivery pipeline

- P1. Branch model: feature branches to `develop` by PR, `develop` to `main` by PR. Both branches protected: PR required, CI checks required, no force push. Mike merges by hand during the session.
- P2. GitHub Actions on every PR and push in each app repo: install, lint, typecheck, tests, docs-drift check, build. Postgres and Redis run as service containers in the workflow.
- P3. Railway project with two environments, `staging` and `production`. Each environment has an API service, a static web service, a Postgres, and a Redis. The Railway GitHub integration deploys `develop` to staging and `main` to production, with Railway's wait-for-CI setting on so a red check suite never deploys.
- P4. Each app repo has a `promote` workflow that runs on pull requests from `develop` to `main`. It waits until staging serves that repo's candidate SHA (the API through `GET /api/v1/health`, the web through `/version.json`), then runs the shared Playwright smoke package, which lives in the assembly-line repo, against the staging URL. `promote` is a required check on `main` in both repos. For a change spanning both repos, the API is promoted first; additive migrations and additive API changes keep the previous web build working in between.
- P5. Environment configuration by variables only. The API needs database URL, Redis URL, JWT secret, Anthropic API key, web origin, GitHub token for the optional feature-request page, environment name, and rate-limit values. The web needs the API base URL at build time.
- P6. Database migrations run on API service start, before the server accepts traffic. Migration files are committed and generated by Drizzle.
- P7. Local development: Homebrew Postgres and Redis, `.env.example` in each repo, one command to start each app, one command to run each test suite. No Docker dependency.

## 8. The assembly-line harness

### 8.1 Per-repo harness (in each app repo's `.claude/`)

- H1. `CLAUDE.md` that states the conventions of section 6 briefly and points to the skills, the docs set, and the list of architectural files.
- H2. Skills: `add-api-endpoint` (API repo), `add-frontend-feature` (web repo), `write-adr` (both), `release-notes` (both, turns Unreleased into a version).
- H3. Agents: `reviewer` that checks a diff against section 6 conventions and returns a pass or a list of violations, and `test-writer` that drafts failing tests from acceptance criteria.
- H4. Hooks: the blocking Stop docs-drift hook (E11), and a PostToolUse hook that runs the formatter on edited files.

### 8.2 Cross-repo harness (in `kaizen-tasks-assembly-line`)

- H5. Workspace layout: a script that clones both app repos as siblings under one folder and a root `CLAUDE.md` describing the two-repo shape so a single Claude Code session can work across both.
- H6. Issue form: a GitHub issue form template with fields for problem statement, proposed behavior, acceptance criteria, and out of scope. Label `feature-request` applied automatically.
- H7. `triage-requests` skill: fetches open `feature-request` issues, scores each 1 to 5 on clarity, complexity, and risk, flags architecture change, computes a readiness rank (clarity high, complexity and risk low, architecture-change requests deferred), writes a ranked markdown report, applies score labels to each issue, and comments on issues with clarity below 3 with two or three concrete clarifying questions. Idempotent: re-running updates labels and edits its own comment rather than duplicating. It has a `--score-only` mode that scores one issue body or file with the rubric and writes nothing to GitHub; that mode is what the Part 2 `refine-request` skill calls, and it needs no repo permissions.
- H8. `implement-issue` skill: takes an issue number, restates acceptance criteria, plans the change across API and web, creates a feature branch in each affected repo, works test-first using the per-repo skills, runs the full local test suites, opens a PR per repo linking the issue, and stops. It never merges. If the issue is flagged architecture change, it writes the ADR first and asks for confirmation before code.
- H9. Seeded requests: four issue bodies of deliberately varied quality (one clear and small, one vague, one large architecture change, one medium) filed under Mike's account a day before the session so ranking always has material.
- H10. The ranking rubric is a versioned markdown file shared by the triage skill and by the Part 2 request-refinement skill, so both sides of the workshop use one definition of "ready".

## 9. Part 2: product harness (`nice-product-skills`)

- Q1. Repo `kaizen-tasks-product-skills`. Packaged as a Claude Code plugin (plugin manifest plus a `skills/` folder) so it can be published to the company marketplace later without restructuring. In the session PMs clone the repo and run the skills directly. The same skill folders work in Claude Desktop and Cowork.
- Q2. `refine-request` skill (the hands-on): interviews the PM about one feature request, one question at a time, against the shared rubric from H10, until clarity, scope, and acceptance criteria would score 4 or higher. It then outputs a rewritten issue body in the issue form's structure and a local read-only score using the same rubric, so the PM sees the before and after on their own machine. If the GitHub CLI is available, it offers to edit the PM's own issue, which any issue author can do. Applying labels and triage comments needs write access to the repo, so only Mike runs the write-back triage (H7); PMs never need repo permissions.
- Q3. `synthesize-interviews` skill (the take-home): takes one or more interview transcripts and produces jobs to be done, pains with supporting quotes, an opportunity list, and two or three candidate feature requests already in the issue form structure. Ships with three synthetic NICE contact-center interview transcripts (supervisor, agent, workforce planner) so it runs without real data.
- Q4. A one-page README for PMs: install in three steps, run each skill, where the rubric lives, how to propose a new skill.

## 10. Part 3: agentic layer planning

- T1. A printable one-page canvas: four columns for discover, define, deliver, learn, with rows for tasks done today, pain, candidate agent or skill, and evidence needed. PDF and markdown.
- T2. A 30/60/90 plan template: three columns, each with up to three commitments, an owner, and a measurable signal. PDF and markdown.
- T3. A facilitator sheet with the exercise timing, prompts for each column, and a prioritization step (value against effort, top three go to the plan).
- T4. No ongoing commitment from Mike is promised. The takeaway is the plan and the skills repo.

## 11. Facilitator runbook and rehearsal

- F1. A minute-by-minute runbook for the 3 hours, in the assembly-line repo, with the exact commands to run, the URLs to open, what to say at each gate, and what the room does meanwhile.
- F2. Part 1 timing target inside 75 minutes: 8 minutes framing and app tour, 12 minutes the room files requests, 8 minutes triage on screen, 25 minutes implementation on screen, 12 minutes merge, staging, smoke, promote, production, and 10 minutes of recovery buffer. The buffer is not a fallback: there is no pre-built PR and no recording. It is slack for a slow CI run or a provider retry. Cutoff rule: at minute 65 the facilitator states which live steps are still incomplete and moves on; whatever finishes later is shown at the start of Part 2.
- F3. A pre-session checklist: keys in place, seeded issues filed, staging and production healthy, rate limits raised for the session, rehearsal completed within the previous three days.
- F4. One full rehearsal of Part 1 with Mike before the session, timed, with findings folded back into the runbook.

## 12. Non-goals

- Email verification, password reset, social login, multi-tenancy, teams, sharing tasks between users.
- Real-time push (WebSockets). Polling is sufficient.
- Mobile layout beyond not breaking on a narrow window.
- Demonstrating company marketplace publishing or Enterprise connector setup.
- Slides. They come after the material is proven.
- Cost controls beyond the per-user limit, the session budget, and the kill switch in R16.

## 13. Open questions and risks for the spec step

- O1. Verify Railway's wait-for-CI behavior with GitHub check suites on the current Railway plan, and confirm the two-environment layout with per-environment Postgres and Redis. Fallback: GitHub Actions deploys through the Railway CLI.
- O2. Confirm the smoke-test trigger mechanism (P4) works without GitHub deployment events. The commit-SHA poll is the plan; validate it in the first deploy.
- O3. Cursor encoding and default page size for list endpoints.
- O4. Whether the optional feature-request page (R18) makes the cut. Decide after the core is green.
- O5. Anthropic API budget for the session: 20 attendees creating tasks freely. Estimate cost per breakdown during rehearsal and set the session budget (R16) accordingly.
- O6. Railway plan limits on services per project and usage. Mike's personal account may need an upgrade before rehearsal.
- O7. Live risk: no fallback was chosen. The rehearsal is the mitigation. The runbook should still list what to do if the API key, Railway, or GitHub Actions fail mid-session, even without a pre-built PR.

## Appendix A. Decision log

All settled. Do not reopen in the spec step.

| #   | Decision         | Choice                                                                                                                                                       |
| --- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| D1  | Audience         | PMs and product leads, 10 to 20, mixed hands-on                                                                                                              |
| D2  | Format           | One session, 3 hours, 75 / 60 / 45 minutes                                                                                                                   |
| D3  | Date             | Within two weeks of 2026-09-08                                                                                                                               |
| D4  | PM tooling       | Claude Code, Claude Desktop, Cowork available                                                                                                                |
| D5  | GitHub           | Mike's personal account, public repos                                                                                                                        |
| D6  | Repo topology    | Two app repos with own `.claude/`, plus assembly-line repo, plus product-skills repo. All named `kaizen-tasks-*`                                             |
| D7  | Language         | TypeScript everywhere                                                                                                                                        |
| D8  | Data             | Railway Postgres, Redis as BullMQ queue and rate limiter, Homebrew locally                                                                                   |
| D9  | AI breakdown UX  | Auto-run on create, land as suggested, accept / edit / dismiss                                                                                               |
| D10 | Agent            | Sonnet 5, structured output, sees tags and open tasks, proposes tags                                                                                         |
| D11 | Pipeline         | Railway GitHub integration with wait-for-CI, GitHub Actions runs tests, Mike merges live                                                                     |
| D12 | Tests            | Unit and API on PR, Playwright smoke on staging gating promotion                                                                                             |
| D13 | Docs             | Full set, blocking Stop hook, ADR when architecture change                                                                                                   |
| D14 | Intake           | GitHub issue form, plus in-app request page if time allows                                                                                                   |
| D15 | Triage           | Rank plus labels plus clarifying comments on issues                                                                                                          |
| D16 | Live run         | No fallback, one full rehearsal                                                                                                                              |
| D17 | Name             | Kaizen Tasks                                                                                                                                                 |
| D18 | Part 2           | `refine-request` hands-on, `synthesize-interviews` take-home, synthetic NICE CX data                                                                         |
| D19 | Part 3           | Lifecycle canvas plus 30/60/90 plan, paper, no ongoing commitment                                                                                            |
| D20 | Deliverables now | Build all, push and deploy from here, runbook, rehearsal, slides later                                                                                       |
| D21 | Auth and seed    | Open registration plus one seeded demo user                                                                                                                  |
| D22 | Ranking          | Readiness score, architecture-change deferred                                                                                                                |
| D23 | Seeding          | Four seeded requests of varied quality                                                                                                                       |
| D24 | Part 2 surface   | Claude Code skills, same folders work in Cowork, plugin-shaped for the marketplace later                                                                     |
| D25 | Part 3 medium    | Printable PDF and markdown                                                                                                                                   |
| D26 | Railway          | Mike's personal account                                                                                                                                      |
| D27 | Tooling          | Install GitHub CLI and Railway CLI, git identity from GitHub account                                                                                         |
| D28 | API key          | Railway variables and git-ignored local `.env`, Mike pastes                                                                                                  |
| D29 | Local dev        | Homebrew Postgres and Redis, no Docker                                                                                                                       |
| D30 | Task hierarchy   | One `tasks` table with `parent_id`, depth capped at two by a named constant, subtask routes folded into task routes                                          |
| D31 | Auth transport   | Same-origin: web service proxies `/api/*` to the API over Railway private networking; first-party httpOnly refresh cookie; no CORS; API has no public domain |
| D32 | Worker           | BullMQ worker runs inside the API process behind `WORKER_ENABLED`                                                                                            |
| D33 | Test database    | Real local Postgres, truncate before each test; service containers in CI                                                                                     |
| D34 | Disk layout      | Workshop root is a plain folder; `webapp/` = assembly-line repo with `backend/` and `frontend/` nested and git-ignored; `product-skills/` at the root        |
| D35 | Node             | Node 24 LTS everywhere, pinned by `.nvmrc`, for least maintenance                                                                                            |
| D36 | AI budget        | Per-user limit, session-wide budget, and an operator kill switch; task creation never fails because of AI                                                    |
| D37 | Promotion gate   | Per-repo `promote` workflow waits for staging to serve the candidate SHA, then runs the shared smoke package from the assembly-line repo                     |
| D38 | Railway scope    | Only a new project named `kaizen-tasks`; existing Railway projects are never touched. Railway work follows Railway's official agent skills                   |
| D39 | Recovery buffer  | 10 minutes of slack inside Part 1 with a cutoff rule; still no fallback PR or recording                                                                      |

## Appendix B. Assumptions made without asking

- Vite, React, Tailwind, React Router, TanStack Query on the web. Drizzle ORM and zod-to-OpenAPI on the API. Vitest and Supertest. MIT license.
- Short-lived access token plus Redis-backed refresh token in a first-party httpOnly cookie (same-origin, D31).
- Web app served by Railway as a static Caddy service that also proxies `/api/*` to the API (D31). One Railway project, two environments.
- The smoke package lives in the assembly-line repo and is run by each app repo's `promote` workflow after staging serves that repo's SHA.
- AI breakdown rate limit of 20 per user per hour by default.
- Seeded requests are drafted by the build and filed under Mike's account during rehearsal.
