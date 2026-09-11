#!/usr/bin/env bash
# cut-release.sh <dir> <repo> <version>: the release commit in one app repo checkout, on the branch
# release/<version>, pushed and opened as a pull request to develop. Idempotent: develop already at
# <version> -> nothing to do; release/<version> already pushed -> verified and reused; a pull
# request already open or merged -> reused. Mirrors each repo's release-notes skill: move the
# [Unreleased] bullets under a dated version heading, bump package.json and the lockfile,
# regenerate the product map, format, lint, commit with the trailer.
set -euo pipefail
. "$(dirname "$0")/lib.sh"
dir="$1"
repo="$2"
version="$3"
cd "$dir"
git config user.name "kaizen-ship"
git config user.email "kaizen-ship@users.noreply.github.com"

current="$(jq -r .version package.json)"
if [[ "$current" == "$version" ]]; then
  echo "$repo develop is already at $version"
  exit 0
fi
semver_gt "$version" "$current" || fail "$repo: $version is not greater than $current"

branch="release/$version"
if git fetch origin "$branch" 2>/dev/null; then
  # Somebody (an earlier run) pushed it: accept it only if it is exactly one release commit.
  count="$(git rev-list --count "origin/develop..origin/$branch")"
  files="$(git diff --name-only "origin/develop..origin/$branch" | sort | tr '\n' ' ')"
  [[ "$count" == "1" ]] || fail "$repo: $branch has $count commits over develop, expected 1"
  pushed_version="$(git show "origin/$branch:package.json" | jq -r .version)"
  [[ "$pushed_version" == "$version" ]] || fail "$repo: $branch carries version $pushed_version, expected $version"
  for f in $files; do
    case "$f" in
    CHANGELOG.md | package.json | package-lock.json | docs/product-map.md) ;;
    *) fail "$repo: $branch touches $f, which a release commit never does" ;;
    esac
  done
  echo "$repo: reusing $branch ($files)"
else
  git switch -c "$branch"
  node - "$version" <<'JS'
const fs = require("fs");
const version = process.argv[2];
const date = new Date().toISOString().slice(0, 10);
const path = "CHANGELOG.md";
let s = fs.readFileSync(path, "utf8");
const head = "## [Unreleased]\n\n";
if (!s.includes(head)) {
  console.error("CHANGELOG.md has no [Unreleased] heading");
  process.exit(1);
}
if (!s.includes(`## [${version}]`)) s = s.replace(head, `${head}## [${version}] - ${date}\n\n`);
fs.writeFileSync(path, s);
JS
  npm version --no-git-tag-version "$version" >/dev/null
  npm run product-map >/dev/null
  npx prettier --write CHANGELOG.md >/dev/null
  npm run lint >/dev/null
  git add -A
  git commit -q -m "chore: release $version" -m "$TRAILER"
  run "push $repo $branch" -- git push -u origin "$branch"
fi

if dry; then
  echo "dry-run: would open the $repo pull request $branch → develop"
  exit 0
fi
if [[ -z "$(pr_number "$repo" "$branch" develop open)" && -z "$(pr_number "$repo" "$branch" develop merged)" ]]; then
  gh pr create --repo "$repo" --base develop --head "$branch" \
    --title "chore: release $version" --body "Cut $version (ship $REQUEST_ID)." >/dev/null
fi
echo "$repo release pull request: #$(pr_number "$repo" "$branch" develop open || true)"
