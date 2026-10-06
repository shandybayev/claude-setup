# Builder brief: <slice name> (<date>)

Worktree: `<path>`. Branch: `<branch>`. Scratch folder (name it; the builder runs scripts only from here): `<path>`.

## Scope

What this slice builds, in one or two sentences. Files this builder owns (disjoint from any other lane running in parallel):
- `<file or glob>`
- `<file or glob>`

## Context

What the real code currently does (file and line references), and why this change is needed. Link to the plan this brief came from, if any, by file path (not by round label).

## What to build

Concrete, numbered steps. Settle every judgement call here; if the builder thinks a ruling is wrong, it should build nothing for that item and say so, not improvise.

1. <step>
2. <step>

## Tests

What to add or extend, and for each test, the one line that should break to make it fail. Keep a revert table: remove each guard, confirm the named test fails, restore, and prove the file is byte-identical afterward (hash before and after).

## Rules for this builder

- No git commands that change state. No build. No servers. No writes to any shared or production database; only throwaway instances named here.
- Comments and docstrings describe the code itself; no references to this brief, review rounds, or plan codes.
- Report line counts for every file touched. Never edit a size-ratchet or baseline file.
- No em dashes or en dashes.

## Report

Write the report to `<path>`, stating which revision each claim describes. Reply with ONE line, then HOLD.
