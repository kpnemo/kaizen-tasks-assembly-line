# Changelog

All notable changes to this repository are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Facilitator runbook (`docs/runbook.md`): pre-session checklists, the Part 1 minute-by-minute table, gate scripts, a failure page, rollback, and the Part 2/3 handoffs.
- `scripts/check-versions.sh`: checks that `backend/package.json` and `frontend/package.json` carry the same version, for the shared-versioning convention across the app repos.
- `smoke/tests/smoke.spec.ts` step 1b: asserts the web footer prints the version and short commit reported by `GET /api/v1/health`.

### Changed

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
