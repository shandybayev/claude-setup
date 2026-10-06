# Read the repo's rules files in full, at session start

**Rule:** At the start of a session in any repo, read its agent-facing rules files (for example `AGENTS.md`, a harness or testing guide referenced by it) end to end, before the first edit. Do not wait until compliance is about to be checked.

**Why:** On one project, a rules file was only read at the very end of a multi-day branch, by which point several of its rules had already been broken and some deliverables needed rewriting to match a convention stated on line one.

**How to apply:** Before the first edit of any session in a repo, read its full rules file(s) end to end, plus any harness or testing guide those files point to if that part of the system will be touched. Re-read them again if a long session gets compacted or resumed. See also [[checklist-preconditions-verified]] and [[ask-branch-before-code]].
