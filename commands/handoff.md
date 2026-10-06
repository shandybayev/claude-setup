---
description: Write a handoff block before a compaction or a pause, so a fresh session can resume from it alone.
---

Write a new handoff block using `~/.claude/claude-setup/templates/docs/handoff-block.md` as the shape, and add it to the top of the project's `briefs/HANDOFF.md` (create the file from `~/.claude/claude-setup/templates/project/HANDOFF.md.template` if it does not exist yet). Mark any prior block as superseded rather than deleting it.

Fill in: what is live, what is in flight (worktree, branch, commit, brief and review paths, gate/test/build status), what is waiting on whom, the exact next step, open questions for the owner, carried known issues, and which teammates are idle and can be closed once the current slice ships.

Do this before ending the session if a compaction or a long pause is coming, and whenever the owner asks for a handoff directly.
