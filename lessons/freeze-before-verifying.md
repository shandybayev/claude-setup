# Freeze a tree before verifying it, not after being told it moved

**Rule:** A check against a moving tree does not count as a check. Get an explicit "holding, no changes" confirmation from whoever last touched the code before you (or a reviewer) start measuring it.

**Why:** A reviewer handed a moving target has returned failures that were not real, because files were still being saved mid-measurement.

**How to apply:** Tell a builder to HOLD before handing its work to a reviewer. Give the reviewer the frozen baseline explicitly: head revision, test count, line counts, so it can tell on its own if the tree moved under it. See [[orchestration-workflow]].
