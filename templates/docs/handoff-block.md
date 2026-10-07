<!--
A handoff block: write this into the project's briefs/HANDOFF.md (or
equivalent state file) before a compaction or a long pause, so a fresh
session can resume from this block alone. See
~/.claude/claude-setup/templates/project/HANDOFF.md.template for the file
this block goes into.

Several efforts can share one HANDOFF.md. Each new block goes at the TOP of
the file, regardless of which effort wrote it, so the file reads newest
first overall. When an effort writes a new block, find that SAME effort's
previous block further down and add " (SUPERSEDED)" right after "READ THIS
BLOCK FIRST" in its header line (one space, nothing else changed); never
edit or remove the superseded block's body. The SessionStart hook
(hooks/session_context.py) parses this exact header shape to find the
newest non-superseded block per effort, so keep the header on one line in
this shape, including the "Z" directly after the minutes with no space.
-->

################################################################################
## ===== <EFFORT> CURRENT STATE, <YYYY-MM-DD HH:MM>Z (<reason>). READ THIS BLOCK FIRST =====
################################################################################

**Workflow:** <e.g. "the owner's default-workflow skill; roles in ~/.claude/agents, spawn by subagent_type, no model override.">

**What is live:** <what is deployed or merged, and its commit/version>.

**In flight:** <effort name> on worktree `<path>`, branch `<branch>`, commit `<sha or "uncommitted">`.
- Brief / reviews: `<paths>`.
- Gates, tests, build: <status>.
- Waiting on: <who, for what>.
- Next step: <the exact next action>.

**Open questions for the owner:** <list, or "none">.

**Carried known issues:** <list, or "none">.

**Idle teammates for this slice:** <names to close once it ships>.

**Last LOG entry:** <the date and one-line summary of the most recent briefs/LOG.md entry, or "none yet">.
