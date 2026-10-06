"""PreToolUse guard for Bash and PowerShell: enforce the "only the main
session touches git and GitHub" rule from the global CLAUDE.md.

A SUBAGENT (the hook input carries agent_id) may never run a state-changing
git command, or any gh command that writes. Decision: deny.

The MAIN session is deliberately NOT prompted here, per command. The owner's
rule is to approve outward-facing git and GitHub work once, in chat, per
batch, not once per command; that rule lives in the global CLAUDE.md, not in
this hook. A hook that also gated the main session would just add a second,
conflicting approval flow.

Everything else passes silently.

FAILURE POLICY (owner decision): when this hook cannot reach a real decision
at all -- the payload will not parse as JSON, it parses but is not the shape
decide() expects, or something inside decide() itself raises -- it fails
CLOSED for a subagent and OPEN for the main session. A guard bug must never
wedge the orchestrator, but "we could not tell" is exactly the case a
subagent-restraining control cannot shrug off: that population is the one
the guard exists to restrain, and letting an undecidable payload through
unexamined defeats the whole point in precisely the situation where it
matters most. The closed path exits 2 with the reason on stderr (the
convention Claude Code hooks use to block a tool call outright); the open
path exits 0, same as before.

Telling the two apart when the payload itself will not parse means we
cannot read payload["agent_id"] the normal way. _sniff_agent_id below reads
the raw bytes directly instead. The exact rule, "clearly main", is narrow on
purpose: the text must (a) decode, (b) look like a COMPLETE JSON object --
starts with "{" and ends with "}", once surrounding whitespace is trimmed --
and (c) contain no "agent_id" text anywhere. Anything short of all three is
a subagent: a non-empty agent_id value; the key present but not a simple
quoted value; no visible key but the text is not even a plausible object;
or -- the case that matters most here -- a payload truncated before the
agent_id field was reached, which also truncates away the closing "}" and
so fails the completeness check even though no agent_id text survived.
Claude Code does not truncate hook stdin, so this last case is theoretical,
but it is exactly the gap a looser "no visible key -> main" rule would
leave: that reads a cut-off subagent payload as the main session. The same
rule is implemented a second time in git_guard.sh's own no-interpreter
fallback (grep-based there, since a JSON parser is not guaranteed on PATH
either); the two must agree, since either one failing open independently
defeats the other being correct.
"""

import json
import re
import sys

# A command position: start of the string, after a shell separator, inside
# $( ) or backticks, after a wrapper like xargs/env/sudo/time/timeout/
# command, as the argument of `bash -c "..."`/`Invoke-Expression "..."`/
# `cmd /c ...`/`powershell -Command "..."`, inside a block opener (bash
# `{ ...; }`, PowerShell `try {}`/`if(){}`/a ForEach-Object scriptblock),
# after a keyword that only means anything at a command boundary
# (if/while/then/do/else/! -- each gated on actually following a separator
# itself, so "else" or "!" inside an unrelated sentence does not count), or
# after one or more env-var assignments (bash's `VAR=val [VAR2=val2 ...]
# cmd`, or a single PowerShell-style `$r = cmd`). A git or gh inside a
# quoted grep pattern is not at a command position, so `grep "git add" file`
# is not mistaken for a write.
_START = r"""(?:
    ^ | [;&|(`\n{] | \$\(                                     |
    \b(?:xargs|env|sudo|time|exec|nohup|command)\s+             |
    \btimeout\s+(?:-\S+\s+)*\d+\S*\s+                            |
    \s-c\s+["']?                                                |
    \b(?:Invoke-Expression|iex)\s+["']?                         |
    \bStart-Process\s+(?:-FilePath\s+)?                         |
    \bcmd(?:\.exe)?\s+/c\s+["']?                                 |
    \b(?:powershell|pwsh)(?:\.exe)?\s+(?:-\S+\s+)*-(?:Command|c)\s+["']? |
    (?:^|[;&|\n])\s*(?:if|while|then|do|else)\b\s+               |
    (?:^|[;&|\n])\s*!\s+                                         |
    (?:^|[;&|\n])\s*\$?\w+\s*=\s*                                |
    (?:^|[;&|\n])\s*(?:\w+=(?:"[^"]*"|'[^']*'|[^\s;&|]*)\s+)+
)\s*"""

# git itself: bare (optionally path-prefixed, no spaces), a short quoted name
# with nothing else inside ("git" / "git.exe" / 'git.exe', the & 'git' ...
# idiom), or a quoted PATH that must contain an actual separator before
# "git" (the & "C:\Program Files\Git\cmd\git.exe" ... idiom). The separator
# requirement on the quoted-path form is load-bearing: without it, a
# harmless string that merely ENDS in the word "git" (e.g. a log message
# assigned to a variable) would match too, since both the quoted and the
# assignment start above would otherwise line up with it.
_GIT_BARE = r"""(?:\S*[/\\])?git(?:\.exe)?"""
_GIT_QUOTED_NAME = r'''(?:"git(?:\.exe)?"|'git(?:\.exe)?')'''
_GIT_QUOTED_PATH = r'''(?:"[^"]*?[/\\]git(?:\.exe)?"|'[^']*?[/\\]git(?:\.exe)?')'''
_GIT = r"(?:" + _GIT_QUOTED_NAME + "|" + _GIT_QUOTED_PATH + "|" + _GIT_BARE + ")"

_VAL = r"""(?:"[^"]*"|'[^']*'|\S+)"""
# The last alternative (a single-dash, multi-letter flag, e.g.
# -ArgumentList) is not a real git option: it covers a PowerShell cmdlet
# parameter sitting between "git" and the verb (Start-Process git
# -ArgumentList "commit ...") so the verb underneath still gets matched.
_GIT_OPTS = (
    r"""(?:\s+(?:-C\s+""" + _VAL + r"""|-c\s+""" + _VAL +
    r"""|--[\w-]+(?:=""" + _VAL + r""")?|-[pPh]|-[A-Za-z][\w-]+))*"""
)

_GIT_WRITE_VERB = r"""(?:
    add|commit|push|pull|checkout|switch|reset|restore|stash|merge|rebase|
    cherry-pick|revert|tag|rm|mv|am|apply|clean|init|gc|prune|update-ref|
    update-index|notes|filter-branch|replace|
    worktree\s+(?:add|remove|move|prune|lock|unlock|repair)|
    submodule\s+(?:add|update|init|deinit|sync|set-branch|set-url)|
    config(?!\s+(?:--get|--get-all|--get-regexp|--list|-l\b|--show-origin|--show-scope))|
    branch\s+(?:-[dDmMcCfu]\b|--(?:delete|move|copy|force|set-upstream-to|unset-upstream|edit-description)\b|(?!-)\S+)
)\b"""

# The optional quote right before the verb covers PowerShell's quoted/
# array -ArgumentList form (Start-Process git -ArgumentList 'commit','-m','x'):
# the verb is the first element of that list, not a bare word.
GIT_WRITE = re.compile(_START + _GIT + _GIT_OPTS + r"""\s+['"]?""" + _GIT_WRITE_VERB, re.X | re.I)

# gh gets the same bare/quoted-name/quoted-path treatment as git, for the
# same reasons (& 'gh' pr create, & "...\gh.exe" pr create).
_GH_BARE = r"""(?:\S*[/\\])?gh(?:\.exe)?"""
_GH_QUOTED_NAME = r'''(?:"gh(?:\.exe)?"|'gh(?:\.exe)?')'''
_GH_QUOTED_PATH = r'''(?:"[^"]*?[/\\]gh(?:\.exe)?"|'[^']*?[/\\]gh(?:\.exe)?')'''
_GH = r"(?:" + _GH_QUOTED_NAME + "|" + _GH_QUOTED_PATH + "|" + _GH_BARE + ")"
GH_WRITE_SUBCOMMAND = re.compile(
    _START + _GH + r"""\s+(?:
        pr\s+(?:create|merge|close|edit|comment|review|ready|reopen|lock|unlock)|
        issue\s+(?:create|comment|close|edit|reopen|delete|transfer|lock|unlock|pin|unpin)|
        release\s+(?:create|delete|edit|upload)|
        repo\s+(?:create|delete|fork|rename|archive|unarchive|edit|sync)|
        label\s+(?:create|delete|edit|clone)|
        gist\s+(?:create|edit|delete)|
        workflow\s+(?:run|enable|disable)|
        run\s+(?:rerun|cancel|delete)|
        secret\s+(?:set|delete)|
        variable\s+(?:set|delete)|
        api\b
    )""",
    re.X | re.I,
)

GH_API = re.compile(_START + _GH + r"\s+api\b(?P<rest>[^;&|\n]*)", re.X | re.I)
_METHOD = re.compile(r"""(?:-X|--method)(?:\s+|=)["']?(\w+)""", re.I)
_FIELDS = re.compile(r"""(?:^|\s)(?:-f|-F|--field|--raw-field|--input)(?:\s|=)""")


def gh_api_writes(command):
    """True when any `gh api` call in the command writes.

    An explicit -X/--method decides. Without one, gh sends POST as soon as a
    field or --input is given, so fields mean a write; a bare call is a GET.
    """
    for match in GH_API.finditer(command):
        rest = match.group("rest")
        method = _METHOD.search(rest)
        if method:
            if method.group(1).upper() != "GET":
                return True
        elif _FIELDS.search(" " + rest):
            return True
    return False


def gh_writes(command):
    """True for a gh write subcommand, or a gh api call that writes."""
    for match in GH_WRITE_SUBCOMMAND.finditer(command):
        if not match.group(0).rstrip().lower().endswith("api"):
            return True
    return gh_api_writes(command)


# PowerShell's backtick is its escape character everywhere, not just as a
# line-continuation marker: a bare backtick before an ordinary character
# (unquoted or inside a double-quoted string) just passes that character
# through, which means `g`it` is read by PowerShell as the plain word
# "git" -- a cheap way to dodge a literal-text match. Stripping every
# backtick before matching normalizes both that and the line-continuation
# case (`git `\n  commit` -> "git   commit", and \s+ already crosses
# ordinary whitespace including a newline) in one pass. This is a strict
# OVER-approximation: it does not reproduce what `n or `t mean inside a
# real double-quoted string, but this hook only cares whether the literal
# text "git"/"gh" appears, so matching in a few more places than PowerShell
# would literally produce is the safe direction to be wrong in.
_PS_BACKTICK = re.compile(r"`")


def normalize_for_shell(command, tool_name):
    if tool_name == "PowerShell":
        return _PS_BACKTICK.sub("", command)
    return command


def decide(payload):
    """Return (decision, reason) or (None, None) to stay silent."""
    tool_name = payload.get("tool_name")
    if tool_name not in ("Bash", "PowerShell"):
        return None, None
    command = (payload.get("tool_input") or {}).get("command") or ""
    command = normalize_for_shell(command, tool_name)
    is_subagent = bool(payload.get("agent_id"))

    if is_subagent:
        if GIT_WRITE.search(command):
            return "deny", (
                "Blocked by the owner's git rule: teammates and subagents never "
                "run state-changing git commands. Only the main session does "
                "git. Report what you need committed or changed and hold."
            )
        if gh_writes(command):
            return "deny", (
                "Blocked by the owner's git rule: teammates and subagents never "
                "run gh commands that write to GitHub. Only the main session "
                "does, and only after the owner says go."
            )
        return None, None

    # The main session is NOT prompted per command: it asks once in chat
    # before a batch of outward-facing actions, and one go covers the whole
    # batch it listed. See the global CLAUDE.md, section "Git and GitHub".
    return None, None


_AGENT_ID_VALUE_RE = re.compile(rb'"agent_id"\s*:\s*"([^"]*)"')
_AGENT_ID_KEY_RE = re.compile(rb'"agent_id"')


def _sniff_agent_id(raw_bytes):
    """Best-effort "is this a subagent call" read of the raw bytes, used
    only when a real JSON parse already failed. Returns True (treat as
    subagent, the closed path) unless the text is "clearly main": see the
    module docstring for the exact rule. git_guard.sh's no-interpreter
    fallback implements the identical rule; keep the two in sync.
    """
    m = _AGENT_ID_VALUE_RE.search(raw_bytes)
    if m:
        return bool(m.group(1).strip())
    if _AGENT_ID_KEY_RE.search(raw_bytes):
        # The key is present but not as a simple quoted string value (a
        # number, null, or something mangled) -- cannot tell, so treat it
        # as present rather than assume it away.
        return True
    try:
        text = raw_bytes.decode("utf-8-sig", "replace").strip()
    except Exception:
        return True  # not even decodable as text: cannot tell, assume subagent
    if '"agent_id"' in text:
        return True
    # "Clearly main" requires a COMPLETE-looking object, not just the
    # absence of visible agent_id text: a payload truncated before ever
    # reaching that field is still missing its OUTER closing "}", so it
    # must fail here rather than be waved through. A plain text.endswith
    # ("}") check is not enough for that: a payload cut off right after a
    # NESTED object (e.g. {"tool_name":"Bash","tool_input":{"command":"x"}
    # with the real outer brace never reached) still ends in "}" from that
    # inner object, so the check has to actually balance the braces.
    return not _looks_like_complete_object(text)


def _looks_like_complete_object(text):
    """True when text starts with "{" and its braces are balanced by the
    end (string contents are skipped, so a brace inside a quoted value
    never counts). Not a real parser: does not catch every malformed
    shape, only answers "does this look cut off", which is all the
    truncation case above needs.
    """
    if not text.startswith("{"):
        return False
    depth = 0
    in_string = False
    escape = False
    for ch in text:
        if in_string:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


def main():
    raw_bytes = sys.stdin.buffer.read()
    try:
        # utf-8-sig, not plain utf-8: it transparently strips a leading
        # byte-order mark when one is present and behaves exactly like
        # utf-8 when one is not. Without this, a BOM'd payload (seen from a
        # PowerShell pipeline, which adds one by default) makes json.loads
        # raise, which used to fall straight into the except below and
        # fail open unconditionally -- a subagent's git write would have
        # gone through undetected instead of being denied.
        raw = raw_bytes.decode("utf-8-sig", "replace")
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("top-level payload is not a JSON object")
        decision, reason = decide(payload)
    except Exception as exc:
        # Could not reach a real decision. See the module docstring: fail
        # CLOSED (exit 2, deny) for a subagent, OPEN (exit 0) for the main
        # session, and treat "cannot tell which" as a subagent.
        if _sniff_agent_id(raw_bytes):
            sys.stderr.write(
                "git_guard: could not decide (%s); blocking because this looks "
                "like a subagent call and the guard cannot verify it is safe.\n"
                % exc
            )
            return 2
        sys.stderr.write(
            "git_guard: could not decide (%s); allowing because this looks like "
            "the main session, where a guard failure must not wedge the "
            "session.\n" % exc
        )
        return 0
    if decision:
        sys.stdout.write(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
