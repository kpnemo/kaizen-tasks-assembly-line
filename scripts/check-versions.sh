#!/usr/bin/env bash
# Check that the two nested app repos carry the same semver in package.json.
# Usage: scripts/check-versions.sh
#
# Prints "api <version>" and "web <version>" read from backend/package.json and
# frontend/package.json with `jq -r .version`, relative to the repo root.
#
# Exit 1 with a one-line message if either nested repo or its package.json is
# missing, or if the two versions differ. Exit 0 printing "versions match: <version>"
# otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for name in backend frontend; do
  if [ ! -d "$ROOT/$name" ]; then
    echo "missing nested repo: $name" >&2
    exit 1
  fi
  if [ ! -f "$ROOT/$name/package.json" ]; then
    echo "missing $name/package.json" >&2
    exit 1
  fi
done

api_version="$(jq -r .version "$ROOT/backend/package.json")"
web_version="$(jq -r .version "$ROOT/frontend/package.json")"

echo "api $api_version"
echo "web $web_version"

if [ "$api_version" != "$web_version" ]; then
  echo "versions differ: api $api_version, web $web_version; cut the same version in both repos with /release-notes" >&2
  exit 1
fi

echo "versions match: $api_version"
