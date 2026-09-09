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
npm run typecheck
npm run lint
npm run openapi
npm run docs:check
git add -A && git commit -m "feat: <short title> (#<n>)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
cd ..
```

Every command above must exit 0 before the commit.

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
npm run typecheck
npm run lint
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

````markdown
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
````

Print the pull request URLs. The API pull request is listed first.

## Step 8: Mark the issue

```bash
gh issue edit <n> --repo $REPO --add-label implementing
gh issue comment <n> --repo $REPO --body "Pull requests: <api url> <web url>"
```

## Step 9: Stop

Print the pull request URLs and the sentence `Ready for review and merge`. Do nothing else. Merging, promotion, and closing the issue are done by the facilitator following `docs/runbook.md`.

## Note on issue closing across repos

`Closes kpnemo/kaizen-tasks-assembly-line#<n>` closes the issue when the pull request merges because the author has write access to the assembly-line repo (verification item L1 in the assembly-line spec). The runbook checks `gh issue view <n> --repo $REPO --json state` after the merge; if the issue is still open, the facilitator runs `gh issue close <n> --repo $REPO --comment "Shipped in <pr url>"`.
