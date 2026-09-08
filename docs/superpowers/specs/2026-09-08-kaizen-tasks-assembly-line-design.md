# Kaizen Tasks Assembly Line: Design Spec

| Field | Value |
|---|---|
| Repo | `kaizen-tasks-assembly-line`, folder `webapp/` (the workspace root for the two app repos) |
| Status | Approved design 2026-09-08 |
| Upstream | `docs/PRD.md` (sections 8, 11, 7); API spec in `backend/docs/superpowers/specs/`; web spec in `frontend/docs/superpowers/specs/` |
| Downstream | `superpowers:writing-plans` produces `docs/superpowers/plans/` from this spec |

## 1. Purpose and scope

The cross-repo harness and the facilitator's kit: the workspace that holds both app repos, the feature-request intake, the readiness rubric, the triage and implement skills, the smoke package that gates promotion in both app repos, the seeded requests, the branch-protection and label scripts, the Railway setup procedure, and the runbook. It owns no application code.

Approach decisions taken in design:

| # | Decision | Choice and reason |
|---|---|---|
| A1 | Orchestration | One Claude Code session at the workspace root runs `implement-issue`. Per-repo skills are read as files by path. A root Stop hook delegates docs-check to each nested repo with changes, because nested repos' hooks do not fire in a root session. CI in each app repo is the final enforcement |
| A2 | Rubric ownership | This repo owns `rubric/readiness.md`. The product-skills repo vendors a copy with a sync script and a drift warning |
| A3 | Triage output | A dated report committed under `triage/`, score labels and one upserted comment per issue, and a pinned "Triage board" issue whose body is rewritten with the current ranking |
| A4 | Smoke location | The Playwright smoke package lives here and is checked out and run by both app repos' `promote` workflows |

## 2. Repo shape

```
webapp/
  .claude/
    settings.json          Stop -> scripts/docs-check-all.sh --hook; PostToolUse Edit|Write -> scripts/format-file.sh
    skills/
      triage-requests/SKILL.md
      implement-issue/SKILL.md
      seed-requests/SKILL.md
  .github/
    ISSUE_TEMPLATE/feature-request.yml
    ISSUE_TEMPLATE/config.yml       blank issues off, link to the form
    workflows/ci.yml                smoke package lint + typecheck, issue form validation, rubric presence
  CLAUDE.md                workspace map and conventions summary
  README.md                what this repo is, setup-workspace, the three skills, the runbook
  backend/                 nested repo kaizen-tasks-api (git-ignored)
  frontend/                nested repo kaizen-tasks-web (git-ignored)
  docs/
    PRD.md
    runbook.md
    railway-setup.md
    superpowers/specs/, superpowers/plans/
  rubric/readiness.md
  seeds/requests/01-mark-all-done.md  02-smarter-ai.md  03-share-task.md  04-regenerate-with-hint.md
  smoke/                   package.json, playwright.config.ts, tests/smoke.spec.ts, README.md
  triage/                  YYYY-MM-DD.md reports
  scripts/
    setup-workspace.sh     clone app repos if missing, check nvm/postgres/redis, createdb
    setup-labels.sh        create or update the label set in this repo
    protect-branches.sh    apply branch protection to both app repos
    seed-requests.sh       file seeds/requests/*.md as issues
    docs-check-all.sh      run each nested repo's docs-check when it has changes
    format-file.sh         route a file to the owning repo's prettier
```

`.gitignore` excludes `backend/`, `frontend/`, `node_modules/`, `smoke/test-results/`, `smoke/playwright-report/`.

## 3. Workspace

`CLAUDE.md` at the root, under one page: the two nested repos and what each owns; how to run both locally (backend on 3000, frontend dev on 5173 proxying to it); the shared conventions in five lines (envelopes, TDD, docs-check, additive migrations, contract copy); the exact paths of the per-repo skills; the rule that the API changes first when both change; the rule that nothing here merges pull requests.

`scripts/setup-workspace.sh`: for each of `backend` and `frontend`, clone `git@github.com:kpnemo/kaizen-tasks-api.git` or `kaizen-tasks-web.git` if the folder is missing; verify `nvm` and switch to 24; verify Postgres and Redis answer; `createdb kaizen_dev` and `kaizen_test` if absent; run `npm ci` in both; print the next commands.

## 4. Intake

### 4.1 Issue form

`.github/ISSUE_TEMPLATE/feature-request.yml`: name "Feature request", labels `["feature-request"]`, fields in order:

| id | Type | Required | Prompt |
|---|---|---|---|
| problem | textarea | yes | What is hard or slow today, for whom, and how do you know |
| behavior | textarea | yes | What should happen instead, as the user would see it |
| acceptance | textarea | yes | How we will know it is done: bullet points a tester could check |
| out_of_scope | textarea | no | What this request deliberately does not include |
| role | input | no | Your role, so the assistant can phrase questions for you |

`config.yml` disables blank issues so every request goes through the form.

### 4.2 Labels

`scripts/setup-labels.sh` uses `gh label create --force` for: `feature-request` (blue), `clarity:1` to `clarity:5`, `complexity:1` to `complexity:5`, `risk:1` to `risk:5` (three gray-to-green gradients), `arch-change` (red), `triaged`, `implementing`, `shipped` (purple gradient), and `triage-board` (used only by the pinned issue).

### 4.3 Triage board

One issue titled "Triage board", labeled `triage-board`, pinned. Its body is fully rewritten by the triage skill: a table of rank, issue link, title, readiness, clarity, complexity, risk, architecture flag, and status, followed by the timestamp of the run. Created by the labels script if missing.

## 5. Rubric

`rubric/readiness.md` is a document written for a model to follow. Sections:

1. **Scales.** Clarity 1 to 5 with anchors: 1 a wish with no user or outcome; 2 a goal with no observable behavior; 3 behavior described but acceptance criteria missing or untestable; 4 testable acceptance criteria, scope stated; 5 also names out of scope and edge cases. Complexity 1 to 5: 1 one file in one repo; 2 one repo, a few files, no schema change; 3 both repos or a schema-additive change; 4 new subsystem or external integration; 5 restructures existing flows. Risk 1 to 5: 1 cosmetic; 2 isolated behavior; 3 touches auth, data, or the AI prompt; 4 could lose or expose data; 5 changes security or multi-user boundaries.
2. **Architecture change test.** True when the request implies touching any of: the database schema beyond additive columns, auth, the queue, the agent prompt or output schema, the proxy, the API contract in a breaking way, or multi-user data sharing.
3. **Readiness.** `clarity * 2 + (6 - complexity) + (6 - risk)`, range 4 to 20. Sort descending; every architecture-change request sorts after every non-architecture request regardless of score; ties by creation date ascending.
4. **Procedure.** Read the whole request. Score clarity first from the acceptance criteria alone. Score complexity and risk by naming the files or areas that would change, in the repo layouts summarized in the rubric. Output the fixed shape: `{ clarity, complexity, risk, archChange, readiness, reasons: { clarity, complexity, risk }, questions: [] }`.
5. **Clarifying questions.** Only when clarity is below 3. Two or three, each answerable in one sentence, drawn from these patterns: who is the user and when does this happen; what does the user see when it works; what would make you say it is done; what should explicitly not change.

The rubric is versioned by a `version:` line in its front matter. The product-skills repo's copy carries the same line, and its drift check compares them.

## 6. Skills

### 6.1 triage-requests

Frontmatter: name, description ("Rank open feature requests by readiness and write scores back to GitHub"), `argument-hint: [--score-only <issue number | file>] [--dry-run]`.

Steps:

1. Read `rubric/readiness.md`.
2. Score-only mode: load the issue body with `gh issue view <n> --json body,title` or read the file; apply the procedure; print the scores, reasons, and questions; stop. No writes.
3. Full mode: `gh issue list --label feature-request --state open --json number,title,body,createdAt,labels --limit 100`.
4. Score every issue with the procedure. Produce the ranking.
5. Write `triage/<YYYY-MM-DD>.md`: the ranking table, then one section per issue with reasons and questions. Commit it with the message `triage: <date>`.
6. For each issue, unless dry run: remove existing `clarity:*`, `complexity:*`, `risk:*` labels, add the new ones and `triaged`, add or remove `arch-change`; upsert one comment containing the hidden marker `<!-- kaizen-triage -->` followed by the scores, one-line reasons, and the questions when clarity is below 3. Upsert means: find the existing comment by the marker with `gh api`, edit it if found, create it otherwise.
7. Rewrite the Triage board body.
8. Print the top three with readiness and the recommended one to implement, which is the top non-architecture request.

Idempotent by construction: labels are replaced, the comment is edited, the board is rewritten.

### 6.2 implement-issue

Frontmatter: name, description ("Implement one feature request end to end across both repos with TDD, open pull requests, never merge"), `argument-hint: <issue number>`.

Steps:

1. `gh issue view <n> --json title,body,labels`. Restate the acceptance criteria as a numbered checklist in the transcript. If any criterion is untestable, say so and stop with the clarifying question; do not guess.
2. If labeled `arch-change`: write the ADR in the affected repo following its `write-adr` skill, commit it on the feature branch, and stop with "ADR written, confirm to continue". Resume only when told.
3. Decide the affected repos and say why. State the smallest slice that satisfies every criterion; the target is a change that finishes in 25 minutes.
4. Time box: note the start time; at 20 minutes, if not at the pull-request step, stop and report what is done and what remains.
5. For the API when affected: `git -C backend switch -c feat/<n>-<slug> develop`, then follow `backend/.claude/skills/add-api-endpoint/SKILL.md` exactly, showing the failing test output before the implementation and the passing output after. Run `npm test`, `npm run openapi`, and `npm run docs:check` in `backend/`. Commit.
6. For the web when affected: same with `frontend/.claude/skills/add-frontend-feature/SKILL.md`. If the contract changed, first run `scripts/pull-openapi.sh --local ../backend/openapi.json` in `frontend/` and `npm run api:types`. Run `npm test` and `npm run docs:check`. Commit.
7. Push both branches. `gh pr create --base develop` in each repo with a body containing the checklist, the test evidence, and `Closes kpnemo/kaizen-tasks-assembly-line#<n>`.
8. `gh issue edit <n> --add-label implementing`, comment with the PR links.
9. Stop. Print the PR URLs and the sentence "Ready for review and merge".

The skill never runs `gh pr merge`, never pushes to `develop` or `main`, and never edits files outside the two app repos.

### 6.3 seed-requests

Reads `seeds/requests/*.md`, each with front matter `title:` and a body already in the issue form's structure, and files them with `gh issue create --label feature-request --title --body-file`. Skips a seed whose title already exists as an open issue. Same logic as `scripts/seed-requests.sh`, packaged as a skill so it can run from Claude Code.

## 7. Root hooks

`scripts/docs-check-all.sh --hook`: for each of `backend` and `frontend` that exists and has uncommitted or unpushed changes relative to its base, run `scripts/docs-check.sh --hook` inside it and collect the exit code and output. If any failed, print all outputs prefixed with the repo name and exit 2. Otherwise exit 0. It honors each repo's own escape hatch and marker file; it adds nothing of its own.

`scripts/format-file.sh`: reads the tool input JSON from stdin, finds `file_path`, determines which nested repo contains it, and runs that repo's `npx prettier --write` on it. Files outside both repos are formatted with the root's prettier only if they are markdown, JSON, or YAML.

## 8. Smoke package

`smoke/`: Node 24, Playwright with Chromium only. Configuration reads `SMOKE_BASE_URL` (required), `SMOKE_AI_TIMEOUT_MS` (default 90000), `SMOKE_FAST` (skip the AI wait when `1`).

`tests/smoke.spec.ts`, one test in sequence:

1. Open the base URL, expect the login page.
2. Register `smoke+<timestamp>@kaizen.local` with a fixed password and display name "Smoke".
3. Expect the task list. Create the task "Prepare the quarterly business review deck for the leadership team" with a two-sentence description.
4. Expect the row with a thinking chip. Unless fast mode, poll the row until the chip leaves thinking, within the AI timeout. Fail on a failed chip or on timeout. Accept skipped as a pass with a console note.
5. Open the detail. If suggestions exist, accept the first one and expect the progress label to read `0/1` or higher.
6. Log out, expect the login page.

`npm test` runs it headless; `npm run test:headed` for rehearsal. Traces and screenshots are kept on failure under `smoke/test-results/` and uploaded as a workflow artifact by the calling workflow. Both app repos call it as: checkout this repo at `main` into a subfolder, `npm ci` in `smoke/`, `SMOKE_BASE_URL=<staging web domain> npm test`.

## 9. Seeds, scripts, and CI

Seeded requests, each a markdown file with front matter and the form's sections:

| File | Title | Intended scoring |
|---|---|---|
| 01 | Add a "Mark all steps done" button on the task detail | clarity 5, complexity 2, risk 1, top of the ranking |
| 02 | Make the AI smarter | clarity 1, questions posted |
| 03 | Share a task with a teammate | architecture change, sorts last |
| 04 | Regenerate suggestions with a hint | clarity 4, complexity 3, risk 3, second |

`scripts/protect-branches.sh <repo>`: for `develop` and `main` on `kpnemo/kaizen-tasks-api` and `kpnemo/kaizen-tasks-web`, `gh api -X PUT repos/<repo>/branches/<branch>/protection` with required status checks `ci` on both, plus `promote` on `main`, required pull request with zero required approvals, no force pushes, no deletions, and enforce for admins off so the facilitator can merge when checks are green.

`.github/workflows/ci.yml`: on pull requests and pushes to `main`: `npm ci` and `npx playwright install --with-deps chromium` then `npm run lint` and `npm run typecheck` in `smoke/`; validate `feature-request.yml` parses and has the five fields; assert `rubric/readiness.md` has a `version:` line. No deploys.

## 10. Railway setup procedure

`docs/railway-setup.md` is followed by the CI/CD lane with Railway's official `use-railway` skill. Scope rule at the top: only the new project `kaizen-tasks`; never link or modify another project. Steps: `railway init` from `backend/` naming the project; create the `staging` environment (production exists by default); in each environment add Postgres and Redis, the `api` service from `kpnemo/kaizen-tasks-api`, and the `web` service from `kpnemo/kaizen-tasks-web`; set the variables listed in the two app specs, with `PORT=3000` on `api` and the `ANTHROPIC_API_KEY`, `JWT_SECRET`, `SEED_DEMO_PASSWORD`, and `ADMIN_TOKEN` values entered by Mike; apply each repo's `.railway/railway.ts` per environment with `railway config apply`; switch wait-for-CI on for both services in both environments in the dashboard; generate the public domain for `web` in each environment; record the two domains in the runbook. Verification: the first push to `develop` shows a waiting deployment while CI runs, then a healthy staging.

## 11. Runbook

`docs/runbook.md` sections:

1. **Pre-session checklist** (T minus one day and T minus one hour): keys and variables present, seeds filed, Triage board pinned, staging and production healthy with the expected SHAs, demo user reset through the admin endpoint, smoke passed against both environments in the last hour, `AI_GLOBAL_LIMIT_PER_HOUR` raised to the session value, rehearsal completed within three days.
2. **Part 1 minute by minute**, 75 minutes: 0 to 8 framing and app tour on the production URL with the demo user; 8 to 20 the room registers and files requests, with the form URL on screen; 20 to 28 triage on screen, Triage board shown; 28 to 53 `implement-issue` on the top request, with the three moments to narrate: the failing test, the docs-check gate, the pull request; 53 to 65 merge to `develop`, watch Railway wait for CI, staging deploy, promote check, merge to `main`, production; 65 to 75 buffer. Cutoff rule at 65.
3. **What to say at each gate**: one paragraph per gate.
4. **Failure page**: API key rejected (switch the key variable, redeploy), Actions slow (show the queue, narrate, use the buffer), Railway deploy stuck (show the deployment log, redeploy), implement-issue stalled (stop at the 20-minute mark, show what exists, open the PR with what is there), staging smoke red (open the trace, explain the gate is doing its job, do not promote).
5. **Rollback**: redeploy the previous deployment in the Railway dashboard; why it is safe.
6. **Part 2 and Part 3 handoffs**: the product-skills repo clone command on screen, the facilitator sheet.

## 12. Verification items

| # | Check | Status | Fallback |
|---|---|---|---|
| L1 | `Closes owner/repo#n` in a PR body closes an issue in another repo on merge | Open, verified on the first implemented seed | The implement skill closes the issue with `gh issue close` after the merge is observed in the runbook step |
| L2 | A root Stop hook can run a nested repo's script with the nested repo as working directory | Open, verified in the first harness task | The nested docs-check scripts accept a `--repo <path>` argument |
| L3 | `actions/checkout` of a public repo into a subfolder needs no token | Open, verified by the first promote run | Use `GITHUB_TOKEN` with read scope |

## 13. Out of scope

Application code, merging pull requests, Railway resources outside `kaizen-tasks`, slides, the product skills.
