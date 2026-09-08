# Facilitator runbook: Kaizen Tasks workshop

Three hours: Part 1 live run (75 minutes), Part 2 hands-on (60 minutes), Part 3 planning (45 minutes). Part 1 has no fallback pull request and no recording; the rehearsal is the safety net and the buffer is slack, not a substitute.

## Fixed facts

| Fact              | Value                                                                                        |
| ----------------- | -------------------------------------------------------------------------------------------- |
| Production web    | https://web-production-7ef71.up.railway.app                                                  |
| Staging web       | https://web-staging-52c0.up.railway.app                                                      |
| Issue form        | https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/new?template=feature-request.yml |
| Triage board      | the pinned issue in https://github.com/kpnemo/kaizen-tasks-assembly-line/issues              |
| Demo user         | `demo@kaizen.local`, password is the `SEED_DEMO_PASSWORD` Railway variable                   |
| Product skills    | `git clone https://github.com/kpnemo/kaizen-tasks-product-skills.git`                        |
| Rehearsal timings | filled after the rehearsal (section 8)                                                       |

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

| Minute   | Segment                 | Facilitator                                                                                                                                                                                                                                                                                                                                                                                | Room                                                                       |
| -------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| 0 to 8   | Framing and app tour    | State the goal: a request from this room reaches production in the next hour with tests and gates, no slides. Open production as the demo user. Show a task with accepted AI steps, one with pending suggestions and its rationale on hover, one failed with retry. Create a task live and let the thinking chip resolve.                                                                  | Watches                                                                    |
| 8 to 20  | The room files requests | Put the issue form URL on screen. Walk the four fields; say that acceptance criteria decide the ranking. Show one seeded request as an example of a clear one.                                                                                                                                                                                                                             | Registers on production, files requests through the form                   |
| 20 to 28 | Triage on screen        | In T1: `/triage-requests`. Narrate the rubric while it runs. Open the Triage board. Read the top three and the recommended one. Open one low-clarity issue and read the questions the skill posted.                                                                                                                                                                                        | Watches; the authors of unclear requests answer the questions in the issue |
| 28 to 53 | Implement on screen     | In T1: `/implement-issue <top request number>`. Narrate the three moments (section 3): the failing test, the docs-check gate, the pull request. Keep the room on what the transcript shows, not on the code.                                                                                                                                                                               | Watches; questions held to the buffer                                      |
| 53 to 65 | Ship                    | Open the pull request; checks green; merge to `develop` (Mike). Show Railway staging deployment `WAITING` then building. Show `/version.json` or health on staging with the new SHA. Open the `develop` to `main` pull request; `promote` runs the smoke against staging; show the Playwright steps in the Actions log. Merge to `main`. Show production with the new SHA and the feature. | Watches the pipeline                                                       |
| 65 to 75 | Buffer                  | Absorb CI, provider, or Railway slowness. Cutoff rule: at minute 65 state which live steps are still incomplete and move to Part 2; whatever finishes later is shown at the start of Part 2.                                                                                                                                                                                               | Questions                                                                  |

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

| Symptom                                                                                                                                                                                         | Do this                                                                                                                                                                                                      | Say this                                                                                                                               |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- |
| API key rejected (tasks stay skipped with "assistant paused" or the breakdown fails with an authentication message in `railway logs --service api --environment production --lines 100 --json`) | In Mike's terminal: `printf '%s' '<new key>' \| railway variable set ANTHROPIC_API_KEY --stdin --service api --environment production`; wait for the redeploy; create a task to prove it.                    | "The provider rejected the key. Keys live only in Railway variables; I am swapping it and the service redeploys in about two minutes." |
| GitHub Actions slow or queued                                                                                                                                                                   | Open the Actions tab, show the queue; narrate the gates from section 3 in the meantime; use the buffer.                                                                                                      | "This is the queue you would see on a busy afternoon; the gate is the same, the wait is not ours to skip."                             |
| Railway deployment stuck (`BUILDING` or `DEPLOYING` beyond five minutes)                                                                                                                        | `railway logs --service <svc> --environment staging --build --lines 200 --json` on screen; if the build is wedged, `railway redeploy --service <svc> --environment staging --yes`; keep the room on the log. | "Here is the build log. I am asking Railway to build again; nothing about the code changes."                                           |
| `implement-issue` stalled or the 20-minute mark passed                                                                                                                                          | Say `stop` in T1; the skill reports what is done; open a pull request with what exists (`gh pr create --draft`); show the branch and the tests that pass.                                                    | "Time-boxing is a rule, not a failure. What exists is on a branch with its tests; the rest is a second, smaller request."              |
| Staging smoke red in `promote`                                                                                                                                                                  | Download the `smoke-results` artifact, `npx playwright show-trace <trace.zip>`, show the failing step. Do not promote.                                                                                       | "The gate did its job. This is exactly the bug you do not want in production, caught by a browser, not by a person. We fix, we rerun." |
| Rate limit reached (`hourly limit reached` chips)                                                                                                                                               | `railway variable set AI_GLOBAL_LIMIT_PER_HOUR=1200 --service api --environment production`; two-minute redeploy.                                                                                            | "The session budget is a variable, not a deploy."                                                                                      |
| Cutoff at minute 65                                                                                                                                                                             | State what is incomplete, move on, show the rest at the start of Part 2.                                                                                                                                     | "The pipeline keeps running without us."                                                                                               |

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

| Date                      | Triage | Implement | Ship | Total | Notes |
| ------------------------- | ------ | --------- | ---- | ----- | ----- |
| (filled at the rehearsal) |        |           |      |       |       |
