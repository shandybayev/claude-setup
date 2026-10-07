import json, os, shutil, subprocess, sys, tempfile, time
from datetime import datetime, timedelta, timezone

HOOKS_DIR = os.path.dirname(os.path.abspath(__file__))
WRAPPER = os.path.join(HOOKS_DIR, "session_context.sh")

# Same reasoning as test_git_guard.py's FAKE_HOME: session_context.sh
# hard-codes "$HOME/.claude/hooks/session_context.py" (correct once
# installed, where that path links back into this repo). A fake HOME
# whose .claude/hooks holds THIS repo's copy makes every subprocess call
# exercise the file actually being edited, not whatever is deployed at
# the real ~/.claude.
_FAKE_HOME_DIR = tempfile.TemporaryDirectory(prefix="session-context-test-home-")
FAKE_HOME = _FAKE_HOME_DIR.name
_fake_hooks = os.path.join(FAKE_HOME, ".claude", "hooks")
os.makedirs(_fake_hooks, exist_ok=True)
shutil.copyfile(os.path.join(HOOKS_DIR, "session_context.py"), os.path.join(_fake_hooks, "session_context.py"))
BASE_ENV = dict(os.environ, HOME=FAKE_HOME)
BASE_ENV.pop("CLAUDE_BRIEFS_DIR", None)


def find_bash():
    """See test_git_guard.py's copy of this function for why the fixed
    Git-for-Windows locations are tried before a plain PATH search."""
    for candidate in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ):
        if os.path.exists(candidate):
            return candidate
    return shutil.which("bash")


GITBASH = find_bash()
if not GITBASH:
    print("CANNOT VERIFY: no bash found on PATH; install Git (ships Git Bash) to run this test.")
    sys.exit(1)


def to_posix_path(path):
    """A Windows path (as sys.executable gives it) in the /c/... form a
    hand-written bash stub can `exec` directly."""
    drive, rest = os.path.splitdrive(path)
    if drive:
        return "/" + drive[0].lower() + rest.replace("\\", "/")
    return path.replace("\\", "/")


# A fake "python3" that answers `-c 1` fine (the old probe this wrapper
# used to trust) but fails the REAL invocation with rc 126, the exact
# shape of a Windows "python3" that resolves on PATH to the WindowsApps
# app-execution alias stub: `command -v` finds it, and even a `-c 1`
# smoke test can pass, but the actual exec of a real script
# intermittently refuses with "Permission denied". Used for both
# candidate slots (named "python3" and "python") so a test can make
# either one, or both, behave this way.
FAKE_EXEC_FAIL_BODY = (
    "#!/usr/bin/env bash\n"
    'if [ "$1" = "-c" ] && [ "$2" = "1" ]; then\n'
    "  exit 0\n"
    "fi\n"
    "exit 126\n"
)


# A fake "python3"/"python" shaped like the WindowsApps stub when NO
# Python is installed behind it at all: prints the Microsoft Store
# prompt and exits 9009, every time, `-c 1` included -- unlike
# FAKE_EXEC_FAIL_BODY's rc 126, this is what the REAL stub actually does
# in that case, and the old "only retry on 126/127" logic would have
# wrongly trusted this as session_context.py's own (silent) result.
FAKE_STORE_BODY = (
    "#!/usr/bin/env bash\n"
    'echo "Python was not found; run without arguments to install from the Microsoft Store." >&2\n'
    "exit 9009\n"
)

# A candidate that answers `-c 1` fine but HANGS on the real invocation
# (never exits on its own): the shape neither rc 126 nor rc 9009 covers,
# since both of those are fast failures. Without the wrapper's own time
# limit, this candidate would tie up the hook until Claude Code's outer
# hook timeout kills it; the wrapper's `timeout 6` must cut it off first
# so the next candidate (or failing open) still gets a chance.
FAKE_HANG_BODY = (
    "#!/usr/bin/env bash\n"
    'if [ "$1" = "-c" ] && [ "$2" = "1" ]; then\n'
    "  exit 0\n"
    "fi\n"
    "sleep 60\n"
)


def make_fake_python_dir(prefix, python_body, python3_body=FAKE_EXEC_FAIL_BODY):
    """A directory holding a fake "python3" (python3_body, default
    FAKE_EXEC_FAIL_BODY) and a "python" with the given body, meant to be
    PREPENDED to PATH (not used as the whole PATH: cat, sed, and bash's
    other external tools still need to resolve from the real PATH).
    python_body is FAKE_EXEC_FAIL_BODY or FAKE_STORE_BODY again to
    simulate every candidate failing to exec, or a stub that execs the
    REAL interpreter running this test (sys.executable, not whatever
    "python3"/"python" happen to resolve to on PATH -- on this machine
    that IS the flaky alias being tested around) to simulate the second
    candidate actually working.
    """
    d = tempfile.mkdtemp(prefix=prefix)
    for name, body in (("python3", python3_body), ("python", python_body)):
        path = os.path.join(d, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        os.chmod(path, 0o755)
    return d


REAL_PYTHON_BODY = '#!/usr/bin/env bash\nexec "%s" "$@"\n' % to_posix_path(sys.executable)

fails = 0
total = 0


def check(label, condition, detail=""):
    global fails, total
    total += 1
    ok = bool(condition)
    fails += not ok
    line = ("OK  " if ok else "FAIL") + " " + label
    if detail and not ok:
        line += "  -- " + detail
    print(line)
    return ok


def run_hook(cwd, source="startup", env_extra=None, raw_stdin=None):
    env = dict(BASE_ENV)
    if env_extra:
        env.update(env_extra)
    if raw_stdin is None:
        payload = {"session_id": "t", "cwd": cwd, "hook_event_name": "SessionStart", "source": source}
        data = json.dumps(payload).encode()
    else:
        data = raw_stdin
    return subprocess.run([GITBASH, WRAPPER], input=data, capture_output=True, env=env)


def additional_context(r):
    out = r.stdout.decode().strip()
    if not out:
        return None
    return json.loads(out)["hookSpecificOutput"]["additionalContext"]


def make_project(tag, briefs_name="briefs"):
    root = tempfile.mkdtemp(prefix="session-context-test-proj-%s-" % tag)
    os.makedirs(os.path.join(root, ".git"), exist_ok=True)
    os.makedirs(os.path.join(root, briefs_name), exist_ok=True)
    return root


def write_bytes(path, text, encoding="utf-8", bom=False, crlf=False):
    if crlf:
        text = text.replace("\n", "\r\n")
    data = text.encode(encoding)
    if bom:
        data = b"\xef\xbb\xbf" + data
    with open(path, "wb") as f:
        f.write(data)


def handoff_block(effort, dt, reason="handoff", superseded=False, body="Body text.", border=True):
    sup = " (SUPERSEDED)" if superseded else ""
    header = "## ===== %s CURRENT STATE, %s Z (%s). READ THIS BLOCK FIRST%s =====" % (
        effort, dt.strftime("%Y-%m-%d %H:%M"), reason, sup,
    )
    if not border:
        return "%s\n\n%s\n" % (header, body)
    rule = "#" * 80
    return "%s\n%s\n%s\n\n%s\n" % (rule, header, rule, body)


def log_entry(dt, effort, decided):
    return "### %s Z - %s\n- Decided: %s\n- Why: reasons\n- By: owner\n" % (
        dt.strftime("%Y-%m-%d %H:%M"), effort, decided,
    )


NOW = datetime.now(timezone.utc)

# ---------------------------------------------------------------------------
# No git root at all: a plain temp dir outside any repo. (system temp roots
# are not expected to sit inside a git work tree; if this ever runs
# somewhere that is not true, the test would need a disposable location
# guaranteed clean of .git, not a workaround here.)
no_git_root = tempfile.mkdtemp(prefix="session-context-test-nogit-")
r = run_hook(no_git_root)
check("no git root -> no output, rc 0", r.returncode == 0 and additional_context(r) is None,
      "rc=%d stdout=%r" % (r.returncode, r.stdout))

# No briefs folder: a git root with nothing else in it.
proj_nobriefs = tempfile.mkdtemp(prefix="session-context-test-nobriefs-")
os.makedirs(os.path.join(proj_nobriefs, ".git"))
r = run_hook(proj_nobriefs)
check("git root, no briefs folder -> no output, rc 0", r.returncode == 0 and additional_context(r) is None,
      "rc=%d stdout=%r" % (r.returncode, r.stdout))

# Empty files: briefs folder exists, HANDOFF/COORDINATION/LOG all present
# but empty -- nothing to inject, same as not having them.
proj_empty = make_project("empty")
for name in ("HANDOFF.md", "COORDINATION.md", "LOG.md"):
    write_bytes(os.path.join(proj_empty, "briefs", name), "")
r = run_hook(proj_empty)
check("empty files -> no output, rc 0", r.returncode == 0 and additional_context(r) is None,
      "rc=%d stdout=%r" % (r.returncode, r.stdout))

# One effort, one block.
proj_one = make_project("one")
write_bytes(os.path.join(proj_one, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Alpha is live."))
r = run_hook(proj_one)
ctx = additional_context(r)
check("one effort -> block is injected", ctx and "Alpha is live." in ctx, repr(ctx))
check("one effort -> age is shown", ctx and "h old)" in ctx, repr(ctx))

# Several efforts, newest-dated effort first.
proj_several = make_project("several")
write_bytes(os.path.join(proj_several, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Alpha newest.") +
            handoff_block("ECHO", NOW - timedelta(hours=5), body="Echo older."))
r = run_hook(proj_several)
ctx = additional_context(r) or ""
check("several efforts -> both injected", "Alpha newest." in ctx and "Echo older." in ctx, repr(ctx))
check("several efforts -> newer effort listed first",
      ctx.find("Alpha newest.") != -1 and ctx.find("Alpha newest.") < ctx.find("Echo older."), repr(ctx))

# Superseded block skipped: only the newest (non-superseded) ALPHA block
# for the shared effort name should appear; the superseded one's unique
# body text must not.
proj_super = make_project("super")
write_bytes(os.path.join(proj_super, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Alpha current body.") +
            handoff_block("ALPHA", NOW - timedelta(hours=30), superseded=True, body="Alpha OLD superseded body."))
r = run_hook(proj_super)
ctx = additional_context(r) or ""
check("superseded block's body is skipped", "OLD superseded" not in ctx, repr(ctx))
check("current block's body is kept", "Alpha current body." in ctx, repr(ctx))

# The real case the skip guards: an effort whose ONLY block is marked
# superseded (finished, or superseded with nothing newer written yet)
# must not appear at all. "current wins over superseded for the same
# effort" above does not exercise this, since the first-seen-wins dedup
# alone already produces the right answer when a current block exists.
proj_lone_super = make_project("lonesuper")
write_bytes(os.path.join(proj_lone_super, "briefs", "HANDOFF.md"),
            handoff_block("DELTA", NOW - timedelta(hours=1), superseded=True, body="Delta lone superseded body."))
r = run_hook(proj_lone_super)
ctx = additional_context(r)
check("a lone superseded block is not injected at all", ctx is None, repr(ctx))

# BOM + CRLF, for real: the BOM sits directly before the header line (no
# border row ahead of it to silently absorb the BOM instead), and the
# whole file is CRLF. Without BOM stripping the header line would start
# with a literal U+FEFF character and "^##" would never match at all --
# nothing would be injected. Without CRLF folding, the injected text
# would carry a stray "\r" before every line break.
proj_bomcrlf = make_project("bomcrlf")
write_bytes(os.path.join(proj_bomcrlf, "briefs", "HANDOFF.md"),
            handoff_block("FOX", NOW - timedelta(hours=1), body="Fox body, CRLF file.", border=False),
            bom=True, crlf=True)
r = run_hook(proj_bomcrlf)
ctx = additional_context(r) or ""
check("BOM directly before the header still parses", "Fox body, CRLF file." in ctx, repr(ctx))
check("CRLF is folded to LF (no stray carriage returns in the output)", "\r" not in ctx, repr(ctx))

# Freeze windows section, from COORDINATION.md.
proj_freeze = make_project("freeze")
write_bytes(os.path.join(proj_freeze, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nNo merges during the migration.\n\n## Active efforts\n\nnone\n")
r = run_hook(proj_freeze)
ctx = additional_context(r) or ""
check("freeze windows section injected", "No merges during the migration." in ctx, repr(ctx))

# Last 10 log entries, newest first, oldest dropped.
proj_log = make_project("log")
entries = "".join(log_entry(NOW - timedelta(days=15 - i), "e%d" % i, "decision %d" % i) + "\n" for i in range(15))
write_bytes(os.path.join(proj_log, "briefs", "LOG.md"), "# Decision log\n\n" + entries)
r = run_hook(proj_log)
ctx = additional_context(r) or ""
check("only last 10 entries kept", "decision 0" not in ctx and "decision 4" not in ctx, repr(ctx))
check("newest entry kept and shown first",
      "decision 14" in ctx and ctx.find("decision 14") < ctx.find("decision 5"), repr(ctx))

# Cap + truncation note: enough moderate-sized log entries that the cap
# must drop some whole entries, not truncate one mid-text. Confirms the
# NEWEST entries survive and the note only appears when something was
# actually dropped.
proj_cap = make_project("cap")
#
# LOG.md's own convention is oldest-first in the file, newest at the
# bottom (the opposite of HANDOFF.md) -- so file position j=0 is the
# OLDEST entry and j=9 is the NEWEST, matching that order for real this
# time (an earlier draft of this fixture had file position and date
# running in opposite directions, which silently flipped which entry
# "survives" and made the assertions pass for the wrong reason).
# Each entry's own "decided" text carries a unique, hyphenated marker
# (tempfile.mkdtemp's random suffix is lowercase letters and digits
# only, never a hyphen) rather than the bare "e0"/"e9" effort label: a
# short 2-character label can and occasionally does turn up by chance
# inside that random suffix, which is itself always present in ctx (the
# "see the full files under <path>" note), producing a false FAIL on
# the "is dropped" check even though the real entry was correctly
# dropped. The marker makes the check immune to that coincidence.
many_entries = "".join(
    log_entry(NOW - timedelta(hours=(9 - j)), "e%d" % j, "decision-marker-%d-" % j + ("y" * 900)) + "\n"
    for j in range(10)
)
write_bytes(os.path.join(proj_cap, "briefs", "LOG.md"), "# Decision log\n\n" + many_entries)
r = run_hook(proj_cap)
ctx = additional_context(r) or ""
check("capped at 8000 characters", len(ctx) <= 8000, "len=%d" % len(ctx))
check("truncation note present when something was dropped", "dropped older content" in ctx, repr(ctx[-200:]))
check("newest entry (e9) survives the cap", "decision-marker-9-" in ctx, repr(ctx[:200]))
check("oldest entry (e0) is the one dropped", "decision-marker-0-" not in ctx, repr(ctx))

# Cut-order test (the actual bug this guards): Freeze windows is a live
# safety constraint and must survive the cap even when an ancient,
# finished effort's block is big enough to otherwise crowd it out. The
# newest effort's current block must also survive whole. The ancient
# one's HEADER must still appear -- it is the block that actually gets
# truncated here, and a block being truncated always keeps its header --
# but its body must be cut short, not kept in full. "Cutting older
# content first" means BRAVO's body is what gets sacrificed, never
# Freeze windows, and never BRAVO's header either. (A THIRD, still older
# effort's block would not get this treatment -- see the "a block after
# a truncated one" test below for that case.)
proj_cutorder = make_project("cutorder")
write_bytes(os.path.join(proj_cutorder, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nNO MERGES UNTIL THE MIGRATION LANDS.\n")
write_bytes(os.path.join(proj_cutorder, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Alpha current.\n" + ("a" * 6000)) +
            handoff_block("BRAVO", NOW - timedelta(hours=400), body="Bravo ancient.\n" + ("b" * 3000)))
r = run_hook(proj_cutorder)
ctx = additional_context(r) or ""
check("cut order: Freeze windows always survives", "NO MERGES UNTIL THE MIGRATION LANDS." in ctx, repr(ctx[:300]))
check("cut order: newest (ALPHA) block survives whole", "Alpha current." in ctx and "a" * 6000 in ctx, repr(ctx[:300]))
check("cut order: oldest (BRAVO) block keeps its header", "BRAVO CURRENT STATE" in ctx, repr(ctx[-400:]))
check("cut order: BRAVO's body is cut short, not kept in full", "b" * 3000 not in ctx, repr(ctx[-400:]))
check("cut order: capped at 8000 characters", len(ctx) <= 8000, "len=%d" % len(ctx))

# A single current block whose body alone (8,882 characters) exceeds the
# budget, plus one small LOG entry, on a compact. The block's header and
# an EARLY marker in its body ("Next step") must survive (truncation
# cuts from the END); the LOG entry, which would have fit on its own, is
# correctly sacrificed since the block already spent the whole budget.
proj_bigblock = make_project("bigblock")
big_body = "**Next step:** run the migration dry run.\n" + ("x" * 8838)
write_bytes(os.path.join(proj_bigblock, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body=big_body))
write_bytes(os.path.join(proj_bigblock, "briefs", "LOG.md"),
            "# Decision log\n\n" + log_entry(NOW - timedelta(hours=1), "e0", "short decision"))
r = run_hook(proj_bigblock, source="compact")
ctx = additional_context(r) or ""
check("oversized newest block keeps its header", "ALPHA CURRENT STATE" in ctx, repr(ctx[:200]))
check("an early marker in the body survives (truncated from the end)",
      "**Next step:** run the migration dry run." in ctx, repr(ctx[:200]))
check("a note names HANDOFF.md for the rest", "HANDOFF.md" in ctx and "truncated" in ctx, repr(ctx[-300:]))
check("oversized block stays capped at 8000 characters", len(ctx) <= 8000, "len=%d" % len(ctx))
check("the LOG entry does not sneak in (budget already spent on the block)",
      "short decision" not in ctx, repr(ctx))

# A third, older effort's block, coming after one that already needed
# truncation: it must not appear at all, not even its header. Once a
# block has been truncated the budget is spent by definition, so the
# loop over blocks must stop there (break) rather than keep checking
# whether something smaller still fits (continue) -- the same shape as
# the LOG-entries loop below, one level up.
proj_afterblock = make_project("afterblock")
write_bytes(os.path.join(proj_afterblock, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Alpha fits whole.\n") +
            handoff_block("BRAVO", NOW - timedelta(hours=2), body="b" * 8000) +
            handoff_block("CHARLIE", NOW - timedelta(hours=400), body="Charlie should never appear.\n"))
r = run_hook(proj_afterblock)
ctx = additional_context(r) or ""
check("a block after a truncated one does not appear at all, not even its header",
      "CHARLIE" not in ctx, repr(ctx[-300:]))
check("the truncated block (BRAVO) still keeps its own header", "BRAVO CURRENT STATE" in ctx, repr(ctx[:200]))

# Freeze windows alone (always kept, even past the cap) already exceeds
# CONTEXT_CAP before any block is even considered. The remaining budget
# for a block's body is then deeply negative; it must clamp to zero
# rather than being used as a negative slice index, which in Python
# counts from the end and would keep most of the body instead of none
# of it.
proj_freezeoverflow = make_project("freezeoverflow")
filler = "## Freeze windows\n\n" + ("f" * 8200)
write_bytes(os.path.join(proj_freezeoverflow, "briefs", "COORDINATION.md"),
            "# Coordination\n\n" + filler + "\n")
marker = "SECRETMARKER" * 50
write_bytes(os.path.join(proj_freezeoverflow, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body=marker + ("x" * 3000)))
r = run_hook(proj_freezeoverflow)
ctx = additional_context(r) or ""
check("a body budget clamps to zero rather than going negative", marker not in ctx, repr(ctx[-300:]))
check("Freeze windows itself still survives past the cap", "f" * 8200 in ctx, "len=%d" % len(ctx))

# "break, not continue" in the LOG-entries loop. Three entries: e2
# (newest) and e1 are both too big to fit in the roughly 2.4K characters
# left after the Freeze windows filler; e0 (oldest) is tiny and WOULD
# fit in that same leftover budget if the loop kept trying smaller older
# entries after e2 and e1 did not fit, instead of stopping at the first
# one that didn't fit. With "break" (what this code does), e0 never gets
# a chance even though it is small enough on its own -- proving the loop
# stops, it does not skip-and-continue. e1/e2 are sized well past the
# leftover budget (not just slightly over it) so only "continue" could
# let e0 slip in afterward; a narrower margin would pass either way.
proj_breaknotcontinue = make_project("breaknotcontinue")
filler = "## Freeze windows\n\n" + ("f" * 5500)
write_bytes(os.path.join(proj_breaknotcontinue, "briefs", "COORDINATION.md"),
            "# Coordination\n\n" + filler + "\n")
entries = (
    log_entry(NOW - timedelta(hours=2), "e0", "tiny")
    + "\n"
    + log_entry(NOW - timedelta(hours=1), "e1", "y" * 3000)
    + "\n"
    + log_entry(NOW, "e2", "z" * 3000)
    + "\n"
)
write_bytes(os.path.join(proj_breaknotcontinue, "briefs", "LOG.md"), "# Decision log\n\n" + entries)
r = run_hook(proj_breaknotcontinue)
ctx = additional_context(r) or ""
check("break, not continue -- the newest-but-oversized entry (e2) does not fit and stops the loop",
      "zzz" not in ctx, repr(ctx[-300:]))
check("break, not continue -- a smaller OLDER entry (e0) is not pulled in after e2 was skipped",
      "tiny" not in ctx, repr(ctx[-300:]))

# Compact staleness line: only on source == compact, and only when the
# newest block for an effort is actually stale (> 2h).
proj_stale = make_project("stale")
write_bytes(os.path.join(proj_stale, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=5), body="Stale alpha."))
r_compact = run_hook(proj_stale, source="compact")
ctx_compact = additional_context(r_compact) or ""
check("compact + stale block -> staleness line shown", "STALE HANDOFF" in ctx_compact and "ALPHA" in ctx_compact, repr(ctx_compact))
r_startup = run_hook(proj_stale, source="startup")
ctx_startup = additional_context(r_startup) or ""
check("startup + stale block -> no staleness line", "STALE HANDOFF" not in ctx_startup, repr(ctx_startup))

proj_fresh = make_project("fresh")
write_bytes(os.path.join(proj_fresh, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(minutes=5), body="Fresh alpha."))
r_compact_fresh = run_hook(proj_fresh, source="compact")
ctx_compact_fresh = additional_context(r_compact_fresh) or ""
check("compact + fresh block -> no staleness line", "STALE HANDOFF" not in ctx_compact_fresh, repr(ctx_compact_fresh))

# CLAUDE_BRIEFS_DIR: absolute.
proj_abs = tempfile.mkdtemp(prefix="session-context-test-abs-")
os.makedirs(os.path.join(proj_abs, ".git"))
ext_briefs = tempfile.mkdtemp(prefix="session-context-test-extbriefs-")
write_bytes(os.path.join(ext_briefs, "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nExternal freeze note.\n")
r = run_hook(proj_abs, env_extra={"CLAUDE_BRIEFS_DIR": ext_briefs})
ctx = additional_context(r) or ""
check("CLAUDE_BRIEFS_DIR absolute is used", "External freeze note." in ctx, repr(ctx))

# CLAUDE_BRIEFS_DIR: relative to the git root.
proj_rel = tempfile.mkdtemp(prefix="session-context-test-rel-")
os.makedirs(os.path.join(proj_rel, ".git"))
os.makedirs(os.path.join(proj_rel, "state", "briefs"))
write_bytes(os.path.join(proj_rel, "state", "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nRelative freeze note.\n")
r = run_hook(proj_rel, env_extra={"CLAUDE_BRIEFS_DIR": "state/briefs"})
ctx = additional_context(r) or ""
check("CLAUDE_BRIEFS_DIR relative is resolved against the git root", "Relative freeze note." in ctx, repr(ctx))

# Malformed stdin payload: must fail open (rc 0, no stdout), not crash.
r = run_hook(None, raw_stdin=b"not even json {")
check("malformed stdin -> rc 0, no stdout", r.returncode == 0 and not r.stdout.strip(),
      "rc=%d stdout=%r stderr=%r" % (r.returncode, r.stdout, r.stderr))

# Same, calling session_context.py DIRECTLY (bypassing the .sh wrapper,
# which has its own unconditional "exit 0" and so would mask a broken
# fail-open guard inside the .py file itself -- the wrapper always exits
# 0 whether or not Python's own try/except caught anything). This is the
# check that actually exercises session_context.py's own guard.
rdirect = subprocess.run([sys.executable, os.path.join(HOOKS_DIR, "session_context.py")],
                          input=b"not even json {", capture_output=True)
check("session_context.py itself fails open on malformed stdin (rc 0, no traceback)",
      rdirect.returncode == 0 and not rdirect.stdout.strip() and b"Traceback" not in rdirect.stderr,
      "rc=%d stdout=%r stderr=%r" % (rdirect.returncode, rdirect.stdout, rdirect.stderr))

# A file that raises on read (a directory sitting where HANDOFF.md should
# be: open() raises on every platform, just with a different exception
# type). The other files must still contribute.
proj_unreadable = make_project("unreadable")
os.makedirs(os.path.join(proj_unreadable, "briefs", "HANDOFF.md"))
write_bytes(os.path.join(proj_unreadable, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nStill readable.\n")
r = run_hook(proj_unreadable)
ctx = additional_context(r) or ""
check("unreadable HANDOFF.md does not break the whole hook", "Still readable." in ctx, repr(ctx))
check("unreadable HANDOFF.md -> rc 0", r.returncode == 0)

# BOM in the STDIN PAYLOAD itself (what a PowerShell pipe adds by
# default), distinct from a BOM in a briefs file: without utf-8-sig on
# the payload decode, json.loads would raise and the hook would fail
# open with nothing injected, even though the briefs files are fine.
proj_stdinbom = make_project("stdinbom")
write_bytes(os.path.join(proj_stdinbom, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body="Stdin BOM test body."))
bom_payload = b"\xef\xbb\xbf" + json.dumps(
    {"session_id": "t", "cwd": proj_stdinbom, "hook_event_name": "SessionStart", "source": "startup"}
).encode()
r = run_hook(None, raw_stdin=bom_payload)
ctx = additional_context(r) or ""
check("BOM in the stdin payload is tolerated", "Stdin BOM test body." in ctx, repr(ctx))

# find_git_root walks UP from a nested cwd, not just checks it directly.
proj_nested = make_project("nested")
write_bytes(os.path.join(proj_nested, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nNested cwd freeze note.\n")
nested_cwd = os.path.join(proj_nested, "src", "deep", "nested", "dir")
os.makedirs(nested_cwd, exist_ok=True)
r = run_hook(nested_cwd)
ctx = additional_context(r) or ""
check("git root is found by walking up from a nested cwd", "Nested cwd freeze note." in ctx, repr(ctx))

# Fresh templates: a project created by new-project copies
# LOG.md.template and COORDINATION.md.template as-is. Their sample
# entries are wrapped in HTML comments, which the hook strips before
# parsing, so a project that has never written a real entry yet must
# inject NOTHING -- not the placeholder's own "<...>" text.
REPO_ROOT = os.path.dirname(HOOKS_DIR)
proj_freshtpl = make_project("freshtpl")
shutil.copyfile(
    os.path.join(REPO_ROOT, "templates", "project", "LOG.md.template"),
    os.path.join(proj_freshtpl, "briefs", "LOG.md"),
)
shutil.copyfile(
    os.path.join(REPO_ROOT, "templates", "project", "COORDINATION.md.template"),
    os.path.join(proj_freshtpl, "briefs", "COORDINATION.md"),
)
r = run_hook(proj_freshtpl)
check("a freshly-templated project injects nothing (placeholders are HTML comments)",
      r.returncode == 0 and additional_context(r) is None,
      "rc=%d stdout=%r" % (r.returncode, r.stdout))

# Worktree: a lane's cwd is a worktree whose own ".git" is a FILE
# ("gitdir: <main>/.git/worktrees/<name>"), not a directory. Built by
# hand (not `git worktree add`) so this test needs no git binary and
# never mutates a real repository; it exercises the exact on-disk shape
# git itself writes for a worktree, which is what find_main_repo_root
# actually parses.
wt_main = tempfile.mkdtemp(prefix="session-context-test-wtmain-")
os.makedirs(os.path.join(wt_main, ".git", "worktrees", "lane1"), exist_ok=True)
os.makedirs(os.path.join(wt_main, "briefs"), exist_ok=True)
write_bytes(os.path.join(wt_main, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nMain checkout freeze note.\n")
wt_lane = tempfile.mkdtemp(prefix="session-context-test-wtlane-")
with open(os.path.join(wt_lane, ".git"), "w", encoding="utf-8") as fh:
    fh.write("gitdir: %s\n" % os.path.join(wt_main, ".git", "worktrees", "lane1"))

r = run_hook(wt_lane)
ctx = additional_context(r) or ""
check("a worktree with no briefs/ of its own falls back to the main checkout's",
      "Main checkout freeze note." in ctx, repr(ctx))

lane_briefs = os.path.join(wt_lane, "briefs")
os.makedirs(lane_briefs, exist_ok=True)
write_bytes(os.path.join(lane_briefs, "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nLane's own freeze note.\n")
r = run_hook(wt_lane)
ctx = additional_context(r) or ""
check("a worktree's own briefs/ takes priority over the main checkout's",
      "Lane's own freeze note." in ctx and "Main checkout freeze note." not in ctx, repr(ctx))

# A RELATIVE CLAUDE_BRIEFS_DIR, set while running inside a worktree,
# resolves against the WORKTREE's own root, not the main checkout's --
# the chosen, documented rule (see resolve_briefs_dir's docstring): an
# explicit override is the user's own choice of path, read literally
# against "the git root this session is in," not reinterpreted through
# the separate (and unrelated) main-checkout fallback that only applies
# when there is no override at all.
wt_lane_relbriefs = os.path.join(wt_lane, "state", "briefs")
os.makedirs(wt_lane_relbriefs, exist_ok=True)
write_bytes(os.path.join(wt_lane_relbriefs, "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nLane-relative-override freeze note.\n")
r = run_hook(wt_lane, env_extra={"CLAUDE_BRIEFS_DIR": "state/briefs"})
ctx = additional_context(r) or ""
check("a relative CLAUDE_BRIEFS_DIR in a worktree resolves against the worktree root",
      "Lane-relative-override freeze note." in ctx, repr(ctx))

# A "python3" candidate that resolves on PATH and answers `-c 1` fine,
# but whose REAL invocation fails to exec (rc 126) -- the wrapper must
# move on to the next candidate rather than treating that as "no
# interpreter at all" or, worse, as session_context.py's own (silent)
# result.
fallback_dir = make_fake_python_dir("session-context-test-fakepy-", REAL_PYTHON_BODY)
proj_execfail = make_project("execfail")
write_bytes(os.path.join(proj_execfail, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nExec-fail fallback freeze note.\n")
r = run_hook(proj_execfail, env_extra={"PATH": fallback_dir + os.pathsep + BASE_ENV["PATH"]})
ctx = additional_context(r) or ""
check("a python3 that fails the real exec (not just -c 1) falls through to python",
      "Exec-fail fallback freeze note." in ctx, repr(ctx))

# Every candidate fails to exec (python3 AND python both answer `-c 1`
# but refuse the real run): still fails open -- rc 0, nothing on
# stdout, same as "no interpreter found at all".
allfail_dir = make_fake_python_dir("session-context-test-fakepyall-", FAKE_EXEC_FAIL_BODY)
proj_execfailall = make_project("execfailall")
write_bytes(os.path.join(proj_execfailall, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nShould never appear.\n")
r = run_hook(proj_execfailall, env_extra={"PATH": allfail_dir + os.pathsep + BASE_ENV["PATH"]})
check("every candidate failing to exec still fails open",
      r.returncode == 0 and not r.stdout.strip(), "rc=%d stdout=%r" % (r.returncode, r.stdout))

# A "python3" shaped like the WindowsApps stub with NO Python installed
# at all (FAKE_STORE_BODY, rc 9009, not 126/127): a retry that only
# checks for 126/127 would wrongly trust this rc as session_context.py's
# own result and stop there instead of trying "python" next.
store_fallback_dir = make_fake_python_dir("session-context-test-store-", REAL_PYTHON_BODY, python3_body=FAKE_STORE_BODY)
proj_store = make_project("storefallback")
write_bytes(os.path.join(proj_store, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nStore-stub fallback freeze note.\n")
r = run_hook(proj_store, env_extra={"PATH": store_fallback_dir + os.pathsep + BASE_ENV["PATH"]})
ctx = additional_context(r) or ""
check("a python3 that exits 9009 (the Store stub, no Python installed) falls through to python",
      "Store-stub fallback freeze note." in ctx, repr(ctx))

# Both candidates are the Store stub (rc 9009 either way): still fails
# open, same as any other "no candidate ever ran" shape.
store_allfail_dir = make_fake_python_dir("session-context-test-storeall-", FAKE_STORE_BODY, python3_body=FAKE_STORE_BODY)
proj_storeall = make_project("storefallall")
write_bytes(os.path.join(proj_storeall, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nShould never appear.\n")
r = run_hook(proj_storeall, env_extra={"PATH": store_allfail_dir + os.pathsep + BASE_ENV["PATH"]})
check("both candidates as the Store stub (rc 9009) still fails open",
      r.returncode == 0 and not r.stdout.strip(), "rc=%d stdout=%r" % (r.returncode, r.stdout))

# A hanging candidate (answers `-c 1`, then never exits on the real
# run): both candidates hang here, so the wrapper must fail open -- and
# do it within the 4s per candidate limit, not wait out the full 60s
# sleep each fake interpreter would otherwise impose. Checked against
# Claude Code's own 20s hook timeout, the real limit that matters, not
# an arbitrary round number.
HOOK_TIMEOUT = 20
hang_dir = make_fake_python_dir("session-context-test-hang-", FAKE_HANG_BODY, python3_body=FAKE_HANG_BODY)
proj_hang = make_project("hang")
write_bytes(os.path.join(proj_hang, "briefs", "COORDINATION.md"),
            "# Coordination\n\n## Freeze windows\n\nShould never appear.\n")
hang_start = time.monotonic()
r = run_hook(proj_hang, env_extra={"PATH": hang_dir + os.pathsep + BASE_ENV["PATH"]})
hang_elapsed = time.monotonic() - hang_start
check("hanging candidates still fail open within the hook timeout",
      r.returncode == 0 and not r.stdout.strip(), "rc=%d stdout=%r" % (r.returncode, r.stdout))
check("the hanging-candidate call finishes under the 20s hook timeout",
      hang_elapsed < HOOK_TIMEOUT, "%.1fs" % hang_elapsed)

# Per-profile session-context cap: sessionContextChars in the installed
# record (<HOME>/.claude/claude-setup-profile.json) caps
# additionalContext at that many characters instead of
# DEFAULT_CONTEXT_CAP (8000). Uses its OWN fake HOME (not the shared one
# above), so writing a record there cannot affect any other test in
# this file.
cap_home = tempfile.mkdtemp(prefix="session-context-test-caphome-")
os.makedirs(os.path.join(cap_home, ".claude", "hooks"), exist_ok=True)
shutil.copyfile(os.path.join(HOOKS_DIR, "session_context.py"), os.path.join(cap_home, ".claude", "hooks", "session_context.py"))
write_bytes(os.path.join(cap_home, ".claude", "claude-setup-profile.json"),
            json.dumps({"name": "lite", "sessionContextChars": 3000}))
proj_cap3000 = make_project("cap3000")
big_body = "**Next step:** stay under the smaller cap.\n" + ("x" * 3200)
write_bytes(os.path.join(proj_cap3000, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body=big_body))
r = run_hook(proj_cap3000, env_extra={"HOME": cap_home})
ctx = additional_context(r) or ""
check("lite's sessionContextChars (3000) caps additionalContext, not the 8000 default",
      len(ctx) <= 3000, "len=%d" % len(ctx))
check("the smaller cap actually did something (truncation happened, not a coincidence)",
      "truncated" in ctx, repr(ctx[-200:]))

# A record missing the key (not a missing record -- every OTHER test in
# this file already covers that) still falls back to the 8000 default.
write_bytes(os.path.join(cap_home, ".claude", "claude-setup-profile.json"),
            json.dumps({"name": "lite"}))
proj_capfallback = make_project("capfallback")
write_bytes(os.path.join(proj_capfallback, "briefs", "HANDOFF.md"),
            handoff_block("ALPHA", NOW - timedelta(hours=1), body=big_body))
r = run_hook(proj_capfallback, env_extra={"HOME": cap_home})
ctx = additional_context(r) or ""
check("a record missing sessionContextChars falls back to the 8000 default (no truncation for a 3200-char body)",
      "truncated" not in ctx, repr(ctx[-200:]))
shutil.rmtree(cap_home, ignore_errors=True)

print("\n%d passed, %d failed" % (total - fails, fails))
sys.exit(1 if fails else 0)
