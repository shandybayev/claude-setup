---
description: List the git/GitHub batch ready to go out, and ask the owner for one go covering all of it.
---

Per the git rule in `~/.claude/CLAUDE.md`: before running any git or GitHub write, list the whole batch in chat and ask for one go.

List, concretely:
- Every commit that will be made (repo, files, message).
- Every push (branch, remote).
- Every PR opened or updated (repo, title, body summary).
- Every comment posted, and where.
- Every review requested, and from whom.

Then ask for a single go-ahead covering everything listed. Once given, run every command in the list without checking back per command. Anything not in this list (a merge, a change to what gets pushed, a second round of pushes) needs a new batch and a new go.
