---
name: seed-requests
description: File the seeded feature requests in seeds/requests as GitHub issues, skipping titles that already exist
argument-hint: "[--dry-run]"
---

# seed-requests

File every `seeds/requests/*.md` as a `feature-request` issue in `kpnemo/kaizen-tasks-assembly-line`. A seed whose title already exists as an open issue is skipped, so the skill can run again safely. The logic lives in `scripts/seed-requests.sh`; this skill runs it and reports.

Seed format: a front matter block with a `title:` line, then the body in the issue form's section structure (`### Problem`, `### Proposed behavior`, `### Acceptance criteria`, `### Out of scope`, `### Your role`).

## Steps

1. Confirm the target and the login:

```bash
gh auth status
gh repo view kpnemo/kaizen-tasks-assembly-line --json nameWithOwner --jq .nameWithOwner
```

If `gh auth status` fails, tell the user to run `gh auth login` and stop. If `gh repo view` fails, tell the user the repository `kpnemo/kaizen-tasks-assembly-line` is not reachable with the current login and stop.

2. Preview:

```bash
scripts/seed-requests.sh --dry-run
```

Print the `WOULD CREATE` and `SKIP` lines. If the argument was `--dry-run`, stop here.

3. File:

```bash
scripts/seed-requests.sh
```

4. Verify and report:

```bash
gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label feature-request --state open --json number,title,url \
  --jq '.[] | "#\(.number) \(.title) \(.url)"'
```

The `CREATED` lines printed by step 3 also carry the URL and may be reported directly. Print the created issue URLs, the skipped titles, and the sentence `Run /triage-requests to score them`.

## Rules

- Never edit or close existing issues. Never file a seed twice.
- Do not change the seed files from this skill; edits to seeds are ordinary commits.
