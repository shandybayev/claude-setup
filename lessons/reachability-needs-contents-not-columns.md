# A reachability argument needs the values, not just the schema

**Rule:** When a review dismisses a code path as unreachable, or a check as unnecessary, the argument must be about the VALUES that can occur, not about the schema. "This field exists on every record we construct" does not answer "can that field hold a null (or an empty, or an out-of-range value) once it is read back from storage or from an upstream system." A guard of the form "does this column exist" never fires on a record that has the column present but empty.

**Why:** This exact gap let a null-handling defect reach production on a real project, past several rounds of review and automated testing. The reviewing argument was written down and it rested entirely on column presence, never on what values the column could actually carry.

**Two companion rules, same shape (treating absence of a signal as a negative result):**
- **Silence is not success.** Reporting a system "clean" after watching a quiet window before any work had even run proves nothing. Count positive signals (cycles started, records actually processed) as well as the absence of errors, and confirm the work ran at all before calling it clean.
- **A crash is not a verdict.** A mutation test, health check, or proof run that crashed, timed out, or produced no usable output is INCONCLUSIVE, never a pass and never a fail. Treat a harness that silently turns "no result" into "passed" as worse than one that fails loudly.

**How to apply:** When a reviewer or you argue something cannot happen, demand value-level evidence, ideally a test that feeds the exact shape in question. When a new path raises or rejects where the old path tolerated a value, read the old code to find out what it actually did with that exact input; do not reason about what it was probably intended to do. See [[parallel-path-invariants]], [[fake-must-model-the-system]].
