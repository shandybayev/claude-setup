import json, os, shutil, subprocess, sys, tempfile, time

HOOKS_DIR = os.path.dirname(os.path.abspath(__file__))
WRAPPER = os.path.join(HOOKS_DIR, "git_guard.sh")

# git_guard.sh hard-codes "$HOME/.claude/hooks/git_guard.py" (correct in
# production, where that path is a link back into this repo). Run from the
# repo UNINSTALLED, $HOME is the developer's real home, and
# $HOME/.claude/hooks/git_guard.py is whatever is already deployed there,
# not this file -- so a run against this checkout would silently grade a
# different, possibly older, copy of the policy and call it a pass. A fake
# HOME whose .claude/hooks holds THIS repo's git_guard.py (and the wrapper,
# which the fake git_guard.sh itself does not re-read) makes every
# subprocess call exercise the file actually being edited.
_FAKE_HOME_DIR = tempfile.TemporaryDirectory(prefix="git-guard-test-home-")
FAKE_HOME = _FAKE_HOME_DIR.name
_fake_hooks = os.path.join(FAKE_HOME, ".claude", "hooks")
os.makedirs(_fake_hooks, exist_ok=True)
shutil.copyfile(os.path.join(HOOKS_DIR, "git_guard.py"), os.path.join(_fake_hooks, "git_guard.py"))
TEST_ENV = dict(os.environ, HOME=FAKE_HOME)


def find_bash():
    """Locate a bash to run the wrapper under. The usual Git for Windows
    install locations come FIRST, deliberately ahead of shutil.which: recent
    Windows ships its own System32\\bash.exe that only forwards to WSL, and
    on a machine with WSL absent or unconfigured that stub wins a plain PATH
    search and fails at exec time, masquerading as "no bash". Mac/Linux has
    no such stub, so shutil.which there is reliable and comes last here
    simply because it is also the right fallback on a Windows box that only
    has Git Bash on PATH, with no copy at either fixed path."""
    for candidate in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ):
        if os.path.exists(candidate):
            return candidate
    return shutil.which("bash")


GITBASH = find_bash()
if not GITBASH:
    # Exit non-zero, not 0: a bare SKIP that "passes" looks identical to a
    # real green run in any runner that only checks the exit code, which is
    # exactly how a missing-bash environment could look safe while the guard
    # it is meant to verify was never actually exercised.
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
# wrongly trusted this as git_guard.py's own (final) result, letting a
# subagent's git write through unguarded (rc 9009 is a non-blocking
# error to Claude Code, not a deny).
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
# so the next candidate (or the fallback) still gets a chance.
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
    PREPENDED to PATH (not used as the whole PATH: grep, sed, and
    bash's other external tools still need to resolve from the real
    PATH). python_body is FAKE_EXEC_FAIL_BODY or FAKE_STORE_BODY again
    to simulate every candidate failing to exec, or a stub that execs
    the REAL interpreter running this test (sys.executable, not
    whatever "python3"/"python" happen to resolve to on PATH -- on this
    machine that IS the flaky alias being tested around) to simulate
    the second candidate actually working.
    """
    d = tempfile.mkdtemp(prefix=prefix)
    for name, body in (("python3", python3_body), ("python", python_body)):
        path = os.path.join(d, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(body)
        os.chmod(path, 0o755)
    return d


REAL_PYTHON_BODY = '#!/usr/bin/env bash\nexec "%s" "$@"\n' % to_posix_path(sys.executable)

# (who, command, expected) ; who: "sub" or "main" ; expected: deny / ask / pass
CASES = [
    # subagent: must DENY git writes
    ("sub", "git commit -m 'x'", "deny"),
    ("sub", "git add -A", "deny"),
    ("sub", "git push origin feat", "deny"),
    ("sub", "cd repo && git stash", "deny"),
    ("sub", "git -C /some/path checkout main", "deny"),
    ("sub", "git -c user.name=x commit -m y", "deny"),
    ("sub", "bash -c \"git reset --hard\"", "deny"),
    ("sub", "git branch -D old", "deny"),
    ("sub", "git branch newbranch", "deny"),
    ("sub", "git config user.name bob", "deny"),
    ("sub", "git worktree add ../x", "deny"),
    ("sub", "/usr/bin/git merge main", "deny"),
    ("sub", "echo hi; git restore file.py", "deny"),
    # subagent: must DENY gh writes
    ("sub", "gh pr create --title x", "deny"),
    ("sub", "gh pr comment 30 --body hi", "deny"),
    ("sub", "gh api repos/o/r/issues/1/comments -f body=hi", "deny"),
    ("sub", "gh api repos/o/r/pulls/1 -X PATCH", "deny"),
    # subagent: must PASS reads (false positives would break builders)
    ("sub", "git status --short", "pass"),
    ("sub", "git diff HEAD --stat", "pass"),
    ("sub", "git log --oneline -3", "pass"),
    ("sub", "git show origin/master:app/x.py", "pass"),
    ("sub", "git branch --show-current", "pass"),
    ("sub", "git branch -a", "pass"),
    ("sub", "git config --get user.name", "pass"),
    ("sub", "git fetch origin", "pass"),
    ("sub", "git rev-parse HEAD", "pass"),
    ("sub", "grep -rn \"git add\" docs/", "pass"),
    ("sub", "python -m pytest tests/ -q", "pass"),
    ("sub", "gh pr view 30 --json state", "pass"),
    ("sub", "gh api repos/o/r/pulls/30/reviews --jq '.[].state'", "pass"),
    ("sub", "gh api search/issues -X GET -f q=repo:o/r", "pass"),
    ("sub", "echo highlight through", "pass"),
    # main session: git and gh writes are NOT the hook's job (settings ask rules)
    ("main", "git commit -m 'x'", "pass"),
    ("main", "git push origin feat", "pass"),
    ("main", "git --git-dir=\"$HOME/.claude-config.git\" --work-tree=\"$HOME/.claude\" push -u origin main", "pass"),
    ("main", "git -C \"/c/some path/repo\" push", "pass"),
    ("main", "cd repo && git -c http.x=y push --force-with-lease", "pass"),
    ("main", "git --git-dir=\"$HOME/.claude-config.git\" --work-tree=\"$HOME/.claude\" log --oneline", "pass"),
    ("main", "git log --grep push", "pass"),
    ("sub", "git --git-dir=\"/x y/.git\" --work-tree=/w push", "deny"),
    ("main", "gh pr create --title x", "pass"),
    ("main", "gh api repos/o/r/issues/1/comments -f body=hi", "pass"),
    ("main", "gh api repos/o/r/pulls/30/requested_reviewers -X POST -f 'reviewers[]=j'", "pass"),
    ("main", "gh api repos/o/r/pulls/30 --method DELETE", "pass"),
    ("main", "gh api repos/o/r/pulls/30/reviews --jq '.[].state'", "pass"),
    ("main", "gh api search/issues -X GET -f q=x", "pass"),
    ("main", "cd x && gh api repos/o/r/issues/1/comments --input body.json", "pass"),
    # non-Bash tools are ignored
]

# PowerShell-shaped commands: same tool_input.command field, but the
# matcher covers the PowerShell tool_name too, not just Bash, so a
# subagent running the same git write through PowerShell is guarded the
# same way. Exercises ";" and "&" as command separators (both already in
# the shared _START pattern), a bare "git.exe" (already optional in the
# git pattern), and a backtick-newline continuation splitting "git" from
# its verb across two lines.
PS_CASES = [
    ("sub", "git commit -m 'x'", "deny"),
    ("sub", "git.exe commit -m 'x'", "deny"),
    ("sub", "git add -A", "deny"),
    ("sub", "& git push origin feat", "deny"),
    ("sub", "Get-Location; git stash", "deny"),
    ("sub", "git `\n  commit -m 'x'", "deny"),
    ("sub", "git.exe `\n  push origin feat", "deny"),
    ("sub", "& gh pr create --title x", "deny"),
    ("sub", "gh.exe api repos/o/r/issues/1/comments -f body=hi", "deny"),
    # reads must still pass, same as under Bash
    ("sub", "git status --short", "pass"),
    ("sub", "git.exe log --oneline -3", "pass"),
    ("sub", "Write-Host 'remember to run git add later'", "pass"),
    ("sub", "gh pr view 30 --json state", "pass"),
    # main session is still not gated per command
    ("main", "git commit -m 'x'", "pass"),
    ("main", "& gh pr create --title x", "pass"),
]

# Guard gaps: PowerShell and Bash shapes that let a git write through
# where the policy wants deny (a conditional, a pipeline, a loop body),
# plus a read-only counterpart for each one so a false positive does not
# break a builder's normal workflow.
GAP_CASES = [
    ("sub", "try { git commit -m x } catch {}", "deny"),
    ("sub", "if ($true) { git push origin feat }", "deny"),
    ("sub", "1 | ForEach-Object { git add -A }", "deny"),
    ("sub", "& 'git' commit -m x", "deny"),
    ("sub", '& "C:\\Program Files\\Git\\cmd\\git.exe" commit -m x', "deny"),
    ("sub", "$r = git commit -m x", "deny"),
    ("sub", "Start-Process git -ArgumentList commit -m x", "deny"),
    ("sub", "Invoke-Expression 'git commit -m x'", "deny"),
    ("sub", "cmd /c git commit -m x", "deny"),
    # a backtick inside the word itself (g`it): PowerShell reads this as
    # the plain word "git", a cheap way to dodge a literal-text match.
    ("sub", "g`it commit -m x", "deny"),
    # each DENY case above, same shape, but a read-only git subcommand --
    # must still pass, or the fix would just trade false negatives for
    # false positives on every builder's normal read commands.
    ("sub", "try { git status } catch {}", "pass"),
    ("sub", "if ($true) { git log }", "pass"),
    ("sub", "1 | ForEach-Object { git log }", "pass"),
    ("sub", "& 'git' status", "pass"),
    ("sub", '& "C:\\Program Files\\Git\\cmd\\git.exe" log', "pass"),
    ("sub", "$r = git log", "pass"),
    ("sub", "Invoke-Expression 'git status'", "pass"),
    ("sub", "cmd /c git status", "pass"),
]

BASH_GAP_CASES = [
    ("sub", "{ git commit; }", "deny"),
    ("sub", "if true; then git push; fi", "deny"),
    ("sub", "for i in 1 2 3; do git add -A; done", "deny"),
    ("sub", "{ git status; }", "pass"),
    ("sub", "if true; then git status; fi", "pass"),
    ("sub", "for i in 1 2 3; do git log; done", "pass"),
    # "then"/"do"/"else" are common English words; they must only trigger
    # as a shell keyword right after a real separator, not anywhere in text.
    ("sub", "echo 'and then git log shows it'", "pass"),
    ("sub", "echo 'what to do git-wise later'", "pass"),
]

# A handful of everyday Bash and PowerShell shapes (env vars before the
# command, an if/while around a git write) that must still deny. Each
# has a read-only counterpart right below it.
EVERYDAY_BASH_CASES = [
    ("sub", "GIT_EDITOR=true git merge main", "deny"),
    ("sub", "FOO=1 BAR=2 git push", "deny"),
    ("sub", "if git commit -m x; then echo ok; fi", "deny"),
    ("sub", "while true; do git push; done", "deny"),
    ("sub", "! git commit -m x", "deny"),
    ("sub", "timeout 60 git push origin feat", "deny"),
    ("sub", "command git commit -m x", "deny"),
    ("sub", "GIT_EDITOR=true git status", "pass"),
    ("sub", "FOO=1 BAR=2 git log", "pass"),
    ("sub", "if git diff --quiet; then echo clean; fi", "pass"),
    ("sub", "while true; do git log; done", "pass"),
    ("sub", "! git diff --quiet", "pass"),
    ("sub", "timeout 60 git status", "pass"),
    ("sub", "command git log", "pass"),
    # an env-var-shaped "=" inside a quoted string, no real command there
    ("sub", 'echo "result=git-friendly text FOO=1"', "pass"),
]

EVERYDAY_PS_CASES = [
    ("sub", 'cmd /c "git commit -m x"', "deny"),
    ("sub", 'powershell -Command "git commit -m x"', "deny"),
    ("sub", "Start-Process git -ArgumentList 'commit','-m','x'", "deny"),
    ('sub', 'Start-Process -FilePath "git.exe" -ArgumentList "push"', "deny"),
    ("sub", 'cmd /c "git status"', "pass"),
    ("sub", 'powershell -Command "git log"', "pass"),
    ("sub", "Start-Process git -ArgumentList 'status'", "pass"),
]

fails = 0
total = 0


def run_cases(cases, tool_name, label):
    global fails, total
    for who, cmd, expected in cases:
        payload = {"tool_name": tool_name, "tool_input": {"command": cmd}, "session_id": "t"}
        if who == "sub":
            payload["agent_id"] = "abc-123"
            payload["agent_type"] = "builder"
        r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=TEST_ENV)
        out = r.stdout.decode().strip()
        got = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
        ok = got == expected and r.returncode == 0
        fails += not ok
        total += 1
        print(("OK  " if ok else "FAIL") + f" {label}{who:4} {expected:5} got={got:5} rc={r.returncode}  {cmd!r}")
        if r.stderr:
            print("     stderr:", r.stderr.decode().strip())


run_cases(CASES, "Bash", "")
run_cases(PS_CASES, "PowerShell", "ps:")
run_cases(GAP_CASES, "PowerShell", "gap:")
run_cases(BASH_GAP_CASES, "Bash", "bgap:")
run_cases(EVERYDAY_BASH_CASES, "Bash", "everyday:")
run_cases(EVERYDAY_PS_CASES, "PowerShell", "everydayps:")

# a non-Bash tool must pass: valid JSON, decide() runs normally and
# returns (None, None) since "Edit" is neither Bash nor PowerShell, never
# touching the undecidable-payload fallback below at all.
r = subprocess.run(
    [GITBASH, WRAPPER],
    input=json.dumps({"tool_name": "Edit", "tool_input": {"file_path": "git"}, "agent_id": "a"}).encode(),
    capture_output=True, env=TEST_ENV,
)
ok = r.returncode == 0 and not r.stdout.strip()
fails += not ok
total += 1
print(("OK  " if ok else "FAIL") + f" non-Bash tool: rc={r.returncode} stdout={r.stdout.decode().strip()!r}")

# An undecidable payload fails CLOSED (exit 2, deny) unless it is
# "clearly main" -- decodes, looks like a COMPLETE JSON object (braces
# balanced, not just first/last character: a payload truncated right
# after a NESTED object still ends in "}" from that inner object), and
# has no agent_id text anywhere. Short of all three, it is a subagent.
for label, data, want_rc in [
    # unparseable, but agent_id is visible in the raw text -> blocked
    ('unparseable + agent_id -> blocked', '{not json but "agent_id": "abc-123" is right there', 2),
    # looks like a complete object (braces balance), a syntax error (no
    # comma) but no agent_id anywhere -> clearly main, allowed
    ('unparseable but complete, no agent_id -> allowed', '{"tool_name": "Bash" "tool_input": {"command": "git status"}}', 0),
    # NOT a JSON object at all (no braces) and no agent_id -> still a
    # subagent: "no visible agent_id" alone is not enough to read this as
    # main, only a complete-looking object with no agent_id is.
    ('not JSON-shaped at all, no agent_id -> blocked', "{not json git", 2),
    # truncated right after a NESTED object closes, before the outer
    # object (and the agent_id field after it) was ever reached: this is
    # the exact shape that used to read as main by mistake, since a naive
    # endswith("}") check is satisfied by the INNER object's closing
    # brace. Must be blocked.
    ('truncated after a nested object, before agent_id -> blocked',
     '{"tool_name": "Bash", "tool_input": {"command": "git status"}', 2),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=data.encode(), capture_output=True, env=TEST_ENV)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")

# CAREFUL (F4): a real, well-formed main-session payload, in the actual
# shape Claude Code sends (several fields beyond tool_name/tool_input, and
# critically no agent_id key at all) must still be allowed. This goes
# through the NORMAL decide() path, not the undecidable fallback -- the
# point is proving the F4 changes above did not touch that path.
real_main_payload = {
    "session_id": "abc123-session",
    "transcript_path": "/home/user/.claude/projects/foo/abc123.jsonl",
    "cwd": "/home/user/project",
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": "git commit -m \"a real commit\"", "description": "Commit changes"},
}
r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(real_main_payload).encode(), capture_output=True, env=TEST_ENV)
ok = r.returncode == 0 and not r.stdout.strip()
fails += not ok
total += 1
print(("OK  " if ok else "FAIL") + f" real main-session payload shape -> allowed: rc={r.returncode} stdout={r.stdout.decode().strip()!r}")

# The same fail-closed rule, one layer earlier: no working Python
# interpreter at all means git_guard.py never runs, so the wrapper
# itself must apply the fail-closed-for-a-subagent rule using its own
# raw-text sniff. PATH is narrowed to just bash's own directory for this
# one call so neither python3 nor python can be found, without
# disturbing any other test.
no_python_env = dict(TEST_ENV)
no_python_env["PATH"] = os.path.dirname(GITBASH)
for label, payload, want_rc in [
    ("no python, subagent -> blocked", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, 2),
    ("no python, main session -> allowed", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}}, 0),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=no_python_env)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")

# G1/G2: the sh fallback's brace count must ignore braces INSIDE a JSON
# string, the same way git_guard.py's real string-aware counter does.
for label, payload, want_rc in [
    # G1: a main command with an unbalanced brace in a quoted argument
    # (a real, everyday shape -- `sed`, `Write-Host '{'`) must still be
    # allowed with no Python. Before the fix, the raw "{"/"}" count saw
    # the lone "{" from inside the command string, read the payload as
    # unbalanced, and blocked the MAIN session over a brace that was
    # never part of the JSON structure at all.
    ('G1: unbalanced brace in a quoted arg, main session -> allowed',
     {"tool_name": "Bash", "tool_input": {"command": 'git log --format="%H" | sed "s/{/(/"'}},
     0),
    # G2: a subagent payload truncated before the agent_id field, with a
    # "}" inside the command string, must be blocked by the sh fallback
    # the same way git_guard.py blocks it -- the point G2 raised was that
    # the two layers disagreed here (py closed, sh open) specifically
    # because of the un-stripped brace inside the string.
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=no_python_env)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")

# G2's truncated case needs hand-built raw bytes (a real json.dumps would
# never produce a cut-off object), one for each layer, proving sh and py
# agree given the identical input.
g2_truncated = b'{"tool_name": "Bash", "tool_input": {"command": "echo }; git commit -m x"}'
for label, env in [("G2: sh fallback, truncated + brace-in-string -> blocked", no_python_env),
                    ("G2: py layer, same payload -> blocked", TEST_ENV)]:
    r = subprocess.run([GITBASH, WRAPPER], input=g2_truncated, capture_output=True, env=env)
    ok = r.returncode == 2
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want 2) stderr={r.stderr.decode().strip()!r}")

# F3: git_guard.py itself missing (a partial copy, or a rename on a pull)
# must NOT wedge the main session. Before the fix, the wrapper always ran
# `"$py" "$guard_py"` and exited with Python's own status; with the .py
# missing, CPython exits 2 ("can't open file"), which the wrapper then
# propagated as a BLOCK -- for the main session too, since the wrapper
# never checked whose call it was before running Python at all. A fake
# HOME with hooks/git_guard.sh but no hooks/git_guard.py reproduces this
# without touching the real interpreter-missing path above.
missing_py_home = tempfile.mkdtemp(prefix="git-guard-test-missing-py-")
os.makedirs(os.path.join(missing_py_home, ".claude", "hooks"), exist_ok=True)
missing_py_env = dict(TEST_ENV, HOME=missing_py_home)
for label, payload, want_rc in [
    ("git_guard.py missing, subagent -> blocked", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, 2),
    ("git_guard.py missing, main session -> allowed", {"tool_name": "Bash", "tool_input": {"command": "git status"}}, 0),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=missing_py_env)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")
shutil.rmtree(missing_py_home, ignore_errors=True)

# A BOM-prefixed payload (what a PowerShell pipe adds by default to stdout)
# must still be decided correctly, not silently fail open the way a plain
# "utf-8" decode used to (json.loads chokes on the leading BOM, which the
# broad except then turned into a no-decision pass). Built as raw bytes,
# not through json.dumps, since the point is to corrupt the JSON envelope
# itself, not the command text inside it.
bom_payload = b"\xef\xbb\xbf" + json.dumps({
    "tool_name": "PowerShell",
    "tool_input": {"command": "git commit -m x"},
    "agent_id": "abc-123",
}).encode()
r = subprocess.run([GITBASH, WRAPPER], input=bom_payload, capture_output=True, env=TEST_ENV)
out = r.stdout.decode().strip()
got = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
ok = got == "deny" and r.returncode == 0
fails += not ok
total += 1
print(("OK  " if ok else "FAIL") + f" bom-payload deny got={got} rc={r.returncode}")

# A "python3" candidate that resolves on PATH and answers `-c 1` fine,
# but whose REAL invocation fails to exec (rc 126) -- the wrapper must
# move on to the next candidate and run the REAL git_guard.py there,
# not fall back to the raw-text sniff (which would still get the right
# answer here, but for the wrong reason, and would not for every shape
# the raw sniff cannot fully replicate).
fallback_dir = make_fake_python_dir("git-guard-test-fakepy-", REAL_PYTHON_BODY)
fallback_env = dict(TEST_ENV, PATH=fallback_dir + os.pathsep + TEST_ENV["PATH"])
# A normal decision from the REAL git_guard.py always exits 0 (the
# decision itself travels as JSON, not the process exit code; exit 2 is
# only the wrapper's OWN fallback below, for when git_guard.py cannot
# run or cannot decide at all) -- so this checks the JSON decision, the
# same way run_cases() does for every other real-git_guard.py case.
for label, payload, want_decision in [
    ("python3 fails real exec, subagent -> blocked by the real git_guard.py",
     {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, "deny"),
    ("python3 fails real exec, main session -> allowed by the real git_guard.py",
     {"tool_name": "Bash", "tool_input": {"command": "git status"}}, "pass"),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=fallback_env)
    out = r.stdout.decode().strip()
    got = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
    ok = got == want_decision and r.returncode == 0
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: got={got} (want {want_decision}) rc={r.returncode} stderr={r.stderr.decode().strip()!r}")

# Every candidate fails to exec (python3 AND python both answer `-c 1`
# but refuse the real run): same fail-closed-for-a-subagent,
# fail-open-for-main rule as "no interpreter found at all", using the
# wrapper's own raw-text sniff.
allfail_dir = make_fake_python_dir("git-guard-test-fakepyall-", FAKE_EXEC_FAIL_BODY)
allfail_env = dict(TEST_ENV, PATH=allfail_dir + os.pathsep + TEST_ENV["PATH"])
for label, payload, want_rc in [
    ("every candidate fails real exec, subagent -> blocked", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, 2),
    ("every candidate fails real exec, main session -> allowed", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}}, 0),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=allfail_env)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")

# A "python3" shaped like the WindowsApps stub with NO Python installed
# at all (FAKE_STORE_BODY, rc 9009, not 126/127, and not 0 or 2 either):
# a retry that only checks for 126/127 would wrongly trust this rc as
# git_guard.py's own result and stop there -- which for a subagent's
# git write means ALLOWED instead of denied, since rc 9009 itself is a
# non-blocking error to Claude Code. The real fix must fall through to
# "python" instead.
store_fallback_dir = make_fake_python_dir("git-guard-test-store-", REAL_PYTHON_BODY, python3_body=FAKE_STORE_BODY)
store_fallback_env = dict(TEST_ENV, PATH=store_fallback_dir + os.pathsep + TEST_ENV["PATH"])
for label, payload, want_decision in [
    ("python3 exits 9009 (Store stub), subagent -> blocked by the real git_guard.py",
     {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, "deny"),
    ("python3 exits 9009 (Store stub), main session -> allowed by the real git_guard.py",
     {"tool_name": "Bash", "tool_input": {"command": "git status"}}, "pass"),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=store_fallback_env)
    out = r.stdout.decode().strip()
    got = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
    ok = got == want_decision and r.returncode == 0
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: got={got} (want {want_decision}) rc={r.returncode} stderr={r.stderr.decode().strip()!r}")

# Both candidates are the Store stub (rc 9009 either way): same
# fail-closed-for-a-subagent, fail-open-for-main rule as "no interpreter
# found at all".
store_allfail_dir = make_fake_python_dir("git-guard-test-storeall-", FAKE_STORE_BODY, python3_body=FAKE_STORE_BODY)
store_allfail_env = dict(TEST_ENV, PATH=store_allfail_dir + os.pathsep + TEST_ENV["PATH"])
for label, payload, want_rc in [
    ("both candidates as the Store stub (9009), subagent -> blocked", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, 2),
    ("both candidates as the Store stub (9009), main session -> allowed", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}}, 0),
]:
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=store_allfail_env)
    ok = r.returncode == want_rc
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) stderr={r.stderr.decode().strip()!r}")

# A hanging candidate (answers `-c 1`, then never exits on the real
# run): both candidates hang here, so the wrapper must fall all the way
# through to the no-interpreter fallback -- and do it within the 4s per
# candidate limit, not wait out the full 60s sleep each fake interpreter
# would otherwise impose. Each call's own elapsed time is checked
# against Claude Code's 20s hook timeout individually (not the two
# calls added together): a 21s call next to a 7s one would pass a
# combined-under-30s check despite one single call already blowing the
# real limit that matters.
hang_dir = make_fake_python_dir("git-guard-test-hang-", FAKE_HANG_BODY, python3_body=FAKE_HANG_BODY)
hang_env = dict(TEST_ENV, PATH=hang_dir + os.pathsep + TEST_ENV["PATH"])
HOOK_TIMEOUT = 20
for label, payload, want_rc in [
    ("hanging candidates, subagent -> blocked within the hook timeout", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}, "agent_id": "abc-123"}, 2),
    ("hanging candidates, main session -> allowed within the hook timeout", {"tool_name": "Bash", "tool_input": {"command": "git commit -m x"}}, 0),
]:
    call_start = time.monotonic()
    r = subprocess.run([GITBASH, WRAPPER], input=json.dumps(payload).encode(), capture_output=True, env=hang_env, timeout=HOOK_TIMEOUT + 10)
    call_elapsed = time.monotonic() - call_start
    ok = r.returncode == want_rc and call_elapsed < HOOK_TIMEOUT
    fails += not ok
    total += 1
    print(("OK  " if ok else "FAIL") + f" {label}: rc={r.returncode} (want {want_rc}) {call_elapsed:.1f}s (want < {HOOK_TIMEOUT}s) stderr={r.stderr.decode().strip()!r}")

print(f"\n{total - fails} passed, {fails} failed")
sys.exit(1 if fails else 0)
