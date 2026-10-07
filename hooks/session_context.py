"""SessionStart hook: inject coordination context (handoff state, freeze
windows, recent decisions) at the start of every session, so a fresh
session or one resuming after a compaction does not have to re-derive it
by reading files one at a time.

Resolution of the briefs folder happens ONLY here, in one place: the
default is `<git root>/briefs`, overridden by the `CLAUDE_BRIEFS_DIR`
environment variable (absolute, or relative to the git root) when a
project keeps its briefs folder outside the repo. Claude Code applies a
project's `.claude/settings.json` `env` block to the process environment,
so this reads the plain environment variable rather than re-parsing that
file. See templates/project/briefs/README.md for the documented rule;
every other piece of this kit (the slash commands, the skills) points
there instead of restating the resolution.

FAILS OPEN, ALWAYS. A SessionStart hook runs on every session start,
resume, compaction, and /clear, so any bug here must never block or break
one: bad encoding, a BOM, a missing section, an unreadable file, a
malformed stdin payload, or anything else unanticipated prints at most a
one-line diagnostic to stderr and exits 0 with no stdout, the same as "no
context to add" looks like. There is no closed path at all, unlike
git_guard.py's PreToolUse guard: a SessionStart hook has nothing to deny.

No briefs folder (missing, or no git root at all): also exits 0 with no
stdout, deliberately indistinguishable from "nothing to add" -- a project
that never adopted this coordination kit should never see any sign this
hook ran.

In a git WORKTREE, the briefs folder is looked up at the worktree's own
root first (a lane may keep its own), falling back to the main checkout's
root (the parent of the worktree's `gitdir:` pointer) when the worktree has
none -- a worktree almost never has its own `briefs/`, so this is what
makes HANDOFF/COORDINATION/LOG resolve to the shared one instead of
silently injecting nothing.

stdlib only. Read as UTF-8 with BOM tolerance (utf-8-sig) and CRLF folded
to LF before any parsing, so a file saved from either platform parses the
same way. HTML comments (`<!-- ... -->`) are stripped before parsing, so a
freshly-created template's own placeholder examples (wrapped in comments
on purpose; see templates/project/LOG.md.template and
COORDINATION.md.template) are never mistaken for real content.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone

DEFAULT_CONTEXT_CAP = 8000
STALE_HOURS = 2
LOG_ENTRY_COUNT = 10

# A handoff block's header, on one line: "## ===== <stuff> =====". The
# <stuff> is then matched against BLOCK_BODY_RE to confirm it is really a
# handoff block (not an unrelated "=====" heading) and to pull out the
# effort name, the date, the reason, and whether it is marked superseded.
HEADER_LINE_RE = re.compile(r"^##\s*=====\s*(.+?)\s*=====\s*$")
BLOCK_BODY_RE = re.compile(
    r"^(?P<effort>.*?)\s*CURRENT STATE,\s*"
    r"(?P<date>\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2})\s*Z\s*"
    r"\((?P<reason>[^)]*)\)\.\s*READ THIS BLOCK FIRST"
    r"(?P<superseded>\s*\(SUPERSEDED\))?\s*$",
    re.IGNORECASE,
)
# A decorative border row (see templates/docs/handoff-block.md): dropped
# from a block's text, never treated as a block boundary itself.
BORDER_RE = re.compile(r"^#{10,}$")

# A markdown "## Heading" line, used to slice one named section (e.g.
# "Freeze windows") out of COORDINATION.md.
SECTION_HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")

# A decision log entry's header, "### <date> <effort>" (see
# templates/project/LOG.md.template). Only the line shape matters here;
# the date/effort text is not re-parsed since the whole entry is injected
# verbatim.
LOG_ENTRY_HEADER_RE = re.compile(r"^###\s+\S.*$")

DATE_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})")

# Stripped out of every file before any other parsing (see the module
# docstring). DOTALL so a comment spanning several lines (the templates'
# own placeholder examples) is removed as one unit.
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)


def find_git_root(start):
    """Walk up from `start` looking for a `.git` entry (a directory for a
    normal clone, a file for a worktree). None if the walk reaches the
    filesystem root without finding one, or `start` itself is unusable.
    """
    try:
        current = os.path.abspath(start)
    except Exception:
        return None
    seen = set()
    while current not in seen:
        seen.add(current)
        git_entry = os.path.join(current, ".git")
        if os.path.isdir(git_entry) or os.path.isfile(git_entry):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent
    return None


def find_main_repo_root(git_root):
    """If `git_root`'s own `.git` is a FILE (a worktree, not a real
    checkout), returns the main checkout's root by following the
    `gitdir:` pointer it holds -- `<main>/.git/worktrees/<name>` -- up two
    levels to `<main>/.git` and then to `<main>` itself. None if `git_root`
    is not a worktree, or anything about the pointer is not the expected
    shape (a foreign `.git` file, a relocated worktree, an unreadable
    pointer): callers then just use `git_root` on its own.
    """
    git_entry = os.path.join(git_root, ".git")
    if not os.path.isfile(git_entry):
        return None
    try:
        with open(git_entry, "r", encoding="utf-8", errors="replace") as fh:
            content = fh.read()
    except Exception:
        return None
    m = re.search(r"^gitdir:\s*(.+?)\s*$", content, re.MULTILINE)
    if not m:
        return None
    gitdir = m.group(1)
    if not os.path.isabs(gitdir):
        gitdir = os.path.join(git_root, gitdir)
    gitdir = os.path.normpath(gitdir)
    worktrees_dir = os.path.dirname(gitdir)
    if os.path.basename(worktrees_dir) != "worktrees":
        return None
    common_dir = os.path.dirname(worktrees_dir)
    main_root = os.path.dirname(common_dir)
    if os.path.isdir(os.path.join(main_root, ".git")):
        return main_root
    return None


def resolve_briefs_dir(git_root):
    """The one place this kit decides where a project's briefs folder is.
    See the module docstring. An explicit `CLAUDE_BRIEFS_DIR` always wins,
    resolved against `git_root` (the worktree, if this is one) when it is
    relative. Otherwise: the worktree's own `briefs/` if it has one, else
    the main checkout's `briefs/` (a worktree almost never has its own).
    """
    override = os.environ.get("CLAUDE_BRIEFS_DIR")
    if override:
        if os.path.isabs(override):
            return override
        return os.path.join(git_root, override)
    worktree_briefs = os.path.join(git_root, "briefs")
    if os.path.isdir(worktree_briefs):
        return worktree_briefs
    main_root = find_main_repo_root(git_root)
    if main_root:
        main_briefs = os.path.join(main_root, "briefs")
        if os.path.isdir(main_briefs):
            return main_briefs
    return worktree_briefs


def resolve_context_cap():
    """The active profile's `sessionContextChars` (lite 3000, standard
    6000, max 8000), read from the record the installer writes right
    next to this file's own installed location (`<install
    root>/claude-setup-profile.json`, one level up from `hooks/`) --
    never from `__file__`'s location in THIS repo, which is correct
    only once installed (this hook always runs from the installed
    copy). Falls back to DEFAULT_CONTEXT_CAP on anything short of a
    clean positive integer: a missing record, an unreadable or
    malformed one, a missing key, or a value that is not a positive
    int -- the record is boundary input, not something this hook trusts
    at face value.
    """
    try:
        install_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        record_path = os.path.join(install_root, "claude-setup-profile.json")
        with open(record_path, "rb") as fh:
            raw = fh.read()
        record = json.loads(raw.decode("utf-8-sig", "replace"))
        cap = record.get("sessionContextChars")
        if isinstance(cap, bool) or not isinstance(cap, int) or cap <= 0:
            return DEFAULT_CONTEXT_CAP
        return cap
    except Exception:
        return DEFAULT_CONTEXT_CAP


def read_text_tolerant(path):
    """UTF-8 (BOM tolerant) text with CRLF folded to LF and HTML comments
    stripped, or None on any read or decode failure -- a missing file, a
    directory at that path, a permissions error, or content that will not
    decode even with `errors="replace"` raising for some other reason.
    Never raises.
    """
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except Exception:
        return None
    try:
        text = raw.decode("utf-8-sig", "replace")
    except Exception:
        return None
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return HTML_COMMENT_RE.sub("", text)


def parse_handoff_blocks(text):
    """Every handoff block in file order (the file's own order is newest
    overall first, by convention: see templates/docs/handoff-block.md).
    Each block is a dict with effort, date, reason, superseded, and text
    (the block's own content, border rows stripped).
    """
    lines = text.split("\n")
    starts = []
    for i, line in enumerate(lines):
        m = HEADER_LINE_RE.match(line.strip())
        if not m:
            continue
        bm = BLOCK_BODY_RE.match(m.group(1).strip())
        if not bm:
            continue
        effort = (bm.group("effort") or "").strip() or "general"
        starts.append({
            "line": i,
            "effort": effort,
            "date": bm.group("date"),
            "reason": bm.group("reason").strip(),
            "superseded": bool(bm.group("superseded")),
        })
    blocks = []
    for idx, s in enumerate(starts):
        end = starts[idx + 1]["line"] if idx + 1 < len(starts) else len(lines)
        body_lines = [ln for ln in lines[s["line"]:end] if not BORDER_RE.match(ln.strip())]
        block = dict(s)
        block["text"] = "\n".join(body_lines).strip("\n")
        blocks.append(block)
    return blocks


def newest_per_effort(blocks):
    """The first non-superseded block for each effort, in file order (so
    "first seen" is "newest", per the newest-block-goes-on-top convention).
    A superseded block is skipped entirely, even if nothing newer for that
    effort exists yet.
    """
    result = {}
    for b in blocks:
        if b["superseded"]:
            continue
        if b["effort"] not in result:
            result[b["effort"]] = b
    return result


def parse_block_datetime(date_str):
    """A block's or log entry's date string as an aware UTC datetime, or
    None if it does not contain a recognizable date -- age is then simply
    omitted rather than guessed at.
    """
    m = DATE_RE.search(date_str or "")
    if not m:
        return None
    try:
        y, mo, d, h, mi = (int(x) for x in m.groups())
        return datetime(y, mo, d, h, mi, tzinfo=timezone.utc)
    except Exception:
        return None


def age_hours(dt):
    if dt is None:
        return None
    try:
        return (datetime.now(timezone.utc) - dt).total_seconds() / 3600.0
    except Exception:
        return None


def parse_section(text, heading_name):
    """The body of one `## <heading_name>` section (up to the next `##`
    heading or EOF), or None if that heading is not present or its body is
    empty.
    """
    lines = text.split("\n")
    start = None
    for i, line in enumerate(lines):
        m = SECTION_HEADING_RE.match(line.strip())
        if m and m.group(1).strip().lower() == heading_name.lower():
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if SECTION_HEADING_RE.match(lines[j].strip()):
            end = j
            break
    content = "\n".join(lines[start + 1:end]).strip()
    return content or None


def parse_log_entries(text):
    """Every decision log entry in file order (oldest first, per the
    newest-at-the-bottom convention: see templates/project/LOG.md.template).
    """
    lines = text.split("\n")
    starts = [i for i, ln in enumerate(lines) if LOG_ENTRY_HEADER_RE.match(ln.strip())]
    entries = []
    for idx, s in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(lines)
        entry_text = "\n".join(lines[s:end]).strip()
        if entry_text:
            entries.append(entry_text)
    return entries


def build_additional_context(briefs_dir, source, context_cap=DEFAULT_CONTEXT_CAP):
    """Everything this hook would inject, already capped at context_cap
    characters (the active profile's sessionContextChars; see
    resolve_context_cap) by priority, not by position:

    1. ALWAYS kept, never dropped for being "old" (a live safety signal,
       not history): the compact staleness note (if any) and the Freeze
       windows section.
    2. The newest handoff block per effort, newest effort-date first.
       NEVER dropped to nothing: a block that does not fit keeps its own
       header line and gets its body truncated from the end instead, with
       a note naming HANDOFF.md for the rest. Once one block has been
       truncated this way the budget is exhausted by definition, so no
       block after it (nor any LOG entry) can still fit.
    3. The last LOG_ENTRY_COUNT decision log entries, newest first, as
       WHOLE units only (an entry is either kept complete or dropped
       complete, never cut mid-text) -- the first one that does not fit
       stops the loop (every entry after it is older still, see the
       "break, not continue" note on that loop below), and every entry
       after it is dropped too.

    Returns "" when there is nothing to say (every file missing or empty).
    """
    newest = {}
    handoff_text = read_text_tolerant(os.path.join(briefs_dir, "HANDOFF.md"))
    if handoff_text:
        newest = newest_per_effort(parse_handoff_blocks(handoff_text))

    # Each item: (header_line, body_text, age_note). Kept separate, not
    # pre-joined into one string, so a block that does not fit can still
    # keep its header line while its body gets truncated -- joining them
    # first would force an all-or-nothing choice on the whole block.
    ordered_items = []
    stale = []
    if newest:
        ordered = sorted(
            newest.values(),
            key=lambda b: parse_block_datetime(b["date"]) or datetime.min.replace(tzinfo=timezone.utc),
            reverse=True,
        )
        for b in ordered:
            hrs = age_hours(parse_block_datetime(b["date"]))
            age_note = "age unknown" if hrs is None else "%.1fh old" % hrs
            header, _, body = b["text"].partition("\n")
            ordered_items.append((header, body, age_note))
            if hrs is not None and hrs > STALE_HOURS:
                stale.append((b["effort"], hrs))

    freeze_section = ""
    coord_text = read_text_tolerant(os.path.join(briefs_dir, "COORDINATION.md"))
    if coord_text:
        freeze = parse_section(coord_text, "Freeze windows")
        if freeze:
            freeze_section = "## Freeze windows\n\n" + freeze

    log_chunks = []
    log_text = read_text_tolerant(os.path.join(briefs_dir, "LOG.md"))
    if log_text:
        entries = parse_log_entries(log_text)
        if entries:
            log_chunks = list(reversed(entries[-LOG_ENTRY_COUNT:]))
    if log_chunks:
        log_chunks[0] = "## Last %d decision log entries\n\n" % len(log_chunks) + log_chunks[0]

    stale_note = ""
    if source == "compact" and stale:
        names = ", ".join("%s (%.1fh)" % (effort, hrs) for effort, hrs in stale)
        stale_note = (
            "STALE HANDOFF: the newest block for %s is older than %gh. "
            "Write a fresh handoff before continuing." % (names, STALE_HOURS)
        )

    handoff_path = os.path.join(briefs_dir, "HANDOFF.md")
    truncation_note = "\n\n[dropped older content to fit %d characters; see the full files under %s]" % (
        context_cap, briefs_dir,
    )

    # Always-kept parts are added unconditionally, even past the cap in
    # the pathological case where they alone exceed it: a mangled or
    # missing freeze notice is worse than a long one. Everything after
    # them is added only while it still fits, newest (most urgent) first.
    kept = [p for p in (stale_note, freeze_section) if p]
    used = len("\n\n".join(kept))
    dropped_any = False

    for idx, (header, body, age_note) in enumerate(ordered_items):
        prefix = "## Handoff: newest block per effort\n\n" if idx == 0 else ""
        full_text = "%s%s\n%s\n(%s)" % (prefix, header, body, age_note)
        sep = 2 if kept else 0
        if used + sep + len(full_text) + len(truncation_note) <= context_cap:
            kept.append(full_text)
            used += sep + len(full_text)
            continue
        # Does not fit whole: keep the header (never dropped) and truncate
        # the body from the end to whatever is left, rather than dropping
        # the block entirely -- a block this big is plausible, since the
        # template asks for live state, in-flight work, waiting items,
        # next step, open questions, and known issues.
        fixed = "%s%s\n" % (prefix, header)
        age_suffix = "\n(%s)" % age_note
        per_block_note = "\n\n[body truncated; see %s for the rest]" % handoff_path
        remaining = context_cap - used - sep - len(truncation_note)
        body_budget = remaining - len(fixed) - len(age_suffix) - len(per_block_note)
        # The header and notes are kept in full even in the pathological
        # case where they alone do not fit (same reasoning as the
        # always-kept Freeze windows/stale note above): the body is the
        # only thing that ever shrinks to zero.
        body_budget = max(0, body_budget)
        truncated = fixed + body[:body_budget] + per_block_note + age_suffix
        kept.append(truncated)
        used += sep + len(truncated)
        dropped_any = True
        # Nothing after this fits: the body was truncated to fill exactly
        # what remained (or the remainder was already zero). Every older
        # block, and every LOG entry, is skipped -- not individually
        # re-checked against a budget that is already spent.
        break
    else:
        # Only reached when the for loop completed without truncating any
        # block (every handoff block fit whole, or there were none): LOG
        # entries get their own chance at whatever budget remains.
        for chunk in log_chunks:
            sep = 2 if kept else 0
            if used + sep + len(chunk) + len(truncation_note) <= context_cap:
                kept.append(chunk)
                used += sep + len(chunk)
            else:
                # break, not continue: once the newest-remaining LOG entry
                # does not fit, every entry still to come is OLDER, so
                # skipping this one to try a smaller older one would
                # inject decisions out of order for no real benefit, and
                # contradicts "drop the oldest first" (an older entry that
                # happened to be smaller would otherwise survive while a
                # newer, larger one it is supposed to rank above does
                # not). See test_session_context.py's "break, not
                # continue" case for exactly this shape.
                dropped_any = True
                break

    context = "\n\n".join(kept)
    if dropped_any:
        context += truncation_note
    return context


def main():
    try:
        raw = sys.stdin.buffer.read()
        payload = json.loads(raw.decode("utf-8-sig", "replace"))
        if not isinstance(payload, dict):
            return 0
        cwd = payload.get("cwd") or os.getcwd()
        source = payload.get("source") or ""
        git_root = find_git_root(cwd)
        if not git_root:
            return 0
        briefs_dir = resolve_briefs_dir(git_root)
        if not briefs_dir or not os.path.isdir(briefs_dir):
            return 0
        context = build_additional_context(briefs_dir, source, resolve_context_cap())
        if not context:
            return 0
        sys.stdout.write(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": context,
            }
        }))
        return 0
    except Exception as exc:
        # Fails open unconditionally: see the module docstring. The
        # diagnostic goes to stderr only, never stdout, so a partial or
        # malformed write never lands in additionalContext.
        sys.stderr.write("session_context: failed open (%s); no context injected.\n" % exc)
        return 0


if __name__ == "__main__":
    sys.exit(main())
