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
    # not a working interpreter. Probe each candidate with `-c 1` before
    # trusting it, since Windows ships a WindowsApps "python3" stub that
    # resolves on PATH but does not actually run.
    py=""
    for cand in python3 python; do
      if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 1 >/dev/null 2>&1; then
        py="$cand"
        break
      fi
    done
    guard_py="$HOME/.claude/hooks/git_guard.py"

    if [ -n "$py" ] && [ -f "$guard_py" ]; then
      printf '%s' "$input" | "$py" "$guard_py"
      exit $?
    fi

    # Either no interpreter, or git_guard.py itself is missing: the
    # normal, correct decision is unavailable either way. Fall back to
    # the same raw-text sniff git_guard.py's _sniff_agent_id implements,
    # done here with grep/sed since no JSON parser is guaranteed on PATH.
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

    if [ -z "$py" ]; then
      reason="no working python3 or python found on PATH"
    else
      reason="$guard_py not found or not readable"
    fi
    if [ "$is_sub" -eq 1 ]; then
      echo "git_guard: $reason; blocking because this looks like a subagent call and the guard cannot verify it is safe without running git_guard.py. Install python3 / restore the file." >&2
      exit 2
    fi
    echo "git_guard: $reason; the git/gh write guard is NOT active this call." >&2
    ;;
esac
exit 0
