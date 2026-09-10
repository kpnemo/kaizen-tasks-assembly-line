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

## 9. Merge to develop (minute 60)

- **TYPE**

```
gh pr checks <api pr url> --watch && gh pr merge <api pr url> --squash --delete-branch
gh pr checks <web pr url> --watch && gh pr merge <web pr url> --squash --delete-branch
gh pr checks <docs pr url> --watch && gh pr merge <docs pr url> --squash --delete-branch
railway deployment list --service web --environment staging --limit 1 --json | jq '.[0].status'
gh issue view <n> --repo kpnemo/kaizen-tasks-assembly-line --json labels --jq '[.labels[].name] | join(",")'
```

- **SEE** green checks, the three merges (API first, docs last), then Railway staging `WAITING` while CI runs, then building
- **SEE** once both halves are live on staging: one `Deployed to staging` comment per half on the issue, and `staging` where `implementing` was
- **SAY** "Railway already has the commit. It waits for GitHub to say the checks passed. The issue moved to `staging` on its own."

## 10. Cut the release in both app repos

- **TYPE** `/release-notes` in each app repo (same version), then

```
git -C backend push -u origin release/<version> && gh pr create --repo kpnemo/kaizen-tasks-api --base develop --head release/<version> --title "chore: release <version>" --body "Cut <version>"
git -C frontend push -u origin release/<version> && gh pr create --repo kpnemo/kaizen-tasks-web --base develop --head release/<version> --title "chore: release <version>" --body "Cut <version>"
gh pr checks <api release pr url> --watch && gh pr merge <api release pr url> --merge
gh pr checks <web release pr url> --watch && gh pr merge <web release pr url> --merge
scripts/check-versions.sh
railway deployment list --service api --environment staging --limit 1 --json | jq '.[0].status'
railway deployment list --service web --environment staging --limit 1 --json | jq '.[0].status'
curl -fsS https://web-staging-52c0.up.railway.app/api/v1/health | jq -r '.data.version + " " + .data.commit[:7]'
curl -fsS https://web-staging-52c0.up.railway.app/version.json | jq -r '.version + " " + .commit[:7]'
```

- **SEE** `versions match: <version>`, both staging deployments `SUCCESS`, and staging reporting the new version and commit
- **SAY** "Both halves carry the same number. The footer will prove it."

## 11. Promote to production

- **TYPE**

```
gh pr create --repo kpnemo/kaizen-tasks-api --base main --head develop --title "release: <version>" --body "Promote develop to main"
# both required gates must have registered before --watch means anything; bounded at 2 minutes
wait_for_gates() {   # $1 = promotion pull request url
  for i in $(seq 1 12); do
    gh pr view "$1" --json statusCheckRollup \
      --jq '[.statusCheckRollup[].name] | (index("ci") != null and index("promote") != null)' | grep -qx true && return 0
    sleep 10
  done
  echo "STOP: ci and promote have not registered on $1 after 2 minutes. Do not merge; open the Actions tab."; return 1
}
wait_for_gates <api promote pr url> && gh pr checks <api promote pr url> --watch && gh pr merge <api promote pr url> --merge
gh pr create --repo kpnemo/kaizen-tasks-web --base main --head develop --title "release: <version>" --body "Promote develop to main"
wait_for_gates <web promote pr url> && gh pr checks <web promote pr url> --watch && gh pr merge <web promote pr url> --merge
```

- **SEE** `wait_for_gates` return within a few seconds once both `ci` and `promote` have registered by name (without it `--watch` finds nothing and `main`'s policy refuses the merge; counting checks is not enough, Railway's own check makes two), then the `promote` job running the Playwright smoke against staging step by step, then the two merges, API first
- **SAY** "A browser is doing your acceptance test right now. Only then may main merge."

## 12. Production and the issue

- **TYPE**

```
curl -fsS https://web-production-7ef71.up.railway.app/api/v1/health | jq -r '.data.version + " " + .data.commit[:7]'
curl -fsS https://web-production-7ef71.up.railway.app/version.json | jq -r '.version + " " + .commit[:7]'
gh issue edit <n> --repo kpnemo/kaizen-tasks-assembly-line --add-label shipped
gh issue close <n> --repo kpnemo/kaizen-tasks-assembly-line --reason completed \
  --comment "Shipped in api <version> (<sha>) and web <version> (<sha>): https://web-production-7ef71.up.railway.app"
for i in $(seq 1 9); do
  read -r state labels <<<"$(gh issue view <n> --repo kpnemo/kaizen-tasks-assembly-line --json state,labels --jq '.state + " " + ([.labels[].name] | join(" "))')"
  case " $labels " in *" implementing "*|*" staging "*) [ "$state" = CLOSED ] && sleep 10 || break ;; *) break ;; esac
done
echo "$state $labels"     # expect: CLOSED shipped. OPEN means the harness reopened it (not in production yet): see section 4, do not add shipped again
```

then open the Triage board and flip that issue's row, Status `implementing` (or `staging`, if triage ran again) → `shipped` (the same cell `/implement-issue` set when it took the issue into work)

- **SEE** the new version and commit on both halves, the feature on production, the footer's new version, and the issue `CLOSED` with the shipped comment as its last line
- **SEE** the loop return within about a minute with `implementing` and `staging` retired by `.github/workflows/issue-lifecycle.yml`, not by you; `shipped` is the one you added
- **SAY** "Label first, then close: that is how the harness knows this close is a ship. Anything else that closes a request in work, it puts straight back. And that is your idea, your criteria, in production."

## If it breaks

| Symptom                                                   | Recovery in one line                                                                                                                                                            |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The in-app assistant is slow or toasts                    | Click "Skip the interview, fill the form" and keep going with the plain form.                                                                                                   |
| The round stalls or asks something silly                  | Answer "take your recommendations" — it takes the rewordings too, so it always moves on. "use the issue text" also ends the questioning, but can leave one criterion to answer. |
| CI red on `develop`                                       | Open the failing job's log on screen, fix forward if it is one line, otherwise move on and say so.                                                                              |
| `promote` red on the smoke                                | Download `smoke-results`, `npx playwright show-trace <trace.zip>`, show the failing step, do not promote.                                                                       |
| Railway slow (`BUILDING` past five minutes)               | Show the build log, talk the room through the pipeline, redeploy only if the build is wedged.                                                                                   |
| A bug report was filed instead of a request               | Run `/implement-issue <n>` anyway; the `bug` label routes it to systematic debugging.                                                                                           |
| `implementing` or `staging` is still there after the wait | `gh issue edit <n> --remove-label implementing --remove-label staging` and carry on; check the run later.                                                                       |
| The issue reopened itself, "Reopened by the harness"      | Before the read-back: a merge closed it, correct, leave it open and keep promoting. After: add `shipped`, close again.                                                          |
| `staging` never arrives after both halves are on staging  | Narration only, not a gate. Check `ASSEMBLY_LINE_TOKEN` in the app repos later and keep going.                                                                                  |

## Numbers to keep in mind

- Interview turn: 7 to 15 seconds. Past 15 with nothing on screen, use the escape hatch.
- Interview limit: 60 turns per user per hour (`INTERVIEW_HOURLY_LIMIT`); breakdowns 20 per user per hour, session budget `AI_GLOBAL_LIMIT_PER_HOUR=600`.
- Part 1 cutoff: minute 70. Name the live steps still running and stop driving them; minutes 70 to 75 are buffer and questions; Part 2 starts at minute 75.
- Briefing: bounded to three minutes from the `Brief start:` line it prints, the code exploration inside it asked for about one. If that exploration overruns two minutes, press Esc; the briefing carries on with the maps alone. The product maps are built before the session, not during it.
- The round: exactly one, at most four questions, every one with a recommended answer. "take your recommendations" answers all of them.
- Implement time box: the skill stops itself 25 minutes after it starts.
- Staging https://web-staging-52c0.up.railway.app, production https://web-production-7ef71.up.railway.app.
