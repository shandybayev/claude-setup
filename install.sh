#!/usr/bin/env bash
# Installs this repo into ~/.claude (or --target) as LIVE links, so a later
# `git pull` here updates every device that ran this. See docs/INSTALL.md.
#
# Usage: install.sh [--target DIR] [--dry-run] [--update]
#
# --update refreshes any path that had to fall back to a plain copy (a real
# link could not be made there), so it picks up the latest content from the
# repo. It is a no-op for anything that is a real link already.
#
# What this does:
#   - links claude-setup itself at <target>/claude-setup, so anything
#     installed can always find templates/, lessons/, harness/, docs/ by an
#     absolute, stable path, even from a different project directory;
#   - links CLAUDE.md and settings.json (files: a real link when the
#     platform allows it, verified; a copy with a WARNING when it does not);
#   - links agents/, commands/, hooks/, and statusline/ as whole directories;
#   - links EACH skill under skills/ individually, so any other skill the
#     target already has stays exactly where it is;
#   - backs up anything it is about to REPLACE into
#     <target>/backups/claude-setup-<UTC timestamp>/, but only the first time
#     a path is taken over: once a path is ours, a later run never backs up
#     our own prior link or copy a second time (that previously stranded the
#     user's real original behind a newer, empty-looking backup);
#   - NEVER touches .credentials.json, history.jsonl, projects/, sessions/,
#     or any cache directory. Those names never appear in the list above, so
#     there is nothing here that could reach them;
#   - never runs git, never commits, never pushes.
#
# A link is only ever trusted as "ours" when it actually resolves to the
# matching path INSIDE this repo (see same_content below), never merely
# because something link-shaped already sits at the destination. A link a
# user made to something else of their own is backed up (as the link entity
# itself, which does not touch what it pointed at) and replaced, same as any
# other pre-existing content.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.claude"
DRY_RUN=0
UPDATE=0

while [ $# -gt 0 ]; do
  case "$1" in
  --target) TARGET="$2"; shift 2 ;;
  --dry-run) DRY_RUN=1; shift ;;
  --update) UPDATE=1; shift ;;
  *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_ROOT="$TARGET/backups/claude-setup-$STAMP"
BACKED_UP=0

say() { printf '%s\n' "$*"; }

# IS_WINDOWS: MSYS/Git-Bash's own `ln -s` is not trustworthy here (see
# create_file_link/create_dir_link below), so directories prefer a native
# junction via cmd.exe's mklink on this platform.
IS_WINDOWS=0
case "$(uname -s 2>/dev/null)" in
MINGW* | MSYS* | CYGWIN*) IS_WINDOWS=1 ;;
esac

to_winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1" | sed -E 's#^/([a-zA-Z])/#\1:/#' | sed 's#/#\\#g'
  fi
}

# same_content <a> <b> -- true when both paths currently hold identical
# content (recursively, for a pair of directories). Used both for "is this
# destination already correctly installed" and, further down, to decide
# whether a manifest-recorded link still matches what it should. NOT a test
# of mechanism (link vs. copy): right after a copy is made it matches too.
# That is exactly why FILE_LINK_OK/DIR_LINK_OK below exist as a separate,
# one-time, dynamic check -- `stat`'s device/inode pair was tried first and
# rejected: on this platform a directory junction that demonstrably shows
# live content through (confirmed by hand) still reports a DIFFERENT inode
# than its target under Git Bash's own `stat`, so inode comparison would
# reject a link that is actually working.
same_content() {
  if [ -d "$1" ] && [ -d "$2" ]; then
    diff -rq "$1" "$2" >/dev/null 2>&1
  elif [ -f "$1" ] && [ -f "$2" ]; then
    cmp -s "$1" "$2"
  else
    return 1
  fi
}

# FILE_LINK_OK / DIR_LINK_OK: determined ONCE per run, dynamically, on a
# throwaway pair this script owns -- never on real content. A static check
# (exit code, `test -L`, an inode compare) cannot tell a real link from a
# copy taken at that same instant, since both look identical immediately
# after creation; only mutating the source AFTER linking and checking
# whether the destination sees it proves which one actually happened. This
# is what caught `ln -s` on some Windows + Git Bash setups silently writing
# a full copy (exit 0, no error) instead of linking.
PROBE_DIR=$(mktemp -d 2>/dev/null) || PROBE_DIR="${TMPDIR:-/tmp}/claude-setup-probe-$$"
mkdir -p "$PROBE_DIR" 2>/dev/null

probe_file_link() {
  local src="$PROBE_DIR/f_src" dst="$PROBE_DIR/f_dst" got
  rm -f "$src" "$dst"
  printf 'before\n' >"$src"
  ln -s "$src" "$dst" 2>/dev/null
  printf 'after\n' >"$src"
  got=$(cat "$dst" 2>/dev/null)
  rm -f "$src" "$dst"
  [ "$got" = "after" ]
}

probe_dir_link() {
  local src="$PROBE_DIR/d_src" dst="$PROBE_DIR/d_dst" ok=1
  rm -rf "$src" "$dst"
  mkdir -p "$src"
  if [ "$IS_WINDOWS" -eq 1 ]; then
    cmd //c mklink //J "$(to_winpath "$dst")" "$(to_winpath "$src")" >/dev/null 2>&1
  else
    ln -s "$src" "$dst" 2>/dev/null
  fi
  : >"$src/marker"
  [ -e "$dst/marker" ] && ok=0
  rm -rf "$src" "$dst"
  return "$ok"
}

FILE_LINK_OK=0
probe_file_link && FILE_LINK_OK=1
DIR_LINK_OK=0
probe_dir_link && DIR_LINK_OK=1
rmdir "$PROBE_DIR" 2>/dev/null || true

ensure_backup_dir() {
  if [ "$BACKED_UP" -eq 0 ]; then
    [ "$DRY_RUN" -eq 0 ] && mkdir -p "$BACKUP_ROOT"
    BACKED_UP=1
  fi
}

# backup_existing <path> <rel> -- moves existing content out of the way and
# prints the backup stamp (just "claude-setup-<UTC>", not the full path) on
# stdout, or prints nothing if there was nothing to back up. The caller
# records that stamp in the manifest so a LATER run (including --update)
# knows this path's original is already safe, and never backs it up again.
backup_existing() {
  local path="$1" rel="$2" dest
  { [ -e "$path" ] || [ -L "$path" ]; } || return 0
  ensure_backup_dir
  dest="$BACKUP_ROOT/$rel"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) back up $rel" >&2
    printf '%s' "claude-setup-$STAMP"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  say "  backed up $rel -> $dest" >&2
  printf '%s' "claude-setup-$STAMP"
}

# MANIFEST: one TAB-separated line per managed path, "rel<TAB>kind<TAB>
# backup_ref<TAB>checksum". kind is link or copy. backup_ref is the backup
# folder name (just the stamp) that holds this path's pre-claude-setup
# original, or empty if there was nothing there the first time we took this
# path over. checksum is the sha256 of a copy-kind file's content as WE
# wrote it (empty for a link, and for a copy-kind directory, where
# per-file checksumming was judged not worth the complexity for what should
# be a rare fallback on any modern filesystem); uninstall uses it to refuse
# to delete a copy a user has since edited.
#
# This same format is written by install.ps1 too, so the two shells agree on
# one manifest no matter which one a user runs on a given machine.
MANIFEST="$TARGET/.claude-setup-installed"

manifest_line() {
  [ -f "$MANIFEST" ] || return 0
  grep -E "^$1	" "$MANIFEST" 2>/dev/null | tail -1
}
manifest_field() { manifest_line "$1" | cut -f"$2"; }

manifest_set() {
  local rel="$1" kind="$2" backup_ref="$3" checksum="${4:-}" tmp
  [ "$DRY_RUN" -eq 1 ] && return 0
  mkdir -p "$(dirname "$MANIFEST")"
  tmp="$MANIFEST.tmp.$$"
  { [ -f "$MANIFEST" ] && grep -vE "^$rel	" "$MANIFEST" 2>/dev/null; true; } >"$tmp"
  printf '%s\t%s\t%s\t%s\n' "$rel" "$kind" "$backup_ref" "$checksum" >>"$tmp"
  mv "$tmp" "$MANIFEST"
}

manifest_remove() {
  local rel="$1" tmp
  [ "$DRY_RUN" -eq 1 ] && return 0
  [ -f "$MANIFEST" ] || return 0
  tmp="$MANIFEST.tmp.$$"
  grep -vE "^$rel	" "$MANIFEST" >"$tmp" 2>/dev/null || true
  mv "$tmp" "$MANIFEST"
}

sha256_of() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# create_dir_link <dest> <source> -- only attempted when DIR_LINK_OK proved
# the mechanism actually works on this run; otherwise fails immediately so
# the caller goes straight to an honest copy instead of repeating a method
# already shown not to work.
create_dir_link() {
  local dest="$1" source="$2"
  [ "$DIR_LINK_OK" -eq 1 ] || return 1
  if [ "$IS_WINDOWS" -eq 1 ]; then
    cmd //c mklink //J "$(to_winpath "$dest")" "$(to_winpath "$source")" >/dev/null 2>&1
  else
    ln -s "$source" "$dest" 2>/dev/null
  fi
}

# create_file_link <dest> <source> -- see create_dir_link.
create_file_link() {
  local dest="$1" source="$2"
  [ "$FILE_LINK_OK" -eq 1 ] || return 1
  ln -s "$source" "$dest" 2>/dev/null
}

# link_dir <rel> <source> -- see the file header for the backup/manifest
# contract this and link_file share.
link_dir() {
  local rel="$1" source="$2" backup_ref kind dest
  dest="$TARGET/$rel"
  kind=$(manifest_field "$rel" 2)

  if [ -e "$dest" ] && same_content "$dest" "$source"; then
    if [ "$kind" = "copy" ]; then
      say "  $rel is already installed as a copy and matches the repo, skipping."
    else
      say "  $rel already links to the repo, skipping."
    fi
    return 0
  fi

  backup_ref=$(manifest_field "$rel" 3)
  if [ -z "$backup_ref" ]; then
    backup_ref=$(backup_existing "$dest" "$rel")
  elif { [ -e "$dest" ] || [ -L "$dest" ]; }; then
    # We already own this path (its backup_ref is on file from the first
    # takeover). What is here now is either our own stale link/copy (safe
    # to just discard, we can always re-link or re-copy it) or something
    # that REPLACED our link with real content since -- a user's own
    # directory, or a tool that saves over a symlink by write-then-rename.
    # That content is not necessarily disposable, so it goes into THIS
    # run's backup folder rather than being deleted outright; the
    # manifest's backup_ref keeps pointing at the ORIGINAL pre-claude-setup
    # content either way, since that is what uninstall should restore, not
    # whatever briefly sat here in between.
    backup_existing "$dest" "$rel" >/dev/null
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) link $rel -> $source"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest" 2>/dev/null
  if create_dir_link "$dest" "$source"; then
    manifest_set "$rel" link "$backup_ref" ""
    if [ "$IS_WINDOWS" -eq 1 ]; then
      say "  linked $rel -> $source (junction)"
    else
      say "  linked $rel -> $source (symlink)"
    fi
  else
    rm -rf "$dest" 2>/dev/null
    cp -r "$source" "$dest"
    manifest_set "$rel" copy "$backup_ref" ""
    say "  WARNING: could not create a real link for $rel (junction/symlink creation failed, or silently produced a copy). Copied instead; re-run with --update after a git pull to refresh it."
  fi
}

# link_file <rel> <source> -- see link_dir and the file header.
link_file() {
  local rel="$1" source="$2" backup_ref kind cur_sum dest
  dest="$TARGET/$rel"
  kind=$(manifest_field "$rel" 2)
  backup_ref=$(manifest_field "$rel" 3)

  if [ "$kind" = "link" ] && [ -e "$dest" ] && same_content "$dest" "$source"; then
    say "  $rel already links to the repo, skipping."
    return 0
  fi

  if [ "$kind" = "copy" ] && [ -e "$dest" ]; then
    cur_sum=$(sha256_of "$dest")
    if [ "$cur_sum" != "$(manifest_field "$rel" 4)" ]; then
      say "  $rel was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
      return 0
    fi
    if [ "$UPDATE" -eq 0 ]; then
      say "  $rel is already installed as a copy, leaving it. Use --update to refresh it."
      return 0
    fi
    # --update on our own, unmodified copy: refresh in place. This is not a
    # new takeover, so it must NOT create a new backup -- the real original
    # is already preserved under backup_ref from the first time this path
    # was taken over, and a second backup here is what used to leave that
    # original stranded behind a newer "backup" that only ever held our
    # own stale copy.
    if [ "$DRY_RUN" -eq 1 ]; then
      say "  (dry run) refresh copy of $rel"
      return 0
    fi
    cp "$source" "$dest"
    manifest_set "$rel" copy "$backup_ref" "$(sha256_of "$dest")"
    say "  refreshed copy of $rel (--update)"
    return 0
  fi

  if [ -z "$backup_ref" ]; then
    backup_ref=$(backup_existing "$dest" "$rel")
  elif { [ -e "$dest" ] || [ -L "$dest" ]; }; then
    # See link_dir's matching comment: this path is already ours, but what
    # is here now does not match the repo (kind=link with mismatched
    # content, since the kind=copy case above already returned). Preserve
    # it in this run's backup rather than deleting it; backup_ref keeps
    # pointing at the real pre-claude-setup original.
    backup_existing "$dest" "$rel" >/dev/null
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) link $rel -> $source"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  rm -f "$dest" 2>/dev/null
  if create_file_link "$dest" "$source"; then
    manifest_set "$rel" link "$backup_ref" ""
    say "  linked $rel -> $source (symlink)"
  else
    rm -f "$dest" 2>/dev/null
    cp "$source" "$dest"
    manifest_set "$rel" copy "$backup_ref" "$(sha256_of "$dest")"
    say "  WARNING: could not create a real link for $rel (symlink creation failed, or silently produced a copy). Copied instead; re-run with --update after a git pull to refresh it."
  fi
}

install_settings() {
  local rel="settings.json" dest="$TARGET/settings.json" source="$HERE/global/settings.json"
  if [ -e "$dest" ] && ! same_content "$dest" "$source" && [ -z "$(manifest_field "$rel" 2)" ]; then
    if command -v python3 >/dev/null 2>&1; then
      python3 - "$dest" "$source" <<'PYEOF'
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        existing = json.load(fh)
    with open(sys.argv[2], "r", encoding="utf-8") as fh:
        incoming = json.load(fh)
    ek, ik = set(existing), set(incoming)
    added = sorted(ik - ek)
    removed = sorted(ek - ik)
    changed = sorted(k for k in (ik & ek) if existing[k] != incoming[k])
    print(f"  settings.json keys -- added: {added}  removed: {removed}  changed: {changed}")
except Exception as exc:
    print(f"  settings.json: could not diff keys ({exc}); backing it up as usual.")
PYEOF
    fi
  fi
  link_file "$rel" "$source"
}

say "Installing claude-setup into: $TARGET"
[ "$DRY_RUN" -eq 0 ] && mkdir -p "$TARGET"

# The repo itself, at a stable absolute path: everything else this repo
# ships (templates/, lessons/, harness/, docs/) is only reachable through
# this one link, since skills and commands cannot know ahead of time where
# a given machine cloned claude-setup to.
link_dir "claude-setup" "$HERE"

link_file "CLAUDE.md" "$HERE/global/CLAUDE.md"
install_settings
link_dir "agents" "$HERE/agents"
link_dir "commands" "$HERE/commands"
link_dir "hooks" "$HERE/hooks"
link_dir "statusline" "$HERE/global/statusline"

[ "$DRY_RUN" -eq 0 ] && mkdir -p "$TARGET/skills"
for dir in "$HERE"/skills/*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  link_dir "skills/$name" "${dir%/}"
done

say ""
if [ "$BACKED_UP" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "(dry run) backups would be written to: $BACKUP_ROOT"
  else
    say "Backups written to: $BACKUP_ROOT"
  fi
fi
say "Repo reachable at: $TARGET/claude-setup"
say "Never touched: .credentials.json, history.jsonl, projects/, sessions/, caches."
say "Nothing was committed; this script never runs git."
say "Done."
