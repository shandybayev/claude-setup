#!/usr/bin/env bash
# Shared diff-scope helpers for the harness gates. SOURCE this file, never run
# it directly:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/scope.sh"
#
# WHY A DIFF AND NOT THE WHOLE TREE
# A file nobody touched never blocks anything, so there is no allowlist to
# keep up to date, and an existing backlog burns down on its own as files get
# worked on. It also keeps the hooks fast: one git process per scope, not one
# per file.
#
# THE THREE MODES
#   commit  what is staged right now (the git index). The pre-commit scope.
#   push    what the push would send: the base commit to HEAD. The pre-push
#           and CI scope. The base is GATE_BASE_REF if set, else the branch
#           upstream, else origin/main or origin/master, else the root
#           commit.
#   all     the working tree against HEAD: tracked edits plus brand-new
#           untracked files. What a developer runs by hand for a full local
#           check.
set -uo pipefail

SCOPE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$SCOPE_ROOT" ]; then
  cd "$SCOPE_ROOT" || true
fi

# scope_base -- the base commit for "push" mode, as a resolved sha. Takes the
# merge base with the chosen ref, not the ref itself, so a branch only answers
# for the commits it actually adds, never for everything the remote has moved
# past.
scope_base() {
  local ref base merged
  if [ -n "${GATE_BASE_REF:-}" ]; then
    base=$(git rev-parse --verify --quiet "${GATE_BASE_REF}^{commit}" 2>/dev/null || true)
    if [ -n "$base" ]; then
      printf '%s\n' "$base"
      return 0
    fi
    # GATE_BASE_REF was set but did not resolve (a typo, a ref the checkout
    # does not have, or CI's all-zero "first push of a branch" value). Say
    # so instead of silently falling through to a different base: that
    # fallback can judge the wrong diff (or an empty one) without anyone
    # noticing the override never took effect.
    echo "harness: GATE_BASE_REF='$GATE_BASE_REF' did not resolve to a commit; falling back to the branch upstream." >&2
  fi
  for ref in '@{u}' 'origin/main' 'origin/master'; do
    base=$(git rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null || true)
    [ -z "$base" ] && continue
    merged=$(git merge-base "$base" HEAD 2>/dev/null || true)
    printf '%s\n' "${merged:-$base}"
    return 0
  done
  git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1
}

# scope_files <mode> -- the changed paths in scope, one per line. Renames
# resolve to their new path (--no-renames); deletions are excluded, since a
# gate cannot read a file that is gone.
scope_files() {
  local mode="$1" base
  case "$mode" in
  commit)
    git diff --cached --name-only --no-renames --diff-filter=ACM -z 2>/dev/null | tr '\0' '\n'
    ;;
  all)
    {
      git diff --name-only --no-renames --diff-filter=ACM -z HEAD 2>/dev/null | tr '\0' '\n'
      git ls-files --others --exclude-standard -z 2>/dev/null | tr '\0' '\n'
    } | sort -u
    ;;
  push)
    base=$(scope_base)
    [ -z "$base" ] && return 0
    git diff --name-only --no-renames --diff-filter=ACM -z "$base..HEAD" 2>/dev/null | tr '\0' '\n'
    ;;
  esac
}

# scope_cat <mode> <path> -- the content a gate should judge. "commit" and
# "push" read the git object (what is actually being committed or pushed),
# never the dirty working copy; "all" reads the file on disk.
scope_cat() {
  local mode="$1" path="$2" base
  case "$mode" in
  commit) git show ":$path" 2>/dev/null ;;
  all) cat -- "$path" 2>/dev/null ;;
  push)
    git show "HEAD:$path" 2>/dev/null
    ;;
  esac
}

# scope_baseline_lines <mode> <path> -- the line count of <path> in the base
# revision, or empty if it did not exist there (a brand-new file). Lets a gate
# tell "already too big" from "just got bigger".
scope_baseline_lines() {
  local mode="$1" path="$2" base
  case "$mode" in
  commit) base=HEAD ;;
  push) base=$(scope_base) ;;
  all) base=HEAD ;;
  esac
  [ -z "${base:-}" ] && return 0
  git show "${base}:${path}" 2>/dev/null | wc -l | tr -d ' '
}

# scope_is_binary <mode> <path> -- true when git itself considers this file
# binary in the given scope. Lets a gate skip binaries without reimplementing
# byte-sniffing: git already decides this (a NUL byte, or .gitattributes) and
# reports it as "-" added/removed lines in --numstat, instead of a number.
scope_is_binary() {
  local mode="$1" path="$2" base out
  case "$mode" in
  commit)
    out=$(git diff --cached --numstat -- "$path" 2>/dev/null)
    ;;
  push)
    base=$(scope_base)
    [ -z "$base" ] && return 1
    out=$(git diff --numstat "$base..HEAD" -- "$path" 2>/dev/null)
    ;;
  all)
    if git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      out=$(git diff --numstat HEAD -- "$path" 2>/dev/null)
    else
      out=$(git diff --no-index --numstat -- /dev/null "$path" 2>/dev/null)
    fi
    ;;
  esac
  case "$out" in
  "-"$'\t'"-"$'\t'*) return 0 ;;
  esac
  return 1
}

# scope_grep <mode> <ere> -- "path:line:match" for every file in scope that
# matches, read from whichever revision/working-tree scope_cat would use.
scope_grep() {
  local mode="$1" re="$2" f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    scope_cat "$mode" "$f" | grep -nE -e "$re" -- 2>/dev/null | while IFS=: read -r line rest; do
      printf '%s:%s:%s\n' "$f" "$line" "$rest"
    done
  done < <(scope_files "$mode")
}
