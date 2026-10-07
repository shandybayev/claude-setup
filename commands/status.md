---
description: "Give a status update in the reporting style (ASD-STE100): result first, then evidence, then done/mocked/next."
---

Before saying anything, read this effort's newest block in `briefs/HANDOFF.md` and its `### Effort:` section in `briefs/COORDINATION.md` (resolve the briefs folder per `~/.claude/claude-setup/templates/project/briefs/README.md`), so the status you give matches what is actually on file, not just what is in this conversation.

Give a status update on the current effort, in the reporting style from `~/.claude/CLAUDE.md`:

1. Lead with the result: is the current slice working, blocked, or still in progress.
2. Give the evidence: what you actually ran (tests, gates, a build), with counts, and which revision it describes. Never state a number you have not just re-checked.
3. Say what is done, what is mocked or stubbed, and what is next.

If the files and this conversation disagree (the handoff names a different next step, or COORDINATION's status line is stale), say so explicitly rather than picking one silently.

Use short sentences, one topic each, active voice, plain words. If teammates are active, name them and their current state (building, holding, idle) rather than only describing the code.
