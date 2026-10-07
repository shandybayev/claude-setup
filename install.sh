#!/usr/bin/env bash
# Installs this repo into ~/.claude (or --target) as LIVE links, so a later
# `git pull` here updates every device that ran this. See docs/INSTALL.md.
#
# Usage: install.sh [--target DIR] [--dry-run] [--update] [--profile NAME] [--yes]
#
# --update refreshes any path that had to fall back to a plain copy (a real
# link could not be made there), so it picks up the latest content from the
# repo. It is a no-op for anything that is a real link already. It does NOT
# affect which profile is used (see --profile below) -- it only controls
# whether a fallback COPY gets refreshed.
#
# --profile <max|standard|lite> picks which profiles/*.json sets the model
# and effort rendered into the agent roles (see profiles/lib/profile.sh).
# Left out entirely: a plain re-run always keeps whatever profile is
# ALREADY recorded at <target>/claude-setup-profile.json, silently, whether
# or not --update is given -- only an explicit --profile ever switches it.
# On a FIRST-TIME install (no record yet) running with a real terminal on
# stdin, it asks which plan to use instead; --update does not change that
# either. --dry-run does NOT suppress the question, only the actual install.
#
# --yes skips that first-time question and uses "max" instead, the same
# silent default a script or CI run already gets (stdin not a terminal)
# without needing the flag at all.
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
TARGET_GIVEN=0
DRY_RUN=0
UPDATE=0
PROFILE_ARG=""
PROFILE_GIVEN=0
FORCE_YES=0

while [ $# -gt 0 ]; do
  case "$1" in
  --target) TARGET="$2"; TARGET_GIVEN=1; shift 2 ;;
  --dry-run) DRY_RUN=1; shift ;;
  --update) UPDATE=1; shift ;;
  --profile) PROFILE_ARG="$2"; PROFILE_GIVEN=1; shift 2 ;;
  --yes) FORCE_YES=1; shift ;;
  *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

say() { printf '%s\n' "$*"; }

# shellcheck source=profiles/lib/profile.sh
. "$HERE/profiles/lib/profile.sh"

PROFILES_DIR="$HERE/profiles"
RECORD_PATH="$TARGET/claude-setup-profile.json"
VALID_PROFILE_NAMES=$(profile_valid_names "$PROFILES_DIR")

if [ "$PROFILE_GIVEN" -eq 1 ]; then
  CHOSEN_PROFILE_NAME="$PROFILE_ARG"
elif [ -f "$RECORD_PATH" ]; then
  # A plain re-run (no --profile) ALWAYS keeps whatever is already
  # recorded, with or without --update: --update only controls whether a
  # fallback copy gets refreshed, never which profile is active.
  CHOSEN_PROFILE_NAME=$(profile_record_name "$RECORD_PATH")
  if [ -z "$CHOSEN_PROFILE_NAME" ]; then
    echo "Could not read a profile name from $RECORD_PATH. Pass --profile explicitly." >&2
    exit 1
  fi
elif [ "$FORCE_YES" -eq 0 ] && [ -t 0 ]; then
  # First-time install, asked for explicitly: no --profile, nothing
  # recorded yet, stdin is a real terminal, and --yes was not given to
  # force the quiet default. --dry-run does NOT suppress this: the point
  # of --dry-run is exploring what a real run would do, and a real run
  # would ask here too.
  MENU_ORDER=$(profile_menu_order "$(printf '%s' "$VALID_PROFILE_NAMES" | tr '\n' ' ')")
  # shellcheck disable=SC2086 # intentional word-splitting: one name per arg
  if ! CHOSEN_PROFILE_NAME=$(profile_prompt_choice "$PROFILES_DIR" $MENU_ORDER); then
    echo "No valid profile chosen after 3 attempts. Nothing was installed." >&2
    exit 1
  fi
else
  # No --profile, no record, and (non-interactive OR --yes): there is
  # no safe default to fall back on, so this stops here, before
  # changing anything, rather than silently installing "max" -- a
  # friend on a cheap plan running this non-interactively (an AI
  # assistant acting on their behalf, say) would otherwise end up on
  # the HEAVIEST profile instead of the lightest, the exact opposite
  # of what "no answer" should ever mean.
  REQUIRED_MESSAGE_TARGET=""
  [ "$TARGET_GIVEN" -eq 1 ] && REQUIRED_MESSAGE_TARGET="$TARGET"
  # shellcheck disable=SC2086 # intentional word-splitting: one name per arg
  profile_required_message "$PROFILES_DIR" "$FORCE_YES" "$REQUIRED_MESSAGE_TARGET" $(profile_menu_order "$(printf '%s' "$VALID_PROFILE_NAMES" | tr '\n' ' ')")
  exit 1
fi

if ! printf '%s\n' "$VALID_PROFILE_NAMES" | grep -qxF "$CHOSEN_PROFILE_NAME"; then
  echo "Unknown profile '$CHOSEN_PROFILE_NAME'. Valid profiles: $(printf '%s' "$VALID_PROFILE_NAMES" | tr '\n' ' ')" >&2
  exit 1
fi

CHOSEN_PROFILE_PATH="$PROFILES_DIR/$CHOSEN_PROFILE_NAME.json"
PROFILE_VALIDATION_ERR=$(profile_validate "$CHOSEN_PROFILE_PATH")
if [ -n "$PROFILE_VALIDATION_ERR" ]; then
  echo "Profile '$CHOSEN_PROFILE_NAME' failed validation: $PROFILE_VALIDATION_ERR" >&2
  exit 1
fi
PROFILE_BUILD_AGENTS="$HERE/.profile-build/$CHOSEN_PROFILE_NAME/agents"
GLOBAL_SETTINGS_PATH="$HERE/global/settings.json"
# An explicit --profile is the user's own stated intent: refresh every
# profile-derived file (agents, settings.json) to match, with no
# --update needed, whether or not it happens to equal what is already
# recorded.
PROFILE_SWITCH=$PROFILE_GIVEN

if [ "$CHOSEN_PROFILE_NAME" = "max" ]; then
  # max links agents/ and settings.json straight from the repo,
  # unchanged -- nothing else enforces that max.json's own values still
  # match them, so check by hand rather than silently installing from
  # the (correct) files while printing a changed "->" value from
  # max.json that was never actually applied.
  if ! profile_validate_max_consistency "$CHOSEN_PROFILE_PATH" "$HERE/agents" "$GLOBAL_SETTINGS_PATH"; then
    echo "Profile 'max' is out of sync; nothing was linked or written." >&2
    exit 1
  fi
  SETTINGS_SOURCE="$GLOBAL_SETTINGS_PATH"
else
  SETTINGS_SOURCE="$HERE/.profile-build/$CHOSEN_PROFILE_NAME/settings.json"
fi

# The 3-line summary, right after the profile is settled (by flag,
# record, prompt, or default) and validated, before anything is linked,
# rendered, or written. The main-session line moves to AFTER
# settings.json is actually installed (see the bottom of this script):
# "applied" must never be said until the file on disk has been read back
# and confirmed to carry these values.
MAIN_MODEL=$(profile_main_field "$CHOSEN_PROFILE_PATH" model)
MAIN_EFFORT=$(profile_main_field "$CHOSEN_PROFILE_PATH" effortLevel)
say ""
say "Profile: $CHOSEN_PROFILE_NAME"
say "Workflow mode: $(profile_field "$CHOSEN_PROFILE_PATH" workflowMode)"
say "Max parallel teammates: $(profile_field "$CHOSEN_PROFILE_PATH" maxParallelTeammates)"

# CLAUDE_SETUP_TEST_STAMP overrides the real clock -- test-only, used to
# force two separate runs to collide on the same stamp deterministically
# (see the collision loop below for why that case needs its own
# handling) instead of needing to win a real race against the wall
# clock.
STAMP="${CLAUDE_SETUP_TEST_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"

# The backup folder name is resolved HERE, once, in the main shell --
# NOT lazily inside a function, and not stamp alone. Several call sites
# capture backup_existing's return value with $(...), which forks a
# SUBSHELL: any assignment made there to BACKUP_ROOT/BACKUP_DIR_NAME
# would vanish the moment that subshell exits, so computing the name
# lazily inside that function meant EVERY such call recomputed a fresh
# name, found the previous call's own folder (created moments earlier,
# in the same run) already on disk, and kept bumping the -2/-3 suffix
# for no reason -- three backups in one run landing in three different
# folders instead of one. Stamp alone is not enough either: two
# SEPARATE runs (two installs back to back, or a profile switch right
# after an install) can land in the same second, and sharing one folder
# meant the second run's mv either nested a junction INSIDE the first
# run's backed-up original, or silently overwrote it outright,
# permanently losing the user's own file. Stamp + PID resolves that in
# practice; the -2, -3... loop is the fallback for the one case PID
# alone cannot rule out (PID reuse hitting the exact same stamp).
BACKUP_DIR_NAME="claude-setup-$STAMP-$$"
_backup_n=2
while [ -e "$TARGET/backups/$BACKUP_DIR_NAME" ] || [ -L "$TARGET/backups/$BACKUP_DIR_NAME" ]; do
  BACKUP_DIR_NAME="claude-setup-$STAMP-$$-$_backup_n"
  _backup_n=$((_backup_n + 1))
done
unset _backup_n
BACKUP_ROOT="$TARGET/backups/$BACKUP_DIR_NAME"
BACKED_UP=0

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

# Resolves a backup folder name this run, and only this run, owns: the
# stamp alone (one-second resolution) is not enough -- two installs back
# to back (or a profile switch run right after an install) can land in
# the same second, and sharing one folder meant the second run's mv
# either nested a junction INSIDE the first run's backed-up original,
# or silently overwrote it outright, permanently losing the user's own
# file. Stamp + PID resolves that in practice; the -2, -3... loop is the
# fallback for the one case PID alone cannot rule out (PID reuse hitting
# the exact same stamp).
# ensure_backup_dir -- creates BACKUP_ROOT (resolved once, above, at the
# top level) the first time this run actually needs it. BACKED_UP being
# reset in a subshell (see the call sites that capture backup_existing
# via $(...)) is harmless here, unlike before: BACKUP_ROOT itself is a
# fixed value either way, so a redundant mkdir -p from a subshell is a
# no-op, not a new, different folder.
ensure_backup_dir() {
  if [ "$BACKED_UP" -eq 0 ]; then
    [ "$DRY_RUN" -eq 0 ] && mkdir -p "$BACKUP_ROOT"
    BACKED_UP=1
  fi
}

# backup_existing <path> <rel> -- moves existing content out of the way and
# prints the backup folder name ("claude-setup-<UTC>-<PID>[-N]") on
# stdout, or prints nothing if there was nothing to back up. The caller
# records that name in the manifest so a LATER run (including --update)
# knows this path's original is already safe, and never backs it up again.
# Never moves onto an existing destination: ensure_backup_dir already
# guarantees this run owns a fresh backup folder no other run has
# touched, so $dest existing here would mean something else is wrong
# (the same rel backed up twice in one run); failing loudly before
# touching anything is safer than a silent overwrite either way.
backup_existing() {
  local path="$1" rel="$2" dest
  { [ -e "$path" ] || [ -L "$path" ]; } || return 0
  ensure_backup_dir
  dest="$BACKUP_ROOT/$rel"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    # return, not exit: several call sites capture this function's
    # output via $(...), which runs it in a SUBSHELL -- exit there would
    # only kill the subshell, silently handing the caller an empty
    # backup_ref instead of stopping the run, which is exactly the kind
    # of silent data loss this check exists to prevent. Every call site
    # checks this function's own exit status and stops the whole run on
    # failure (see link_file/link_dir/write_profile_record/
    # install_profile_settings below).
    echo "claude-setup: refusing to overwrite an existing backup at $dest. This should not happen; please report it. '$rel' itself was NOT moved or touched -- but this run is not atomic, so any path already linked, copied, or backed up earlier in THIS SAME run is already done; re-run once the cause is fixed to pick up where this stopped." >&2
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) back up $rel" >&2
    printf '%s' "$BACKUP_DIR_NAME"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  say "  backed up $rel -> $dest" >&2
  printf '%s' "$BACKUP_DIR_NAME"
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
  if [ -z "$kind" ]; then
    # No manifest line at all: this is the FIRST time this path is taken
    # over, so back up whatever is really there (possibly nothing;
    # backup_existing then correctly leaves backup_ref empty). Checking
    # $kind rather than $backup_ref matters once a profile can point
    # "agents" at a different source between runs (see
    # profile_agents_source in profiles/lib/profile.sh): $backup_ref is
    # legitimately empty whenever there was truly nothing to back up, and
    # that empty STRING must not be mistaken for "no manifest line yet" on
    # a later run, or a profile switch would wrongly back up our OWN prior
    # content as if it were the pre-claude-setup original, and uninstall
    # would later restore that stale content instead of leaving the path
    # empty.
    backup_ref=$(backup_existing "$dest" "$rel") || exit 1
  elif { [ -e "$dest" ] || [ -L "$dest" ]; }; then
    # We already own this path (a manifest line is on file from the first
    # takeover). What is here now is either our own stale link/copy (safe
    # to just discard, we can always re-link or re-copy it, including to a
    # different source on a profile switch) or something that REPLACED our
    # link with real content since -- a user's own directory, or a tool
    # that saves over a symlink by write-then-rename. That content is not
    # necessarily disposable, so it goes into THIS run's backup folder
    # rather than being deleted outright; the manifest's backup_ref keeps
    # pointing at the ORIGINAL pre-claude-setup content either way, since
    # that is what uninstall should restore, not whatever briefly sat here
    # in between.
    backup_existing "$dest" "$rel" >/dev/null || exit 1
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

# link_file <rel> <source> [force_refresh] -- see link_dir and the file
# header. force_refresh=1 refreshes an unmodified copy even without
# --update, the same way --update would -- used by install_settings when
# an explicit profile switch is the reason this file needs to change now
# (a hand-edited copy is still left alone either way; that check runs
# first, below).
link_file() {
  local rel="$1" source="$2" force_refresh="${3:-0}" backup_ref kind cur_sum dest
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
    if [ "$UPDATE" -eq 0 ] && [ "$force_refresh" -eq 0 ]; then
      say "  $rel is already installed as a copy, leaving it. Use --update to refresh it."
      return 0
    fi
    # --update, or an explicit profile switch, on our own, unmodified
    # copy: refresh in place. This is not a new takeover, so it must NOT
    # create a new backup -- the real original is already preserved
    # under backup_ref from the first time this path was taken over, and
    # a second backup here is what used to leave that original stranded
    # behind a newer "backup" that only ever held our own stale copy.
    if [ "$DRY_RUN" -eq 1 ]; then
      say "  (dry run) refresh copy of $rel"
      return 0
    fi
    cp "$source" "$dest"
    manifest_set "$rel" copy "$backup_ref" "$(sha256_of "$dest")"
    if [ "$UPDATE" -eq 1 ]; then
      say "  refreshed copy of $rel (--update)"
    else
      say "  refreshed copy of $rel (profile switch)"
    fi
    return 0
  fi

  if [ -z "$backup_ref" ]; then
    backup_ref=$(backup_existing "$dest" "$rel") || exit 1
  elif { [ -e "$dest" ] || [ -L "$dest" ]; }; then
    # See link_dir's matching comment: this path is already ours, but what
    # is here now does not match the repo (kind=link with mismatched
    # content, since the kind=copy case above already returned). Preserve
    # it in this run's backup rather than deleting it; backup_ref keeps
    # pointing at the real pre-claude-setup original.
    backup_existing "$dest" "$rel" >/dev/null || exit 1
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

# write_settings_key_diff <dest> <source> -- prints which top-level keys
# of the user's own settings.json (if any already exists there,
# unmanaged) would be added, removed, or changed by installing $source
# over it. Shared by install_settings (max) and install_profile_settings
# (standard/lite): a friend on the cheapest plan needs this just as much
# as a max install does -- it is the only way the assistant running
# SETUP-WITH-CLAUDE.md can point out which of the user's own
# permissions, env vars, or hooks stop applying while this is installed.
# Silently does nothing if python3 is not on PATH, same as before this
# existed: the diff is a nice-to-have, never load-bearing for the
# install itself.
write_settings_key_diff() {
  local dest="$1" source="$2"
  command -v python3 >/dev/null 2>&1 || return 0
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
}

install_settings() {
  local rel="settings.json" dest="$TARGET/settings.json" source="$1" force_refresh="${2:-0}"
  if [ -e "$dest" ] && ! same_content "$dest" "$source" && [ -z "$(manifest_field "$rel" 2)" ]; then
    write_settings_key_diff "$dest" "$source"
  fi
  link_file "$rel" "$source" "$force_refresh"
}

# profile_switch_conflict -- checked ONCE, up front, before anything is
# linked, rendered, or written, whenever this run is an explicit profile
# switch (PROFILE_SWITCH=1). If settings.json is already installed as a
# copy and its checksum no longer matches what claude-setup itself last
# wrote there (a hand edit), prints a message and returns 1: the WHOLE
# run stops here, "before changing anything" meaning literally nothing
# changes this run, not even the profile record, rather than aborting
# partway through with some paths already moved and others not.
profile_switch_conflict() {
  local rel="settings.json" dest="$TARGET/settings.json" kind cur_sum checksum
  kind=$(manifest_field "$rel" 2)
  if [ "$kind" = "copy" ] && [ -e "$dest" ]; then
    cur_sum=$(sha256_of "$dest")
    checksum=$(manifest_field "$rel" 4)
    if [ "$cur_sum" != "$checksum" ]; then
      echo "settings.json was edited since claude-setup wrote it as a copy. Refusing to switch profiles until that is resolved by hand: restore claude-setup's copy (then re-run), or do not pass --profile if you want to keep your edit." >&2
      return 1
    fi
  fi
  return 0
}

# install_profile_settings -- used for standard/lite instead of
# install_settings/link_file: settings.json is ALWAYS installed as a
# plain tracked COPY of the rendered file, checksum recorded, never a
# link into .profile-build/<profile>/. .profile-build is gitignored and
# meant to be deleted and regenerated; a symlink into it would leave
# settings.json (and every hook it wires, the git guard included)
# dangling the moment that happens, until the next --update. agents may
# still link into .profile-build -- only settings.json gets this
# never-a-link treatment.
#
# force_refresh=1 (an explicit profile switch, see PROFILE_SWITCH above)
# re-copies even without --update, since the switch itself is the
# user's intent to make this file match NOW. A hand-edited copy is left
# alone either way; profile_switch_conflict already refused the whole
# run before this is ever reached if a switch would have overwritten one.
install_profile_settings() {
  local source="$1" force_refresh="$2"
  local rel="settings.json" dest kind backup_ref checksum cur_sum
  dest="$TARGET/$rel"
  kind=$(manifest_field "$rel" 2)
  backup_ref=$(manifest_field "$rel" 3)
  checksum=$(manifest_field "$rel" 4)

  if [ "$kind" = "copy" ] && [ -e "$dest" ]; then
    cur_sum=$(sha256_of "$dest")
    if [ "$cur_sum" != "$checksum" ]; then
      say "  $rel was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
      return 0
    fi
    if [ "$force_refresh" -eq 0 ] && [ "$UPDATE" -eq 0 ]; then
      say "  $rel is already installed as a copy of this profile's rendered settings, leaving it. Use --update or --profile to refresh it."
      return 0
    fi
  elif [ -n "$kind" ] && [ -e "$dest" ]; then
    # Was a LINK before (an earlier install, or a platform where a file
    # symlink actually succeeds); replacing it with our own copy takes
    # over a path a different mechanism owned, so back up what is
    # physically there first -- same discipline link_dir uses when a
    # link gets replaced by something else.
    backup_existing "$dest" "$rel" >/dev/null || exit 1
  fi

  if [ -z "$kind" ]; then
    [ -e "$dest" ] && write_settings_key_diff "$dest" "$source"
    backup_ref=$(backup_existing "$dest" "$rel") || exit 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) copy $rel <- $source"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$source" "$dest"
  manifest_set "$rel" copy "$backup_ref" "$(sha256_of "$dest")"
  say "  copied $rel <- $source (tracked copy, never a link into .profile-build)"
}

# write_profile_record -- copies the chosen profile's own JSON, byte for
# byte, to <TARGET>/claude-setup-profile.json: a plain file this installer
# owns outright (never a symlink, since each install target can pick its
# own profile), always rewritten to match THIS run's choice. The "already
# managed" check mirrors install_settings' own style: a manifest line's
# kind is never empty once written, so this only backs up pre-existing
# foreign content the very first time, exactly like every other managed
# path.
#
# force_refresh=1 (an explicit profile switch) treats a hand-edited
# record differently from every other hand-edited copy: the switch is
# strong, explicit intent for THIS run's profile, so the edit is
# preserved in the backup folder (never silently lost) but the record
# still gets written, rather than left to fall out of step with the
# agents/settings links this same run just moved: a hand-edited record
# surviving a switch would otherwise mean the NEXT plain re-run silently
# reverted to the old profile.
write_profile_record() {
  local source="$1" force_refresh="$2"
  local rel="claude-setup-profile.json" dest kind backup_ref checksum cur_sum
  dest="$TARGET/$rel"
  kind=$(manifest_field "$rel" 2)
  backup_ref=$(manifest_field "$rel" 3)
  checksum=$(manifest_field "$rel" 4)

  if [ "$kind" = "copy" ] && [ -e "$dest" ]; then
    cur_sum=$(sha256_of "$dest")
    if [ "$cur_sum" != "$checksum" ]; then
      if [ "$force_refresh" -eq 0 ]; then
        say "  $rel was edited since claude-setup wrote it; leaving it alone (not overwriting your changes)."
        return 0
      fi
      if [ "$DRY_RUN" -eq 1 ]; then
        say "  (dry run) back up hand-edited $rel and write the new record"
      else
        backup_existing "$dest" "$rel" >/dev/null || exit 1
      fi
    fi
  fi

  if [ -z "$kind" ]; then
    backup_ref=$(backup_existing "$dest" "$rel") || exit 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  (dry run) write profile record for '$CHOSEN_PROFILE_NAME' -> $rel"
    return 0
  fi
  cp "$source" "$dest"
  manifest_set "$rel" copy "$backup_ref" "$(sha256_of "$dest")"
  say "  wrote profile record: $rel (profile '$CHOSEN_PROFILE_NAME')"
}

if [ "$PROFILE_SWITCH" -eq 1 ]; then
  if ! profile_switch_conflict; then
    exit 1
  fi
fi

say "Installing claude-setup into: $TARGET"
[ "$DRY_RUN" -eq 0 ] && mkdir -p "$TARGET"

# Render (or just diff, under --dry-run or for the max profile) the 7 agent
# files for the chosen profile. The max profile never writes a rendered
# copy at all; it links agents/ straight from the repo.
if [ "$CHOSEN_PROFILE_NAME" = "max" ]; then
  AGENTS_SOURCE="$HERE/agents"
else
  AGENTS_SOURCE="$PROFILE_BUILD_AGENTS"
fi
if [ "$DRY_RUN" -eq 1 ] || [ "$CHOSEN_PROFILE_NAME" = "max" ]; then
  RENDER_DRY=1
else
  RENDER_DRY=0
fi

say "Rendering for '$CHOSEN_PROFILE_NAME' ($(profile_field "$CHOSEN_PROFILE_PATH" description)):"
# Diff lines go to a temp file, not through a pipe: `profile_render_agents
# | while read ...` cannot be trusted to surface a render failure's exit
# status back to this script (the pipeline's own status reflects the
# pipe as a whole). Check the function's own return value directly instead.
RENDER_DIFF=$(mktemp)
if ! profile_render_agents "$CHOSEN_PROFILE_PATH" "$HERE/agents" "$PROFILE_BUILD_AGENTS" "$RENDER_DRY" "$RENDER_DIFF"; then
  rm -f "$RENDER_DIFF"
  echo "Rendering failed for profile '$CHOSEN_PROFILE_NAME'; nothing was linked or written." >&2
  exit 1
fi
while IFS=$'\t' read -r role old_model new_model old_effort new_effort; do
  if [ "$old_model" = "$new_model" ] && [ "$old_effort" = "$new_effort" ]; then
    say "  $role: model=$new_model effort=$new_effort (unchanged)"
  else
    say "  $role: model $old_model -> $new_model, effort $old_effort -> $new_effort"
  fi
done <"$RENDER_DIFF"
rm -f "$RENDER_DIFF"
say ""

# Same temp-then-swap discipline as the agent render: a failure here (an
# unexpected settings.json shape) exits BEFORE anything is linked,
# leaving an earlier render (if any) at $SETTINGS_SOURCE untouched.
if [ "$CHOSEN_PROFILE_NAME" != "max" ]; then
  if ! profile_render_settings "$CHOSEN_PROFILE_PATH" "$GLOBAL_SETTINGS_PATH" "$SETTINGS_SOURCE" "$RENDER_DRY"; then
    echo "Rendering settings.json failed for profile '$CHOSEN_PROFILE_NAME'; nothing was linked or written." >&2
    exit 1
  fi
fi

# The repo itself, at a stable absolute path: everything else this repo
# ships (templates/, lessons/, harness/, docs/) is only reachable through
# this one link, since skills and commands cannot know ahead of time where
# a given machine cloned claude-setup to.
link_dir "claude-setup" "$HERE"

link_file "CLAUDE.md" "$HERE/global/CLAUDE.md"
if [ "$CHOSEN_PROFILE_NAME" = "max" ]; then
  install_settings "$SETTINGS_SOURCE" "$PROFILE_SWITCH"
else
  install_profile_settings "$SETTINGS_SOURCE" "$PROFILE_SWITCH"
fi
link_dir "agents" "$AGENTS_SOURCE"
write_profile_record "$CHOSEN_PROFILE_PATH" "$PROFILE_SWITCH"
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
# Never say "applied" on faith: read back whatever settings.json actually
# holds now and compare, so a left-alone hand-edited copy (or any other
# reason it did not get the profile's values) is reported honestly
# instead of claimed.
if [ "$DRY_RUN" -eq 1 ]; then
  say "Main session (per the '$CHOSEN_PROFILE_NAME' profile, if this were a real run): model=$MAIN_MODEL, effortLevel=$MAIN_EFFORT."
else
  INSTALLED_SETTINGS="$TARGET/settings.json"
  ACTUAL_MODEL=$(grep -m1 -E '^  "model":' "$INSTALLED_SETTINGS" 2>/dev/null | sed -E 's/^  "model":[[:space:]]*"([^"]*)".*/\1/')
  ACTUAL_EFFORT=$(grep -m1 -E '^  "effortLevel":' "$INSTALLED_SETTINGS" 2>/dev/null | sed -E 's/^  "effortLevel":[[:space:]]*"([^"]*)".*/\1/')
  if [ "$ACTUAL_MODEL" = "$MAIN_MODEL" ] && [ "$ACTUAL_EFFORT" = "$MAIN_EFFORT" ]; then
    say "Main session (per the '$CHOSEN_PROFILE_NAME' profile): model=$MAIN_MODEL, effortLevel=$MAIN_EFFORT -- applied to settings.json."
  else
    # Diagnose the real cause instead of guessing "hand-edited": check
    # the same checksum install_settings/install_profile_settings just
    # checked, rather than assuming the one reason that happens to be
    # most common.
    if [ ! -e "$INSTALLED_SETTINGS" ]; then
      REASON="settings.json is missing or could not be read"
    else
      CUR_SUM=$(sha256_of "$INSTALLED_SETTINGS")
      RECORDED_SUM=$(manifest_field "settings.json" 4)
      if [ -n "$RECORDED_SUM" ] && [ "$CUR_SUM" != "$RECORDED_SUM" ]; then
        REASON="it is a hand-edited copy; see the messages above for why"
      else
        REASON="this run did not refresh it (no profile switch and no --update); re-run with --update or --profile to pick up the profile's values"
      fi
    fi
    say "Main session: settings.json currently has model=$ACTUAL_MODEL, effortLevel=$ACTUAL_EFFORT -- NOT yet the '$CHOSEN_PROFILE_NAME' profile's model=$MAIN_MODEL, effortLevel=$MAIN_EFFORT. Left as-is because $REASON."
  fi
fi

say ""
if [ "$BACKED_UP" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    say "(dry run) backups would be written to: $BACKUP_ROOT"
  else
    say "Backups written to: $BACKUP_ROOT"
  fi
fi
say "Repo reachable at: $TARGET/claude-setup"
say "Profile record at: $TARGET/claude-setup-profile.json"
say "Never touched: .credentials.json, history.jsonl, projects/, sessions/, caches."
say "Nothing was committed; this script never runs git."
say "Done."
