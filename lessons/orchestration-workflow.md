# Running multi-lane work: orchestrator and teammates

**Rule:** Run feature work as lanes. The main session is the orchestrator and talks to the human; teammates (planner, plan reviewer, builder, adversarial reviewer, probe) do the planning, building, reviewing and probing. See the `default-workflow` skill for the full sequence; this lesson is the set of corrections earned from running it.

**Why:** Without this split, a single session context fills with build detail, screenshots and review back-and-forth, and the human loses visibility into decisions that are theirs to make.

**How to apply, in detail:**

1. **Review the change against its neighbours, not only on its own.** A defect can be new code that is not wrong in isolation but is silently WEAKER than the existing code beside it (a new lookup path that skips a filter or join the old path applied). Every builder and reviewer brief that adds a path, a guard, a resolver or a writer must ask explicitly: what does the existing sibling enforce, and does this enforce each of those? After fixing one instance, grep for the same call pattern elsewhere before declaring it fixed; the same defect sometimes repeats one call site over, in a more dangerous path (for example a path that writes instead of one that only reads). Treat a guard that refuses an existing test fixture as evidence the fixture is unreal, never as a reason to weaken the guard.

2. **A document under review is frozen.** The author stops revising when a review starts, and waits for the verdict. If something genuinely cannot wait, send the reviewer an explicit delta naming what changed, reviewed as a first pass, not folded into the re-check silently.

3. **Freeze before asking for verification, not after being told the tree moved.** A check against a moving tree does not count. Tell a builder to HOLD before sending its work to a reviewer, and give the reviewer the frozen baseline: head revision, test count, line counts.

4. **Verify a builder's claims yourself before relaying them.** A report describes intent; re-run the tests and re-measure the counts before telling the human anything is done. Builders should state which revision each claim describes.

5. **Give every parallel builder its own named scratch subfolder**, and tell it to run scripts only from that folder and never overlap two mutation runs. A shared scratch folder lets one lane's run mutate another lane's worktree by accident.

6. **Before mutating a builder's tree yourself, get an explicit "holding, no changes" reply first**, and check file modification times; a builder that reported done can still be processing a message that arrived late. Send every instruction for a fix round as ONE message, never as drip-fed asides while the builder is supposed to be frozen.

7. **A teammate that ends its turn waiting on something never restarts itself.** Re-prompt it and watch its background work from your side (poll for processes to exit) so a stall surfaces in minutes, not days.

8. **Several sessions can share one repo if the contract is written down**: worktrees, file ownership, throwaway-resource naming, one-merge-at-a-time, and a merge log every session reads before merging and updates after.

9. **Match review weight to the change's leverage.** A reviewer's patience is a finite resource. Heavy review for irreversible work; a lighter path (fix blocking findings, take cheap non-blocking ones, defer the rest) for guard code behind a flag that has not moved data yet, especially once a reviewer starts flagging patterns instead of concrete bugs. When a reviewer's tone signals they are reaching their limit, relay that signal to the project owner rather than smoothing it over as a plain "approved."

10. **A teammate showing as "running" can still be hung.** Judge it by file and resource activity, not by a status label; when it hangs, stop it, diff its half-finished edits against its last known-good state, and hand the exact state to a fresh teammate.

See [[browser-testing-via-subagents]], [[parallel-path-invariants]], [[fake-must-model-the-system]], [[reviewer-forks-race]].
