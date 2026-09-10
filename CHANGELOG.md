# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Bug intake: `.github/ISSUE_TEMPLATE/bug-report.yml` (What happened, What you expected, Steps to reproduce, Where, Your role; label `bug`), the `bug` label in `scripts/setup-labels.sh`, a contact link in `.github/ISSUE_TEMPLATE/config.yml`, and `scripts/check-issue-form.mjs` extended to validate both forms.
- `docs/playbook.md`: the one-page second-screen cheat sheet for Part 1, each step as type, see, say, with an "If it breaks" block and the numbers to keep in mind.
- Facilitator runbook (`docs/runbook.md`): pre-session checklists, the Part 1 minute-by-minute table, gate scripts, a failure page, rollback, and the Part 2/3 handoffs.
- `scripts/check-versions.sh`: checks that `backend/package.json` and `frontend/package.json` carry the same version, for the shared-versioning convention across the app repos.
- `smoke/tests/smoke.spec.ts` step 1b: asserts the web footer prints the version and short commit reported by `GET /api/v1/health`.

### Changed

- `.claude/skills/triage-requests/SKILL.md`: the skill now ends by asking the facilitator which issue to implement (AskUserQuestion when available: the top three non-architecture issues, the recommended one first and marked `(Recommended)`; a numbered list otherwise) and never starts implementing; a new step pushes the dated report commit to `develop`; the board template's status sentence moved out of the fenced block to an author note; the summary says that a second run is safe and shows the upsert.
- `.claude/skills/implement-issue/SKILL.md`: rewritten as a router into the superpowers plugin. It classifies the issue (`feature-request` or `bug`), marks it `implementing` and assigns it before any interview or code, then routes a request through `superpowers:brainstorming` (the product owner is interviewed about the request, at most four questions, options from the issue text), the spec at `docs/superpowers/specs/<date>-issue-<n>-<slug>.md`, `superpowers:writing-plans` (one to four tasks per repo, each naming that repo's own skill) and `superpowers:executing-plans` (or `superpowers:subagent-driven-development`), and a bug through `superpowers:systematic-debugging`. It creates the working branches through GitHub (`createLinkedBranch`, ids resolved at run time) so they appear under Development on the issue, flips the chosen issue's row on the Triage board, posts one short milestone comment per stage (taken into work, interview done, spec and plan approved, pull request opened) so the issue timeline carries the whole journey, creates the docs branch before brainstorming so the spec and plan commit onto it, forbids `superpowers:using-git-worktrees` and `superpowers:finishing-a-development-branch`, runs the docs gate in its CI form after the commit, and opens the spec and plan as a third, docs-only pull request. It still never merges.
- `docs/PRD.md`: F2 carries the new Part 1 split (8/14/8/30/10/5, cutoff at minute 70, Part 2 from minute 75) and a new R24 for bug intake (the bug form, the `bug` label, and the systematic-debugging route).
- `docs/runbook.md`: Part 1 re-timed inside 75 minutes (framing 0 to 8, requests 8 to 22, triage 22 to 30 ending with the facilitator's choice, implement 30 to 60, ship 60 to 70, buffer 70 to 75, cutoff at minute 70); the Implement row runs `/implement-issue <the number you chose>` and names five moments; section 3 gains the brainstorming interview and the spec-and-plan gates; section 4 gains rows for a stalled interview and for a bug filed instead of a request, and the implement time box moves to 25 minutes; section 8's rehearsal table gains interview and spec-and-plan columns; the top links `docs/playbook.md`; the Ship block merges all three feature pull requests (API, web, and the docs-only spec and plan here) and ends with the shipped comment.
- `CLAUDE.md`: names the one exception to the never-push rule (`triage-requests` pushes its `triage/` report commit to `develop`), lists the two intake forms, and records that `implement-issue` routes into the superpowers skills by name.
- `README.md`: the three-skills table reflects the new flow (triage ends with a question and pushes its report; implement-issue routes through superpowers and takes bugs to systematic debugging) and the docs list gains the playbook.
- `docs/cicd-log.md`: recorded the 1.1.1 promotion (the interview agent) with the production read-backs, the version check, the production smoke and the interview probes.
- `docs/runbook.md`: Part 1's intake segment (8 to 23, was 8 to 20) adds the assistant interview path on "Request a feature" alongside the plain form, with a gate line in section 3, a failure-page row for a slow or erroring assistant, and a pre-session check to run one interview on production the day before; the buffer (section 2) shrinks from 10 to 7 minutes and the cutoff rule moves to minute 68 to keep Part 1 at 75 minutes.
- `docs/PRD.md`: R23 documents the "Request a feature" interview extending R18: what the PM sees, the readiness stop rule, the prefilled form and issue section, and the escape hatch to the plain form.
- `README.md` and `CLAUDE.md`: the readiness rubric now has three consumers (this repo, product-skills, and the API's interview agent); each vendoring repo checks drift with its own `scripts/sync-rubric.sh --check`.
- `docs/cicd-log.md`: recorded the second promotion (release 1.0.0 on both app repos, harness `main` with the footer-version smoke step, production read-backs, production smoke).
- `smoke/README.md` and the runbook: local smoke runs behind a TLS-inspecting proxy need `NODE_OPTIONS=--use-system-ca` for the footer version step (Playwright's Node request client does not read the system trust store).
- `docs/cicd-log.md`: recorded the first `develop`→`main` promotion of both app repos with the production read-backs (Task 12, L3-M2) and the demo-user resets on staging and production plus the production AI probe (Task 13).
- `docs/cicd-log.md`: recorded the IaC apply for `api` and `web` in staging and production (Task 8), the wait-for-CI observation of a gated staging deploy (Task 9, V4), the public domain, proxy and health verification (Task 10, L3-M1), and branch protection on `develop` (`ci`) and `main` (`ci`+`promote`) in both app repos (Task 11).
- `README.md`, `CLAUDE.md`, `docs/runbook.md`, `docs/PRD.md`, and `.claude/skills/implement-issue/SKILL.md`: documented the shared-versioning convention (`scripts/check-versions.sh`, the `/api/v1/health` `version` field, the footer's version and amber mismatch state, and the runbook's Ship-segment release cut).

### Fixed

- Codex review of PR #6: the smoke-on-main check compares against `package.json` with a quoted URL; the implement-issue skill reuses an existing feature branch when resuming after an ADR; the setup script's startup hint runs the API with `AI_MODEL_PROVIDER=fake`.
- PR #6 review: runbook names the five issue-form fields and warns that the production health loop fails before the first promotion; CI calls `npm run check:rubric`; the smoke README example uses the 180 s assistant timeout.
- Runbook smoke row includes `npx playwright install --with-deps chromium`, matching `smoke/README.md` (final re-review).
- Railway setup doc: status and branch read-backs use fields the CLI actually emits; rollback section no longer presents `redeploy` as a rollback.
- `smoke/tests/smoke.spec.ts` step 2: waits for the "Create your account" heading before filling the register form, so a React Router transition can no longer leave the still-mounted login form's email/password fields under the same locators (the form was submitting with an empty email).
- `smoke/tests/smoke.spec.ts` step 5: now waits for the Accept button when step 4 saw a `suggestions` chip, instead of checking `count()` immediately after the heading renders (which raced the detail query and always logged "No suggestion to accept").
- `docs/runbook.md` and `README.md`: assert that `kaizen-tasks-assembly-line` `main` carries `smoke/` before any promotion, since both app repos' `promote` workflows check the smoke package out at `main` (final review C1).
- `docs/runbook.md` and `docs/railway-setup.md`: assert that the repository variable `STAGING_WEB_URL` is set on both app repos, and record when it was set in `docs/cicd-log.md` (final review C2).
- `.claude/skills/implement-issue/SKILL.md`: Steps 5 and 6 now run `npm run typecheck` and `npm run lint` before the tests-green gate in both nested repos, matching their own skills and `ci` workflows, so the pull requests the skill opens cannot go red on `ci` for lint or type reasons (final review I1).
- `.claude/skills/implement-issue/SKILL.md`: the pull-request-body template's outer code fence is now four backticks so the inner three-backtick evidence blocks render instead of terminating the template early (final review I2).
- `scripts/docs-check-all.sh` and `scripts/format-file.sh`: the stdin read is now guarded by a tty check and bounded to 5 seconds (`IFS= read -r -t 5`), so an open-but-silent stdin can no longer hang either script (final review I3).
- `docs/runbook.md`: added a pre-session row for local prerequisites (Postgres and Redis running, both nested trees clean and on `develop`, `nvm use` done) (final review I4).
- `docs/runbook.md`: the smoke row now uses `smoke/README.md`'s full run sequence (`npm ci` then `SMOKE_BASE_URL=... SMOKE_AI_TIMEOUT_MS=180000 npm test`) instead of an incomplete command (final review I5).
