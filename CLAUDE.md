# kaizen-tasks-assembly-line

The workspace and cross-repo harness for the Kaizen Tasks workshop. This repository owns no application code. A Claude Code session started here can work in both app repos at once.

## Status (read this first)

**Phase: preparation.** The workshop has not started. Mike announces the real session; until then every issue, triage run and ship is rehearsal and build work, and the room is not watching.

- Live: **release 1.7.0 in production and staging (2026-09-12 11:52Z)**: the context-aware interview (#31: product context in the prompt, a recommended answer on every question, "Finish with what we have", Fable through `INTERVIEW_MODEL`), on top of 1.6.0's header simplification (#29) and 1.5.0's pipeline control room. `/pipeline` serves in both environments with the facilitator buttons for `kpnemo@gmail.com`; #19, #22, #28, #29 and #31 shipped; `staging-label` runs on Railway's `deployment_status`; `ship.yml` resumes on rerun.
- Interview redesign (#31): DONE in production 2026-09-12; the staging replay of the #29 request passed every check in the spec on Fable (comment on #31). Next: Mike's own end-to-end rehearsal in a fresh session (file → /triage-requests → /implement-issue → Deploy to staging → Deploy to production, all from the page); the next release is 1.8.0. Give every batch of work a tracking issue up front: the page only shows rows for issues. Handover page: the "Kaizen Assembly Line Handover" artifact (2026-09-11 evening).
- The seeded requests #2, #3, #4, #5 are demo material for the live session. Do not implement them during preparation.
- When a plan already names the next issue, do not ask which one to implement; run it. Ask only when nothing decided it.
- Merges: after Mike's one go at a gate, the agent merges and drives the sequence itself (approved 2026-09-11); Mike decides, he does not type the commands.
- Two ways to implement (2026-09-12, #36): `/implement-issue` with Mike answering the round and the two gates, or `/auto-implement-issue` with no questions at all, Codex standing in for him; both run the API and web lanes in parallel after the plan and stop before any merge. The unattended one ends with `Ready for staging` on the issue; Mike presses Deploy to staging.

Update this section when the phase or the order changes.

## Layout

| Path                      | What it is                                                                                                                                                                                                               |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `backend/`                | Nested repo `kpnemo/kaizen-tasks-api`, git-ignored here. Express 5 API on port 3000, Postgres, Redis and BullMQ, Anthropic SDK breakdown agent. Owns the API contract `openapi.json`.                                    |
| `frontend/`               | Nested repo `kpnemo/kaizen-tasks-web`, git-ignored here. React 19 and Vite app on port 5173 in development, typed client generated from the API contract, Caddy proxy for `/api/*` in production.                        |
| `rubric/readiness.md`     | The readiness rubric. Versioned by its `version:` front-matter line; this repo owns it, and the product-skills repo and the API repo each vendor a copy, checking drift with their own `scripts/sync-rubric.sh --check`. |
| `.github/ISSUE_TEMPLATE/` | The two intake forms: `feature-request.yml` (label `feature-request`, scored by the rubric) and `bug-report.yml` (label `bug`, never scored, straight to `/implement-issue`). `npm run check:issue-form` validates both. |
| `.claude/skills/`         | `triage-requests`, `implement-issue`, `auto-implement-issue` (the unattended variant: Codex answers the round and reviews the spec, stops at the Deploy to staging click), `seed-requests`.                            |
| `smoke/`                  | Playwright smoke package, run by both app repos' `promote` workflows against staging.                                                                                                                                    |
| `seeds/requests/`         | Four seeded feature requests. `triage/` holds dated triage reports.                                                                                                                                                      |
| `scripts/`                | Workspace setup, labels, seeds, branch protection, root hooks.                                                                                                                                                           |
| `docs/`                   | PRD, runbook, playbook, Railway setup, specs and plans.                                                                                                                                                                  |

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
6. Versions: both app repos carry the same semver in `package.json`, cut with each repo's `release-notes` skill (same number, same day) on a branch that merges to `develop` before the `develop` to `main` pull requests. `GET /api/v1/health` reports `version`; the web footer prints `v<version> · web <sha> · api <sha>` and turns the API part amber when the versions differ; the smoke test asserts they match; `scripts/check-versions.sh` checks the two checkouts.

## Per-repo skills, read by path from a root session

- `backend/.claude/skills/add-api-endpoint/SKILL.md`
- `frontend/.claude/skills/add-frontend-feature/SKILL.md`
- `backend/.claude/skills/write-adr/SKILL.md` and `frontend/.claude/skills/write-adr/SKILL.md`
- `backend/.claude/skills/release-notes/SKILL.md` and `frontend/.claude/skills/release-notes/SKILL.md`

The superpowers plugin's skills are invoked by name with the Skill tool (`superpowers:brainstorming`, `superpowers:writing-plans`, `superpowers:executing-plans` or `superpowers:subagent-driven-development`, `superpowers:test-driven-development`, `superpowers:systematic-debugging`). `implement-issue` routes into them instead of restating them, and `auto-implement-issue` routes into `implement-issue` the same way.

## Rules

- When a change touches both repos, the API contract changes first; the rest of the API and the web then run in parallel, one implementer per repo, the web after pulling the contract. Never two implementers in the same repo.
- Nothing in this repository merges pull requests. Skills open pull requests and stop. Mike merges.
- Skills never push to `develop` or `main` directly: feature branches and pull requests only, in every repo. The single exception is `triage-requests`, which pushes its dated report commit under `triage/` straight to this repo's `develop`, because the report has to land while triage is on screen; nothing else, in any repo, ever pushes to a shared branch. `main` only ever receives `develop` by pull request after staging verification. (During the initial build, before the first workshop rehearsal, lanes commit straight to `develop`; that exception ends at the rehearsal.)
- Secrets never enter any repository.
- Root hooks: Stop runs `scripts/docs-check-all.sh --hook`; PostToolUse on Edit or Write runs `scripts/format-file.sh`.
