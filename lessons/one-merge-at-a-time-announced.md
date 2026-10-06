# One merge at a time, announced to other sessions

**Rule:** When multiple sessions or efforts share a repository, only one merge happens at a time, and the session doing it announces the merge to the others before starting and confirms completion after. This belongs in the shared coordination file every session reads before merging.

**Why:** Two merges landing close together without coordination can conflict in ways neither author expected, or can interleave migrations and deploys in an order nobody verified, especially when the repo has schema migrations or other ordering-sensitive state.

**How to apply:** Keep a coordination file (see the multi-session skill) that every session reads before merging and updates after. Before merging, state in that file (or by direct message to peers) which branch, which commit, and that a merge is about to happen; confirm after it lands. Never start a second merge while another session's merge is in flight.
