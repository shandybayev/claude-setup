# Verify a teammate's claim before relaying it

**Rule:** A teammate's report describes its intent, not a verified fact. Re-run its tests, re-measure its counts, and read the risky lines yourself before telling the project owner that something is done.

**Why:** Reports have been wrong in both directions: describing work that had not actually landed, and stating a count measured against a stale revision of the code.

**How to apply:** Before relaying any teammate's claim upward, independently re-check it: rerun the named tests, recompute the named counts, and state which revision (commit, file hash) your own check describes. See [[orchestration-workflow]].
