---
description: Spawn the adversarial reviewer over the frozen current diff.
---

Before spawning the reviewer: confirm the tree is frozen (tell any active builder to HOLD first), and gather the baseline it needs (head revision, test count, line counts).

Spawn an `adversarial-reviewer` teammate (never override its model) with:
- The frozen baseline above, so it can detect if the tree moves under it.
- The diff to review (untracked files included), and where to write its report.
- A reminder of its rules: run things rather than reading them, check the change against its neighbours, hunt tests that test nothing, flag any review-history reference left in code comments, and if it forks sub-agents they are read-only and report to it.

Relay only what you have verified yourself from its report; see the `verify-dont-relay` lesson.
