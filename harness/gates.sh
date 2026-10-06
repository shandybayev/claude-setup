#!/usr/bin/env bash
# The harness gate runner. Pre-commit, pre-push, and CI all call this one
# script, so the three can never check different things. See
# harness/README.md for the full contract.
#
# Usage:
#   harness/gates.sh commit                 staged diff only, fast checks
#   harness/gates.sh push                    base..HEAD, fast checks + project
#                                             format/lint/typecheck/test/ratchet
#   harness/gates.sh all                     working tree vs HEAD, same as push
#   harness/gates.sh commit-msg <msg-file>   commit message shape only
#
# Exit 0 pass. Exit 1 a gate blocked. Config comes from harness.config next to
# this script (or HARNESS_CONFIG if set); every key has a safe default when
# the file or the key is missing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/scope.sh
. "$HERE/lib/scope.sh"

CONFIG="${HARNESS_CONFIG:-$HERE/harness.config}"
[ -f "$CONFIG" ] || CONFIG="$HERE/harness.config.example"

# config_get <key> <default> -- read one key=value line, ignoring comments
# and blank lines. Last match wins, matching normal key=value file semantics.
# A key present but set to nothing (KEY=) returns "", not the default: an
# explicit blank means "skip this check", which is different from "unset".
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

LOC_WARN=$(config_get LOC_WARN 500)
LOC_BLOCK=$(config_get LOC_BLOCK 700)
COMMIT_MSG_MAX=$(config_get COMMIT_MSG_MAX 100)
COMMIT_MSG_WARN=$(config_get COMMIT_MSG_WARN 72)
RATCHET_CMD=$(config_get RATCHET_CMD "")
RATCHET_FILE=$(config_get RATCHET_FILE "$HERE/ratchet-baseline.json")

mode="${1:-}"
blocked=0

# A file matching one of these globs (basename or full relative path) is
# never line-counted: a lockfile's size tracks the dependency tree, not code
# someone wrote, so growth there is not a review signal. A project adds more
# with LOC_EXCLUDE (comma-separated globs) in harness.config; these defaults
# are not replaced, only added to.
LOC_EXCLUDE_DEFAULTS="package-lock.json yarn.lock pnpm-lock.yaml poetry.lock Pipfile.lock Cargo.lock Gemfile.lock composer.lock go.sum *.min.js *.min.css"

loc_excluded() {
  local f="$1" base pat extra was_f matched=1
  base=$(basename -- "$f")
  extra=$(config_get LOC_EXCLUDE "")
  extra="${extra//,/ }"
  # set -f (noglob) around the word-split: $LOC_EXCLUDE_DEFAULTS and
  # $extra are unquoted here on purpose, to split on spaces into separate
  # patterns, but unquoted ALSO means bash pathname-expands each one
  # against files in the CURRENT DIRECTORY before the loop ever sees it --
  # "*.min.js" silently became the one real matching filename there (or
  # vanished if none matched), so every OTHER file stopped matching it.
  # noglob stops that expansion while leaving the later `case ... in $pat)`
  # globbing untouched: case pattern matching is not pathname expansion
  # and ignores -f either way.
  case $- in *f*) was_f=1 ;; *) was_f=0 ;; esac
  set -f
  for pat in $LOC_EXCLUDE_DEFAULTS $extra; do
    [ -z "$pat" ] && continue
    case "$base" in $pat) matched=0; break ;; esac
    case "$f" in $pat) matched=0; break ;; esac
  done
  [ "$was_f" -eq 0 ] && set +f
  return "$matched"
}

# --- gate: file size --------------------------------------------------------
gate_loc() {
  local scope_mode="$1" files f loc base
  files=$(scope_files "$scope_mode")
  [ -z "$files" ] && { echo "  loc: nothing in scope."; return 0; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if loc_excluded "$f"; then
      continue
    fi
    if scope_is_binary "$scope_mode" "$f"; then
      continue
    fi
    loc=$(scope_cat "$scope_mode" "$f" | wc -l | tr -d ' ')
    [ -z "$loc" ] && continue
    if [ "$loc" -gt "$LOC_BLOCK" ]; then
      base=$(scope_baseline_lines "$scope_mode" "$f")
      if [ -n "$base" ] && [ "$base" -ge "$loc" ]; then
        printf '  over-cap: %s is %s lines (was %s, not growing).\n' "$f" "$loc" "$base"
      else
        printf '  BLOCK: %s is %s lines (limit %s).\n' "$f" "$loc" "$LOC_BLOCK"
        blocked=1
      fi
    elif [ "$loc" -gt "$LOC_WARN" ]; then
      printf '  warn: %s is %s lines (over %s).\n' "$f" "$loc" "$LOC_WARN"
    fi
  done <<EOF
$files
EOF
}

# --- gate: debug leftovers --------------------------------------------------
# Empty means "no default for this extension": a file this gate does not
# recognize as code (a .md, .yml, .json, harness.config itself) is skipped
# entirely rather than scanned with the generic JS-ish pattern, which used to
# flag the word "debugger" inside this very file's own comments. A project
# can still opt an extension in with DEBUG_PATTERN_<ext> in harness.config.
default_debug_pattern() {
  case "$1" in
  py) printf '%s' '(^|[[:space:];])(breakpoint\(\)|import pdb\b)' ;;
  js | jsx | ts | tsx | mjs | cjs) printf '%s' '(^|[[:space:];{])(debugger|console\.log)\b' ;;
  *) printf '' ;;
  esac
}

gate_debug() {
  local scope_mode="$1" files f ext pattern hits
  files=$(scope_files "$scope_mode")
  [ -z "$files" ] && return 0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    ext="${f##*.}"
    pattern=$(config_get "DEBUG_PATTERN_$ext" "$(default_debug_pattern "$ext")")
    [ -z "$pattern" ] && continue
    hits=$(scope_cat "$scope_mode" "$f" | grep -nE -e "$pattern" -- 2>/dev/null || true)
    if [ -n "$hits" ]; then
      printf '%s\n' "$hits" | sed "s|^|  BLOCK $f:|"
      blocked=1
    fi
  done <<EOF
$files
EOF
}

# --- gate: project commands (push/all only) ---------------------------------
run_project_cmd() {
  local label="$1" cmd="$2"
  if [ -z "$cmd" ]; then
    echo "  $label: not configured, skipping."
    return 0
  fi
  echo "  $label: $cmd"
  if ! (eval "$cmd"); then
    echo "  BLOCK: $label failed."
    blocked=1
  fi
}

# --- gate: ratchet (push/all only) ------------------------------------------
gate_ratchet() {
  local current baseline
  [ -z "$RATCHET_CMD" ] && { echo "  ratchet: not configured, skipping."; return 0; }
  # The FIRST number in the output, not every digit in it run together:
  # `tr -dc 0-9` used to turn "5 problems (3 errors, 2 warnings)" into 532.
  current=$(eval "$RATCHET_CMD" 2>/dev/null | grep -oE '[0-9]+' | head -1)
  if [ -z "$current" ]; then
    echo "  ratchet: RATCHET_CMD produced no number, skipping."
    return 0
  fi
  if [ ! -f "$RATCHET_FILE" ]; then
    # No baseline yet: a project adopting the ratchet should not have its
    # very first run blocked by an assumed baseline of 0. Seed it with the
    # current count and pass; only a later RISE blocks.
    printf '  ratchet: %s (seeding the baseline, no file yet).\n' "$current"
    mkdir -p "$(dirname "$RATCHET_FILE")"
    printf '{"count": %s}\n' "$current" >"$RATCHET_FILE"
    return 0
  fi
  baseline=$(grep -oE '[0-9]+' "$RATCHET_FILE" | head -1)
  baseline=${baseline:-0}
  if [ "$current" -gt "$baseline" ]; then
    printf '  BLOCK: ratchet count rose %s -> %s.\n' "$baseline" "$current"
    blocked=1
  else
    printf '  ratchet: %s (baseline %s).\n' "$current" "$baseline"
    if [ "$current" -lt "$baseline" ]; then
      printf '{"count": %s}\n' "$current" >"$RATCHET_FILE"
    fi
  fi
}

# --- gate: commit message ---------------------------------------------------
gate_commit_msg() {
  local msg_file="$1" subject len
  [ -f "$msg_file" ] || { echo "  BLOCK: commit message file not found."; blocked=1; return 0; }
  # Strip a trailing \r (a CRLF-saved file) and a leading UTF-8 BOM (some
  # Windows editors and PowerShell's default "utf8" encoding write one): both
  # are invisible in most viewers but would desync every offset below,
  # starting with the ^type(scope): match.
  subject=$(head -1 "$msg_file" | tr -d '\r')
  subject="${subject#$'\xef\xbb\xbf'}"
  case "$subject" in
  "Merge "* | 'Revert "'* | "fixup!"* | "squash!"* | "amend!"*) return 0 ;;
  esac
  if [ -z "$subject" ]; then
    echo "  BLOCK: commit message is empty."
    blocked=1
    return 0
  fi
  if [[ ! "$subject" =~ ^[a-z]+\([a-z0-9./-]+\)!?:[[:space:]].+ ]]; then
    echo "  BLOCK: subject must read \"type(scope): subject\", e.g. feat(api): add retry."
    blocked=1
  fi
  len=${#subject}
  if [ "$len" -gt "$COMMIT_MSG_MAX" ]; then
    printf '  BLOCK: subject is %s chars, over the %s limit.\n' "$len" "$COMMIT_MSG_MAX"
    blocked=1
  elif [ "$len" -gt "$COMMIT_MSG_WARN" ]; then
    printf '  warn: subject is %s chars (over %s).\n' "$len" "$COMMIT_MSG_WARN"
  fi
  # Scan only the real message: everything above git's scissors line
  # ("# ---...--- >8 ---...---", written by `commit -v`), below which is an
  # unmarked diff dump, not message content. Scanning the whole file let a
  # dash in the diff below that line block a commit whose actual message
  # had none.
  body=$(awk '/^#.*>8/ { exit } { print }' "$msg_file")
  # Em dash / en dash / horizontal bar as raw UTF-8 bytes (E2 80 94/93/95),
  # matched with -F so this works on both GNU and BSD grep without a -P
  # (PCRE) dependency neither platform is guaranteed to have.
  if printf '%s\n' "$body" | grep -qF $'\xe2\x80\x94' 2>/dev/null \
    || printf '%s\n' "$body" | grep -qF $'\xe2\x80\x93' 2>/dev/null \
    || printf '%s\n' "$body" | grep -qF $'\xe2\x80\x95' 2>/dev/null; then
    echo "  BLOCK: em dash, en dash, or horizontal bar in the commit message."
    blocked=1
  fi
}

case "$mode" in
commit)
  echo "harness: commit-scope gates"
  gate_loc commit
  gate_debug commit
  ;;
push | all)
  scope_mode="$mode"
  echo "harness: $mode-scope gates"
  gate_loc "$scope_mode"
  gate_debug "$scope_mode"
  run_project_cmd format "$(config_get FORMAT_CMD "")"
  run_project_cmd lint "$(config_get LINT_CMD "")"
  run_project_cmd typecheck "$(config_get TYPECHECK_CMD "")"
  run_project_cmd test "$(config_get TEST_CMD "")"
  gate_ratchet
  ;;
commit-msg)
  echo "harness: commit message gate"
  gate_commit_msg "${2:?usage: gates.sh commit-msg <file>}"
  ;;
*)
  echo "usage: gates.sh <commit|push|all|commit-msg> [commit-msg-file]" >&2
  exit 1
  ;;
esac

if [ "$blocked" -eq 1 ]; then
  echo "x harness: one or more gates blocked. Fix them, or use --no-verify with a reason."
  exit 1
fi
echo "harness: all gates passed."
exit 0
