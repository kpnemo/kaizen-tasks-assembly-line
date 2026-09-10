# Part 1 playbook (second screen)

One page, command first. TYPE is what you type or click, SEE is what appears on screen, SAY is the one line for the room. The full reference, the pre-session checklist and the rollback are in `docs/runbook.md`.

## 1. Open production as the demo user (minute 0)

- **TYPE** open https://web-production-7ef71.up.railway.app and log in as `demo@kaizen.local`
- **SEE** tasks with accepted AI steps, one with pending suggestions, one failed with retry; a new task's thinking chip resolving
- **SAY** "This is live production. Everything you see next reaches this URL within the hour."

## 2. The room files requests (minute 8)

- **TYPE** put on screen: https://github.com/kpnemo/kaizen-tasks-assembly-line/issues/new?template=feature-request.yml
- **SEE** the five fields: Problem, Proposed behavior, Acceptance criteria, Out of scope, Your role
- **SAY** "Acceptance criteria decide the ranking. Write for a tester, not for a developer."

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

- **TYPE** answer the skill's question on screen: pick one of the three offered issues
- **SEE** the top three by readiness, the recommended one first; then `Chosen: #<n>` and the next command
- **SAY** "The agent ranks. A person chooses. It never picks its own work."

## 6. Implement (minute 30)

- **TYPE**

```
/implement-issue <the number you chose>
```

- **SEE** the issue take the `implementing` label and an assignee, the issue showing the two branches under Development, and the Triage board status change
- **SAY** "It takes the issue into work first, so the board is honest while it runs."

## 7. The interview, the approach, the spec, the plan

- **TYPE** answer three or four questions, then one yes to the approach and spec, one yes to the plan
- **SEE** questions about the request (who, where, edges, what stays untouched), then the spec and plan files under `docs/superpowers/`
- **SAY** "It asks the product owner, not the engineer, and only what changes what gets built."

## 8. The failing test, the docs gate, the pull requests

- **TYPE** nothing; narrate
- **SEE** the red test output before any implementation, then green, then the docs gate, then the pull request URLs (API first, docs last); on the issue the timeline reads: taken into work → interview done → spec and plan approved → pull requests
- **SAY** "The failure is the specification. When it passes, your criterion is met exactly."

## 9. Merge to develop (minute 60)

- **TYPE**

```
gh pr checks <pr url> --watch && gh pr merge <pr url> --squash --delete-branch
```

- **SEE** green checks, the merge, then Railway staging `WAITING` while CI runs, then building
- **SAY** "Railway already has the commit. It waits for GitHub to say the checks passed."

## 10. Cut the release in both app repos

- **TYPE** `/release-notes` in each app repo (same version), then

```
git -C backend push -u origin release/<version> && gh pr create --repo kpnemo/kaizen-tasks-api --base develop --head release/<version> --title "chore: release <version>" --body "Cut <version>"
git -C frontend push -u origin release/<version> && gh pr create --repo kpnemo/kaizen-tasks-web --base develop --head release/<version> --title "chore: release <version>" --body "Cut <version>"
scripts/check-versions.sh
```

- **SEE** `versions match: <version>`, then both staging deployments `SUCCESS`
- **SAY** "Both halves carry the same number. The footer will prove it."

## 11. Promote to production

- **TYPE**

```
gh pr create --repo kpnemo/kaizen-tasks-api --base main --head develop --title "release: <version>" --body "Promote develop to main"
gh pr create --repo kpnemo/kaizen-tasks-web --base main --head develop --title "release: <version>" --body "Promote develop to main"
```

- **SEE** the `promote` job running the Playwright smoke against staging, step by step, then the merges
- **SAY** "A browser is doing your acceptance test right now. Only then may main merge."

## 12. Production and the issue

- **TYPE**

```
curl -fsS https://web-production-7ef71.up.railway.app/version.json | jq -r '.version + " " + .commit[:7]'
gh issue view <n> --repo kpnemo/kaizen-tasks-assembly-line --json state --jq .state
gh issue edit <n> --repo kpnemo/kaizen-tasks-assembly-line --add-label shipped --remove-label implementing
```

- **SEE** the new version and commit, the feature on production, the footer's new version, and the issue `CLOSED` with a last line: shipped in the promotion pull request
- **SAY** "Your idea, your criteria, in production, with the tests and gates that got it there."

## If it breaks

| Symptom                                                    | Recovery in one line                                                                                      |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| The in-app assistant is slow or toasts                     | Click "Skip the interview, fill the form" and keep going with the plain form.                             |
| The brainstorming interview stalls or asks something silly | Answer "use the issue text"; the skill accepts that and moves to the approaches.                          |
| CI red on `develop`                                        | Open the failing job's log on screen, fix forward if it is one line, otherwise move on and say so.        |
| `promote` red on the smoke                                 | Download `smoke-results`, `npx playwright show-trace <trace.zip>`, show the failing step, do not promote. |
| Railway slow (`BUILDING` past five minutes)                | Show the build log, talk the room through the pipeline, redeploy only if the build is wedged.             |
| A bug report was filed instead of a request                | Run `/implement-issue <n>` anyway; the `bug` label routes it to systematic debugging.                     |

## Numbers to keep in mind

- Interview turn: 7 to 15 seconds. Past 15 with nothing on screen, use the escape hatch.
- Interview limit: 60 turns per user per hour (`INTERVIEW_HOURLY_LIMIT`); breakdowns 20 per user per hour, session budget `AI_GLOBAL_LIMIT_PER_HOUR=600`.
- Part 1 cutoff: minute 70. State what is incomplete and move to Part 2.
- Implement time box: the skill stops itself 25 minutes after it starts.
- Staging https://web-staging-52c0.up.railway.app, production https://web-production-7ef71.up.railway.app.
