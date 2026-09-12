---
name: auto-implement-issue
description: Implement one issue unattended — implement-issue's journey with assumptions instead of questions, Codex instead of the facilitator, the two lanes, pull requests, green checks — then stop at the Deploy to staging click
argument-hint: "<issue number>"
---

# auto-implement-issue

Take one issue from `kpnemo/kaizen-tasks-assembly-line` to the point where the facilitator has exactly one thing left to do: press **Deploy to staging** on `/pipeline`. Nobody is watching the terminal while it runs. The facilitator starts it, takes the room to the product conversation, and comes back to a `Ready for staging` comment on the issue.

This skill routes. **Read `.claude/skills/implement-issue/SKILL.md` from disk** — never the copy a slash command may have injected — and follow it step by step under the **Unattended overrides** below. The overrides win wherever the two differ. Everything not named here is unchanged: the branches and their names, the briefing, the milestone comments, the acceptance-criteria pass, the contract ripple, the checks and the docs gate, the pull request bodies, the no-closing-keyword rule, the timeline check.

Two rules above all others:

1. **Never call AskUserQuestion, never print a question, never wait for input.** Every place implement-issue says "ask", "wait for the facilitator's yes", "confirm to continue" or "stop with that blocker" is answered by an override below. A question that has no override is answered by its own recommended answer, and recorded as an assumption.
2. **The run ends in one of three ways**, each a comment on the issue: `Ready for staging: …`, `Auto-implement stopped at …`, or `Auto-implement stopped: checks red on …`. It never ends silently and it never ends by asking.

Constants, on top of implement-issue's:

- Runner: `CODEX=$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs | tail -1)`. Every Codex call is read-only (never `--write`), started with `task --background`, and run from this workspace root — the runner keeps its job store per working directory.
- Scratch: `.superpowers/auto/<n>/`, git-ignored (`.superpowers/` is in `.gitignore`), for the issue body, the round, the filled prompts and the raw Codex results. Nothing in it is ever committed.
- Prompt templates, beside this file: `round-prompt.md`, `spec-review-prompt.md`. Fill the `<placeholders>` with `sed` into the scratch; never paste a template into the transcript.

## Calling Codex

The same four lines every time; only the prompt and the budget change:

```bash
out=$(node "$CODEX" task --background --effort <medium|high> "$(cat .superpowers/auto/<n>/<prompt>.md)")
id=$(printf '%s' "$out" | grep -oE 'task-[a-z0-9-]+' | head -1)
node "$CODEX" status "$id" --wait --timeout-ms <budget> --json | jq -r .job.status      # completed | running | failed
node "$CODEX" result "$id" --json > .superpowers/auto/<n>/<prompt>.result.json
```

The reply text is `jq -r .job.summary` of the result. When it does not have the shape the prompt asked for, read the `.job.logFile` path from the same JSON for the full transcript before deciding it is malformed. Any of these is a **fallback, not a stop**: no runner, `codex login status` not logged in, status still `running` at the deadline, `failed`, or a reply without the requested shape. The fallback is always the recommended answer, and the record always says why: `codex: unavailable`, `codex: timeout`, `codex: failed`, `codex: malformed`.

The plugin's `/codex:rescue` is a forwarder that returns raw output and is forbidden from acting on findings; do not use it here. The four lines above are the whole integration.

## Unattended overrides

**Preflight (Step 1).** Print `Start:` as implement-issue does. Then resolve `$CODEX`, run `codex login status`, and print one line: `codex: ready` or `codex: unavailable, running on recommendations`. There is no 25-minute time box on this path: print the elapsed minutes since `Start:` at every milestone comment instead. Path classification is unchanged; an issue with neither label or both is a bug.

**Take into work (Step 2).** The comment reads `Taken into work: implementing through /auto-implement-issue <n> (unattended). Branches: …` — the rest as implement-issue.

**Briefing (Step 2b) and criteria (Step 3).** Unchanged, with one addition: save the issue body and every comment to `.superpowers/auto/<n>/issue.md` while reading them, so Codex can read the same text.

**Architecture change (Step 4).** Write and commit the ADR exactly as implement-issue says. Do not stop. Comment `ADR written: <path> (unattended, no confirmation)` and continue to Step 5.

**The round (Step 5) goes to Codex, not to a person.** Build the round exactly as implement-issue's "Building the round" says — the deduplicated list cut to four, the design question first with its two or three options and their text mockups, the blockers with their proposed rewordings — but do not invoke the grilling skill, do not call AskUserQuestion, and do not print it as a question. Write it to `.superpowers/auto/<n>/round.md`, fill `round-prompt.md`, call Codex with `--effort medium` and a budget of `240000` ms. Its numbered list is the answers; an item it could not answer, or a fallback, takes the recommended answer. If an acceptance criterion is still untestable after Codex's answer (Step 3's one stop on the attended path), do not stop: take the rewording Step 3 proposed, record it under `## Assumptions` as `untestable criterion, rewording taken`, and let the spec review below challenge it. Then append to the briefing:

```markdown
## Assumptions

1. <question> — <answer> — taken by: codex (kept | changed) | recommendation (<codex: reason>) — <one-line reason>
```

Comment: `Interview done (unattended): <k> questions answered by Codex, <r> recommendations kept, <c> changed; approach chosen: <one line>.` With a fallback, `answered by Codex` becomes `answered by recommendation (<reason>)`. When implement-issue's step 2 leaves the list empty (`UI: none`, nothing open), print its `No open questions` sentence, skip Codex, and comment with `0 questions`.

**Approaches and spec.** Invoke `superpowers:brainstorming` at the approaches as implement-issue says, with one more constraint in its override: there is no product owner in the room; the recommended approach is the chosen one, and the spec is written without asking for a yes. Then **Codex reviews the spec**: fill `spec-review-prompt.md`, call Codex with `--effort high` and a budget of `360000` ms. Fold every `Must fix` item into the spec and mark each changed passage **(review)**; fold in a `Should fix` item when it costs one sentence, otherwise list it as declined with a reason. Under the spec's `Context:` line add one paragraph, in the shape `docs/superpowers/specs/2026-09-11-pipeline-control-room-design.md` uses: `Codex review (<date>, "<verdict>"): <m> must-fix folded in, marked **(review)**. Declined: <item, reason>; …` — or `Codex review: <codex: reason>` on a fallback. One review, no re-review. `unsound` does not stop the run: the must-fix items are the repair, and the verdict goes in the comment as it was given. Comment: `Spec reviewed by Codex: <verdict>; <m> must-fix folded in, <d> declined. Spec: <path>.`

**Plan.** Invoke `superpowers:writing-plans` exactly as implement-issue's "The plan" says — the lanes, contract first, the `## Joins` block — and do not wait for a yes. Comment: `Spec and plan set (unattended): <spec path>, <plan path> on feat/<n>-<slug>.` In Step 9's checklist, this line stands where `Spec and plan approved` would.

**Execute (Step 7).** Always `superpowers:subagent-driven-development`, always the lanes of implement-issue's "Two lanes", never `superpowers:executing-plans`. The execution skill already rules instead of stalling; keep to that. Two situations end the run: the fix-loop breaker trips with a load-bearing finding still open, or an implementer reports BLOCKED after one re-dispatch on a more capable model. Then push whatever the lane has committed, comment `Auto-implement stopped at <API|Web> Task <n>: <one line>`, print the same line with the branch names, and stop. Never wait for someone to unblock it.

**Bug path (Step 6).** Systematic debugging as implement-issue says. When the root cause turns out to need a product decision, take the decision the evidence recommends, record it under `## Assumptions` in the pull request body, and continue; never stop to ask whether to file a feature request instead. When the steps do not reproduce, write the test from the report's expected behavior, note `not reproduced as written` under `## Assumptions`, and continue.

**Pull requests (Step 8).** As implement-issue, per lane, with two more sections in every body, after `## Test evidence`:

```markdown
## Assumptions

- <the briefing's list, one per line> — or `none`

## Codex review

<verdict line from the spec review> — or `unavailable`
```

**Green (Step 11, after Step 9).** For every pull request the run opened, the app ones and the docs one:

```bash
gh pr checks <url> --watch --fail-fast      # bounded: 15 minutes per pull request, run the watches in the background together
```

A red check: one fix dispatch in that repo in the execution skill's final-review shape — one implementer, one scoped re-review — then push and watch again. A second red on the same pull request, or a watch still running at 15 minutes: comment `Auto-implement stopped: checks red on <url>` and stop. Every pull request green: comment

```
Ready for staging: press "Deploy to staging" for #<n> on /pipeline.
```

and print the same sentence followed by the pull request URLs, API first, docs last. Do not merge, do not touch a label, do not open `/pipeline`: the button is the facilitator's, and the page shows it on its own once the checks are green and the issue is `implementing`.

## What the room reads

The issue carries the whole journey, in order: `Taken into work … (unattended)`, `Context gathered`, `ADR written` when there was one, `Interview done (unattended)`, `Spec reviewed by Codex`, `Spec and plan set (unattended)`, one `Pull request opened` per pull request, `Ready for staging`. Step 9 checks for exactly these on this path.

## Not on this path

- The 25-minute time box, `take your recommendations`, `use the issue text`: there is nobody to say them.
- `superpowers:using-git-worktrees`, `superpowers:finishing-a-development-branch`, `/codex:rescue`, `/codex:review`.
- Merging, labels other than `implementing`, releases, promotion, closing the issue: `docs/runbook.md`, Ship, and the pipeline page own all of it.
