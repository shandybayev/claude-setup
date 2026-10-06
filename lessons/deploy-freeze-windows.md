# Respect deploy freeze windows (such as migration days)

**Rule:** Some days or windows are declared off-limits for merges or deploys (for example, a day reserved for a database migration, or a freeze around a release). Check the project's coordination file for an active freeze window before merging or deploying, and never schedule a merge into one without the project owner's explicit go-ahead.

**Why:** Merging unrelated work during a migration or release window can interleave with the sensitive operation in ways that are hard to reason about and hard to revert, even when the unrelated work is itself safe on an ordinary day.

**How to apply:** Record any declared freeze windows in the shared coordination file, with their dates and reason. Before merging, check for an active window. If a merge is urgent during a freeze, ask the project owner explicitly rather than deciding on your own that it is safe.
