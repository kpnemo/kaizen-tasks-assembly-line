---
name: triage-requests
description: Rank open feature requests by readiness, write the scores back to GitHub, and ask which one to implement
argument-hint: "[--score-only <issue number | file>] [--dry-run]"
---

# triage-requests

Score every open `feature-request` issue with `rubric/readiness.md`, rank them, write a dated report under `triage/`, write the scores back to GitHub as labels, one upserted comment per issue and the pinned Triage board, push the report, and end by asking the facilitator which issue to implement. Every write is a replacement, so running the skill twice leaves the same state: run it a second time in front of the room to show the board, the labels and the comments unchanged.

`bug` issues are never scored. The rubric ranks requests, not defects: a bug goes straight to `/implement-issue <n>`, which routes it to systematic debugging.

Constants:

- `REPO=kpnemo/kaizen-tasks-assembly-line`
- Comment marker: `<!-- kaizen-triage -->`
- Board marker: `<!-- kaizen-triage-board -->`
- Working directory: the workspace root (the folder containing `rubric/`, `triage/`, `.claude/`).

## Modes

| Invocation                                                      | Effect                                                                                                                                     |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `/triage-requests`                                              | Full mode: score, report, labels, comments, board, push, summary, the question                                                             |
| `/triage-requests --dry-run`                                    | Score and write the report file (uncommitted); print what would change on GitHub; write nothing to GitHub; no commit, no push, no question |
| `/triage-requests --score-only 12`                              | Score issue 12 and print the result; write nothing anywhere                                                                                |
| `/triage-requests --score-only seeds/requests/02-smarter-ai.md` | Score a file; write nothing anywhere                                                                                                       |

## Step 1: Read the rubric

Read `rubric/readiness.md` in full. Print `Rubric version: <n>` from its front matter. Follow its procedure section literally for every score: clarity from the acceptance criteria alone, complexity and risk by naming files or areas, the architecture change test, the formula, questions only when clarity is below 3.

## Step 2: Score-only mode

Applies when `--score-only` is given. No writes of any kind: no labels, no comments, no report, no commit, no push, no question.

1. Load the request text.
   - A number: `gh issue view <n> --repo $REPO --json title,body --jq '"# " + .title + "\n\n" + .body'`
   - A file path: read the file; the front matter `title:` line is the title, everything after the second `---` is the body.
2. Apply the rubric procedure.
3. Print the fixed output shape as a JSON block, then the three reasons and the questions as prose. Stop.

## Step 3: Full mode, fetch the open requests

```bash
gh issue list --repo $REPO --label feature-request --state open \
  --json number,title,body,createdAt,labels --limit 100
```

The label filter is the scope: the Triage board carries `triage-board` and bug reports carry `bug`, so neither ever appears here. If the list is empty, print "No open feature requests" and stop.

## Step 4: Score and rank

Score every issue with the rubric procedure. Rank by readiness descending; every issue with `archChange: true` after every issue with `archChange: false`, regardless of score; ties by `createdAt` ascending.

## Step 5: Write the report

Write `triage/<YYYY-MM-DD>.md` with today's UTC date (`date -u +%F`):

```markdown
# Triage <YYYY-MM-DD>

Rubric version <n>. <count> issues scored at <ISO timestamp, date -u +%FT%TZ>.

| Rank | Issue | Title   | Readiness | Clarity | Complexity | Risk | Arch |
| ---- | ----- | ------- | --------- | ------- | ---------- | ---- | ---- |
| 1    | #<n>  | <title> | 19        | 5       | 2          | 1    | no   |

## #<n> <title>

- Clarity <c>: <reason>
- Complexity <x>: <reason>
- Risk <r>: <reason>
- Architecture change: <yes | no>
- Questions: none | 1. ... 2. ... 3. ...
```

Unless `--dry-run`, commit it:

```bash
git add triage/<YYYY-MM-DD>.md
git commit -m "triage: <YYYY-MM-DD>" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

In `--dry-run`, leave the file uncommitted and say so.

## Step 6: Labels and the triage comment, per issue

Skip this step entirely in `--dry-run`; instead print, per issue, the labels that would be set and whether the comment would be created or edited.

For each issue `<n>` with scores `<c>`, `<x>`, `<r>` and `archChange`:

1. Remove the score labels currently present:

```bash
current="$(gh issue view <n> --repo $REPO --json labels \
  --jq '[.labels[].name | select(test("^(clarity|complexity|risk):"))] | join(",")')"
if [ -n "$current" ]; then gh issue edit <n> --repo $REPO --remove-label "$current"; fi
```

2. Add the new ones and `triaged`:

```bash
gh issue edit <n> --repo $REPO --add-label "clarity:<c>,complexity:<x>,risk:<r>,triaged"
```

3. Architecture flag: when `archChange` is true, `gh issue edit <n> --repo $REPO --add-label arch-change`. When false and the fetched labels include `arch-change`, `gh issue edit <n> --repo $REPO --remove-label arch-change`.

Never touch `implementing` or `shipped`: `/implement-issue` sets `implementing` when it takes an issue into work, and the runbook's Ship block sets `shipped` after the merge.

4. Write the comment to a temp file:

```markdown
<!-- kaizen-triage -->

**Triage** (rubric v<n>, <YYYY-MM-DD>): readiness **<score>**. Clarity <c>, complexity <x>, risk <r><, architecture change>.

- Clarity: <one-line reason>
- Complexity: <one-line reason>
- Risk: <one-line reason>

**Questions** (only when clarity is below 3; omit the heading otherwise)

1. <question>
2. <question>
```

5. Upsert: find the existing comment by the marker, edit it if found, create it otherwise.

```bash
cid="$(gh api "repos/$REPO/issues/<n>/comments" --paginate \
  --jq '[.[] | select(.body | contains("<!-- kaizen-triage -->"))][0].id // empty' | head -1)"
if [ -n "$cid" ]; then
  gh api -X PATCH "repos/$REPO/issues/comments/$cid" -F body=@<tempfile> --jq .html_url
else
  gh issue comment <n> --repo $REPO --body-file <tempfile>
fi
```

## Step 7: Rewrite the Triage board

Skip in `--dry-run` (print the table instead).

```bash
board="$(gh issue list --repo $REPO --label triage-board --state open --json number --jq '.[0].number // empty')"
```

If empty, run `scripts/setup-labels.sh` (it creates and pins the board) and read the number again. Write the body to a temp file:

```markdown
<!-- kaizen-triage-board -->

# Triage board

| Rank | Issue | Title   | Readiness | Clarity | Complexity | Risk | Arch | Status  |
| ---- | ----- | ------- | --------- | ------- | ---------- | ---- | ---- | ------- |
| 1    | #<n>  | <title> | 19        | 5       | 2          | 1    | no   | triaged |

Last run: <ISO timestamp>. Report: `triage/<YYYY-MM-DD>.md`. Rubric version <n>.
```

The Status column is read from the issue's labels, not decided here: `shipped` when the issue carries `shipped`, else `implementing` when it carries `implementing` (`/implement-issue` adds that label the moment it takes the issue into work, before any interview or code), else `triaged`.

Then `gh issue edit $board --repo $REPO --body-file <tempfile>`.

## Step 8: Summary

Print the top three as `#<n> <title> (readiness <score>)`, then `Recommended to implement next: #<n> <title>`, which is the first ranked issue with `archChange: false`. If every issue is an architecture change, say so and recommend none.

## Step 9: Push the report

Skip in `--dry-run`. The only local commit is the triage report, so:

```bash
git fetch origin develop
git rebase origin/develop
git push origin HEAD:develop
```

This is the one skill in this workspace allowed to push straight to `develop`, and only for a docs commit under `triage/` (`CLAUDE.md`, Rules). Everything else here and in both app repos goes through a pull request. If the push is refused, say so, leave the commit local, and carry on to Step 10; the report is a record, not a gate.

## Step 10: Ask which issue to implement

The skill ends here, with a question. Never start implementing; never assume the recommended issue was chosen.

With the AskUserQuestion tool available: one question, `Which issue should we implement?`, with the top three issues that are **not** architecture changes as the options, the recommended one first and its label ending in `(Recommended)`. Each option's description is `readiness <score>, clarity <c>` and the one-line clarity reason. Without the tool: print those three as a numbered list and the sentence `Reply with 1, 2 or 3, or another issue number.`

Print the answer back as `Chosen: #<n> <title>` and the exact next command, `/implement-issue <n>`. Do not run it.

## Rules

- Never merge, never close issues, never edit an issue's title or body. The only body this skill rewrites is the Triage board's.
- Never post a second triage comment on an issue; always upsert by the marker.
- Score from the text as written. Do not read linked pull requests or other issues.
- Never implement, and never pick the issue for the facilitator. The last thing this skill does is ask.
