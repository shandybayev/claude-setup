# briefs/

This folder holds the working documents for running this project with the owner's default workflow: plans, builder briefs, review reports, and coordination state. None of it is required reading for using the project itself; it exists so an agent (or a human) picking up mid-effort can resume without re-deriving context.

- `COORDINATION.md`: the contract between sessions or lanes sharing this repo right now: worktrees, file ownership, freeze windows, the merge log. Read this before any git, migration, merge, or deploy action. See the `multi-session` skill.
- `HANDOFF.md`: the latest handoff block, written before a compaction or a pause, naming what is live, what is in flight, and the exact next step.
- Per-slice documents (plans, briefs, review reports) go in this folder as they are created, named for the slice they cover. Use the templates in `~/.claude/claude-setup/templates/docs/` as a starting shape for each one.

Clean up this folder's per-slice documents once a slice ships and nothing references them anymore; keep `COORDINATION.md` and `HANDOFF.md` current rather than deleting them.
