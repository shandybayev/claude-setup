# <Slice name>, adversarial review (<date>)

One-line verdict up top, always: **SHIP** or **CHANGES NEEDED**.

## What held up (verified by running it)

What you actually ran (tests, mutations, a real-system proof) and what passed. "Verified by running it," not "read and looks right."

## Findings

Each finding: file, line, the concrete failure (the input and state that produces the wrong output), and how you verified it. Rank each as **MUST-FIX** or **NON-BLOCKING**.

### <area> findings

- **MUST-FIX**: <finding>
- **NON-BLOCKING**: <finding>

## Could not verify

Anything you were not able to check, named as such, rather than silently assumed fine.

## Questions answered

If the builder's brief or report raised open questions, answer them here with evidence.

---

## Re-check (fix round <n>, <date>)

Append, never overwrite, a prior section. Confirm the tree is the frozen baseline you were given (head revision, test count, line counts) before re-checking; if it moved, say so instead of proceeding.

### Tree

Head revision, test count, line counts at the time of this re-check.

### Findings re-verified

For each MUST-FIX from the prior round: fixed, how you verified it, and whether the fix introduced anything new.

### Re-check verdict: SHIP | CHANGES NEEDED
