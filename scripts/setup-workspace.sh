#!/usr/bin/env bash
# Prepare the workspace: clone the two app repos if missing, select Node 24 with nvm, check Postgres and Redis,
# create the local databases, run npm ci in both repos, print the next commands.
# Usage: scripts/setup-workspace.sh [--dry-run]
# Every step is idempotent. In --dry-run, mutations are printed and missing services are reported as WARN.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then DRY_RUN=1; fi

# Homebrew's postgresql@17 is keg-only: pg_isready, psql and createdb are not linked
# onto PATH by default. Fall back to the keg's bin directory when the tools aren't found.
if ! command -v pg_isready >/dev/null 2>&1; then
  if [ -d /opt/homebrew/opt/postgresql@17/bin ]; then
    PATH="/opt/homebrew/opt/postgresql@17/bin:$PATH"
  elif [ -d /usr/local/opt/postgresql@17/bin ]; then
    PATH="/usr/local/opt/postgresql@17/bin:$PATH"
  fi
  export PATH
fi

run() {
  if [ "$DRY_RUN" = 1 ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}
problem() {
  if [ "$DRY_RUN" = 1 ]; then echo "WARN  $*"; else echo "ERROR $*" >&2; exit 1; fi
}

echo "== 1. Nested repos"
for dir in backend frontend; do
  case "$dir" in
    backend) repo="kpnemo/kaizen-tasks-api" ;;
    frontend) repo="kpnemo/kaizen-tasks-web" ;;
  esac
  if [ -d "$ROOT/$dir/.git" ]; then
    echo "OK    $dir is a git checkout"
  else
    # gh honours the user's configured git protocol (HTTPS with the CLI's credential helper on this machine)
    run gh repo clone "$repo" "$ROOT/$dir"
  fi
done

echo "== 2. Node 24 through nvm"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
set +u
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
elif [ -s /opt/homebrew/opt/nvm/nvm.sh ]; then
  . /opt/homebrew/opt/nvm/nvm.sh
else
  problem "nvm not found; install it from https://github.com/nvm-sh/nvm and rerun"
fi
if command -v nvm >/dev/null 2>&1; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "DRY-RUN: nvm install 24 && nvm use 24"
  else
    nvm install 24 >/dev/null
    nvm use 24 >/dev/null
  fi
  echo "OK    node $(node --version 2>/dev/null || echo '?')"
fi
set -u

echo "== 3. Postgres and Redis"
if ! command -v pg_isready >/dev/null 2>&1; then
  problem "pg_isready not found; install postgresql@17 with Homebrew or add its bin directory to PATH"
elif pg_isready -q 2>/dev/null; then
  echo "OK    Postgres answers"
else
  problem "Postgres is not answering; run: brew services start postgresql@17"
fi
if [ "$(redis-cli ping 2>/dev/null || true)" = "PONG" ]; then
  echo "OK    Redis answers"
else
  problem "Redis is not answering; run: brew services start redis"
fi

echo "== 4. Databases"
for db in kaizen_dev kaizen_test; do
  if psql -lqt 2>/dev/null | cut -d '|' -f 1 | tr -d ' ' | grep -qx "$db"; then
    echo "OK    database $db exists"
  else
    run createdb "$db"
  fi
done

echo "== 5. Dependencies"
for dir in backend frontend; do
  if [ -f "$ROOT/$dir/package.json" ]; then
    (cd "$ROOT/$dir" && run npm ci)
  else
    echo "SKIP  $dir has no package.json yet"
  fi
done

cat <<EOF
== Next
  API:  cd backend  && nvm use && cp -n .env.example .env; AI_MODEL_PROVIDER=fake npm run dev   # http://localhost:3000 (set a real ANTHROPIC_API_KEY in .env to use the assistant)
  Web:  cd frontend && nvm use && VITE_PROXY_TARGET=http://localhost:3000 npm run dev   # http://localhost:5173
  Both test suites: (cd backend && npm test) && (cd frontend && npm test)
EOF
