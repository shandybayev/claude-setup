#!/usr/bin/env bash
# SessionStart hook wrapper, same shape as git_guard.sh: find a working
# Python, run the real script, and pass its stdout through untouched.
#
# FAILURE POLICY: unlike git_guard.sh, there is no closed path at all. A
# SessionStart hook has nothing to deny, only context to add or not add,
# so every failure here (no interpreter, session_context.py missing or
# unreadable, the script itself failing) prints nothing to stdout and
# exits 0. A broken hook must never block a session from starting.
input=$(cat)

script="$HOME/.claude/hooks/session_context.py"

# A time limit per candidate: `timeout 4` where `timeout` exists (GNU
# coreutils; ships with Git for Windows, not stock macOS), else
# `perl -e 'alarm shift; exec @ARGV or exit 127' 4` where perl exists (ships with
# macOS; SIGALRM there gives rc 142, which already falls into the same
# "did not run" bucket as any other non-zero rc below), else no limit
# at all -- a documented residual on a machine with neither. Without
# ANY limit, a HUNG interpreter (not a fast failure like rc 126/9009)
# ties up this whole hook until Claude Code's own hook timeout kills it
# from outside, at which point whether a killed hook still fails open
# is Claude Code's call, not this script's. An ARRAY, not a string: a
# plain string containing the perl one-liner's own quotes would not
# survive unquoted word-splitting below (the shell would split it into
# the wrong argv entirely); an empty array expands to nothing, unlike
# an empty string variable, which would still pass one stray empty
# argument.
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD=(timeout 4)
elif command -v perl >/dev/null 2>&1; then
  TIMEOUT_CMD=(perl -e 'alarm shift; exec @ARGV or exit 127' 4)
fi

# Try each candidate's REAL invocation (piping the actual input), not a
# synthetic probe: `command -v` finding a candidate, or even a prior
# `-c 1` smoke test passing, does not guarantee the exec that follows
# will actually run it. On Windows, a bare "python3" on PATH can resolve
# to the WindowsApps app-execution alias stub, which: with Python
# actually installed behind it, intermittently fails the real exec with
# "Permission denied" (rc 126) even though it just answered `-c 1` fine
# moments earlier; with NO Python installed at all, instead prints a
# Microsoft Store prompt and exits 9009, every time, `-c 1` included --
# so no single rc value is a reliable signal of "ran", only of "did
# not": session_context.py's own policy (see above) is to ALWAYS exit 0,
# so any OTHER rc, whatever its value (including 124, a timeout), means
# THIS candidate never actually ran the script, and the next one gets a
# try.
if [ -f "$script" ]; then
  for cand in python3 python; do
    command -v "$cand" >/dev/null 2>&1 || continue
    printf '%s' "$input" | "${TIMEOUT_CMD[@]}" "$cand" "$script"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      continue
    fi
    break
  done
fi
exit 0
