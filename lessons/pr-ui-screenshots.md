# UI pull requests include screenshots, unless the project opts out

**Rule:** A default, not an absolute: a pull request that changes UI includes screenshots of the changed screens or states in its description (the after state, plus before when it helps, at phone and desktop widths when layout changes). A given project can opt out of this if its human maintainer says so; screenshots can still be taken for the maintainer's own review even when they are not required in the pull request.

**Why:** It is useful team practice by default, but not every project wants it, and the decision belongs to the project's human owner, not to the agent.

**How to apply:**
- A `probe` captures the screenshots to files; name them in the batch you present to the human before acting.
- If the git hosting tool used cannot attach images on its own, a browser-driven probe can open the exact pull request, drop the files into the comment box WITHOUT submitting, and return the image links the host generates. The orchestrator then adds those links to the description as part of an approved batch, diffs the description before and after, and checks each link loads. The probe never clicks Submit, Comment, Merge or Edit.
- Default to light-mode screenshots unless dark mode is specifically what changed.
- Record per project whether screenshots are required in pull requests or only wanted for the human's own review.

Related: [[code-comments-no-review-refs]], [[browser-testing-via-subagents]].
