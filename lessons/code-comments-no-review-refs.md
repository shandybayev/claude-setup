# Code comments describe the code, never the review

**Rule:** Code comments and docstrings describe what the code does and why, in terms of the code alone. Never reference brief or plan file paths, review documents, review-round labels ("round 2", "R2-1"), plan or decision codes, or fix history. Those do not persist with the repo. Review history and rationale belong in the pull request description.

**Why:** An outside reviewer on a real project flagged many such comments in one pull request: the labels stop making sense to the next reader, who has no access to the review thread that produced them.

**How to apply:**
- Put this rule in every builder and reviewer brief.
- Before any push, grep the diff for review-shaped tokens: path fragments like `briefs/`, round labels (`round [0-9]`, `R[0-9]-[0-9]`), and short decision codes.
- Test docstrings state the scenario pinned and the expected outcome, not which review round asked for the test.
