<!--
A handoff block: write this into the project's briefs/HANDOFF.md (or
equivalent state file) before a compaction or a long pause, so a fresh
session can resume from this block alone. See
~/.claude/claude-setup/templates/project/HANDOFF.md.template for the file
this block goes into.
-->

################################################################################
## ===== CURRENT STATE, <date> (<reason>). READ THIS BLOCK FIRST =====
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
