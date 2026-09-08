# Kaizen Tasks CI/CD and Railway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Every Railway step also follows the official `use-railway` skill at `/Users/Mike.Bogdanovsky/.claude/skills/use-railway/SKILL.md`. **PAUSE** steps stop the executor until Mike has done what the step asks and has replied.

**Goal:** Provision GitHub and Railway for the workshop from day one: the four public repos with `develop` as default, the label set, the Railway project `kaizen-tasks` with `staging` and `production` each holding `api`, `web`, `Postgres`, and `Redis` with the full variable set, wait-for-CI, public domains for `web`, branch protection with `ci` and `promote`, and one proven `develop` to `main` promotion per app repo.

**Architecture:** This lane changes GitHub and Railway state, not application code. It executes `docs/railway-setup.md` (written by the assembly-line lane) with the Railway CLI, pausing wherever a secret must be pasted or a dashboard toggle clicked. Production is built first and `staging` is created by duplicating it, then the two differences (source branch, `APP_ENV`) are overridden. Each task ends with a read-back that proves the state and a row appended to `docs/cicd-log.md` in the assembly-line repo, so the orchestrator can test the master plan's unblock conditions from the log.

**Tech Stack:** GitHub CLI `gh` 2.100 (logged in as `kpnemo`), Railway CLI 5.49.5, `jq` 1.7, `curl`, `openssl`. The Railway GitHub integration deploys `develop` to staging and `main` to production with wait-for-CI on. GitHub Actions workflows `ci` and `promote` are owned by the app repos (L1 and L2).

**Spec:** Master plan section 6 (`docs/superpowers/plans/2026-09-08-master-plan.md`), expanded here; `docs/railway-setup.md` (assembly-line plan Task 14); PRD section 7; API spec sections 2.4, 10.1 to 10.4; web spec sections 2.3, 2.4, 8; assembly-line spec sections 9, 10, 12.

## Global Constraints

Every lane plan inherits these. They are copied from the specs and from Mike's standing rules.

- Node 24 LTS everywhere, pinned by `.nvmrc` containing `24`; `engines.node` is `>=24 <25`. Run `nvm use` before any npm command.
- Branching: work on `develop`. Feature branches come off `develop` and merge by pull request. `main` receives only `develop` by pull request after staging verification. Nothing is ever pushed to `main` directly. `develop` is the default branch on GitHub.
- Commit messages end with the two trailer lines `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01HWmLNo9LBp2SgKdYisfRoJ`.
- Secrets never enter a repository. `ANTHROPIC_API_KEY`, `JWT_SECRET`, `ADMIN_TOKEN`, `SEED_DEMO_PASSWORD`, and any GitHub token live only in Railway variables and in git-ignored local `.env` files. Mike pastes them.
- Railway: only the new project `kaizen-tasks`. Never link to, modify, or redeploy any other project in the account. Railway operations follow the official `use-railway` skill.
- GitHub: repos `kpnemo/kaizen-tasks-api`, `kpnemo/kaizen-tasks-web`, `kpnemo/kaizen-tasks-assembly-line`, `kpnemo/kaizen-tasks-product-skills`, all public.
- TypeScript strict in every repo. ESM. Prettier formatting. ESLint flat config.
- Test first: every task shows a failing test before implementation. Tests that hit external services are opt-in and excluded from CI.
- Docs are part of every change: `CHANGELOG.md` `[Unreleased]` bullet, regenerated OpenAPI or types where applicable, ADR when an architectural file changes. The docs-check script enforces it locally and in CI.
- Migrations are additive only (ADR 0004 in the API repo).
- The API service pins `PORT=3000`; the web service proxies `/api/*` to `http://api.railway.internal:3000`.
- The workshop root folder is not a repository. `webapp/` is `kaizen-tasks-assembly-line`; `webapp/backend/` and `webapp/frontend/` are nested, git-ignored repositories; `product-skills/` is at the root.

Lane-specific rules:

- **Standing Railway rule.** Only the project `kaizen-tasks` is touched. Before every mutating `railway` command, the linked project is verified: `railway status --json | jq -e '.name == "kaizen-tasks"' >/dev/null || { echo "REFUSING: not linked to kaizen-tasks"; exit 1; }`. That line is written as `GUARD` below and appears verbatim at the top of every mutating block. `railway link` is run only with `--project kaizen-tasks`. No `railway` command with `--project` naming any other project, and no `railway list`-driven loop over projects, is ever run.
- Railway CLI calls carry the skill's telemetry prefix: every block that runs `railway` starts with `export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3`.
- Secrets are pasted by Mike in his own terminal through `--stdin`, never typed into a transcript. The executor only ever lists variable **names**.
- `railway config apply --yes` is run only after Mike has read the exact plan output in a PAUSE and replied "apply"; `--yes` stands in for the interactive confirmation the harness cannot answer, nothing more. Never `--confirm-destructive`, never `railway service delete`, `railway down`, or `railway environment delete`. Deletion of anything is out of scope.
- This lane never edits `backend/`, `frontend/`, or `product-skills/`. It edits only `webapp/docs/runbook.md`, `webapp/docs/railway-setup.md`, and `webapp/docs/cicd-log.md`, on `develop` of the assembly-line repo, committed with the trailers.
- A deploy is reported as successful only after `railway deployment list ... --json` shows `SUCCESS` for that deployment (use-railway execution rule 9).

---

## Working directory and conventions used by every task

- `$WS` is the workshop root; `$WS/webapp` is the assembly-line repo; `$WS/webapp/backend`, `$WS/webapp/frontend`, `$WS/product-skills` are the other three. Shell state does not persist between tool calls, so this preamble is prepended to every command block (omitted from the listings for brevity):

```bash
WS=/Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026
SCRATCH=/private/tmp/claude-502/-Users-Mike-Bogdanovsky-Projects-nice-product-workshop-Sep-2026/b173ad22-2840-489c-891e-760f2df96511/scratchpad; mkdir -p "$SCRATCH"
```
- The trailer, used verbatim in every commit:

```bash
TRAILER="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01HWmLNo9LBp2SgKdYisfRoJ"
```

- The Railway prefix and guard, used verbatim at the top of every block that runs a mutating `railway` command:

```bash
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
```

- Each task's last step appends one row to `docs/cicd-log.md` and commits it. The log is the evidence the orchestrator reads to test unblock conditions. It is an L3 artifact, added beyond the assembly-line spec's repo shape; it is mentioned in the final report.
- Shell state does not persist between tool calls: re-run `cd`, `export`, and `GUARD` in every block.

## Task map against the master plan's section 6

| Master plan item | Tasks here | Milestone |
|---|---|---|
| 1 GitHub repos | 2 | L3-M0 |
| 2 Labels | 3 | L3-M0 |
| 3 Railway project | 4 | L3-M0 |
| 4 Databases and variables | 5, 6, 7 | L3-M0 |
| 5 Apply IaC and first deploys | 8, 9, 10 | L3-M1 |
| 6 Branch protection | 11 | L3-M2 |
| 7 Promotion proof | 12 | L3-M2 |
| 8 Runbook Railway sections | 13, 14 | INT |

Task 1 is the preflight. Unblock conditions are quoted from master plan section 2 at the top of the task that depends on them.

---

### Task 1: Preflight, standing rule, and the evidence log

**Files:**

- Create: `docs/cicd-log.md` (in `$WS/webapp`)

**Interfaces:**

- Consumes: `gh` logged in as `kpnemo`; Railway CLI 5.49.5 logged in to Mike's account.
- Produces: `docs/cicd-log.md`; a snapshot of the Railway project names before this lane touches anything (`$SCRATCH/railway-projects-before.txt`), compared at the end of every Railway task.

- [ ] **Step 1: GitHub and Railway logins**

```bash
gh auth status
gh api user --jq .login
command -v railway && railway --version
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway whoami --json | jq '{name, email}'
railway --help 2>&1 | grep -A4 "Agent tooling:" || echo "no agent tooling section (older CLI), skip"
```

Expected: `✓ Logged in to github.com account kpnemo`; `kpnemo`; `/opt/homebrew/bin/railway` and `railway 5.49.5`; a JSON object with Mike's Railway name and email. If `railway whoami` fails with an authentication error, run `railway login` (it opens the browser; Mike signs in) and repeat. If the agent tooling section reports an update, run `railway skills update` and tell Mike to restart Claude Code after this task.

- [ ] **Step 2: Snapshot the existing Railway projects (read-only)**

```bash
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway list --json > "$SCRATCH/railway-list-before.json"
jq -r '.. | objects | select(has("name") and has("id") and (has("environments") or has("services"))) | .name' "$SCRATCH/railway-list-before.json" | sort -u > "$SCRATCH/railway-projects-before.txt"
wc -l "$SCRATCH/railway-projects-before.txt"; cat "$SCRATCH/railway-projects-before.txt"
grep -qx kaizen-tasks "$SCRATCH/railway-projects-before.txt" && echo "WARNING: a kaizen-tasks project already exists; stop and ask Mike" || echo "OK: no kaizen-tasks project yet"
cd "$WS/webapp/backend" && railway status --json 2>&1 | head -c 300; echo
```

Expected: a list of Mike's existing project names (none named `kaizen-tasks`), `OK: no kaizen-tasks project yet`, and `railway status` in `backend/` reporting that the directory is not linked (an error such as `No linked project found`). Nothing was modified. The `jq` filter selects project objects wherever the CLI nests them; if the file is a flat array, `jq -r '.[].name'` gives the same list.

- [ ] **Step 3: Create the evidence log**

Write `$WS/webapp/docs/cicd-log.md`:

```markdown
# CI/CD lane log

One row per task of `docs/superpowers/plans/2026-09-08-kaizen-tasks-cicd.md`, newest last. The verification column quotes the read-back that proved the state. Secrets are never recorded; variable names are.

| Date (UTC) | Task | State reached | Verification |
|---|---|---|---|
| (filled by Task 1) | 1 | Preflight | `gh api user` = kpnemo; `railway whoami` ok; no `kaizen-tasks` project exists yet |
```

Replace `(filled by Task 1)` with `date -u +%F`.

- [ ] **Step 4: Commit**

```bash
cd "$WS/webapp" && git switch develop
git add docs/cicd-log.md
git commit -m "docs: CI/CD lane evidence log" -m "$TRAILER"
```

---

### Task 2: GitHub repositories (master plan item 1)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: the four local repos, each with `develop` and `main` and no remote.
- Produces: `kpnemo/kaizen-tasks-api`, `kpnemo/kaizen-tasks-web`, `kpnemo/kaizen-tasks-assembly-line`, `kpnemo/kaizen-tasks-product-skills`, public, `develop` default, both branches pushed, `origin` set in each local repo. L4's `setup-workspace.sh` clones the first two; L5's `sync-rubric.sh` reads the third; Railway connects the first two.

- [ ] **Step 1: Confirm the local state**

```bash
for d in "$WS/webapp/backend" "$WS/webapp/frontend" "$WS/webapp" "$WS/product-skills"; do
  echo "== $d"; git -C "$d" branch --show-current; git -C "$d" branch --list develop main | tr -d ' *' | tr '\n' ' '; echo; git -C "$d" remote -v | wc -l | tr -d ' '; git -C "$d" status --porcelain | wc -l | tr -d ' '
done
gh repo list kpnemo --limit 100 --json name --jq '.[].name' | grep '^kaizen-tasks-' || echo "no kaizen-tasks repos yet"
```

Expected per repo: `develop`, `develop main`, `0` remotes, `0` dirty files. `no kaizen-tasks repos yet`. If a repo already exists on GitHub, skip its create step and only verify.

- [ ] **Step 2: Create and push each repo**

Descriptions are fixed here so every repo reads the same on GitHub:

```bash
create() { # dir name description
  cd "$1" && git switch develop
  gh repo create "kpnemo/$2" --public --source . --remote origin --push --description "$3"
  git push -u origin main
  gh repo edit "kpnemo/$2" --default-branch develop
}
create "$WS/webapp/backend"  kaizen-tasks-api            "Kaizen Tasks API: Express 5, Postgres, Redis and BullMQ, Anthropic SDK breakdown agent"
create "$WS/webapp/frontend" kaizen-tasks-web            "Kaizen Tasks web app: React 19 and Vite, typed client generated from the API contract, Caddy proxy"
create "$WS/webapp"          kaizen-tasks-assembly-line  "Cross-repo harness for the Kaizen Tasks workshop: intake form, readiness rubric, triage and implement skills, smoke package, runbook"
create "$WS/product-skills"  kaizen-tasks-product-skills "Product skills plugin for the Kaizen Tasks workshop: refine-request, synthesize-interviews, Part 3 templates"
```

Expected per repo: `✓ Created repository kpnemo/<name> on GitHub`, `✓ Added remote https://github.com/kpnemo/<name>.git`, the push of `develop`, then `branch 'main' set up to track 'origin/main'`, then `✓ Edited repository kpnemo/<name>`.

- [ ] **Step 3: Verify**

```bash
for n in kaizen-tasks-api kaizen-tasks-web kaizen-tasks-assembly-line kaizen-tasks-product-skills; do
  printf '%-28s ' "$n"
  gh repo view "kpnemo/$n" --json defaultBranchRef,visibility --jq '[.defaultBranchRef.name, .visibility] | @tsv' | tr '\n' ' '
  gh api "repos/kpnemo/$n/branches" --jq '[.[].name] | sort | join(",")'
done
```

Expected, four lines: `develop PUBLIC develop,main`.

- [ ] **Step 4: Log and commit**

Append to `docs/cicd-log.md`:

```markdown
| <date> | 2 | Four public repos, develop default, both branches pushed | `gh repo view` x4: `develop PUBLIC develop,main` |
```

```bash
cd "$WS/webapp" && git add docs/cicd-log.md && git commit -m "docs: log GitHub repos created" -m "$TRAILER" && git push origin develop
```

---

### Task 3: Labels (master plan item 2)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: `scripts/setup-labels.sh` from the assembly-line plan Task 4 (part of L4-M1). Until L4-M1 lands, Step 1 creates `feature-request` by hand.
- Produces: the master plan "Labels" interface in `kpnemo/kaizen-tasks-assembly-line` and the pinned `Triage board` issue.

- [ ] **Step 1: `feature-request` by hand (only if L4-M1 has not landed)**

```bash
gh label create feature-request --repo kpnemo/kaizen-tasks-assembly-line --force --color 1D76DB --description "A request filed through the feature request form"
gh label list --repo kpnemo/kaizen-tasks-assembly-line --json name --jq '.[].name' | grep -x feature-request
```

Expected: `✓ Label "feature-request" created in kpnemo/kaizen-tasks-assembly-line` and the grep echoes the name.

- [ ] **Step 2: Full set once L4-M1 exists**

Unblock condition (master plan): "L4-M1: `rubric/readiness.md` with a `version:` line, the issue form, `scripts/setup-labels.sh`, four seeds, root `CLAUDE.md` committed on `develop`."

```bash
cd "$WS/webapp" && git pull --ff-only origin develop && test -x scripts/setup-labels.sh && echo "script present"
scripts/setup-labels.sh --dry-run | tail -3
scripts/setup-labels.sh
gh label list --repo kpnemo/kaizen-tasks-assembly-line --limit 50 --json name --jq '.[].name' | sort | tee "$SCRATCH/labels.txt" | wc -l | tr -d ' '
gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label triage-board --state open --json number,title,isPinned --jq '.[] | "#\(.number) \(.title) pinned=\(.isPinned)"'
```

Expected: `script present`; 21 `✓ Label ... created` or `updated` lines then `Triage board created and pinned: #<n> (<url>)`; the count `21`; `#<n> Triage board pinned=true`. Running the script a second time prints `Triage board exists: #<n>` and no new issue.

- [ ] **Step 3: Log and commit**

Append `| <date> | 3 | 21 labels, Triage board #<n> pinned | gh label list count 21; isPinned=true |` to `docs/cicd-log.md`; commit `docs: log labels and Triage board` with the trailer; push `develop`.

---

### Task 4: Railway project `kaizen-tasks` (master plan item 3)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: Railway login (Task 1).
- Produces: project `kaizen-tasks` with the default `production` environment, linked from `$WS/webapp/backend`. (`staging` is created in Task 6 by duplication, after production is complete, so the copy carries every service and variable.)

- [ ] **Step 1: Create and link**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway init --name kaizen-tasks --json | tee "$SCRATCH/railway-init.json" | jq '{id, name}'
railway status
railway status --json | jq -r .name
```

Expected: JSON with `"name": "kaizen-tasks"` and a project id; `railway status` shows `Project: kaizen-tasks` and `Environment: production`; the last line prints `kaizen-tasks`. If `init` asks for a workspace, rerun with `--workspace "<Mike's personal workspace name from railway whoami>"`.

- [ ] **Step 2: Prove nothing else changed**

```bash
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway list --json > "$SCRATCH/railway-list-after.json"
jq -r '.. | objects | select(has("name") and has("id") and (has("environments") or has("services"))) | .name' "$SCRATCH/railway-list-after.json" | sort -u > "$SCRATCH/railway-projects-after.txt"
diff "$SCRATCH/railway-projects-before.txt" "$SCRATCH/railway-projects-after.txt"
```

Expected: exactly one diff line, `> kaizen-tasks`. Any other line means another project changed name or appeared; stop and report.

- [ ] **Step 3: Log and commit**

Append `| <date> | 4 | Railway project kaizen-tasks created, backend/ linked to production | railway status name=kaizen-tasks; project list diff = +kaizen-tasks only |`; commit `docs: log Railway project creation`; push.

---

### Task 5: Production environment: databases, services, variables (master plan item 4, part 1)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: repos from Task 2; the variable table in API spec section 2.4 and web spec sections 2.3 and 2.4; `docs/railway-setup.md` section 2.
- Produces: in `production`: services `Postgres`, `Redis`, `api` (source `kpnemo/kaizen-tasks-api` branch `main`), `web` (source `kpnemo/kaizen-tasks-web` branch `main`); the non-secret variables on `api` and `PORT=8080` on `web`; the four secrets pasted by Mike.

- [ ] **Step 1: Databases**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway service list --json | jq -r '.[].name'
railway add --database postgres --json
railway add --database redis --json
railway service list --json | jq -r '.[].name' | sort
```

Expected: the first list is empty; each `add` prints `{"serviceId":"...","serviceName":"Postgres"}` and `{"serviceId":"...","serviceName":"Redis"}`; the final list is `Postgres` and `Redis`. Never retry an `add` whose output is unclear: list first (use-railway setup rule).

- [ ] **Step 2: Application services from GitHub**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway add --service api --repo kpnemo/kaizen-tasks-api --branch main --json
railway add --service web --repo kpnemo/kaizen-tasks-web --branch main --json
railway service list --json | jq -r '.[].name' | sort
```

Expected: two JSON lines with `"serviceName":"api"` and `"serviceName":"web"`; the list is `Postgres Redis api web`.

> **PAUSE (Mike), only if `railway add --repo` reports the repository is not visible or not authorized:** open https://railway.com/account/integrations (or Dashboard, Account settings, GitHub, Configure), install or extend the Railway GitHub App to include `kaizen-tasks-api` and `kaizen-tasks-web`, then reply "done". The executor re-runs the two `add` commands (after `railway service list --json` confirms they did not partially succeed).

Note: Railway will start a first build of each service from `main` immediately. `main` currently has only docs, so the build fails or the deploy crashes; that is expected until L1-M1 and L2-M1 land. Do not troubleshoot these first deployments.

- [ ] **Step 3: Non-secret variables**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway variable set \
  'DATABASE_URL=${{Postgres.DATABASE_URL}}' 'REDIS_URL=${{Redis.REDIS_URL}}' \
  PORT=3000 APP_ENV=production WORKER_ENABLED=true \
  AI_MODEL=claude-sonnet-5 AI_RATE_LIMIT_PER_HOUR=20 AI_GLOBAL_LIMIT_PER_HOUR=300 \
  AI_ENABLED=true AI_STALE_MINUTES=10 SEED_DEMO_USER=true LOG_LEVEL=info \
  --service api --environment production --skip-deploys
railway variable set PORT=8080 --service web --environment production --skip-deploys
railway variable list --service api --environment production --json | jq -r 'keys[]' | grep -v '^RAILWAY_' | sort | tr '\n' ' '; echo
railway variable list --service web --environment production --json | jq -r 'keys[]' | grep -v '^RAILWAY_' | sort | tr '\n' ' '; echo
```

Expected: `api`: `AI_ENABLED AI_GLOBAL_LIMIT_PER_HOUR AI_MODEL AI_RATE_LIMIT_PER_HOUR AI_STALE_MINUTES APP_ENV DATABASE_URL LOG_LEVEL PORT REDIS_URL SEED_DEMO_USER WORKER_ENABLED`; `web`: `PORT`. The `DATABASE_URL` reference must be written with single quotes so the shell does not expand `${{...}}`.

- [ ] **Step 4: PAUSE for the production secrets**

> **PAUSE (Mike):** in your own terminal, from `webapp/backend/` (which is linked to `kaizen-tasks` / `production`), run these four commands. The first two generate the values; the last two take values you paste. Nothing is echoed. Then reply "done".
>
> ```bash
> cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/backend
> railway status | head -3      # must say Project: kaizen-tasks, Environment: production
> openssl rand -hex 32 | tr -d '\n' | railway variable set JWT_SECRET --stdin --service api --environment production --skip-deploys
> openssl rand -hex 32 | tr -d '\n' | railway variable set ADMIN_TOKEN --stdin --service api --environment production --skip-deploys
> printf '%s' 'PASTE-THE-DEMO-PASSWORD' | railway variable set SEED_DEMO_PASSWORD --stdin --service api --environment production --skip-deploys
> printf '%s' 'PASTE-THE-ANTHROPIC-KEY' | railway variable set ANTHROPIC_API_KEY --stdin --service api --environment production --skip-deploys
> ```
>
> Keep the `ADMIN_TOKEN` value somewhere you can paste it during the session (the seed-reset curl in the runbook needs it). The demo password is what you will type on stage; the PRD default is `kaizen-demo-2026`.

- [ ] **Step 5: Verify the names only**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway variable list --service api --environment production --json | jq -r 'keys[]' | grep -v '^RAILWAY_' | sort | tr '\n' ' '; echo
railway variable list --service api --environment production --json | jq -r '[.JWT_SECRET, .ADMIN_TOKEN] | map(length >= 32) | all'
```

Expected: the 16 names `ADMIN_TOKEN AI_ENABLED AI_GLOBAL_LIMIT_PER_HOUR AI_MODEL AI_RATE_LIMIT_PER_HOUR AI_STALE_MINUTES ANTHROPIC_API_KEY APP_ENV DATABASE_URL JWT_SECRET LOG_LEVEL PORT REDIS_URL SEED_DEMO_PASSWORD SEED_DEMO_USER WORKER_ENABLED`, then `true`. Do not print values; the `jq` above only reports lengths.

- [ ] **Step 6: Log and commit**

Append `| <date> | 5 | production: Postgres, Redis, api(main), web(main); 16 api variables, web PORT=8080; secrets pasted | variable list names as expected; JWT_SECRET and ADMIN_TOKEN length >= 32 |`; commit `docs: log production environment`; push.

---

### Task 6: Staging environment by duplication (master plan item 4, part 2)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: production from Task 5.
- Produces: `staging` with the same four services and variables, `api` and `web` tracking `develop`, `APP_ENV=staging`, its own `JWT_SECRET` and `ADMIN_TOKEN`, and separate Postgres and Redis instances.

- [ ] **Step 1: Duplicate and link**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway environment new staging --duplicate production
railway environment link staging
railway status | head -3
railway service list --json | jq -r '.[].name' | sort
railway variable list --service api --environment staging --json | jq -r 'keys[]' | grep -v '^RAILWAY_' | sort | tr '\n' ' '; echo
```

Expected: the environment is created (the CLI prints the new environment and may take a minute while the databases are provisioned); `railway status` shows `Environment: staging`; the services are `Postgres Redis api web`; the same 16 variable names exist on `api`. Duplicated databases are new instances: `railway variable list --service Postgres --environment staging --json | jq -r '.RAILWAY_PRIVATE_DOMAIN'` differs from the production value.

- [ ] **Step 2: Override what differs**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway environment edit --environment staging --service-config api source.branch develop -m "staging api tracks develop"
railway environment edit --environment staging --service-config web source.branch develop -m "staging web tracks develop"
railway variable set APP_ENV=staging --service api --environment staging --skip-deploys
railway environment config --environment staging --json > "$SCRATCH/staging-config.json"
jq -r '.. | objects | select(has("source")) | select(.source.branch?) | "\(.source.repo // .source.repository // "?") \(.source.branch)"' "$SCRATCH/staging-config.json"
railway variable list --service api --environment staging --json | jq -r .APP_ENV
```

Expected: two `source` lines ending in `develop` (one per app service), and `staging`. If the config JSON keys differ from the `jq` path, inspect `$SCRATCH/staging-config.json` and confirm `branch` is `develop` for both `api` and `web` by eye; record the path that worked in the log.

- [ ] **Step 3: PAUSE for the staging secrets**

> **PAUSE (Mike):** duplication copied the production secrets. Staging gets its own `JWT_SECRET` and `ADMIN_TOKEN`; the Anthropic key and demo password may stay. In your terminal:
>
> ```bash
> cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/backend
> railway status | head -3      # Project: kaizen-tasks, Environment: staging
> openssl rand -hex 32 | tr -d '\n' | railway variable set JWT_SECRET --stdin --service api --environment staging --skip-deploys
> openssl rand -hex 32 | tr -d '\n' | railway variable set ADMIN_TOKEN --stdin --service api --environment staging --skip-deploys
> ```
>
> Reply "done" with the staging `ADMIN_TOKEN` kept for the runbook's staging seed-reset.

- [ ] **Step 4: Verify staging differs from production where it must**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
for k in JWT_SECRET ADMIN_TOKEN; do
  s="$(railway variable list --service api --environment staging --json | jq -r ".$k" | shasum -a 256 | cut -c1-12)"
  p="$(railway variable list --service api --environment production --json | jq -r ".$k" | shasum -a 256 | cut -c1-12)"
  [ "$s" != "$p" ] && echo "$k differs between environments" || echo "WARNING $k identical in both environments"
done
railway variable list --service api --environment staging --json | jq -r '.APP_ENV, .PORT, .AI_MODEL'
```

Expected: `JWT_SECRET differs between environments`, `ADMIN_TOKEN differs between environments`, then `staging`, `3000`, `claude-sonnet-5`. Only hashes of values are computed; nothing secret is printed.

- [ ] **Step 5: Log and commit**

Append `| <date> | 6 | staging duplicated from production; api and web track develop; APP_ENV=staging; own JWT_SECRET and ADMIN_TOKEN | branches develop x2; secrets differ; 16 variable names |`; commit `docs: log staging environment`; push.

---

### Task 7: Link the web checkout and close L3-M0

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: Tasks 2 to 6.
- Produces: `$WS/webapp/frontend` linked to `kaizen-tasks` / `staging` (needed for `railway config apply` from the web repo in Task 8); the L3-M0 condition met: "Four GitHub repos exist with `develop` default and both branches pushed; labels created in the assembly-line repo; Railway project `kaizen-tasks` has `staging` and `production`, each with Postgres and Redis and the variable set from the specs, secrets pasted by Mike."

- [ ] **Step 1: Link the frontend directory**

```bash
cd "$WS/webapp/frontend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway link --project kaizen-tasks --environment staging --service web
railway status | head -4
railway status --json | jq -r .name
```

Expected: `Project: kaizen-tasks`, `Environment: staging`, `Service: web`; `kaizen-tasks`. Also set the backend link's service so later commands default sensibly: `cd "$WS/webapp/backend" && railway service link api && railway status | head -4`.

- [ ] **Step 2: L3-M0 read-back in one block**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
for n in kaizen-tasks-api kaizen-tasks-web kaizen-tasks-assembly-line kaizen-tasks-product-skills; do gh repo view "kpnemo/$n" --json defaultBranchRef --jq "\"$n \" + .defaultBranchRef.name"; done
gh label list --repo kpnemo/kaizen-tasks-assembly-line --limit 50 --json name --jq 'length'
railway environment list --json | jq -r '.[].name' | sort | tr '\n' ' '; echo
for env in staging production; do
  echo "== $env: $(railway service list --environment $env --json | jq -r '[.[].name] | sort | join(" ")')"
  railway variable list --service api --environment $env --json | jq -r 'keys[]' | grep -v '^RAILWAY_' | sort | tr '\n' ' '; echo
done
```

Expected: four `develop` lines; `21`; `production staging`; per environment `Postgres Redis api web` and the 16 names. **L3-M0 is met.** Tell the orchestrator.

- [ ] **Step 3: Log and commit**

Append `| <date> | 7 | L3-M0 met; frontend/ linked to kaizen-tasks/staging | read-back block: 4 repos develop, 21 labels, 2 envs x 4 services x 16 names |`; commit `docs: log L3-M0`; push.

---

### Task 8: Apply each repo's IaC per environment (master plan item 5, part 1)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: unblock conditions "L1-M1: `npm test` and `npm run build` pass in `backend/`; `GET /api/v1/health` serves locally; `openapi.json` committed; `ci.yml` green on `develop`" and "L2-M1: `npm test` and `npm run build` pass in `frontend/`; `dist/version.json` exists after build; `Caddyfile` and `.railway/railway.ts` committed; `ci.yml` green on `develop`". Each repo's `.railway/railway.ts` (API spec 10.3: Railpack build, start `node dist/server.js`, healthcheck `/api/v1/health`, timeout 120, branch from environment; web spec 8: build `npm ci && npm run build`, Caddyfile, healthcheck `/version.json`, branch from environment).
- Produces: service configuration in both environments matching the files. Wait-for-CI is not in the files (Task 9).

- [ ] **Step 1: Confirm the unblock conditions**

```bash
cd "$WS/webapp/backend" && git fetch origin && git switch develop && git pull --ff-only && ls .railway/railway.ts openapi.json
gh run list --repo kpnemo/kaizen-tasks-api --branch develop --workflow ci --limit 1 --json conclusion,headSha --jq '.[0] | "\(.conclusion) \(.headSha[0:7])"'
cd "$WS/webapp/frontend" && git fetch origin && git switch develop && git pull --ff-only && ls .railway/railway.ts Caddyfile
gh run list --repo kpnemo/kaizen-tasks-web --branch develop --workflow ci --limit 1 --json conclusion,headSha --jq '.[0] | "\(.conclusion) \(.headSha[0:7])"'
```

Expected: both file lists succeed; both runs print `success <sha>`. Otherwise wait; do not continue.

- [ ] **Step 2: Plan and apply for the API, staging then production**

```bash
cd "$WS/webapp/backend"
source "$HOME/.nvm/nvm.sh" && nvm use >/dev/null && npm ci >/dev/null     # the railway authoring package is a devDependency of the repo
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway environment link staging
railway config plan --verbose | tee "$SCRATCH/plan-api-staging.txt" | tail -25
```

Expected: a Terraform-style summary ending in `Plan: 0 to add, 1 to change, 0 to destroy` (the `api` service gains build, start, healthcheck, and branch settings). If the summary shows `to destroy` greater than zero, or names `web`, `Postgres`, or `Redis`, stop: the authoring file claims resources it does not own; report to the L1 lane with the plan text and do not apply. If `plan` fails with a missing `railway` module, report to L1 (the package belongs in that repo's `devDependencies`).

> **PAUSE (Mike):** read `$SCRATCH/plan-api-staging.txt` (the executor pastes the summary). Reply "apply" to continue or "stop".

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway config apply --yes    # --yes replaces the interactive confirmation for the exact plan Mike approved; never --confirm-destructive
railway config plan --detailed-exit-code >/dev/null; echo "drift exit=$?"
```

Expected: `apply` reports the change applied; the second `plan` prints `drift exit=0` (no pending changes). If `apply` refuses because the plan became destructive between plan and apply, stop and re-plan; do not add `--confirm-destructive`. Repeat the same three blocks with `railway environment link production` and `$SCRATCH/plan-api-production.txt`, with a second PAUSE for Mike's "apply".

- [ ] **Step 3: Plan and apply for the web, staging then production**

Same sequence from `$WS/webapp/frontend` (already linked to `kaizen-tasks` / `staging` in Task 7):

```bash
cd "$WS/webapp/frontend"
source "$HOME/.nvm/nvm.sh" && nvm use >/dev/null && npm ci >/dev/null
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway environment link staging
railway config plan --verbose | tee "$SCRATCH/plan-web-staging.txt" | tail -25
```

PAUSE for Mike's "apply", then `railway config apply --yes` and the drift check as in Step 2; then `railway environment link production`, plan, PAUSE, apply, drift check. Expected each time: `0 to destroy`, then `drift exit=0`.

- [ ] **Step 4: Read back the applied configuration**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
for env in staging production; do
  railway environment config --environment $env --json > "$SCRATCH/config-$env.json"
  echo "== $env"; jq -r '.. | objects | select(has("source") and has("deploy")) | "\(.source.branch // "?") start=\(.deploy.startCommand // "?") health=\(.deploy.healthcheckPath // "?")"' "$SCRATCH/config-$env.json"
done
```

Expected: staging lines show `develop` and production lines show `main`; the api line shows `start=node dist/server.js health=/api/v1/health`; the web line shows `health=/version.json`. If the `jq` path does not match the CLI's JSON shape, open the file and confirm the same four facts by eye.

- [ ] **Step 5: Log and commit**

Append `| <date> | 8 | .railway/railway.ts applied for api and web in staging and production | plan 0 to destroy x4; drift exit=0 x4; branches develop/main; healthchecks set |`; commit `docs: log IaC applied`; push.

---

### Task 9: Wait-for-CI and the first gated deploys (master plan item 5, part 2; verifies V4)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: Task 8; the `ci` workflow in both app repos (workflow name and job id `ci`).
- Produces: wait-for-CI on for `api` and `web` in both environments; one observed deployment per service in staging that went `WAITING` while `ci` ran and then `SUCCESS`. This is API spec verification item V4 and the master plan's L3-M1 clause "a push to `develop` in either repo shows a Railway deployment waiting on CI".

- [ ] **Step 1: Try the config patch for check suites**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
for env in staging production; do
  railway environment edit --environment $env --service-config api source.checkSuites true -m "wait for CI on api"
  railway environment edit --environment $env --service-config web source.checkSuites true -m "wait for CI on web"
done
railway environment config --environment staging --json | jq '[.. | objects | select(has("source")) | .source.checkSuites]'
```

Expected: four edits accepted and the final line `[true, true]` (or `[true, true, null, null]` including the databases). If the CLI rejects `source.checkSuites`, go to Step 2 regardless; the dashboard is the source of truth.

- [ ] **Step 2: PAUSE for the dashboard confirmation**

> **PAUSE (Mike):** open the Railway project `kaizen-tasks`. For each of the two environments (selector top-left) and each of `api` and `web`: click the service, Settings, scroll to the Source section, confirm the toggle named "Wait for CI" (Railway may label it "Check Suites") is on; switch it on if not. Reply with the exact label text you saw, so the runbook records it.

- [ ] **Step 3: Trigger a staging deploy and watch it wait**

The lane does not commit to the app repos. Ask the orchestrator for the next `develop` push from L1 or L2; if none is due within ten minutes:

> **PAUSE (Mike):** run `cd /Users/Mike.Bogdanovsky/Projects/nice-product-workshop-Sep.2026/webapp/backend && git switch develop && git pull --ff-only && git commit --allow-empty -m "chore: trigger staging deploy" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01HWmLNo9LBp2SgKdYisfRoJ" && git push origin develop`, then reply "pushed".

Then watch both systems:

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
SHA="$(git rev-parse origin/develop)"
gh run list --repo kpnemo/kaizen-tasks-api --branch develop --workflow ci --limit 1 --json status,conclusion,headSha --jq '.[0] | "\(.status) \(.conclusion) \(.headSha[0:7])"'
railway deployment list --service api --environment staging --limit 3 --json | jq -r '.[] | "\(.status) \(.meta.commitHash // .commitHash // "?" | .[0:7]) \(.createdAt)"'
```

Expected while `ci` is `in_progress`: the newest deployment line reads `WAITING <sha7> <time>`. Poll every 30 seconds (`sleep` is blocked in the harness; use the Monitor tool or repeat the block) until `ci` shows `completed success` and the deployment shows `SUCCESS`. Record the two timestamps (CI completion, deployment `SUCCESS`); the deployment must not have started `BUILDING` before CI completed. If the deployment went straight to `BUILDING` with CI still running, wait-for-CI is off: return to Step 2.

Repeat for the web repo (`kpnemo/kaizen-tasks-web`, service `web`) with an L2 push or the same empty-commit PAUSE in `webapp/frontend/`.

- [ ] **Step 4: Health from inside Railway (no public domain yet)**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway logs --service api --environment staging --lines 60 --json | jq -r '.[].message' | grep -iE 'listening|migrat|seed|error' | tail -10
```

Expected: lines showing migrations applied, the demo seed created (first boot), and the server listening on 3000; no `error` lines. If the deployment is `CRASHED`, triage with `railway logs --service api --environment staging --lines 200 --json` and hand the log to L1; the usual causes are a missing variable name (compare with Task 5's list) or a startup asset check.

- [ ] **Step 5: Log and commit**

Append `| <date> | 9 | wait-for-CI on x4 (label seen: "<text>"); staging api and web deployments WAITING during ci then SUCCESS (V4 verified) | ci completed <t1>, deployment SUCCESS <t2> per service |`; commit `docs: log wait-for-CI and first gated deploys`; push.

---

### Task 10: Public domains, proxy and health verification, record in the runbook (L3-M1)

**Files:**

- Modify: `docs/runbook.md` ("Fixed facts" rows for the two web domains, and every `<staging web domain>` / `<production web domain>` occurrence), `docs/railway-setup.md` (nothing unless a command differed), `docs/cicd-log.md`

**Interfaces:**

- Consumes: Task 9; the web `Caddyfile` proxy (`/api/*` to `http://api.railway.internal:3000`); `PORT=8080` on `web`.
- Produces: the two `web` domains; the L3-M1 condition: "Staging `web` domain serves the app shell and `/version.json`; staging `web` domain `/api/v1/health` returns the API's commit SHA through the proxy; a push to `develop` in either repo shows a Railway deployment waiting on CI" (the last clause from Task 9). The domains are handed to L1 and L2 for their `promote.yml` staging URL.

- [ ] **Step 1: Generate the domains**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway domain --service web --environment staging --port 8080 --json | tee "$SCRATCH/domain-staging.json"
railway domain --service web --environment production --port 8080 --json | tee "$SCRATCH/domain-production.json"
railway domain list --service web --environment staging --json | jq -r '.. | .domain? // empty'
railway domain list --service web --environment production --json | jq -r '.. | .domain? // empty'
railway domain list --service api --environment staging --json | jq -r '.. | .domain? // empty' | wc -l | tr -d ' '
```

Expected: two generated domains of the form `web-staging-<hash>.up.railway.app` and `web-production-<hash>.up.railway.app` (Railway picks the names); the `api` domain count is `0`. Write the two values into `$SCRATCH/domains.txt` as `STAGING=https://...` and `PRODUCTION=https://...`.

- [ ] **Step 2: Verify the shell, version, and the proxied health**

```bash
cd "$WS/webapp/backend"
. "$SCRATCH/domains.txt"
curl -sS -o /dev/null -w 'shell %{http_code} %{content_type}\n' "$STAGING/"
curl -fsS -D - -o "$SCRATCH/version.json" "$STAGING/version.json" | grep -i 'cache-control'
cat "$SCRATCH/version.json"; echo
echo "expected web sha: $(git -C "$WS/webapp/frontend" rev-parse origin/develop)"
curl -fsS "$STAGING/api/v1/health" | tee "$SCRATCH/health.json" | jq .
echo "expected api sha: $(git rev-parse origin/develop)"
jq -e '.data.status == "ok" and .data.env == "staging" and .data.checks.db == "ok" and .data.checks.redis == "ok"' "$SCRATCH/health.json" >/dev/null && echo "HEALTH OK THROUGH PROXY"
```

Expected: `shell 200 text/html...`; `cache-control: no-store`; `{"commit":"<web sha>","builtAt":"<iso>"}` matching the expected web SHA; the health envelope `{ "data": { "status": "ok", "commit": "<api sha>", "env": "staging", "checks": { "db": "ok", "redis": "ok" } } }` with the expected API SHA; `HEALTH OK THROUGH PROXY`. A 502 on `/api/v1/health` with a 200 shell means the proxy target or private networking is wrong: check `railway variable list --service api --environment staging --json | jq -r .PORT` is `3000` and `railway logs --service web --environment staging --lines 50 --json` for Caddy's upstream error; hand the log to L2 if the `Caddyfile` is at fault (web spec verification item W1 and its fallback live there).

Production serves whatever `main` holds (docs only until the first promotion), so only `curl -sS -o /dev/null -w '%{http_code}\n' "$PRODUCTION/"` is checked now; a non-200 is expected until Task 12.

- [ ] **Step 3: Record the domains in the runbook**

```bash
cd "$WS/webapp" && git switch develop && git pull --ff-only origin develop
. "$SCRATCH/domains.txt"
S="${STAGING#https://}"; P="${PRODUCTION#https://}"
sed -i '' -e "s|<staging web domain>|$S|g" -e "s|<production web domain>|$P|g" docs/runbook.md
sed -i '' -e "s| (filled by the CI/CD lane at L3-M1)||g" docs/runbook.md
grep -n "up.railway.app" docs/runbook.md | head -5
grep -c '<staging web domain>\|<production web domain>' docs/runbook.md
```

Expected: the "Fixed facts" rows and every command in the runbook now carry the real hostnames; the last count is `0`. Tell the L1 and L2 lanes the staging domain for their `promote.yml` (`https://$S`) and the smoke `SMOKE_BASE_URL`.

- [ ] **Step 4: Log and commit (L3-M1)**

Append `| <date> | 10 | L3-M1 met: web domains generated; staging shell 200, version.json no-store with develop sha, /api/v1/health ok through the proxy with the api develop sha | curl outputs above |`.

```bash
cd "$WS/webapp"
npx prettier --write docs/runbook.md docs/cicd-log.md
git add docs/runbook.md docs/cicd-log.md
git commit -m "docs: record the staging and production web domains (L3-M1)" -m "$TRAILER"
git push origin develop
```

---

### Task 11: Branch protection (master plan item 6)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: `scripts/protect-branches.sh` (assembly-line plan Task 12); the check names `ci` and `promote` (master plan interface "Check names"); unblock condition "after both repos' `ci` has run at least once and `promote` exists" (the `promote.yml` file is committed in both app repos, which needs the staging domain from Task 10).
- Produces: protection on `develop` and `main` in both app repos: `develop` requires `ci`; `main` requires `ci` and `promote`; pull request required, zero approvals, no force pushes, no deletions, enforce-admins off.

- [ ] **Step 1: Confirm the preconditions**

```bash
for r in kaizen-tasks-api kaizen-tasks-web; do
  echo "== $r"
  gh run list --repo "kpnemo/$r" --workflow ci --limit 1 --json conclusion --jq '.[0].conclusion'
  gh api "repos/kpnemo/$r/contents/.github/workflows/promote.yml?ref=develop" --jq .name
  gh api "repos/kpnemo/$r/branches/main/protection" >/dev/null 2>&1 && echo "already protected" || echo "not yet protected"
done
```

Expected per repo: `success`, `promote.yml`, `not yet protected`.

- [ ] **Step 2: Apply**

```bash
cd "$WS/webapp" && git pull --ff-only origin develop && test -x scripts/protect-branches.sh
scripts/protect-branches.sh kpnemo/kaizen-tasks-api --dry-run | head -3
scripts/protect-branches.sh kpnemo/kaizen-tasks-api
scripts/protect-branches.sh kpnemo/kaizen-tasks-web
```

Expected per repo, two JSON lines from the script's `--jq`: `{"branch":"develop","checks":["ci"],"enforce_admins":false,"approvals":0,"force_pushes":false,"deletions":false}` and `{"branch":"main","checks":["ci","promote"],...}`.

- [ ] **Step 3: Verify with the API directly**

```bash
for r in kaizen-tasks-api kaizen-tasks-web; do
  for b in develop main; do
    printf '%-18s %-8s ' "$r" "$b"
    gh api "repos/kpnemo/$r/branches/$b/protection" --jq '[(.required_status_checks.contexts | join("+")), (.required_pull_request_reviews.required_approving_review_count | tostring), (.enforce_admins.enabled | tostring), (.allow_force_pushes.enabled | tostring), (.allow_deletions.enabled | tostring)] | join(" ")'
  done
done
```

Expected four lines: `... develop ci 0 false false false` and `... main ci+promote 0 false false false`.

- [ ] **Step 4: Announce the consequence**

From now on, no lane can push to `develop` directly in the app repos: every change goes through a feature branch and a pull request whose `ci` is green. Tell the orchestrator; the master plan's "every lane commits to its repo's `develop` in small commits" now means "via pull request".

- [ ] **Step 5: Log and commit**

Append `| <date> | 11 | branch protection on develop (ci) and main (ci+promote) in both app repos | gh api protection x4 as expected |`; commit `docs: log branch protection`; push (the assembly-line repo itself is unprotected, so this push still works).

---

### Task 12: Promotion proof, `develop` to `main` in each app repo (master plan item 7; L3-M2; proves L3)

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: unblock condition "L4-M2: `smoke/` passes locally against staging; both skills run end to end against the seeds in dry-run; runbook and railway-setup docs complete" (the smoke package must be on `main` of the assembly-line repo, because `promote` checks it out at `main`); Task 11; the `promote` workflows (API: poll `/api/v1/health` for the head SHA then run the smoke; web: poll `/version.json`).
- Produces: one merged promotion per app repo, production serving the merged SHAs; the L3-M2 condition met; assembly-line verification item L3 (`actions/checkout` of the public assembly-line repo into a subfolder without a token) observed in the `promote` log.

- [ ] **Step 1: Put the smoke package on `main` of the assembly-line repo**

The assembly-line repo is not branch-protected, but `main` receives `develop` only by pull request (global constraint):

```bash
cd "$WS/webapp" && git switch develop && git pull --ff-only origin develop
gh pr create --repo kpnemo/kaizen-tasks-assembly-line --base main --head develop --title "release: harness to main for the first promotion" --body "Promote develop to main so the app repos' promote workflows can check out smoke/ at main."
gh pr checks --repo kpnemo/kaizen-tasks-assembly-line --watch "$(gh pr list --repo kpnemo/kaizen-tasks-assembly-line --base main --head develop --json number --jq '.[0].number')"
```

> **PAUSE (Mike):** merge that pull request with `gh pr merge <number> --repo kpnemo/kaizen-tasks-assembly-line --merge` (a merge commit keeps `develop` and `main` in sync), then reply "merged".

Verify: `gh api repos/kpnemo/kaizen-tasks-assembly-line/contents/smoke/package.json?ref=main --jq .name` prints `package.json`.

- [ ] **Step 2: API promotion**

```bash
cd "$WS/webapp/backend" && git fetch origin
echo "candidate api sha: $(git rev-parse origin/develop)"
gh pr create --repo kpnemo/kaizen-tasks-api --base main --head develop --title "release: first promotion to production" --body "Promote develop to main. Gate: promote runs the smoke package against staging."
PR="$(gh pr list --repo kpnemo/kaizen-tasks-api --base main --head develop --json number --jq '.[0].number')"
gh pr checks "$PR" --repo kpnemo/kaizen-tasks-api --watch
gh pr checks "$PR" --repo kpnemo/kaizen-tasks-api --json name,state --jq '.[] | "\(.name) \(.state)"'
```

Expected: `ci SUCCESS` and `promote SUCCESS` (the promote job takes the staging poll plus the smoke, typically three to six minutes). If `promote` fails on the poll, staging is not serving the head SHA: check `railway deployment list --service api --environment staging --limit 1 --json` (the last `develop` merge must be `SUCCESS`). If it fails in the smoke, download the artifact (`gh run download <run id> --repo kpnemo/kaizen-tasks-api -n smoke-results`) and open the trace; hand it to the owning lane; do not merge.

Then observe L3 in the log:

```bash
RUN="$(gh run list --repo kpnemo/kaizen-tasks-api --workflow promote --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$RUN" --repo kpnemo/kaizen-tasks-api --log | grep -iE "assembly-line|Checking out the ref|Successfully" | head -8
```

Expected: a checkout step for `kpnemo/kaizen-tasks-assembly-line` at `main` into a subfolder that completes with no token prompt or 401 (verification item L3 met; the fallback `token: ${{ github.token }}` was not needed).

> **PAUSE (Mike):** merge with `gh pr merge <PR> --repo kpnemo/kaizen-tasks-api --merge`, reply "merged".

```bash
cd "$WS/webapp/backend" && git fetch origin
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
railway deployment list --service api --environment production --limit 1 --json | jq -r '.[0].status'
. "$SCRATCH/domains.txt"
curl -fsS "$PRODUCTION/api/v1/health" | jq -r '.data | "\(.status) \(.env) \(.commit[0:7])"'
echo "expected: ok production $(git rev-parse origin/main | cut -c1-7)"
```

Expected: `WAITING` while the push-to-`main` `ci` runs, then `SUCCESS`; then `ok production <sha7>` equal to the expected line.

- [ ] **Step 3: Web promotion**

Same sequence with `kpnemo/kaizen-tasks-web` and `$WS/webapp/frontend`, verifying with:

```bash
. "$SCRATCH/domains.txt"
curl -fsS "$PRODUCTION/version.json" | jq -r .commit | cut -c1-7
git -C "$WS/webapp/frontend" rev-parse origin/main | cut -c1-7
curl -sS -o /dev/null -w 'shell %{http_code}\n' "$PRODUCTION/"
```

Expected: the two SHAs match and the shell is `200`. Then run the smoke against production once from the assembly-line checkout: `cd "$WS/webapp/smoke" && SMOKE_BASE_URL=$PRODUCTION npm test` prints `1 passed`.

- [ ] **Step 4: Log and commit (L3-M2)**

Append `| <date> | 12 | L3-M2 met: develop→main promoted in both app repos with promote green; production health and version.json show the main SHAs; L3 verified (checkout of the public repo needed no token) | promote run ids <api run>, <web run>; production sha7 <api>, <web> |`; commit `docs: log the first promotions (L3-M2)`; push `develop`.

---

### Task 13: Integration support: demo user reset and the L1 observation

**Files:**

- Modify: `docs/cicd-log.md`

**Interfaces:**

- Consumes: master plan interface "Seed reset": `POST /api/v1/admin/seed-reset` with header `x-admin-token`, demo user `demo@kaizen.local`; the INT milestone run from the workspace root with the assembly-line skills (seed 01 implemented by `implement-issue`, merged to `develop` by Mike, promoted to `main`).
- Produces: the demo user reset on both environments; assembly-line verification item L1 observed (the cross-repo `Closes` line closed the issue) or its fallback applied.

- [ ] **Step 1: Demo user reset**

> **PAUSE (Mike):** in your terminal, with the `ADMIN_TOKEN` values from Tasks 5 and 6:
>
> ```bash
> . /private/tmp/claude-502/-Users-Mike-Bogdanovsky-Projects-nice-product-workshop-Sep-2026/b173ad22-2840-489c-891e-760f2df96511/scratchpad/domains.txt
> curl -fsS -X POST "$STAGING/api/v1/admin/seed-reset" -H "x-admin-token: <staging ADMIN_TOKEN>" | jq .
> curl -fsS -X POST "$PRODUCTION/api/v1/admin/seed-reset" -H "x-admin-token: <production ADMIN_TOKEN>" | jq .
> ```
>
> Each prints `{ "data": { "demoUserId": "<uuid>" }, "meta": { "requestId": "..." } }`. Reply "reset done".

Verify without the token: `curl -sS -o /dev/null -w '%{http_code}\n' -X POST "$PRODUCTION/api/v1/admin/seed-reset"` prints `404` (the route is invisible without the header, API spec 4.4).

- [ ] **Step 2: Observe L1 after seed 01 merges**

After INT's `implement-issue` pull request for seed 01 has been merged by Mike (the runbook's Ship segment):

```bash
N="$(gh issue list --repo kpnemo/kaizen-tasks-assembly-line --label feature-request --state all --search 'Mark all steps done in:title' --json number --jq '.[0].number')"
gh issue view "$N" --repo kpnemo/kaizen-tasks-assembly-line --json state,closedByPullRequestsReferences --jq '"\(.state) closedBy=\(.closedByPullRequestsReferences | length)"'
```

Expected: `CLOSED closedBy=1`. L1 verified. If it prints `OPEN closedBy=0`, apply the fallback recorded in the assembly-line plan: `gh issue close "$N" --repo kpnemo/kaizen-tasks-assembly-line --comment "Shipped in <pr url>"`, and tell the L4 lane to add that command to the implement skill's Step 8.

- [ ] **Step 3: Log and commit**

Append `| <date> | 13 | demo user reset on staging and production; L1 <verified | fallback applied> for issue #<N> | seed-reset 200 x2, 404 without token; issue state CLOSED |`; commit `docs: log integration support`; push.

---

### Task 14: Runbook Railway sections from what was actually seen (master plan item 8)

**Files:**

- Modify: `docs/runbook.md` (sections 5 "Rollback" and the T-minus-one-hour variable step), `docs/railway-setup.md` (section 5 "Wait-for-CI" dashboard wording, section "Rollback"), `docs/cicd-log.md`

**Interfaces:**

- Consumes: the label text Mike reported in Task 9, the deployment list and redeploy behavior observed in Tasks 9 and 12.
- Produces: runbook click paths that match the dashboard, and a rehearsed rollback.

- [ ] **Step 1: Rehearse the rollback on staging**

```bash
cd "$WS/webapp/backend"
export RAILWAY_CALLER=skill:use-railway@1.4.0 RAILWAY_AGENT_SESSION=railway-skill-kaizen-tasks-l3
GUARD='railway status --json | jq -e ".name == \"kaizen-tasks\"" >/dev/null || { echo "REFUSING: not linked to kaizen-tasks" >&2; exit 1; }'
eval "$GUARD"
railway deployment list --service web --environment staging --limit 3 --json | jq -r '.[] | "\(.id[0:8]) \(.status) \(.createdAt)"'
```

> **PAUSE (Mike):** in the dashboard, staging, service `web`, Deployments tab: open the menu of the previous successful deployment and click Redeploy. Reply with the exact menu wording (for example "Redeploy" or "Rollback to this version").

```bash
. "$SCRATCH/domains.txt"
curl -fsS "$STAGING/version.json" | jq -r .commit | cut -c1-7
```

Expected: the previous web SHA is served within about a minute. Then restore the newest build with the same click on the newest deployment, and confirm `version.json` shows the `develop` SHA again.

- [ ] **Step 2: Write the observed wording into the docs**

Edit `docs/runbook.md` section 5 and `docs/railway-setup.md` section "Rollback" to use the exact menu label Mike reported, and `docs/railway-setup.md` section 5 to use the exact "Wait for CI" label from Task 9. Add to the runbook's T-minus-one-hour list the observed redeploy time for `api` after `railway variable set AI_GLOBAL_LIMIT_PER_HOUR=600 ...` (measured with `railway deployment list --service api --environment production --limit 1 --json` timestamps).

```bash
cd "$WS/webapp"
grep -n 'Redeploy\|Wait for CI' docs/runbook.md docs/railway-setup.md
```

Expected: every occurrence uses the observed wording; none says "(filled" anywhere: `grep -c '(filled' docs/runbook.md docs/railway-setup.md` prints `0` for both, except the rehearsal-timings row that the rehearsal itself fills.

- [ ] **Step 3: Log and commit**

Append `| <date> | 14 | runbook and railway-setup carry the dashboard wording; rollback rehearsed on staging web (<previous sha7> served, then restored) | version.json before/after |`.

```bash
cd "$WS/webapp"
npx prettier --write docs/runbook.md docs/railway-setup.md docs/cicd-log.md
git add docs/runbook.md docs/railway-setup.md docs/cicd-log.md
git commit -m "docs: runbook Railway sections from the dashboard as seen; rollback rehearsed" -m "$TRAILER"
git push origin develop
```

---

## Verification items, mapped

| Item | Proven by | Fallback |
|---|---|---|
| API spec V4: wait-for-CI holds a push-triggered deploy | Task 9, Step 3: deployment `WAITING` while `ci` runs, `SUCCESS` after | GitHub Actions deploys through the Railway CLI (`railway up --ci`) from a deploy job; would be added to both app repos' `ci.yml` by L1 and L2 |
| Assembly-line L1: cross-repo `Closes` closes the issue | Task 13, Step 2 after the first merged seed | `gh issue close` in the runbook, then in the implement skill |
| Assembly-line L3: checkout of the public repo into a subfolder without a token | Task 12, Step 2, promote log | `token: ${{ github.token }}` on the checkout step in both promote workflows |
| Web spec W1: Railpack static provider honors the root `Caddyfile` with a private-hostname proxy | Task 10, Step 2 (`/api/v1/health` through the staging web domain) | L2's fallback (a small Node static server with a proxy) |
| Master plan O2 (PRD): the SHA poll works without deployment events | Task 12, `promote` passes its poll stage | none needed once observed |

## Self-review

**Coverage of master plan section 6.** Item 1 (repos) Task 2; item 2 (labels) Task 3; item 3 (project and environments) Tasks 4 and 6; item 4 (databases, services, variables, secrets pause) Tasks 5 to 7; item 5 (IaC, domains, wait-for-CI, trivial push, curl verification, runbook domains) Tasks 8 to 10; item 6 (protection) Task 11; item 7 (promotion proof) Task 12; item 8 (runbook Railway sections) Tasks 13 and 14. Mike's inputs from master plan section 5 each have a PAUSE: Anthropic key (Task 5), generated secrets per environment (Tasks 5 and 6), wait-for-CI toggle (Task 9), Railway GitHub App (Task 5), merges of `develop` to `main` (Task 12), empty commit when no push is due (Task 9).

**Standing rule.** Every mutating block begins with the `GUARD` line; `railway link` appears only with `--project kaizen-tasks`; Task 4 diffs the project list before and after creation; no delete, down, or `--confirm-destructive` anywhere.

**use-railway compliance.** Preflight (`whoami`, `status`, agent tooling freshness) in Task 1; `--json` on every `railway add`; list before retry; secrets through `--stdin` in Mike's terminal; `config plan` reviewed by Mike before every `config apply`, no `--yes`; deployments reported only on observed `SUCCESS`; bounded `railway logs` with `--lines`.

**Placeholder scan.** `<sha>`, `<n>`, `<date>`, `<PR>`, and the two domains are runtime values recorded into `docs/cicd-log.md` and `docs/runbook.md` as they appear; `PASTE-THE-...` strings appear only inside Mike's PAUSE commands, by design. Every command is written out with its expected output.

**Name consistency.** Service names `api`, `web`, `Postgres`, `Redis` and environment names `staging`, `production` match the master plan interface "Railway services" and the variable references `${{Postgres.DATABASE_URL}}`, `${{Redis.REDIS_URL}}`. Variable names match API spec 2.4 exactly. Check names `ci` and `promote` match `scripts/protect-branches.sh` and the app specs. The staging domain file `$SCRATCH/domains.txt` uses `STAGING` and `PRODUCTION` in every task that reads it.
