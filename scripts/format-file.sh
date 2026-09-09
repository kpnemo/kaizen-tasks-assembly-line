#!/usr/bin/env bash
# Root PostToolUse hook for Edit|Write: format the edited file with the owning repo's prettier.
# stdin: the hook JSON ({"tool_name":"Edit","tool_input":{"file_path":"..."}}).
#   KAIZEN_WORKSPACE_ROOT=<dir> overrides the workspace root (used by the fixture test).
# Files under backend/ or frontend/ are formatted by that repo's prettier (any extension prettier knows).
# Files elsewhere are formatted by the root prettier only when they are markdown, JSON, or YAML.
# Never blocks: always exits 0.
set -uo pipefail

ROOT="${KAIZEN_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
input=""
if [ ! -t 0 ]; then IFS= read -r -t 5 input || true; fi
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
if [ -z "$file" ]; then exit 0; fi
case "$file" in
  /*) ;;
  *) file="$ROOT/$file" ;;
esac
if [ ! -f "$file" ]; then exit 0; fi

format_in() { # repo file
  local repo="$1" target="$2"
  if [ ! -x "$repo/node_modules/.bin/prettier" ]; then
    echo "format-file: prettier is not installed in $repo, skipped $target"
    return 0
  fi
  if (cd "$repo" && ./node_modules/.bin/prettier --write --ignore-unknown --log-level warn "$target"); then
    echo "format-file: formatted $target with $repo/node_modules/.bin/prettier"
  else
    echo "format-file: prettier failed on $target"
  fi
}

case "$file" in
  "$ROOT/backend/"*) format_in "$ROOT/backend" "$file" ;;
  "$ROOT/frontend/"*) format_in "$ROOT/frontend" "$file" ;;
  *.md | *.json | *.yml | *.yaml) format_in "$ROOT" "$file" ;;
  *) echo "format-file: $file is outside both repos and not markdown, JSON, or YAML; skipped" ;;
esac
exit 0
