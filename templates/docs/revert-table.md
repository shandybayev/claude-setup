# Revert table: <slice name>

For each guard, check, or fix this slice adds, prove it actually does something by reverting it, confirming the expected test fails, then restoring it and proving the file is unchanged.

| # | Guard / fix (file:line) | Reverse mutation applied | Expected failing test | Actually failed? | File hash before | File hash after restore | Match? |
|---|---|---|---|---|---|---|---|
| 1 | `<file>:<line>` | <what you changed to undo the guard> | `<test name>` | yes/no | `<sha256>` | `<sha256>` | yes/no |

Notes:
- Be suspicious of any row where FEWER tests fail than expected; that is usually a vacuous test, not a lucky result.
- Hash with binary I/O so line endings cannot flip silently, especially on Windows.
- Never overlap two mutation runs against the same worktree; run them one at a time from the scratch folder named in the brief.
- A mutation that crashes, times out, or produces no output is INCONCLUSIVE, not a pass or a fail; record it as such and investigate separately.
