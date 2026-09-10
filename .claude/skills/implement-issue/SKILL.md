---
name: implement-issue
description: Route one issue through the superpowers skills — brief, one grilling round, spec, plan and TDD for a request, systematic debugging for a bug — open pull requests, never merge
argument-hint: "<issue number>"
---

# implement-issue

Take one issue from `kpnemo/kaizen-tasks-assembly-line`, mark it in progress, and route it through the superpowers skills installed in this Claude Code: a feature request is briefed against the product maps and the code first, then goes one bounded round of questions, approaches, spec, plan, and test-first execution; a bug goes to systematic debugging. Both paths end the same way: the nested repos' own skills, their full checks, one pull request per affected repo, and stop.

The briefing is what makes the round short. The agent reads the two product maps, the whole issue thread and any mockup, and explores the code once, before it asks anything — so the questions that survive are only the ones the issue genuinely does not answer.

This skill routes. It does not restate what the superpowers skills say: invoke each by name with the Skill tool and follow it as written.

Constants:

- `REPO=kpnemo/kaizen-tasks-assembly-line`
- Nested repos: `backend/` is `kpnemo/kaizen-tasks-api`; `frontend/` is `kpnemo/kaizen-tasks-web`. Base branch `develop` in both.
- Branch name: `feat/<n>-<slug>` where `<slug>` is the issue title lowercased, with every **run** of non-alphanumerics collapsed to a single `-`, then truncated to at most 40 characters, then trimmed of any leading or trailing `-`. Collapse the run, never one character at a time: "Add light, dark, and system theme toggle" is `add-light-dark-and-system-theme-toggle`, not `add-light--dark--and-system-theme-toggle`. Check it before you use it: `printf '%s' "<title>" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-40 | sed -E 's/-+$//'`. The same branch name in every repo, this one included.
- Briefing: `docs/superpowers/briefs/<YYYY-MM-DD>-issue-<n>-<slug>.md`. Spec: `docs/superpowers/specs/<YYYY-MM-DD>-issue-<n>-<slug>.md`. Plan: `docs/superpowers/plans/<YYYY-MM-DD>-issue-<n>-<slug>.md`. All three in this workspace repo, all three on `feat/<n>-<slug>`.
- Briefing scratch: `.superpowers/briefs/<n>/`, git-ignored, for downloaded attachments only. Nothing in it is ever committed.
- Read at Step 2b: `backend/docs/product-map.md`, `frontend/docs/product-map.md`, `frontend/docs/ui-conventions.md`. Each app repo regenerates its map with `npm run product-map`; a stale map fails that repo's docs gate.
- Working directory: the workspace root. Run every npm command inside the nested repo after `nvm use`.

## Hard rules

- Never run `gh pr merge`. Never push to `develop` or `main`. Never edit files outside `backend/`, `frontend/`, this repo's `docs/superpowers/` (its `briefs/`, `specs/` and `plans/`), and the git-ignored scratch `.superpowers/briefs/<n>/`.
- In this workspace repo commit only the briefing, the spec and the plan, on `feat/<n>-<slug>`, and open all three as one docs-only pull request. `.superpowers/` is scratch and stays out of git: if `git check-ignore -q .superpowers/` does not succeed, add the line `.superpowers/` to `.gitignore` before writing anything there (the trailing slash matters — the pattern is directory-only).
- Never guess at an untestable criterion. It is no longer a stop: it leads the Step 5 round as a question carrying a recommended testable rewording (Step 3). If the answer still leaves it untestable, stop there with that blocker.
- The Step 5 round is one message with at most four numbered questions, each carrying its recommended answer; the design question inside it goes through AskUserQuestion with the recommended option first. Every other question, on either path, is asked one at a time, through the AskUserQuestion tool when it is available and a numbered list otherwise.
- Show the failing test output in the transcript before writing implementation code, and the passing output after. The transcript is what the room sees.
- Every commit ends with the trailer line:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
```

## Milestone comments

The issue is the story the room follows, so every milestone lands on it as one short comment, in this fixed shape and nothing more (no transcripts, no diffs):

| When                                         | Comment                                                                                                                                                                                                                |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Step 2, decision time                        | `Taken into work: implementing through /implement-issue <n>. Branches: <affected repo> feat/<n>-<slug>[, <other repo> ...]. Pull requests will reference this issue; it closes when the change is live in production.` |
| Step 2b, after the briefing                  | `Context gathered: touches <areas>; today <one line>; open questions: <k>.`                                                                                                                                            |
| Step 5, after the round                      | `Interview done: <k> questions, <r> recommendations taken; approach chosen: <one line>.`                                                                                                                               |
| Step 5, after the spec and plan are approved | `Spec and plan approved: <spec path>, <plan path> on feat/<n>-<slug>.`                                                                                                                                                 |
| Step 8, as each pull request opens           | `Pull request opened: <url>` (once per pull request, the docs one included)                                                                                                                                            |
| Runbook Ship, after the production read-back | `Shipped in api <version> (<sha>) and web <version> (<sha>): <production url>`, posted by the facilitator's `gh issue close --comment`, not by this skill                                                              |

These are new comments. Never edit or reuse the triage comment, which is upserted by its marker `<!-- kaizen-triage -->`.

## Step 1: Read the issue and classify

```bash
gh issue view <n> --repo $REPO --json title,body,labels
```

Print `Start: $(date +%H:%M)`, then the path:

- Labels include `feature-request` (the request form's six sections: Problem, Proposed behavior, Acceptance criteria, Out of scope, Looks or mockup — optional — and Your role) → `Path: request`. Steps 2, 2b, 3, 4 (only when the labels also include `arch-change`), 5, 7, 8, 9, 10.
- Labels include `bug` (the bug form's five sections: What happened, What you expected, Steps to reproduce, Where, Your role) → `Path: bug`. Steps 2, 6, 7, 8, 9, 10. An issue carrying both labels is a bug.
- Neither label, or both: print the sections the body actually has and ask the facilitator which path, then follow the answer.

## Step 2: Take the issue into work

Before the interview, before any code:

```bash
gh issue edit <n> --repo $REPO --add-label implementing --add-assignee @me
```

The Triage board reads `implementing` from this label, so the room sees the status move before the work starts.

`implementing` is the only lifecycle label this skill ever touches. The three states, and who sets each:

| Label          | Meaning                                           | Set by                                                              |
| -------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| `implementing` | taken into work, code being written               | **this skill**, right here                                          |
| `staging`      | every pull request merged and staging serves them | the app repos' `staging-label` workflow, after the merges           |
| `shipped`      | live in production                                | the facilitator's Ship step, immediately before it closes the issue |

Never set or remove `staging` or `shipped`. Both arrive after this skill has stopped. `.github/workflows/issue-lifecycle.yml` retires `implementing` and `staging` on that close — and puts the issue back if something closes it while it is still in work.

Then create the harness branch here, in this workspace repo, before anything writes a file:

```bash
git fetch origin develop
git switch -c feat/<n>-<slug> origin/develop 2>/dev/null || git switch feat/<n>-<slug>
```

This branch used to be created at Step 5. It is created here because Step 2b writes the briefing, and the briefing, the spec and the plan all belong on the branch Step 8 pushes.

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

`createLinkedBranch` accepts a `repositoryId` in a different repository from the issue's, so a branch in either app repo links back to this issue (`issueId` and `oid` are required, `name` and `repositoryId` optional; check with `gh api graphql -f query='{ __type(name:"CreateLinkedBranchInput"){ inputFields{ name } } }'` if a call is rejected). The branch shows under **Development** immediately, and it is the linked branch — not the `Part of` line in the pull request body — that keeps that panel populated once the pull request opens from it. Nothing a pull request says ever closes the issue (see the note at the end).

If the mutation fails (the branch already exists from an earlier run, or the API refuses), create the branches locally with the `git switch -c` fallback in Step 7; the branch names still go in the comment below, they just do not appear under Development.

Then the first milestone comment, naming the branches that now exist:

```bash
gh issue comment <n> --repo $REPO --body "Taken into work: implementing through /implement-issue <n>. Branches: kaizen-tasks-api feat/<n>-<slug>. Pull requests will reference this issue; it closes when the change is live in production."
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

## Step 2b: Brief (request path)

Read the product and the code before asking anything, so every question that survives is one the issue really does not answer. The whole step has an aggregate deadline of **three minutes** from the `Start:` clock printed in Step 1; when that runs out, write the briefing with what you have and say in it what is missing.

Read, in this order:

1. The issue body, its "Looks or mockup" section included.
2. **Every** comment on the issue, not only the triage one:

```bash
gh issue view <n> --repo $REPO --json comments \
  --jq '.comments[] | "--- " + .author.login + " " + .createdAt + "\n" + .body'
```

The triage comment (marker `<!-- kaizen-triage -->`) carries the scores and the clarity questions. Every **later** comment from the requester or the facilitator is a decision: it overrides anything earlier that contradicts it, the issue body included. No triage comment is not a blocker — record `triage: not run` and carry on.

3. `backend/docs/product-map.md` and `frontend/docs/product-map.md`: what the product does today, its endpoints, its tables, its routes and screens. Each app repo keeps its map fresh with `npm run product-map`, and its docs gate fails if it is stale, so the maps can be trusted as of this checkout.
4. `frontend/docs/ui-conventions.md`: the vocabulary the design question is drawn from.

### Attachments

Download every image the issue body references — `![…](https://github.com/user-attachments/assets/…)` and `<img src="…">` alike — **at most four**, into the git-ignored scratch:

```bash
mkdir -p .superpowers/briefs/<n>
curl -fsSL --max-time 10 --max-filesize 5000000 -o .superpowers/briefs/<n>/<name> "<url>"
```

Open each downloaded file with the Read tool and write down what it shows: the screen, the control, where it sits, what is labelled. A download that fails is one line in the briefing (`attachment <url>: <reason>`) and nothing more — never retry it, never block on it.

### One exploration

Dispatch **one** read-only Explore subagent, breadth `medium`. Its prompt carries the request text and, from the two maps, the route list, the endpoint table and the table names — never the maps whole. Ask it for exactly four things:

1. the screens, components, endpoints and tables the request touches;
2. the current behavior in those places;
3. anything that already exists which the request may be asking for;
4. anything standing in the way.

Say in the prompt: **answer in under 25 lines, and you have about 60 seconds**. One subagent, never two, and no follow-up dispatch. If it has not reported after 90 seconds, carry on with the maps alone and list what stayed unknown under **Unknowns** in the briefing. Do not wait for it a second time.

### Classify

From all of that, decide and write down:

- `UI: visible` — the request adds or changes something a user sees — or `UI: none`.
- The repos touched (`kaizen-tasks-api`, `kaizen-tasks-web`, or both), checked against the guess Step 2 branched from. If that guess was wrong, branch the other repo now with Step 2's block and say so in this step's comment.

### Write the briefing

Write `docs/superpowers/briefs/<YYYY-MM-DD>-issue-<n>-<slug>.md`, under two pages, with these headings and nothing else:

```markdown
# Briefing: #<n> <title>

- Summary: <two or three lines, the request in the requester's own terms>
- Triage: readiness <score>, clarity <c>, complexity <x>, risk <r> — or `not run`
- UI: visible | none
- Repos: <list>

## What exists today

<what the maps and the exploration say is already there, in the places this request touches>

## Touched areas

<screens, components, endpoints, tables, each with its path>

## Mockups seen

<one line per attachment: what it shows — or "none">

## Unknowns

<whatever the exploration did not answer in time — or "none">

## Open questions

1. <question> — suggested answer: <the answer this briefing would give>
2. ...
```

**Open questions** are only the ones the briefing genuinely cannot settle. Anything the maps, the comments or the exploration already answer is settled, and a settled thing is never asked. Three at most: if more than three survive, keep the three that change what gets built, and record the rest as decisions you took.

Leave the file uncommitted — Step 8 stages it with the spec and the plan. Then the milestone comment:

```bash
gh issue comment <n> --repo $REPO --body "Context gathered: touches <areas>; today <one line>; open questions: <k>."
```

There is no briefing on the bug path: Step 6 restates the report and goes to systematic debugging.

## Step 3: Restate the effective acceptance criteria (request path)

Print a numbered checklist of the **effective** acceptance criteria — one line per criterion, and under each the test that will prove it (file and test name).

Effective, not copied. Step 2b read every comment on the issue and established that a later comment from the requester or the facilitator is a decision that overrides the body. The acceptance criteria are no exception: a criterion the requester changed in a reply is the changed one, and testing the form's original wording would ship the wrong thing. So start from the `### Acceptance criteria` section, then apply every later decision in the thread — replaced, added or struck — and **cite the comment that made each change** on the line it changed:

```
1. <criterion, as it now stands> — <test file>::<test name>
   (replaced by @<author>, <date>: "<the words that changed it>")
2. <criterion nothing overrode> — <test file>::<test name>
3. <criterion> — struck by @<author>, <date>: "<the words that struck it>"
```

A criterion nothing overrode carries no citation. If the thread contradicts itself, the latest comment wins and that line says so. If a later comment adds a criterion the form never had, it joins the list with its citation like any other. This checklist, not the form's text, is what the spec restates as tests and what the pull request checks off.

A criterion that cannot be turned into a test — an adjective with no observable behavior, a number nobody stated — is **not a stop**. Print `Untestable criterion: <text>` and add it to the briefing's **Open questions**, ahead of the ones Step 2b found, with a testable rewording you would accept as its recommended answer:

```
Untestable criterion: "the list should feel fast"
Suggested rewording: the list renders the first 50 tasks within 200 ms of the response arriving, asserted in the component test.
```

These are blockers, and Step 5 places them in the round after the design question's reserved slot and before the briefing's open questions ("Building the round"). They never enlarge it past four and they are never dropped to make room: when the slots are short, all of them are combined into one question. Add each to the briefing's **Open questions** marked `blocker:` so the round-builder can recognise it and count it once. If an answer still leaves a criterion untestable, stop there with that blocker — say which criterion and what is still missing. That is the one place a criterion stops this path.

Step 2b's `Context gathered` comment was posted before this pass, so its count does not include these. Do not re-post it; the count that has to be right is the round's own, in `Interview done`.

## Step 4: Architecture change (request path)

If the labels include `arch-change`:

1. Decide the affected repo from the request (schema, queue, auth, prompt, proxy: `backend/`; router, client, Caddyfile: `frontend/`).
2. Check out the feature branch there (Step 2 already created it; the Step 7 command switches onto it and creates it locally if the linked branch was not made).
3. Read that repo's `.claude/skills/write-adr/SKILL.md` and write the ADR exactly as it says; commit it on the feature branch.
4. Stop with the sentence `ADR written, confirm to continue`.

Resume from Step 5 only when told to continue. This is the **only** ADR that stops for a human; the ones the nested repos' own skills ask for during Step 7 are records, not gates (Step 7, "One gate, one confirmation").

## Step 5: One round, the design, the spec, the plan (request path)

The branch here already exists (Step 2) and the briefing is written (Step 2b). What is left is the handful of questions the briefing could not settle, one design decision when the request is visible, and then the approaches, the spec and the plan.

### The round

Invoke `mattpocock-skills:grilling` and give it this override block, verbatim, as the workshop instructions it runs under. They take precedence over that skill's own text wherever the two differ:

> **Workshop overrides — these win over the grilling skill's own text.**
>
> - **Exactly one round.** Ask the frontier once. There is no second round, no follow-up round, and no recomputed frontier. When the round is answered, the interview is over.
> - **No subagents.** Do not dispatch anything to find facts. The facts are already gathered: they are in `docs/superpowers/briefs/<YYYY-MM-DD>-issue-<n>-<slug>.md`, and the one exploration that produced them has already run (Step 2b).
> - **No "shared understanding" confirmation.** Do not ask the user to confirm a shared understanding at the end. The gates are the ones named below and nothing else.
> - **At most four numbered questions**, in the skill's own format (`❓ **Q1** — **<title>**: …` then `➡️ <recommended answer>`), every one of them carrying its recommended answer.
> - **The round ends** the moment the product owner answers, or says `take your recommendations`, or says `use the issue text` — whichever comes first. Then stop asking and continue with what you have.

#### Building the round

Four questions is a hard ceiling, and the design question must never be the one that falls off the end. So the round is **one deduplicated list cut to four**, not three sources added together:

1. **Collect** into one list: the design question (only when `UI: visible`), every untestable criterion Step 3 found, and the briefing's open questions.
2. **Deduplicate.** A blocker that Step 3 appended to the briefing's **Open questions** is the same item read twice — keep it once, as the blocker. So is a briefing question that only asks what a blocker's proposed rewording already settles. Count each decision once, never twice.
3. **Allocate the four slots in this order**, and stop when they are full:
   - **The design question first**, when `UI: visible`. Its slot is reserved before anything else is placed, so it can never be squeezed out by blockers or by the briefing.
   - **Then the blockers**, in the order Step 3 found them.
   - **Then the briefing's open questions**, the ones that most change what gets built first.
4. **Never drop a blocker to make room.** If the blockers do not fit in the slots that are left, combine their rewordings into **one** question that lists each criterion with the rewording proposed for it and takes a single answer. One question, several criteria, one answer.
5. Anything that still does not fit is **not asked**. Record it in the briefing as a decision you took, with the answer you took, so the room can see it was decided rather than forgotten.

Two rules on shape. When two open questions depend on each other, never ask them separately: present complete alternatives as the options — bundles, each one answering both, so no answer can strand the other (a bundle is one slot, not two). And when the list is empty after step 2 — the briefing left nothing open and the classification is `UI: none` — there is no round at all: print `No open questions: the issue and the product maps answer everything, and nothing visible changes.` and go straight to the approaches.

`take your recommendations` answers the whole round at once; `use the issue text` ends it with what the issue already says. Both are in the runbook's failure page, and neither is permission to merge anything: this skill still never merges.

Gates after the round, and only these: the `arch-change` confirmation at Step 4 when the label is present, one yes on the design (the approaches and the spec together), one yes on the plan.

### The design question

When the briefing says `UI: visible`, exactly one design question, through AskUserQuestion, the **recommended option first**:

- Two or three options, drawn from `frontend/docs/ui-conventions.md` and the header controls the web product map inventories — a group of `Button` variants with `aria-pressed` and a lucide icon each, an entry in the existing dropdown menu, a `NativeSelect` only past eight options.
- Every option's description carries a **small text mockup** of what it looks like, so the room sees the choice instead of reading about it:

```
[ ☀ Light | ☾ Dark | ▣ System ]     in the header, left of the account menu
```

- The options are what the user sees, never how it is built. Never ask which component file, which library, which prop.
- **Confirmation, not a menu, when the request already decided.** If the issue carries a mockup (Step 2b downloaded it and looked at it) or names a look in its "Looks or mockup" section, do not offer alternatives: show that design back as the first option, recommended, with its text mockup, and make the second `Something else — say what`. A request that names a look wins, within `ui-conventions.md`'s accessibility rules.

### The approaches and the spec

Then invoke `superpowers:brainstorming` and **start it at the approaches**: state that the questions are done, that the round has been held and must not be repeated, and hand it the briefing together with the answers. Its constraints here:

- The person interviewed is the product owner in the room, never an engineer. The subject is the REQUEST, never the implementation.
- Two or three approaches with trade-offs and a recommendation, presented with the spec as **one** section taking **one** yes. Never ask for an approval per section.
- Do not offer the visual companion, and do not run `superpowers:using-git-worktrees`.
- Write the spec to the constant path above. Sections: what, who, behavior, acceptance criteria restated as tests, out of scope, the repos and files touched. The criteria it restates are Step 3's **effective** ones, citations included — never a fresh copy of the form's text.
- The line under the spec's title is `Context: docs/superpowers/briefs/<YYYY-MM-DD>-issue-<n>-<slug>.md` — the briefing is where everything the spec asserts about today's behavior comes from.
- When the briefing says `UI: visible`, the spec carries a `## Looks` section: the control type, its icons, where it sits, and how it reads in both themes. That section is what the screenshots are checked against before the web pull request opens.
- The facilitator's yes on the spec is the gate. No plan before it.

When the design has been answered, comment once:

```bash
gh issue comment <n> --repo $REPO --body "Interview done: <k> questions, <r> recommendations taken; approach chosen: <one line>."
```

`<k>` is how many questions the round actually asked (`0` when it was skipped), `<r>` how many of them were answered by taking the recommendation (`take your recommendations` makes the two equal).

### The plan

Then invoke `superpowers:writing-plans`, scaled down for a live 30-minute segment:

- Write the plan to the constant path above.
- One to four tasks per affected repo, no more. Each task names the repo's own skill (`backend/.claude/skills/add-api-endpoint/SKILL.md` for the API, `frontend/.claude/skills/add-frontend-feature/SKILL.md` for the web) and carries the failing test, the implementation, that repo's checks, and the commit.
- **The web task carries the screenshot step whenever anything visible changes**: after the change is committed, run `node scripts/screenshot.mjs <scenario>` in `frontend/` (the scenarios are small files under `frontend/scripts/screenshots/`), open both PNGs with the Read tool, compare them against the spec's `## Looks` section, and commit `docs/screenshots/<name>-{light,dark}.png`. The web pull request body then embeds them with **commit-pinned** URLs — `https://raw.githubusercontent.com/kpnemo/kaizen-tasks-web/<sha of the commit that added the PNGs>/docs/screenshots/<file>`, never the branch name, and re-pinned if a later commit replaces the images. If the script exits 2, the body carries the one line `Screenshot unavailable: <the reason it printed>` and no images; that is the only allowed exception.
- The spec's acceptance criteria are the global constraints; the smallest slice that satisfies all of them is the whole plan. If both repos change, the API changes first and the web follows after pulling the contract. When the contract itself changes, the plan carries the ripple as named tasks, not as an afterthought (Step 7, "The contract ripple"): the API's `docs/API.md` and README route table, the web's pull and regenerated types, the web's ADR, and the auth-store literal if the user shape moved.
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

### The contract ripple

A change to the API contract is never one file. When `backend/` adds or changes a route, a request body or a response shape, walk the whole ripple before the web half is touched — `backend/.claude/skills/add-api-endpoint/SKILL.md` is the authority, this is the checklist:

1. In `backend/`: `npm run openapi` regenerates `openapi.json` **and** `docs/API.md`, the endpoint inventory — commit both. Add the route to the `## Routes` table in `backend/README.md` by hand; the generator does not touch it.
2. In `frontend/`, before any web code:

```bash
cd frontend && scripts/pull-openapi.sh --local ../backend/openapi.json && npm run api:types && cd ..
```

3. Still in `frontend/`: write the ADR. `src/api/**` is the first glob in that repo's `docs/architectural-files.txt`, and the pull rewrites `src/api/openapi.json` and `src/api/types.ts`, so **every** contract pull needs an ADR under `docs/adr/`. That is by design, not a snag: the ADR records which contract the web half pulled and what it had to change to match. Follow `frontend/.claude/skills/write-adr/SKILL.md`; one short ADR, no confirmation asked (see the gate note below).
4. If the change alters the user shape, `frontend/src/api/auth-store.ts` and its `auth-store.test.ts` literal follow it in the same commit. Say so in the API commit message so the web half knows to look.

Then, in each affected repo, after `nvm use`:

```bash
npm run openapi                                   # backend only, when the contract changed; it feeds the map, so it runs first
npm run product-map                               # regenerates docs/product-map.md from this checkout
npm test
npm run typecheck
npm run lint
git add -A && git commit -m "feat: <short title> (#<n>)" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
BASE_SHA=$(git merge-base origin/develop HEAD) bash scripts/docs-check.sh --ci    # last line must be `docs-check: OK`
```

Every command must exit 0, and the docs gate must print `docs-check: OK` on its last line.

`npm run product-map` comes before the checks and before the commit for a reason: the docs gate regenerates the map on every run and compares it with the committed one, so a map that was not rebuilt fails the gate — and the map is what the next `/implement-issue` reads at Step 2b instead of guessing at the product. It is deterministic: on an unchanged tree it rewrites the same bytes and `git status` stays clean.

Two traps in that last command, both of which cost time in the 2026-09-10 dry run:

- **Never `npm run docs:check` here.** In both app repos that script is `bash scripts/docs-check.sh --hook`, the Stop-hook mode: it expects the hook's JSON on stdin, counts consecutive blocks, and after three of them writes `.claude/DOCS-CHECK-FAILED` and stops blocking. `--ci` is the mode CI runs, and the only one that answers "would this pull request pass".
- **Always pass `BASE_SHA`.** `--ci` diffs `$BASE_SHA...HEAD`. The API's script refuses to run without it; the web's silently falls back to `HEAD~1`, which sees only the last commit of a multi-commit branch and waves through docs drift from every commit before it. `git merge-base origin/develop HEAD` is the same base the pull request will have.

The gate runs after the commit because it reads the committed diff; if it fails, fix the docs and amend the commit.

Do not run `superpowers:using-git-worktrees`. The isolated workspaces are the `feat/<n>-<slug>` branches created at Step 2 inside `backend/` and `frontend/` (and, at the same step, here, for the docs); a worktree of this repository would hold neither app repo, because both are git-ignored here. When `executing-plans` or `subagent-driven-development` asks for a worktree, say the branch is it and carry on.

Do not run `superpowers:finishing-a-development-branch` either. Its menu offers integration choices; here the skill opens pull requests and stops, and the facilitator merges (`docs/runbook.md`).

### One gate, one confirmation

`arch-change` is the only architecture question that stops for a human, and it stops exactly once, at Step 4, with `ADR written, confirm to continue`. Every other ADR — the contract-pull one above, and any ADR a nested repo's own skill asks for because the change touched that repo's architectural files — is a **record, not a gate**: write it, commit it, carry on, and never ask the facilitator to confirm it. `.claude/skills/triage-requests/SKILL.md`, which sets the label, says the same thing in the same words.

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

Part of kpnemo/kaizen-tasks-assembly-line#<n>

## Acceptance criteria

- [x] <criterion 1, as Step 3 made it effective>: <test file and name>
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

Docs-check: `docs-check: OK`
````

**No closing keyword, in any pull request, ever.** `develop` is the app repos' default branch, so GitHub acts on `Closes`/`Fixes` the moment a pull request merges there — that is staging, not production, and the issue must close only when the request is live in production. `Part of` puts the pull request on the issue's timeline as a cross-reference without any of that; the facilitator closes the issue by hand after the production read-back (`docs/runbook.md`, Ship), and `.github/workflows/issue-lifecycle.yml` moves the labels.

Then, on the request path, the briefing, the spec and the plan in this workspace repo, as a third, docs-only pull request:

```bash
git switch feat/<n>-<slug>                                   # created at Step 2; the briefing, the spec and the plan are on it
git add docs/superpowers/briefs/<file> docs/superpowers/specs/<file> docs/superpowers/plans/<file>
git commit -m "docs: briefing, spec and plan for #<n>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"   # only if anything is still uncommitted
git push -u origin feat/<n>-<slug>
gh pr create --repo $REPO --base develop --head feat/<n>-<slug> \
  --title "docs: briefing, spec and plan for #<n>" --body "Briefing, spec and plan for #<n>. Docs only."
```

All three files, never two: the briefing is the record of what the agent knew before it asked anything, and the reviewer reads the spec against it. Nothing from `.superpowers/` is staged — it is git-ignored scratch.

Comment each pull request on the issue as it opens, one line each:

```bash
gh issue comment <n> --repo $REPO --body "Pull request opened: <url>"
```

Print the pull request URLs. The API pull request is listed first, the docs one last.

## Step 9: Check the issue timeline

Open the issue and read it top to bottom against the path you took.

- Both paths: `Taken into work` with the branches, one `Pull request opened` per pull request, the label `implementing`, the assignee.
- Request path only: `Context gathered`, `Interview done`, `Spec and plan approved`, and the docs pull request among the `Pull request opened` lines. Open that docs pull request and check it carries three files: the briefing, the spec and the plan.
- Bug path: none of those four, by design. There is no spec, no plan and no docs pull request to link, and a bug carries no triage comment because bugs are never scored.
- The **Development** panel lists whatever Step 2's `createLinkedBranch` managed to link, and nothing else: the `Part of` line in a pull request body is a plain cross-reference, so it shows on the timeline ("mentioned this issue in ...") but never in that panel. The documented fallback (local branches, named in the take-into-work comment) is a pass, not a gap.
- What must **not** be there yet: the `staging` label, the `shipped` label, a shipped comment, a closed state. All four come after this skill stops — `staging` from the app repos' workflow once the merges land, the rest at ship time.

Post any comment genuinely missing for the path you took, and invent none. The room reads the journey here, not in the terminal. The issue stays **open** and labelled `implementing`.

## Step 10: Stop

Print the pull request URLs and the sentence `Ready for review and merge`. Do nothing else. Merging, promotion, and closing the issue are done by the facilitator following `docs/runbook.md`.

## Note on issue closing across repos

The issue closes when the request is live in production, and never before. No pull request this skill opens carries `Closes`, `Fixes` or `Resolves`: `develop` is the default branch in both app repos, so a keyword would close the issue on the first merge to staging — which is exactly what happened to #11 in the 2026-09-10 dry run, half a feature and two promotions early. A keyword close also leaves the labels behind, because GitHub does not touch them.

The keyword is not the only way, though, and this one is worth knowing before you rely on Step 2's linked branches: a pull request opened from a GitHub-linked branch closes its linked issue on merge into the default branch **with no keyword in the body at all**, across repositories included — proved on 2026-09-10 with issue #15 and `kaizen-tasks-api#11`, which closed one second after that merge. The linked branches stay (the room reads the **Development** panel), and three things stop them closing anything early: the harness repository has "Auto-close issues with merged linked pull requests" switched off, the facilitator adds `shipped` before closing so a real ship is distinguishable, and `.github/workflows/issue-lifecycle.yml` reopens with a comment any issue closed while it still carries `implementing` or `staging`.

So: every pull request body says `Part of kpnemo/kaizen-tasks-assembly-line#<n>`. That is a plain cross-reference — it puts the pull request on the issue's timeline as "mentioned this issue in ...", which is what the room reads; the **Development** panel is fed by the branch Step 2 linked, not by this line. The facilitator then labels and closes the issue after the production read-back, with the commands in `docs/runbook.md`, Ship, and the lifecycle workflow retires `implementing` and `staging`.
