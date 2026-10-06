# Ask which branch before writing code

**Rule:** If a coding task does not name a branch, ask before the first file edit, or confirm the current branch is the intended one. Never create or switch branches without being asked, unless you are acting as the orchestrator of a teammate workflow (see below).

**Why:** Nobody creates a branch implicitly. A whole feature once landed on the main branch by accident because neither side thought to name one, and the human had to move several files to a new branch by hand afterward.

**How to apply:**
- At the start of a coding task, if no branch was named, ask "which branch?" before the first edit, not after.
- Exception, when running the orchestrator role of a teammate workflow (see [[orchestration-workflow]]): the orchestrator may cut a lane's worktree and branch itself (`git worktree add -b <branch> ../<dir> main`) and start that worktree's dev server, because teammates cannot run git. The branch name still comes from the agreed plan, never invented on the spot. Commits, pushes and PRs stay the user's call unless they ask for them in that message.
