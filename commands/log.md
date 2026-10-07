---
description: Append one entry to the decision log.
---

Resolve the briefs folder per the rule in `~/.claude/claude-setup/templates/project/briefs/README.md` (default `<git root>/briefs`, overridden by `CLAUDE_BRIEFS_DIR`). Create `briefs/LOG.md` from `~/.claude/claude-setup/templates/project/LOG.md.template` first if it does not exist yet.

Append one new entry at the BOTTOM of the file, in the template's exact shape: a `### <date> <effort>` line, then `Decided`, `Why`, and `By` lines. Never edit or delete an existing entry, even a wrong one; if this entry reverses an earlier one, say so in `Decided` and name the entry it reverses (its date and effort).

Ask for whatever of these the owner did not already give: what was decided, why, and (if more than one effort is active) which effort this belongs to. "By" is the owner unless a named reviewer or session made the call.
