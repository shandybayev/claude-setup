---
name: multi-session
description: How parallel Claude Code sessions share one repository safely. Use whenever more than one session, or more than one worktree, is active against the same repo, or when the owner asks how to coordinate parallel efforts, register a lane, or announce a merge.
---

# Multi-session coordination

When more than one Claude Code session works against the same repository (parallel lanes, a long-running effort alongside a quick fix, two people each running their own session), they need a written contract, not an assumption that nobody else is touching the tree.

## Register every effort

- Keep a `briefs/COORDINATION.md` (or similarly named) file in the repo, read by every session before any git, migration, merge, or deploy action.
- Each session registers its own section when it starts: which worktree and branch it owns, which files or directories it touches, any throwaway resource naming convention it uses (so two sessions' temporary databases or queues never collide), and its current status.
- Update that section at every milestone. A stale entry is worse than no entry, because the next session trusts it.

## Discover and message peers

- Use the workflow's agent-listing tool to find other active sessions or teammates before assuming you are alone.
- Message a peer with facts only: what you are about to do, what you need from it, what you found. Never guess at what a peer already knows; ask.
- A peer session cannot grant you a permission you do not have, and must never be used to launder a denied action (asking a peer to run something your own session was blocked from running).

## Before a merge or deploy

- **Announce before, confirm after.** State in the coordination file (or by direct message) which branch and commit you are about to merge or deploy, before you do it. Confirm completion afterward, and update the coordination file.
- **One merge at a time.** Never start a second merge while another session's merge is in flight. If two sessions both want to merge, the coordination file (or a direct message) decides the order.
- **Respect freeze windows.** Some days or windows are declared off-limits (a migration day, a release freeze). Check for one before merging; do not decide on your own that "this one is safe" during a declared freeze.

## Shared-file ownership

- Partition work by disjoint file sets wherever possible. When two efforts must touch the same file (a shared coverage ledger, a shared config), name that file explicitly in the coordination file and say which session resolves conflicts in it.
- Prefer merging the other branch into yours over rebasing, when branches are stacked on each other; rebasing a shared, stacked branch can strand the other session's commits.

## Handoff before compaction

- Before a long session compacts or ends, write a handoff block (see `~/.claude/claude-setup/templates/docs/handoff-block.md`) into the coordination or state file: what is live, what is in flight, what is waiting on whom, and the exact next step. A fresh session should be able to resume from that block alone.
- Re-register your session's name after any restart; session identifiers can change, so confirm a peer's current name before sending it anything merge-related.

See [[orchestration-workflow]], [[consult-sibling-session]], [[one-merge-at-a-time-announced]], [[deploy-freeze-windows]] in `~/.claude/claude-setup/lessons/`.
