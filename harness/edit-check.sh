#!/usr/bin/env bash
# Edit-time gate. Wired as a Claude Code PostToolUse hook on Edit|Write: the
# shift-left layer, catching a problem in the same turn it is created instead
# of at commit time.
#
# Fast only. For the file's extension, runs the configured formatter (never
# blocks) then the configured linter (blocks only on a real failure). An
# extension with neither configured is skipped silently, so this script never
# needs editing to support a new language, only two lines in harness.config.
#
# Usage: edit-check.sh [file-path]
#   With no argument and no terminal on stdin, reads the Claude Code hook
#   payload as JSON and pulls tool_input.file_path out of it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HARNESS_CONFIG:-$HERE/harness.config}"
[ -f "$CONFIG" ] || CONFIG="$HERE/harness.config.example"

config_get() {
  local key="$1" default="${2:-}" value
  [ -f "$CONFIG" ] || { printf '%s\n' "$default"; return 0; }
  value=$(grep -E "^${key}=" "$CONFIG" 2>/dev/null | tail -1)
  if [ -n "$value" ]; then
    printf '%s\n' "${value#*=}"
  else
    printf '%s\n' "$default"
  fi
}

f="${1:-}"
if [ -z "$f" ] && [ ! -t 0 ]; then
  # Pull tool_input.file_path out of the hook JSON with a tiny, dependency-
  # free parser: good enough for one known key, no python/node/jq assumed.
  payload=$(cat)
  f=$(printf '%s' "$payload" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed -E 's/.*:[[:space:]]*"(.*)"/\1/')
fi
f="${f//\\//}"
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

ext="${f##*.}"
format_cmd=$(config_get "FORMAT_$ext" "")
lint_cmd=$(config_get "LINT_$ext" "")

[ -z "$format_cmd" ] && [ -z "$lint_cmd" ] && exit 0

if [ -n "$format_cmd" ]; then
  eval "$format_cmd \"\$f\"" >/dev/null 2>&1 || true
fi

if [ -n "$lint_cmd" ]; then
  if ! out=$(eval "$lint_cmd \"\$f\"" 2>&1); then
    printf 'Edit-time check failed for %s:\n%s\n' "$f" "$out" >&2
    exit 2
  fi
fi
exit 0
