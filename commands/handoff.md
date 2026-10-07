---
description: Write a handoff block before a compaction or a pause, so a fresh session can resume from it alone.
---

Resolve the briefs folder per the rule in `~/.claude/claude-setup/templates/project/briefs/README.md` (default `<git root>/briefs`, overridden by `CLAUDE_BRIEFS_DIR`). Write a new handoff block using `~/.claude/claude-setup/templates/docs/handoff-block.md` as the shape, with THIS effort's name in the header, and add it to the top of `briefs/HANDOFF.md` (create the file from `~/.claude/claude-setup/templates/project/HANDOFF.md.template` if it does not exist yet; other efforts' blocks may already be there, above or below this one). Find this SAME effort's previous block further down and add " (SUPERSEDED)" to its header, right after "READ THIS BLOCK FIRST"; never edit or remove its body.

Fill in: what is live, what is in flight (worktree, branch, commit, brief and review paths, gate/test/build status), what is waiting on whom, the exact next step, open questions for the owner, carried known issues, and which teammates are idle and can be closed once the current slice ships.

Fill "Last LOG entry" with the date and one-line summary of `briefs/LOG.md`'s most recent entry for this effort (or "none yet"). If this handoff also records a decision that is not already logged (a product call, a deferred item, a reversal), run `/log` for it first, so the block's "Last LOG entry" line is accurate.

Do this before ending the session if a compaction or a long pause is coming, and whenever the owner asks for a handoff directly. The SessionStart hook re-injects the newest block for each effort after every compaction, so an out-of-date handoff is what a fresh session sees; keep it current rather than writing it only at the very end.
