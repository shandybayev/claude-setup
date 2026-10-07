#!/usr/bin/env bash
# PreToolUse Bash/PowerShell hook wrapper. Starts Python only when the
# command mentions git or gh, since this runs on every Bash/PowerShell call
# in every session. The normal decision travels as JSON on stdout with
# exit 0 (see git_guard.py); this script exits with WHATEVER git_guard.py
# itself exits with, which matters for its exit-2 path (git_guard.py fails
# closed for an undecidable subagent payload; this wrapper must not
# swallow that back into exit 0).
#
# FAILURE POLICY (owner decision, see git_guard.py's docstring for the
# full reasoning): this layer has its OWN undecidable cases that
# git_guard.py never gets a chance to handle, because git_guard.py itself
# cannot run -- no working Python interpreter at all, or the .py file is
# missing or unreadable (a partial copy, a rename on a pull). The same
# rule applies: fail CLOSED (exit 2, deny) for what looks like a subagent
# call, fail OPEN (exit 0) for the main session, found with the same
# "clearly main" test git_guard.py's _sniff_agent_id uses (see its
# docstring for the exact rule) -- the two must agree, or one layer
# failing open independently defeats the other being correct.
input=$(cat)
# Check the backtick-stripped text, not $input itself: PowerShell reads a
# bare backtick as its own escape character (g`it is the plain word "git"
# to PowerShell), so a command built that way never contains the literal
# substring "git" or "gh" at all, and would skip Python entirely -- the
# exact obfuscation git_guard.py's own normalize_for_shell exists to catch,
# just one step earlier, in the cheap pre-filter meant to avoid spawning
# Python on every ordinary call. Python still gets the ORIGINAL $input;
# this stripped copy exists only to decide whether to call it.
filter="${input//\`/}"
case "$filter" in
  *git*|*gh*)
    # Try python3 first, then python: recent macOS and stock Debian/Ubuntu
    # ship only python3, and a bare "python" there is "command not found",
    # not a working interpreter. Each candidate's REAL invocation is what
    # gets tried (piping the actual input), not a synthetic probe:
    # `command -v` finding a candidate does not guarantee the exec that
    # follows will actually run it. On Windows, a bare "python3" on PATH
    # can resolve to the WindowsApps app-execution alias stub, which:
    # with Python actually installed behind it, intermittently fails the
    # real exec with "Permission denied" (rc 126) even on a call that
    # otherwise looks identical to one that just worked; with NO Python
    # installed at all, instead prints a Microsoft Store prompt and
    # exits 9009, every time, `-c 1` included -- neither is a value
    # git_guard.py itself would ever produce (see its own main(): it
    # only ever returns 0 -- a decision, if any, travels as JSON on
    # stdout, not the exit code -- or 2, its own fail-closed path when
    # IT cannot decide). So the check is the other way around: only rc 0
    # or rc 2 are git_guard.py's own, real, final result; ANY other
    # value, whatever it is (including 124, a timeout -- see below),
    # means THIS candidate never actually ran it, and the next one gets
    # a try.
    #
    # A time limit per candidate: `timeout 4` where `timeout` exists
    # (GNU coreutils; ships with Git for Windows, not stock macOS), else
    # `perl -e 'alarm shift; exec @ARGV or exit 127' 4` where perl exists (ships
    # with macOS; SIGALRM there gives rc 142, which already falls into
    # the same "did not run" bucket as any other non-matching rc
    # below), else no limit at all -- a documented residual on a
    # machine with neither. Without ANY limit, a HUNG interpreter (not
    # a fast failure like rc 126/9009) ties up this hook, which runs on
    # EVERY git/gh Bash or PowerShell call, until Claude Code's own
    # hook timeout kills it from outside; whether a killed hook still
    # fails open (letting a subagent's git write through unguarded) is
    # Claude Code's call, not this script's, so a candidate that would
    # hang is cut off here first, before that question even comes up.
    # An ARRAY, not a string: a plain string containing the perl
    # one-liner's own quotes would not survive unquoted word-splitting
    # below (the shell would split it into the wrong argv entirely); an
    # empty array expands to nothing, unlike an empty string variable,
    # which would still pass one stray empty argument.
    guard_py="$HOME/.claude/hooks/git_guard.py"
    ran=0
    rc=0
    timeout_cmd=()
    if command -v timeout >/dev/null 2>&1; then
      timeout_cmd=(timeout 4)
    elif command -v perl >/dev/null 2>&1; then
      timeout_cmd=(perl -e 'alarm shift; exec @ARGV or exit 127' 4)
    fi
    if [ -f "$guard_py" ]; then
      for cand in python3 python; do
        command -v "$cand" >/dev/null 2>&1 || continue
        printf '%s' "$input" | "${timeout_cmd[@]}" "$cand" "$guard_py"
        rc=$?
        if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then
          continue
        fi
        ran=1
        break
      done
    fi

    if [ "$ran" -eq 1 ]; then
      exit "$rc"
    fi

    # Either no candidate could actually run git_guard.py, or the file
    # itself is missing: the normal, correct decision is unavailable
    # either way. Fall back to the same raw-text sniff git_guard.py's
    # _sniff_agent_id implements, done here with grep/sed since no JSON
    # parser is guaranteed on PATH.
    #
    # "Clearly main" requires a non-empty agent_id value to be absent AND
    # the text to look like a COMPLETE JSON object. Checking only that it
    # STARTS with "{" is not enough: a payload truncated right after a
    # nested object (e.g. {"tool_name":"Bash","tool_input":{"command":"x"}
    # with the real outer brace, and agent_id, never reached) still ends
    # in a "}" from that inner object. The brace count must also ignore
    # braces INSIDE a JSON string (a command containing a literal "{" or
    # "}", e.g. `git log --format='%H' | sed 's/{/(/'`, would otherwise
    # look unbalanced and wrongly block the main session): strip every
    # quoted string first, the same way git_guard.py's string-aware depth
    # counter does, so only the JSON structure's own braces are counted.
    stripped=$(printf '%s' "$input" | sed -E 's/"([^"\\]|\\.)*"//g')
    is_sub=0
    if printf '%s' "$input" | grep -Eq '"agent_id"[[:space:]]*:[[:space:]]*"[^"]+"'; then
      is_sub=1
    elif printf '%s' "$input" | grep -q '"agent_id"'; then
      is_sub=1
    elif ! printf '%s' "$input" | grep -Eq '^[[:space:]]*\{'; then
      is_sub=1
    else
      opens=$(printf '%s' "$stripped" | tr -cd '{' | wc -c)
      closes=$(printf '%s' "$stripped" | tr -cd '}' | wc -c)
      if [ "$opens" -eq 0 ] || [ "$opens" -ne "$closes" ]; then
        is_sub=1
      fi
    fi

    if [ ! -f "$guard_py" ]; then
      reason="$guard_py not found or not readable"
    else
      reason="no working python3 or python found on PATH"
    fi
    if [ "$is_sub" -eq 1 ]; then
      echo "git_guard: $reason; blocking because this looks like a subagent call and the guard cannot verify it is safe without running git_guard.py. Install python3 / restore the file." >&2
      exit 2
    fi
    echo "git_guard: $reason; the git/gh write guard is NOT active this call." >&2
    ;;
esac
exit 0
