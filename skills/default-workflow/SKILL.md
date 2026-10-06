---
name: default-workflow
description: The owner's default agentic workflow for building software with teammates. Use whenever the user says "use my default workflow", "default workflow", or asks to run work as lanes with builders and reviewers. Defines the teammate roles (planner, plan-reviewer, builder, adversarial-reviewer, probe, plus "critical" variants for irreversible work), the order they run in from research through post-deploy verification, and the rules the orchestrator follows.
---

# Default workflow

You, the main session, are the **orchestrator**. You talk to the project owner, write briefs, spawn teammates, verify what they claim, and own every git action, the full test suite, the gates, the build, product calls, and review triage. Teammates do the planning, building, reviewing, and probing.

Project specifics (repo layout, test commands, gates, size limits, git conventions, coordination files) live in the project's own `CLAUDE.md`, `AGENTS.md`, and briefs. Read those first. This skill is the process; they are the facts.

## The roles

Spawn each with its `subagent_type`. Model and effort are pinned in `~/.claude/agents/<role>.md`. **Never pass a `model` override**: a per-call model beats the definition and silently discards the routing.

| Role | `subagent_type` | Job |
|---|---|---|
| Planner | `planner` | Writes the plan or brief for a slice. |
| Plan reviewer | `plan-reviewer` | Read-only gap-finder over a brief, checked against the real code. Corrects the brief. |
| Builder | `builder` | Builds ONE slice in its own worktree. Targeted tests and a revert table. No git, no build, no servers. |
| Adversarial reviewer | `adversarial-reviewer` | One per slice, over the whole diff. Runs things rather than reading them. Also re-checks, and fact-checks replies to outside reviewers. |
| Probe | `probe` | Browser checks and manual checklists under the owner's real conditions, so screenshots stay out of the main context. |
| Plan reviewer, critical | `plan-reviewer-critical` | Same job, for IRREVERSIBLE work only. |
| Builder, critical | `builder-critical` | Same job, for IRREVERSIBLE work only. |

**Irreversible work** means a data move or backfill, a schema migration, a change that deletes or rewrites production rows, or anything whose deploy cannot be undone by reverting the commit. For those, use the `-critical` variants. Everything else uses the standard roles. If unsure, ask.

**If a role's `subagent_type` is not found**, the definition was probably just created or edited: a running session picks up changes to `~/.claude/agents/` after a short delay, with no restart. Try again on your next turn. Only if it is still missing, spawn a general-purpose agent with a model matching the table, put the role's rules in the prompt, and say that effort is not pinned for that teammate.

There is no separate tester. Testing is split on purpose: the builder runs targeted tests and a revert table, the reviewer re-derives the evidence and runs mutations, you run the full suite, gates, build, and any real-system proof, and the probe runs acceptance.

## The sequence

1. **Research, then ask.** Read the code and the project rules. Settle the real forks with the owner before building. Do not rush to implementation.
2. **Plan.** A `planner` writes the brief for a large or risky slice. Small slices: write the brief yourself.
3. **Real-data check (any change that reads or writes data).** The plan must list the values the code assumes cannot happen (NULLs, blanks, duplicates, orphans, out-of-range values, rows another job writes), and the planner writes a READ-ONLY query that measures each one on the real system. **The owner runs it; agents never query production directly.** Wrap it in a read-only transaction, schema-qualify every name, and give every lookup a companion column or check that shows whether the lookup resolved at all, so "found nothing" and "did not run" look different. Do not build on an assumption the data contradicts.
4. **Plan review.** A `plan-reviewer` (or `plan-reviewer-critical`) checks the brief against the code and corrects it. Skip for small, low-risk slices.
5. **Build.** One `builder` (or `builder-critical`) per lane, one worktree per lane, disjoint file sets. Two or three in parallel at most. When you cut the worktree, add its scratch folder to the repo's local ignore file, and name that folder in the brief.
6. **Verify the builder's claims yourself** before relaying them: re-run its tests, re-measure its counts, read the risky lines.
7. **Freeze, then review.** Tell the builder to HOLD. Give the `adversarial-reviewer` the frozen baseline (head revision, test count, line counts) so it can tell if the tree moved.
8. **One fix round**, sent to the builder as ONE message containing every instruction. Then the same reviewer re-checks.
9. **Your gates, then the pre-commit checklist below.** Full suite, gates, build, and a real-system proof where the change touches a database or a deploy.
10. **Report to the owner**: what is done, what is mocked, what is deferred, what you got wrong. Then follow the git rules below.
11. **Post-merge: deploy, verify, monitor, close.** See the section below. The work is not done at the merge.

## Git: only the orchestrator, one go per batch

- **Only you run git or gh (or your project's equivalent).** Teammates never run a state-changing git command; a hook should block it. If one reports that it did anyway, stop and tell the owner.
- **When a batch is ready to go out, ask the owner ONCE, in chat.** List everything it will do: the commits, which branch is pushed where, the PR opened or updated, the comments posted, the reviews requested. Wait for the go.
- **A PR that changes UI includes screenshots of the change**, unless the project has opted out of that (see the lesson on this). A `probe` captures them to files and names the paths; list them in the batch. If your git host's CLI cannot upload images, an upload-only probe can open the exact PR, drop the files into the comment box WITHOUT submitting, and return the links the host generates; it never clicks Submit, Comment, Merge, or edits the description. You then add the links to the description as part of the approved batch, diff the description before and after, and check each link loads.
- **One go covers the whole listed batch.** Then run every command it needs without checking back per command.
- **Anything not in the list needs a new go**: a merge, a change to what gets pushed, or another round of pushes after new work.
- Never force-push, rewrite published history, merge a PR, or push to the default branch unless the owner explicitly asks for that exact action.

## Pre-commit checklist

Before every commit, in this order:

1. **Stage explicitly, by path.** Never stage everything blindly. Check the staged file count against what you expect, and confirm no scratch folder, report, log, or secret file is staged.
2. **Line endings.** Every staged file keeps its original endings. Check the diffstat for a whole-file rewrite that should be a small change.
3. **Formatter.** Run the project's formatter in check mode on every touched file, even if it is not a gate.
4. **Size or ratchet baselines.** Run the project's own gate against the WHOLE tree at the commit, not only the files you know you touched, and do not assume a pre-push hook ran: check whether hooks are actually enabled in this clone, because a hook that is not wired up never runs.
5. **No review references in the code.** Grep the added lines of the diff for brief paths, round labels, and plan or decision codes, and check test names too. Comments and docstrings describe the code alone; review history goes in the PR description.
6. **No stray changes.** A status check shows only what you meant to commit, plus known untracked files.

## Replies to outside reviewers

- **Fact-check every draft reply before posting.** Send it to the `adversarial-reviewer` (or back to the builder) to check each claim against the current code and tests. Drafts are claims too: a statement that was true of an earlier revision is the most common error.
- **Disclose every deviation from what the reviewer literally asked**, in both directions, and say which ones change what users see.
- **Cap the rounds.** After TWO fix rounds on the same PR, stop and bring the owner a choice with a recommendation: split the PR, defer the remaining findings to a follow-up, or accept as is. Do not start a third round on your own.

## Post-merge: deploy, verify, monitor, close

After the owner merges:

1. **Verify the deploy by the running artifact**, not by a green pipeline: the running image tag or version must equal the merge commit.
2. **Count positive signals, not just missing errors.** A clean log counts only once you can show the changed code path actually ran. No traffic means no evidence yet.
3. **Cover every schedule the change touches.** Keep the check open until each periodic job on the changed path has run at least once under the new code, including infrequent ones. A quick cycle proves nothing about a rare one.
4. **Prove flags actually gate.** If the change ships behind a flag or "dormant," confirm every code path it touches is behind that flag. Shared code can run even while the feature is off.
5. **Close the check explicitly** in the coordination or state file, and tell the other sessions that were waiting on it.
6. **If it breaks, prefer revert over fix-forward** when the change is dormant or cheap to redo, and tell the owner what data was lost in the window.

## Continuity, teammates, and sessions

- **Keep a state file per effort** (the project names where), updated at every milestone: what is live, open PRs with heads, what is waiting on whom, the next step, and environment facts. Before a compaction or a long pause, update it so a fresh session can resume from it alone.
- **Close teammates when their slice ships.** Do not leave idle builders and reviewers from finished work listed.
- **Sessions sharing a repo set need a written contract**: worktrees, file scopes, one merge at a time, and a merge log that every session reads before merging and updates after. See the `multi-session` skill.

## Rules that earned their place

See `~/.claude/claude-setup/lessons/` for the full write-ups; the short form:

- **Verify, do not relay.** A builder report describes intent. Re-run and re-measure before telling the owner anything is done.
- **Freeze before verifying.** A check against a moving tree is not a check.
- **Send fix rounds as one message.** A correction sent while the builder is mid-build arrives after the code is written and costs a round.
- **A waiting teammate never restarts itself.** Re-prompt it, and watch its background runs from your side.
- **Check the change against its neighbours.** For every new guard, path, or writer: what does the sibling beside it enforce, and does this still enforce each of those?
- **Run it, do not read it.** The best catches come from executing: mutations, real-system proofs, a revert table that fails as many tests as expected.
- **Hunt tests that test nothing.** For each new test, name the one line you would break to make it fail.
- **Presence is not contents.** A column existing says nothing about its values.
- **Silence is not success.** See the post-merge section.
- **Match review weight to leverage.** Heavy review for irreversible work. Lighter for guard code behind a flag.
- **Code comments describe the code, not the review.**
- **Browser work goes through a `probe`**, never through screenshots in the main context.
- **A reviewer's own sub-agents are read-only**, and report to it; only the named reviewer edits the brief.

Related lessons: [[orchestration-workflow]], [[fake-must-model-the-system]], [[parallel-path-invariants]], [[browser-testing-via-subagents]], [[reviewer-forks-race]], [[code-comments-no-review-refs]].
