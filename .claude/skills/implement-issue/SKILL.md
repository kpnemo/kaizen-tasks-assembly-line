---
name: implement-issue
description: Route one issue through the superpowers skills — brainstorm, spec, plan and TDD for a request, systematic debugging for a bug — open pull requests, never merge
argument-hint: "<issue number>"
---

# implement-issue

Take one issue from `kpnemo/kaizen-tasks-assembly-line`, mark it in progress, and route it through the superpowers skills installed in this Claude Code: a feature request goes interview, approaches, spec, plan, then test-first execution; a bug goes to systematic debugging. Both paths end the same way: the nested repos' own skills, their full checks, one pull request per affected repo, and stop.

This skill routes. It does not restate what the superpowers skills say: invoke each by name with the Skill tool and follow it as written.

Constants:

- `REPO=kpnemo/kaizen-tasks-assembly-line`
- Nested repos: `backend/` is `kpnemo/kaizen-tasks-api`; `frontend/` is `kpnemo/kaizen-tasks-web`. Base branch `develop` in both.
- Branch name: `feat/<n>-<slug>` where `<slug>` is the issue title lowercased, non-alphanumerics replaced by `-`, at most 40 characters. The same branch name in every repo, this one included.
- Spec: `docs/superpowers/specs/<YYYY-MM-DD>-issue-<n>-<slug>.md`. Plan: `docs/superpowers/plans/<YYYY-MM-DD>-issue-<n>-<slug>.md`. Both in this workspace repo.
- Working directory: the workspace root. Run every npm command inside the nested repo after `nvm use`.

## Hard rules

- Never run `gh pr merge`. Never push to `develop` or `main`. Never edit files outside `backend/`, `frontend/`, and this repo's `docs/superpowers/`.
- In this workspace repo commit only the spec and the plan, on `feat/<n>-<slug>`, and open them as a docs-only pull request.
- Never guess at an untestable criterion; stop and ask.
- One question at a time, through the AskUserQuestion tool when it is available, a numbered list otherwise.
- Show the failing test output in the transcript before writing implementation code, and the passing output after. The transcript is what the room sees.
- Every commit ends with the trailer line:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
```

## Milestone comments

The issue is the story the room follows, so every milestone lands on it as one short comment, in this fixed shape and nothing more (no transcripts, no diffs):

| When                                         | Comment                                                                                                                                                                                     |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 2, decision time                        | `Taken into work: implementing through /implement-issue <n>. Branches: <affected repo> feat/<n>-<slug>[, <other repo> ...]. Pull requests will reference this issue and close it on merge.` |
| Step 5, after the interview                  | `Interview done: <k> questions; approach chosen: <one line>.`                                                                                                                               |
| Step 5, after the spec and plan are approved | `Spec and plan approved: <spec path>, <plan path> on feat/<n>-<slug>.`                                                                                                                      |
| Step 8, as each pull request opens           | `Pull request opened: <url>` (once per pull request, the docs one included)                                                                                                                 |
| Runbook Ship, after the promotion            | `Shipped in <promotion pr url>; production serves <version>.` (the facilitator, not this skill)                                                                                             |

These are new comments. Never edit or reuse the triage comment, which is upserted by its marker `<!-- kaizen-triage -->`.

## Step 1: Read the issue and classify

```bash
gh issue view <n> --repo $REPO --json title,body,labels
```

Print `Start: $(date +%H:%M)`, then the path:

- Labels include `feature-request` (the request form's five sections: Problem, Proposed behavior, Acceptance criteria, Out of scope, Your role) → `Path: request`. Steps 2, 3, 4 (only when the labels also include `arch-change`), 5, 7, 8, 9, 10.
- Labels include `bug` (the bug form's five sections: What happened, What you expected, Steps to reproduce, Where, Your role) → `Path: bug`. Steps 2, 6, 7, 8, 9, 10. An issue carrying both labels is a bug.
- Neither label, or both: print the sections the body actually has and ask the facilitator which path, then follow the answer.

## Step 2: Take the issue into work

Before the interview, before any code:

```bash
gh issue edit <n> --repo $REPO --add-label implementing --add-assignee @me
```

The Triage board reads `implementing` from this label, so the room sees the status move before the work starts. Never set `shipped`: the runbook's Ship block does that after the merge.

Then create the working branch in each repo the request touches, **through GitHub**, so it shows under **Development** on the issue at once. Guess the repos from the request now (schema, queue, auth, prompt, proxy: `kaizen-tasks-api`; router, client, Caddyfile: `kaizen-tasks-web`); if the spec later pulls in the other repo, run the same block for it then. Resolve every id at run time, never hardcode one:

```bash
N=<n>; SLUG=<slug>
ISSUE_ID=$(gh api graphql -f query='{ repository(owner:"kpnemo", name:"kaizen-tasks-assembly-line"){ issue(number:'"$N"'){ id } } }' --jq .data.repository.issue.id)
for APP_REPO in kaizen-tasks-api kaizen-tasks-web; do   # only the affected ones
  read REPO_ID OID < <(gh api graphql -f query='{ repository(owner:"kpnemo", name:"'"$APP_REPO"'"){ id ref(qualifiedName:"refs/heads/develop"){ target{ oid } } } }' --jq '.data.repository | "\(.id) \(.ref.target.oid)"')
  gh api graphql -f query='mutation($issue:ID!, $repo:ID!, $oid:GitObjectID!, $name:String!){ createLinkedBranch(input:{issueId:$issue, repositoryId:$repo, oid:$oid, name:$name}){ linkedBranch{ ref{ name } } } }' \
    -F issue="$ISSUE_ID" -F repo="$REPO_ID" -F oid="$OID" -F name="feat/$N-$SLUG" \
    --jq '.data.createLinkedBranch.linkedBranch.ref.name'
done
git -C <backend|frontend> fetch origin && git -C <backend|frontend> switch feat/$N-$SLUG
```

`createLinkedBranch` accepts a `repositoryId` in a different repository from the issue's, so a branch in either app repo links back to this issue (`issueId` and `oid` are required, `name` and `repositoryId` optional; check with `gh api graphql -f query='{ __type(name:"CreateLinkedBranchInput"){ inputFields{ name } } }'` if a call is rejected). The branch shows under Development immediately and the pull request links when it opens; `Closes kpnemo/kaizen-tasks-assembly-line#<n>` in the pull request body is still what closes the issue on merge.

If the mutation fails (the branch already exists from an earlier run, or the API refuses), create the branches locally with the `git switch -c` fallback in Step 7; the branch names still go in the comment below, they just do not appear under Development.

Then the first milestone comment, naming the branches that now exist:

```bash
gh issue comment <n> --repo $REPO --body "Taken into work: implementing through /implement-issue <n>. Branches: kaizen-tasks-api feat/<n>-<slug>. Pull requests will reference this issue and close it on merge."
```

Name only the repositories you actually branched: one for one repo, both when the request touches both. If a later step pulls in the other repo, branch it then and say so in that step's comment.

Then flip this issue's row on the Triage board, so the board and the labels agree from this moment:

```bash
board=$(gh issue list --repo $REPO --label triage-board --state open --json number --jq '.[0].number // empty')
gh issue view "$board" --repo $REPO --json body --jq .body > /tmp/board.md
# edit exactly one cell: on the row whose Issue column is #<n>, Status triaged -> implementing
gh issue edit "$board" --repo $REPO --body-file /tmp/board.md
```

One cell, nothing else: no re-ranking, no new rows, no touch to the `Last run` line. If the issue has no row (it was filed after the last triage run), leave the board alone and say so; the next `/triage-requests` picks it up.

## Step 3: Restate the acceptance criteria (request path)

Print a numbered checklist copied from the `### Acceptance criteria` section, one line per bullet, and under each the test that will prove it (file and test name). If any criterion cannot be turned into a test (an adjective with no observable behavior, a number nobody stated), print `Untestable criterion: <text>` and `Question: <one sentence the requester can answer>` and stop. Do not continue with a guess.

## Step 4: Architecture change (request path)

If the labels include `arch-change`:

1. Decide the affected repo from the request (schema, queue, auth, prompt, proxy: `backend/`; router, client, Caddyfile: `frontend/`).
2. Check out the feature branch there (Step 2 already created it; the Step 7 command switches onto it and creates it locally if the linked branch was not made).
3. Read that repo's `.claude/skills/write-adr/SKILL.md` and write the ADR exactly as it says; commit it on the feature branch.
4. Stop with the sentence `ADR written, confirm to continue`.

Resume from Step 5 only when told to continue.

## Step 5: Brainstorm, spec, plan (request path)

First, in this workspace repo, so every commit the next two skills make lands on the branch Step 8 pushes:

```bash
git fetch origin develop
git switch -c feat/<n>-<slug> origin/develop 2>/dev/null || git switch feat/<n>-<slug>
```

Then invoke `superpowers:brainstorming` and follow it, with these constraints:

- The person interviewed is the product owner in the room, never an engineer. The subject is the REQUEST, never the implementation.
- Zero to four questions, one per turn, with the options drawn from the issue text. Skip every question the issue already answers; if it answers all four, say so and go straight to the approaches with no questions at all.
- Ask only what changes what gets built: who it is for, where in the UI it appears, what happens at the edge, what stays untouched. Never ask which library, which file, or which pattern.
- Take its architectural path, but present the whole design as **one** section and take **one** yes; never ask for an approval per section. Two or three approaches with trade-offs and a recommendation come first, and they need an answer before the spec.
- Do not offer the visual companion, and do not run `superpowers:using-git-worktrees`.
- Escape hatch: the facilitator may answer `use the issue text` to any question. Accept it, ask nothing further, and continue with what the issue already says.
- Write the spec to the constant path above. Sections: what, who, behavior, acceptance criteria restated as tests, out of scope, the repos and files touched.
- The facilitator's yes on the spec is the gate. No plan before it.

When the approaches have been answered, comment once:

```bash
gh issue comment <n> --repo $REPO --body "Interview done: <k> questions; approach chosen: <one line>."
```

Then invoke `superpowers:writing-plans`, scaled down for a live 30-minute segment:

- Write the plan to the constant path above.
- One to four tasks per affected repo, no more. Each task names the repo's own skill (`backend/.claude/skills/add-api-endpoint/SKILL.md` for the API, `frontend/.claude/skills/add-frontend-feature/SKILL.md` for the web) and carries the failing test, the implementation, that repo's checks, and the commit.
- The spec's acceptance criteria are the global constraints; the smallest slice that satisfies all of them is the whole plan. If both repos change, the API changes first and the web follows after pulling the contract.
- Show the plan and wait for the facilitator's yes.

On that yes, comment once (the docs pull request URL is added in Step 8, when it exists):

```bash
gh issue comment <n> --repo $REPO --body "Spec and plan approved: <spec path>, <plan path> on feat/<n>-<slug>."
```

Then Step 7.

## Step 6: Bug path

Check out the working branch before anything can write a fix (Step 2 created it on GitHub; this creates it locally if that failed):

```bash
git -C <backend|frontend> fetch origin
git -C <backend|frontend> switch feat/<n>-<slug> 2>/dev/null || git -C <backend|frontend> switch -c feat/<n>-<slug> origin/develop
```

Restate, in the reporter's words: expected behavior, actual behavior, and the reproduction steps as a numbered list; under them, the test that will capture the bug. If the steps do not reproduce, say so and ask the reporter one question. Do not guess.

Then invoke `superpowers:systematic-debugging` and follow its phases inside the affected repo: root cause before any fix, pattern analysis, hypothesis tested, then the fix. `superpowers:test-driven-development` still governs it — the failing test that captures the bug is written and shown failing before the fix.

No spec and no plan on this path: the issue is the specification. If the root cause turns out to need a product decision (behavior nobody ever specified), stop, say so, and ask the facilitator whether to file it as a feature request instead.

Then Step 7.

## Step 7: Execute in the affected repos

Request path: execute the plan with `superpowers:executing-plans`, or with `superpowers:subagent-driven-development` when the facilitator asks for subagents; say which one you are using. Bug path: the fix from Step 6 is the execution. Either way each task follows the nested repo's own skill, and every task is test-first.

Branch, API first when both repos change. Step 2 already created these on GitHub, so this checks them out and falls back to a local branch if it did not:

```bash
git -C backend fetch origin
git -C backend switch feat/<n>-<slug> 2>/dev/null || git -C backend switch -c feat/<n>-<slug> origin/develop
git -C frontend fetch origin
git -C frontend switch feat/<n>-<slug> 2>/dev/null || git -C frontend switch -c feat/<n>-<slug> origin/develop
```

When the contract changed in `backend/`, before any web code:

```bash
cd frontend && scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types && cd ..
```

Then, in each affected repo, after `nvm use`:

```bash
npm test
npm run typecheck
npm run lint
npm run openapi                                   # backend only, when the contract changed
git add -A && git commit -m "feat: <short title> (#<n>)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
npm run docs:check                                # the CI form of the docs gate, never the --hook form
```

Every command must exit 0. The docs gate runs after the commit because it reads the committed diff; if it fails, fix the docs and amend the commit.

Do not run `superpowers:using-git-worktrees`. The isolated workspaces are the `feat/<n>-<slug>` branches created at Step 2 inside `backend/` and `frontend/` (and at Step 5 here, for the docs); a worktree of this repository would hold neither app repo, because both are git-ignored here. When `executing-plans` or `subagent-driven-development` asks for a worktree, say the branch is it and carry on.

Do not run `superpowers:finishing-a-development-branch` either. Its menu offers integration choices; here the skill opens pull requests and stops, and the facilitator merges (`docs/runbook.md`).

Time box: check the clock at each step boundary against the `Start:` printed in Step 1. At 25 minutes, if Step 8 has not begun, stop and report what is done, what remains, which branch holds the commits, and the exact next command.

## Step 8: Push and open the pull requests

For each affected repo (`backend` with `kpnemo/kaizen-tasks-api`, `frontend` with `kpnemo/kaizen-tasks-web`):

```bash
git -C <dir> push -u origin feat/<n>-<slug>
gh pr create --repo kpnemo/<repo> --base develop --head feat/<n>-<slug> \
  --title "feat: <issue title> (#<n>)" --body-file <tempfile>
```

Do not bump `package.json` versions in feature pull requests; the release is cut with `/release-notes` in both repos at promotion time (runbook, Ship).

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

Then, on the request path, the spec and the plan in this workspace repo, as a third, docs-only pull request:

```bash
git switch feat/<n>-<slug>                                   # created at Step 5; brainstorming and writing-plans committed onto it
git add docs/superpowers/specs/<file> docs/superpowers/plans/<file>
git commit -m "docs: spec and plan for #<n>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"   # only if anything is still uncommitted
git push -u origin feat/<n>-<slug>
gh pr create --repo $REPO --base develop --head feat/<n>-<slug> \
  --title "docs: spec and plan for #<n>" --body "Spec and plan for #<n>. Docs only."
```

Comment each pull request on the issue as it opens, one line each:

```bash
gh issue comment <n> --repo $REPO --body "Pull request opened: <url>"
```

Print the pull request URLs. The API pull request is listed first, the docs one last.

## Step 9: Check the issue timeline

Open the issue and read it top to bottom against the path you took.

- Both paths: `Taken into work` with the branches, one `Pull request opened` per pull request, the label `implementing`, the assignee.
- Request path only: `Interview done`, `Spec and plan approved`, and the docs pull request among the `Pull request opened` lines.
- Bug path: none of those three, by design. There is no spec, no plan and no docs pull request to link, and a bug carries no triage comment because bugs are never scored.
- Linked branches under Development only when Step 2's mutation succeeded. The documented fallback (local branches, named in the take-into-work comment) is a pass, not a gap.

Post any comment genuinely missing for the path you took, and invent none. The room reads the journey here, not in the terminal. `shipped` and the final comment come later, from the runbook's Ship block.

## Step 10: Stop

Print the pull request URLs and the sentence `Ready for review and merge`. Do nothing else. Merging, promotion, and closing the issue are done by the facilitator following `docs/runbook.md`.

## Note on issue closing across repos

`Closes kpnemo/kaizen-tasks-assembly-line#<n>` closes the issue when the pull request merges because the author has write access to the assembly-line repo (verification item L1 in the assembly-line spec). The runbook checks `gh issue view <n> --repo $REPO --json state` after the merge; if the issue is still open, the facilitator runs `gh issue close <n> --repo $REPO --comment "Shipped in <pr url>"`.
