#!/usr/bin/env bash
# Removes the links/copies install.sh created and restores each one's own
# pre-claude-setup original, if it had one.
#
# Usage: uninstall.sh [--target DIR] [--dry-run]
#
# Driven ENTIRELY by the manifest (.claude-setup-installed) install.sh
# writes. No fixed name list, and nothing it did not itself record is ever
# touched: a second uninstall run, or one on a target where install never
# ran, used to fall back to "anything at one of our well-known names that
# is not currently a link must be a copy of ours" and delete real user
# files that way. If there is no manifest, there is nothing recorded as
# installed here, so nothing is removed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.claude"
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
  --target) TARGET="$2"; shift 2 ;;
  --dry-run) DRY_RUN=1; shift ;;
  *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }

# Matches install.sh's same_content exactly (see its comment there): an
# inode/device compare was tried first and rejected, because on this
# platform a directory junction that demonstrably shows live content
# through still reports a DIFFERENT inode than its target under Git Bash's
# own `stat`. Content comparison is what install.sh's dynamic capability
# probe actually proves links by, so uninstall checks the same way.
same_content() {
  if [ -d "$1" ] && [ -d "$2" ]; then
    diff -rq "$1" "$2" >/dev/null 2>&1
  elif [ -f "$1" ] && [ -f "$2" ]; then
    cmp -s "$1" "$2"
  else
    return 1
  fi
}

sha256_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# rel_source <rel> -- the repo path a managed rel ought to point at, used as
# a second, independent check (beyond the manifest's say-so) that a "link"
# entry still really resolves into THIS repo before it gets deleted.
rel_source() {
  case "$1" in
  claude-setup) printf '%s' "$HERE" ;;
  CLAUDE.md) printf '%s' "$HERE/global/CLAUDE.md" ;;
  settings.json) printf '%s' "$HERE/global/settings.json" ;;
  agents) printf '%s' "$HERE/agents" ;;
  commands) printf '%s' "$HERE/commands" ;;
  hooks) printf '%s' "$HERE/hooks" ;;
  statusline) printf '%s' "$HERE/global/statusline" ;;
  skills/*) printf '%s' "$HERE/$1" ;;
  *) printf '' ;;
  esac
}

MANIFEST="$TARGET/.claude-setup-installed"
if [ ! -f "$MANIFEST" ]; then
  say "No install manifest at $MANIFEST. Nothing was recorded as installed by claude-setup here, so nothing will be removed."
  exit 0
fi

BACKUPS_DIR="$TARGET/backups"

while IFS=$'\t' read -r rel kind backup_ref checksum; do
  [ -z "$rel" ] && continue
  path="$TARGET/$rel"
  source=$(rel_source "$rel")

  case "$kind" in
  link)
    if [ ! -e "$path" ]; then
      say "  $rel is already gone."
    elif [ -n "$source" ] && ! same_content "$path" "$source"; then
      say "  $rel no longer points into this repo (something replaced it since install); leaving it alone. Remove it by hand if you want it gone."
      continue
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        say "  (dry run) remove $rel (link)"
      else
        rm -rf "$path"
        say "  removed $rel (link)"
      fi
    fi
    ;;
  copy)
    if [ ! -e "$path" ]; then
      say "  $rel is already gone."
    else
      cur_sum=$(sha256_of "$path")
      if [ -n "$checksum" ] && [ "$cur_sum" != "$checksum" ]; then
        say "  $rel was edited since claude-setup wrote it; leaving it alone so your changes are not lost."
        continue
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        say "  (dry run) remove $rel (copy)"
      else
        rm -rf "$path"
        say "  removed $rel (copy)"
      fi
    fi
    ;;
  *)
    say "  $rel: unrecognized manifest kind '$kind', leaving it alone."
    continue
    ;;
  esac

  if [ -n "$backup_ref" ] && [ -e "$BACKUPS_DIR/$backup_ref/$rel" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      say "  (dry run) restore $rel from $backup_ref"
    else
      mkdir -p "$(dirname "$path")"
      mv "$BACKUPS_DIR/$backup_ref/$rel" "$path"
      say "  restored $rel from $backup_ref"
    fi
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    tmp="$MANIFEST.tmp.$$"
    grep -vE "^$rel	" "$MANIFEST" >"$tmp" 2>/dev/null || true
    mv "$tmp" "$MANIFEST"
  fi
done <"$MANIFEST"

[ "$DRY_RUN" -eq 0 ] && [ -f "$MANIFEST" ] && [ ! -s "$MANIFEST" ] && rm -f "$MANIFEST"

say ""
say "Nothing outside what the manifest listed was touched. Nothing was committed."
say "Done."
