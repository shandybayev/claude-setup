---
description: Register (or update) this session's effort in the coordination file.
---

Resolve the briefs folder per the rule in `~/.claude/claude-setup/templates/project/briefs/README.md` (default `<git root>/briefs`, overridden by `CLAUDE_BRIEFS_DIR`). Create `briefs/COORDINATION.md` from `~/.claude/claude-setup/templates/project/COORDINATION.md.template` first if it does not exist yet.

Add or update THIS session's own `### Effort: <name>` section under "Active efforts": worktree and branch, the files or directories this effort touches, any throwaway resource naming convention in use, and a one-line status. If a section for this effort already exists, update it in place rather than adding a duplicate.

Ask for whatever of these the owner or the session's own state did not already make obvious. See the `multi-session` skill for what the rest of this file is for and when to re-register (after a restart, a session identifier can change).
