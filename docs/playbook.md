# Part 1 playbook (second screen)

One page, command first. TYPE is what you type or click, SEE is what appears on screen, SAY is the one line for the room. The full reference, the pre-session checklist and the rollback are in `docs/runbook.md`.

## 1. Open production as the demo user (minute 0)

- **TYPE** open https://web-production-7ef71.up.railway.app and log in as `demo@kaizen.local`
- **SEE** tasks with accepted AI steps, one with pending suggestions, one failed with retry; a new task's thinking chip resolving
- **SAY** "This is live production. Everything you see next reaches this URL within the hour."

## 2. The room files requests (minute 8)

- **TYPE** put on screen: https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/new/choose
- **SEE** the two forms, Feature request and Bug report; the request form's six fields: Problem, Proposed behavior, Acceptance criteria, Out of scope, Looks or mockup (optional), Your role
- **SAY** "Acceptance criteria decide the ranking. Something broken? Use the bug form instead."

## 3. The in-app interview (same segment)

- **TYPE** in production, "Request a feature": type a one-sentence idea, answer the chips, click "Review and file"
- **SEE** the fields filling in beside the chat, the readiness chip rising, then the issue with "How this request was refined"
- **SAY** "The assistant scores with the same rubric engineering triages with. No translation loss."

## 4. Triage (minute 22)

- **TYPE** in T1 (Claude Code at `webapp/`):

```
/triage-requests
```

- **SEE** the rubric narration, the dated report, score labels on each issue, the rewritten Triage board (the pinned issue), and the questions posted on low-clarity requests
- **SAY** "Same rubric, applied to every request, written back where you filed it."

## 5. Choose the issue (end of triage)

- **TYPE** answer the skill's question on screen: pick one of the offered issues, or name any other number
- **SEE** up to three non-architecture requests by readiness, the recommended one first; then `Chosen: #<n>` and the next command
- **SAY** "The agent ranks. A person chooses. It never picks its own work."

## 6. Implement (minute 30)

- **TYPE**

```
/implement-issue <the number you chose>
```

- **OR TYPE** `/auto-implement-issue <the number you chose>` and walk away from T1: no questions, Codex stands in for you on the round and reviews the spec, and the issue thread tells the story until it reads `Ready for staging`. Come back for the Deploy to staging click.

- **SEE** the issue take the `implementing` label and an assignee, the branches for the affected repos under Development (or their names in the comment when linking is refused), and that issue's row on the board flip to `implementing`
- **SEE** then the briefing, under three minutes: both product maps read, the whole issue thread, any attached mockup opened, one pass over the code, and on the issue a new comment `Context gathered: touches <areas>; today <one line>; open questions: <k>.`
- **SAY** "It takes the issue into work first, so the board is honest while it runs. Then it reads the product and the code before it asks you anything."

## 7. One round, the design, the approach, the spec, the plan

- **TYPE** answer the round in one message, or say "take your recommendations" (takes every one, rewordings included, so the run always carries on), or say "use the issue text" (ends the questioning too, but may leave one untestable criterion to answer); pick the design option when it appears; then one yes to the design, one yes to the plan
- **SEE** **one** round of at most four numbered questions, each with the agent's own recommended answer under it (blockers first: any acceptance criterion that cannot be turned into a test, with a testable rewording offered); no second round
- **SEE** when the request changes something visible, the design question as option cards with a small mockup in each, the recommended one first — or, when your request already said how it should look, that design shown back for a yes instead of a menu
- **SEE** then the approaches with a recommendation, and the briefing, spec and plan files under `docs/superpowers/`; the spec's `Looks` section says the control, the icons, the placement and both themes
- **SEE** on the issue: `Interview done: <k> questions, <r> recommendations taken; approach chosen: <one line>.`
- **SAY** "It read the product and the code before asking; every question left is one the issue really does not answer. And each one comes with the answer it would give, so I can just take them."

## 8. The failing test, the docs gate, the pull requests

- **TYPE** nothing; narrate
- **SEE** the red test output before any implementation, then green, then the docs gate, then the pull request URLs (API first, docs last); on the issue the timeline reads: taken into work → context gathered → interview done → spec and plan approved → pull requests
- **SAY** "The failure is the specification. When it passes, your criterion is met exactly."

## 9. Deploy to staging from the Pipeline page (minute 60)

- **TYPE** open https://web-production-7ef71.up.railway.app/pipeline (signed in as the facilitator account), find the issue's row, click **Deploy to staging**, type the deploy passphrase, confirm
- **SEE** before the click: the row at stage `Implementing`, one badge per pull request (api, web, the harness docs one), each green; the button appears only when every badge is green
- **SEE** after: the badges turn to merged, api then web then harness; the staging card goes `deploying`, then `current` with the new commits; on the issue one `Deployed to staging` comment per half, and the row's chip moves to `Staging` (the page polls every 10 s over a 30 s cache, so allow up to forty seconds)
- **SAY** "I am the person who merges, and I merge with a passphrase. Railway already has the commit; it waits for GitHub to say the checks passed. The issue moved to `staging` on its own."

## 10. Deploy to production from the Pipeline page

- **TYPE** on the same row, click **Deploy <version> to production**, type the passphrase, confirm; then click the run link that appears on the row
- **SEE** the version on the button before you press: minor when either changelog has Added or Changed bullets, patch otherwise, one number for both halves; the confirmation names every issue that ships with it
- **SEE** the row read `Shipping: <step>` and advance: Record the ship on the issues, Preflight, Cut release in api, Cut release in web, Merge the release pull requests, Wait for staging to serve the release, Open the promotion pull requests, Promote api, Promote web, Close the issues as shipped; inside the promotions, `promote` running the Playwright smoke against staging step by step
- **SEE** the production card show the new version and commit for both halves, the row move to `Shipped`, and the issue `CLOSED` with the shipped comment as its last line; `implementing` and `staging` retired within a minute
- **SAY** "One button, one workflow, in public. A browser is doing your acceptance test right now; only then may main merge. And nothing closes your request until production has read back the same hash."

## 11. If the page cannot do it

- **TYPE** in T2, the dispatch from the runbook's appendix ("Appendix: the same steps from a terminal", section 2): `gh workflow run ship.yml --repo kpnemo/kaizen-tasks-assembly-line -f request_id=$(uuidgen) -f version=<version> -f issues=<n>` and the `gh run watch` line under it; only if the workflow cannot run either, the hand sequence below them
- **SEE** the same run in Actions with the same step names, and the Pipeline page still showing it on the row: it reads the runs, not the button
- **SAY** "The button is a convenience. The pipeline is the workflow, and the workflow does not care who started it."

## 12. Production and the issue

- **TYPE** open https://web-production-7ef71.up.railway.app and refresh; open the issue on GitHub; if anyone wants the hash spelled out:

```
curl -fsS https://web-production-7ef71.up.railway.app/api/v1/health | jq -r '.data.version + " " + .data.commit[:7]'
curl -fsS https://web-production-7ef71.up.railway.app/version.json | jq -r '.version + " " + .commit[:7]'
```

- **SEE** the feature on production and the footer's new version on both halves; the issue `CLOSED`, last comment `Shipped in api <version> (<sha>) and web <version> (<sha>): <production url>`, labels down to `shipped`; the Triage board row flipped to `shipped`
- **SAY** "No pull request closed this, and I typed no label. Merging to `develop` was staging; the workflow closed it after production read back the same hash. That is your idea, your criteria, in production, in under an hour."

## If it breaks

| Symptom                                                                    | Recovery in one line                                                                                                                                                                                                           |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| The in-app assistant is slow or toasts                                     | Click "Skip the interview, fill the form" and keep going with the plain form.                                                                                                                                                  |
| The round stalls or asks something silly                                   | Answer "take your recommendations" — it takes the rewordings too, so it always moves on. "use the issue text" also ends the questioning, but can leave one criterion to answer.                                                |
| CI red on `develop`                                                        | Open the failing job's log on screen, fix forward if it is one line, otherwise move on and say so.                                                                                                                             |
| `promote` red on the smoke (`Ship failed at Promote api` or `Promote web`) | Open the run from the badge, download `smoke-results`, `npx playwright show-trace <trace.zip>`, show the failing step; fix, then Retry. Never promote by hand around a red smoke.                                              |
| Railway slow (`BUILDING` past five minutes)                                | Show the build log, talk the room through the pipeline, redeploy only if the build is wedged.                                                                                                                                  |
| A bug report was filed instead of a request                                | Run `/implement-issue <n>` anyway; the `bug` label routes it to systematic debugging.                                                                                                                                          |
| `implementing` or `staging` is still there after the wait                  | `gh issue edit <n> --remove-label implementing --remove-label staging` and carry on; check the run later.                                                                                                                      |
| The issue reopened itself, "Reopened by the harness"                       | Before production read back: a merge closed it, correct, leave it open and press Deploy to production as usual. After: add `shipped`, close again (runbook failure page).                                                      |
| The deploy buttons are missing                                             | Not a facilitator email, or the feature is off: `curl -fsS <web url>/api/v1/health \| jq -r .data.features.pipeline` must print `true`; check the five pipeline variables on `api` (runbook checklist). Meanwhile: section 11. |
| "Wrong passphrase" or "Too many attempts"                                  | Five wrong tries lock the account for ten minutes: wait for the time it names, or set a new `DEPLOY_PASSPHRASE` (12+ characters) on `api` (redeploys the API, two minutes). Meanwhile: section 11.                             |
| The page says "GitHub unreachable"                                         | Rate limit or token: the API serves its last-good snapshot with its age. Check `PIPELINE_GITHUB_TOKEN` expiry and permissions (spec tokens table). Meanwhile: section 11.                                                      |
| `Ship failed at <step>` on the row                                         | Open the run from the badge, fix what the step names, press Retry: the workflow reruns with the same inputs and resumes at that step.                                                                                          |
| `staging` never arrives after both halves are on staging                   | Narration only, not a gate. Check `ASSEMBLY_LINE_TOKEN` in the app repos later and keep going.                                                                                                                                 |

## Numbers to keep in mind

- Interview turn: 7 to 15 seconds. Past 15 with nothing on screen, use the escape hatch.
- Interview limit: 60 turns per user per hour (`INTERVIEW_HOURLY_LIMIT`); breakdowns 20 per user per hour, session budget `AI_GLOBAL_LIMIT_PER_HOUR=600`.
- Part 1 cutoff: minute 70. Name the live steps still running and stop driving them; minutes 70 to 75 are buffer and questions; Part 2 starts at minute 75.
- Briefing: bounded to three minutes from the `Brief start:` line it prints, the code exploration inside it asked for about one. If that exploration overruns two minutes, press Esc; the briefing carries on with the maps alone. The product maps are built before the session, not during it.
- The round: exactly one, at most four questions, every one with a recommended answer. "take your recommendations" answers all of them.
- Implement time box: the skill stops itself 25 minutes after it starts.
- Pipeline page: polls every 10 s over a 30 s API cache, so a merge or a label shows within about forty seconds. Passphrase: five wrong attempts lock the account for ten minutes.
- Ship: the button removes the typing, not the CI and deploy minutes; a full production ship is about eight to twelve minutes end to end. The Ship slot is ten, the buffer five.
- Staging https://web-staging-52c0.up.railway.app, production https://web-production-7ef71.up.railway.app.
