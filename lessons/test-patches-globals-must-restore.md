# A test that patches global state must always restore it

**Rule:** A test that patches a module registry, an environment variable, a global singleton, or any other process-wide state must restore the original state unconditionally (in a `finally` block, or an equivalent teardown fixture), including when the test itself fails or raises partway through.

**Why:** A test that patches global state without a guaranteed restore leaks that patched state into whichever test happens to run next, producing failures (or, worse, false passes) in unrelated tests that depend on which order the suite happened to run in. This kind of bug is hard to localize because the failing test is innocent; the test that broke the contract has already finished.

**How to apply:** Whenever a test modifies anything broader than its own local variables, pair the patch with teardown in a `finally`, a context manager, or a fixture's cleanup phase, and verify the restore actually runs by checking the state after the test, not just by reading the code and assuming it does.
