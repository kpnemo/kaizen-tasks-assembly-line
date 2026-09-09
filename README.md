# kaizen-tasks-assembly-line

The cross-repo harness and facilitator kit for the Kaizen Tasks workshop. It holds the workspace that contains the two application repos, the feature-request intake, the readiness rubric, the triage and implement skills, the smoke package that gates promotion in both app repos, the seeded requests, and the runbook. It owns no application code.

Related repositories: [kaizen-tasks-api](https://github.com/kpnemo/kaizen-tasks-api), [kaizen-tasks-web](https://github.com/kpnemo/kaizen-tasks-web), [kaizen-tasks-product-skills](https://github.com/kpnemo/kaizen-tasks-product-skills).

## Set up the workspace

```bash
gh repo clone kpnemo/kaizen-tasks-assembly-line webapp
cd webapp
scripts/setup-workspace.sh
```

The script clones `backend/` and `frontend/` (both git-ignored here), selects Node 24 through nvm, checks that Postgres and Redis answer, creates the `kaizen_dev` and `kaizen_test` databases, runs `npm ci` in both repos, and prints the commands to start each app. Run it again any time; every step is idempotent.

## The three skills

Open Claude Code at the workspace root (`claude` in this folder). The skills are in `.claude/skills/`.

| Skill                  | What it does                                                                                                                                                                                                                                                                                                          |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/seed-requests`       | Files `seeds/requests/*.md` as `feature-request` issues, skipping titles that already exist.                                                                                                                                                                                                                          |
| `/triage-requests`     | Scores every open `feature-request` issue with `rubric/readiness.md`, writes `triage/<date>.md`, applies score labels, upserts one comment per issue, rewrites the pinned Triage board. `--score-only <n \| file>` scores one request and writes nothing; `--dry-run` scores everything and writes nothing to GitHub. |
| `/implement-issue <n>` | Implements one request end to end across both repos with TDD, opens one pull request per affected repo, and stops. It never merges.                                                                                                                                                                                   |

## Other scripts

| Script                                                 | Purpose                                                                       |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `scripts/setup-labels.sh [--dry-run]`                  | Create or update the label set and the pinned Triage board issue.             |
| `scripts/seed-requests.sh [--dry-run]`                 | Same as the seed skill, from a shell.                                         |
| `scripts/protect-branches.sh <owner/repo> [--dry-run]` | Apply branch protection to `develop` and `main` of an app repo.               |
| `scripts/docs-check-all.sh --hook`                     | Root Stop hook: run each nested repo's docs-check when it has changes.        |
| `scripts/format-file.sh`                               | Root PostToolUse hook: format an edited file with the owning repo's prettier. |

## Smoke package

`smoke/` is a Playwright test that registers a user, creates a task, waits for the assistant, accepts a suggestion, and logs out. Both app repos check this repository out at `main` and run it against staging in their `promote` workflow. See `smoke/README.md`. Because `promote` reads `main`, not `develop`, `main` must be re-pointed at `develop` after any change to `smoke/` — verify with `gh api repos/kpnemo/kaizen-tasks-assembly-line/contents/smoke/package.json?ref=main --jq .name`, expecting `kaizen-tasks-smoke`.

## Docs

- `docs/PRD.md`: the product requirements.
- `docs/runbook.md`: the facilitator runbook, minute by minute, with the failure page and rollback.
- `docs/railway-setup.md`: how the Railway project `kaizen-tasks` is set up.
- `docs/superpowers/specs/` and `docs/superpowers/plans/`: design specs and implementation plans.
