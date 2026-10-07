# briefs/

This folder holds the working documents for running this project with the owner's default workflow: plans, builder briefs, review reports, and coordination state. None of it is required reading for using the project itself; it exists so an agent (or a human) picking up mid-effort can resume without re-deriving context.

## Where this folder lives

Default: `<git root>/briefs`. A project that wants its briefs kept outside the repo instead sets `CLAUDE_BRIEFS_DIR` in its `.claude/settings.json` `env` block, either an absolute path or a path relative to the git root. This is the ONE rule for where the folder is; the SessionStart hook (`hooks/session_context.py`), the `/log`, `/register`, and `/handoff` commands, and the `multi-session` skill all resolve it this exact same way, by pointing back here rather than restating it.

## What is in it

- `COORDINATION.md`: the contract between sessions or lanes sharing this repo right now: worktrees, file ownership, freeze windows, the merge log. Read this before any git, migration, merge, or deploy action. See the `multi-session` skill. Update your own effort's section with `/register`.
- `HANDOFF.md`: one or more efforts' handoff blocks, newest overall at the top. Each effort's newest, non-superseded block names what is live, what is in flight, and the exact next step for THAT effort; write one with `/handoff` before a compaction or a long pause.
- `LOG.md`: the append-only decision log, newest at the bottom, one entry per decision or owner call. Add an entry with `/log`; never edit or delete an old one.
- Per-slice documents (plans, builder briefs, review reports) go in this folder as they are created, named for the slice they cover. Use the templates in `~/.claude/claude-setup/templates/docs/` as a starting shape for each one.

## Read-first order

For a session picking up an effort cold: this effort's newest block in `HANDOFF.md` first, then its section in `COORDINATION.md`, then the tail of `LOG.md` for recent decisions. The SessionStart hook injects a trimmed version of exactly this (newest handoff block per effort, the Freeze windows section, and the last 10 log entries) at the start of every session and after every compaction, so a resuming session already has it without reading the files by hand -- reading them directly still matters for anything the hook's 8000-character cap had to cut.

Clean up this folder's per-slice documents once a slice ships and nothing references them anymore; keep `COORDINATION.md`, `HANDOFF.md`, and `LOG.md` current rather than deleting them.
