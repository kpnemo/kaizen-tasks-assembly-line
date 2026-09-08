# Railway setup for Kaizen Tasks

**Scope rule.** The workshop touches exactly one Railway project, the new project `kaizen-tasks`, created by `railway init` from `backend/`. Never `railway link` to, modify, redeploy, or delete any other project in the account. Before any command that changes state, `railway status --json | jq -r .name` must print `kaizen-tasks`. Railway work follows the official `use-railway` skill (`railway setup agent`); its preflight is `railway whoami --json` and `railway status --json`.

**State on 2026-09-08 evening** (master plan section 2, L3-M0 status). Sections 1 to 3, 5, and 6 below have been executed: project `kaizen-tasks` (id `67adb3e0-f2af-4ad3-bbaa-32ec8a53b10e`) exists with `staging` and `production`; each has `Postgres`, `Redis`, `api` from `kpnemo/kaizen-tasks-api`, and `web` from `kpnemo/kaizen-tasks-web` on that environment's branch; the variable set is in place with `PORT=3000` on `api` and `PORT=8080` on `web`; wait-for-CI is on through `source.checkSuites`; healthchecks are set (`/api/v1/health` on `api`, `/version.json` on `web`); the `web` domains are generated. Still open: `ANTHROPIC_API_KEY` is the placeholder `REPLACE_ME_WITH_REAL_KEY` in both environments until Mike replaces it (the paste command is in section 2), and section 4 (IaC apply) waits for L1-M1 and L2-M1. Everything below stays the procedure of record: each step is safe to repeat, and together they rebuild the project if it is ever deleted.

## Target state

| Environment  | Services                          | Source branch | Public domain                                             |
| ------------ | --------------------------------- | ------------- | --------------------------------------------------------- |
| `production` | `api`, `web`, `Postgres`, `Redis` | `main`        | `web` only: `https://web-production-7ef71.up.railway.app` |
| `staging`    | `api`, `web`, `Postgres`, `Redis` | `develop`     | `web` only: `https://web-staging-52c0.up.railway.app`     |

`api` has no public domain. `web` proxies `/api/*` to `http://api.railway.internal:3000`; `api` pins `PORT=3000` and `web` pins `PORT=8080`. Wait-for-CI (`source.checkSuites: true`) is on for `api` and `web` in both environments so a red check suite never deploys.

## 1. Create the project

From `webapp/backend/`:

```bash
railway whoami --json
railway init --name kaizen-tasks --json
railway status | grep -E '^Project:|^Environment:'
railway list --json | jq -r '.[].name'
```

`init` creates the project with the default `production` environment and links the directory to it. `list` must show `kaizen-tasks` alongside the pre-existing projects, none of which change. Read-backs in this document are verified against Railway CLI 5.49.5. `railway status --json` serializes the raw Project object and has no field for the currently linked environment (`.environment` is `null`, and `--environment <name>` only filters which environment's data the JSON includes, it does not reflect what is actually linked); the human-readable `railway status` output reads the real link and prints both `Project:` and `Environment:` lines, so the grep above is the read-back that actually confirms it.

## 2. Build production first

Still linked to `production`:

```bash
railway add --database postgres --json      # service name Postgres
railway add --database redis --json         # service name Redis
railway add --service api --repo kpnemo/kaizen-tasks-api --branch main --json
railway add --service web --repo kpnemo/kaizen-tasks-web --branch main --json
railway service list --json | jq -r '.[].name'
```

If `railway add --repo` reports that the repo is not visible, Mike installs or extends the Railway GitHub App for `kpnemo/kaizen-tasks-api` and `kpnemo/kaizen-tasks-web` (Railway dashboard, Account settings, GitHub, Configure), then the command is repeated. Always pass `--json` to `railway add`; never retry blind, list services first.

Variables on `api` (non-secret; use `--skip-deploys` until the last one so the service does not redeploy for every change):

```bash
railway variable set \
  'DATABASE_URL=${{Postgres.DATABASE_URL}}' 'REDIS_URL=${{Redis.REDIS_URL}}' \
  PORT=3000 APP_ENV=production WORKER_ENABLED=true \
  AI_MODEL=claude-sonnet-5 AI_RATE_LIMIT_PER_HOUR=20 AI_GLOBAL_LIMIT_PER_HOUR=300 \
  AI_ENABLED=true AI_STALE_MINUTES=10 SEED_DEMO_USER=true LOG_LEVEL=info \
  --service api --environment production --skip-deploys
```

Variables on `web`: `PORT=8080` (Caddy binds `:{$PORT}`; a fixed value makes the domain's target port deterministic).

```bash
railway variable set PORT=8080 --service web --environment production --skip-deploys
```

Secrets on `api`, pasted by Mike in his own terminal so they never pass through an agent transcript. `JWT_SECRET` and `ADMIN_TOKEN` are at least 32 characters; `openssl rand -hex 32` produces 64.

```bash
openssl rand -hex 32 | tr -d '\n' | railway variable set JWT_SECRET --stdin --service api --environment production --skip-deploys
openssl rand -hex 32 | tr -d '\n' | railway variable set ADMIN_TOKEN --stdin --service api --environment production --skip-deploys
printf '%s' '<demo password>' | railway variable set SEED_DEMO_PASSWORD --stdin --service api --environment production --skip-deploys
printf '%s' '<anthropic key>'  | railway variable set ANTHROPIC_API_KEY --stdin --service api --environment production
```

Verify the names (values are not printed):

```bash
railway variable list --service api --environment production --json | jq -r 'keys[]' | sort
```

Expected names: `ADMIN_TOKEN AI_ENABLED AI_GLOBAL_LIMIT_PER_HOUR AI_MODEL AI_RATE_LIMIT_PER_HOUR AI_STALE_MINUTES ANTHROPIC_API_KEY APP_ENV DATABASE_URL JWT_SECRET LOG_LEVEL PORT REDIS_URL SEED_DEMO_PASSWORD SEED_DEMO_USER WORKER_ENABLED` plus Railway's own `RAILWAY_*` entries.

Then confirm the key is real, without printing it:

```bash
railway variable list --service api --environment production --json | jq -r '.ANTHROPIC_API_KEY | startswith("REPLACE_ME")'
```

Expected `false`. On 2026-09-08 it prints `true` in both environments: the placeholder `REPLACE_ME_WITH_REAL_KEY` is set and Mike replaces it with the `ANTHROPIC_API_KEY` command above; until then every AI breakdown on Railway fails.

`GITHUB_TOKEN` and `GITHUB_REPO=kpnemo/kaizen-tasks-assembly-line` are added only if the optional feature-request page ships.

## 3. Create staging by duplicating production

```bash
railway environment new staging --duplicate production
railway environment link staging
railway status | grep -E '^Project:|^Environment:'
railway service list --json | jq -r '.[].name'
```

Duplication copies every service, its configuration, and its variables; the databases are new instances with their own volumes and credentials, and the reference variables `${{Postgres.DATABASE_URL}}` resolve to the staging databases. Then override what differs:

```bash
railway environment edit --service-config api source.branch develop --environment staging -m "staging tracks develop"
railway environment edit --service-config web source.branch develop --environment staging -m "staging tracks develop"
railway variable set APP_ENV=staging --service api --environment staging --skip-deploys
NAMES=$(railway service list --json | jq -c '[.[] | {id, name}]')
railway environment config --environment staging --json | jq --argjson names "$NAMES" '
  ($names | map({(.id): .name}) | add) as $id2name
  | .services
  | to_entries[]
  | select($id2name[.key] == "api" or $id2name[.key] == "web")
  | {name: $id2name[.key], branch: .value.source.branch}
'
```

In `environment config --json`, `.services` is an object keyed by service ID and each entry has no `name` field, so filtering on `.name` prints nothing; the id-to-name join above reads `railway service list --json` for the mapping. Expected output, two objects: `{"name":"api","branch":"develop"}` and `{"name":"web","branch":"develop"}`.

Secrets for staging are pasted again by Mike with the same four commands as section 2 with `--environment staging`; staging gets its own `JWT_SECRET` and `ADMIN_TOKEN`, and the same Anthropic key unless Mike prefers a second one.

## 4. Apply each repo's `.railway/railway.ts` per environment

After L1-M1 and L2-M1 (the files exist and are pushed). The IaC file declares the service's build, start, healthcheck, and source branch chosen from the environment name. `railway config` commands act on the linked environment and cannot take `--environment`, so link, plan, review, apply, and repeat.

From `webapp/backend/`:

```bash
railway environment link staging
railway config plan --verbose
# review: only the api service changes; "0 to destroy" is required. If the plan destroys anything, stop.
railway config apply --yes        # only after Mike has read that exact plan and said "apply"
railway environment link production
railway config plan --verbose
railway config apply --yes
```

From `webapp/frontend/` (link the directory first):

```bash
railway link --project kaizen-tasks --environment staging
railway config plan --verbose
railway config apply --yes
railway environment link production
railway config plan --verbose
railway config apply --yes
```

`--yes` only stands in for the interactive confirmation in a non-interactive shell, and only after Mike has read the exact plan. Never pass `--confirm-destructive`; a plan that destroys anything is not applied. After each apply, re-run the wait-for-CI read-back in section 5: the IaC file does not carry `source.checkSuites`, and the field must still read `true` afterwards.

## 5. Wait-for-CI

Wait-for-CI is the per-environment service config field `source.checkSuites` (the `use-railway` skill lists it under Source: `source.checkSuites` (boolean)). It is not declared in `.railway/railway.ts`, so it is set with `railway environment edit` and read back with `railway environment config`. It has been on for `api` and `web` in both environments since 2026-09-08 (master plan section 4, "Wait-for-CI"); the commands below are the procedure of record and are safe to repeat.

```bash
for env in staging production; do
  railway environment edit --service-config api source.checkSuites true --environment $env -m "wait for CI"
  railway environment edit --service-config web source.checkSuites true --environment $env -m "wait for CI"
done
for env in staging production; do
  echo "== $env"
  railway environment config --environment $env --json | jq -c '[.. | objects | select(has("source")) | .source.checkSuites]'
done
```

Expected per environment: `[true,true]` (or `[true,true,null,null]` when the databases are listed too). Re-run the read-back after every `railway config apply` in section 4; if an apply ever resets the field, run the loop above again.

Dashboard, for verification only, never the way the field is set (Mike): project `kaizen-tasks`, environment selector top-left, service `api`, Settings, Source, the toggle named "Wait for CI" (Railway may label it "Check Suites") reads on; the same for `web`; the same in the other environment. The runbook records the exact label seen.

Verification (item V4 in the API spec): push a trivial commit to `develop` in either app repo; `railway deployment list --service api --environment staging --limit 1 --json` shows status `WAITING` while GitHub Actions runs, then `BUILDING`, `DEPLOYING`, `SUCCESS`.

## 6. Public domains for `web`

Generated on 2026-09-08: staging `https://web-staging-52c0.up.railway.app`, production `https://web-production-7ef71.up.railway.app`. `api` never gets a domain. The procedure, for the record; read the existing domains with `railway domain list` before generating anything:

```bash
railway domain list --service web --environment staging --json
railway domain list --service web --environment production --json
railway domain --service web --environment staging --port 8080 --json       # only when the list above is empty
railway domain --service web --environment production --port 8080 --json    # only when the list above is empty
```

Both domains are recorded in `docs/runbook.md` (section "Fixed facts") and are the `SMOKE_BASE_URL` of the app repos' `promote` workflows.

## 7. Verify

```bash
STAGING=https://web-staging-52c0.up.railway.app
curl -fsS "$STAGING/version.json" | jq .
curl -fsS "$STAGING/api/v1/health" | jq .
```

Expected: `version.json` shows `{ "commit": "<sha>", "builtAt": "<iso>" }` where `<sha>` is `git -C frontend rev-parse origin/develop`; health shows `{ "data": { "status": "ok", "commit": "<api sha>", "env": "staging", "checks": { "db": "ok", "redis": "ok" } } }`, proving the proxy and private networking. Repeat with the production domain after the first `main` deploy.

## Changing a variable during the session

`railway variable set AI_GLOBAL_LIMIT_PER_HOUR=600 --service api --environment production` triggers a redeploy of `api` (about two minutes). `AI_ENABLED=false` pauses the assistant the same way. Dashboard path: service `api`, Variables tab, edit, Deploy.

## Rollback

Rollback is a dashboard-only action: service `api` (or `web`), Deployments tab, the previous successful deployment, its menu, Redeploy. Safe because migrations are additive only (API ADR 0004): the previous application runs against the already-migrated database.

`railway redeploy --service api --environment production --yes` is **not** a rollback. Railway CLI 5.49.5 documents `redeploy` (and its alias `railway deployment redeploy`) as redeploying only the _latest_ deployment of a service (`railway redeploy --help`: "Redeploy the latest deployment of a service"), and neither command nor `railway deployment list` accepts a deployment ID to target, so the CLI cannot reach an older deployment. Use `railway redeploy` only to restart the current deployment (for example after a variable change), never to go back to a previous one.
