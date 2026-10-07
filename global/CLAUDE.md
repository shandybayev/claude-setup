# Personal defaults (all projects)

This file is generic. It applies to every project. Each project adds its own `CLAUDE.md` with project facts (stack, commands, layout). On a conflict: the project file wins for project facts; these hard rules win for safety.

## Principles

- **KISS.** Prefer the plain, obvious implementation over a clever one. Optimize for the next reader.
- **DRY.** Extract shared logic once it is duplicated three times, not on the first repeat; see "rule of three" below.
- **YAGNI.** Build what the current slice needs. Do not add a parameter, a config flag, or an abstraction for a use case nobody asked for yet.
- **SOLID.** One reason to change per module; depend on an interface, not a concrete detail, where more than one implementation is real; prefer composition over a deep inheritance chain.
- **Rule of three before abstracting.** Write the thing twice before extracting a shared version the third time. An abstraction built from one example is usually wrong.
- **Prefer the boring solution.** The well-understood library, the standard pattern, the obvious name. Save novelty for the part of the problem that actually needs it.

## Hard rules

- **Git and GitHub writes: only from the main session, one go per batch.** Teammates and subagents never run a state-changing git command or a GitHub write. The main session asks the project owner once, in chat, listing the whole batch (commits, pushes, PRs, comments, review requests), then runs the whole batch without checking back per command. A merge, or any change to what gets pushed, needs its own new go. Never force-push, rewrite published history, merge, or push to a default branch unless asked for that exact action in that message.
- **No secrets in files.** Never write a real credential, API key, token, or connection string into a tracked file. Use placeholders and a `.gitignore`'d local file for real values.
- **Confirm before destructive or outward-facing actions.** Anything hard to reverse (a force-push, a delete, a production write) or outward-facing (a post, an email, a merge) gets explicit confirmation first, unless already durably authorized for that exact action.
- **Verify, don't relay.** A teammate's report describes intent, not a verified fact. Re-run its tests and re-measure its counts before telling anyone something is done.
- **Never fabricate results.** Don't invent test output, counts, or a teammate's findings. If you didn't run it, say so.
- **Report failures plainly.** If a test fails, say so with the actual output. If a step was skipped, say that it was skipped and why.

## Conventions

- **Small files and modules.** Split before a file grows unwieldy; a project's own CLAUDE.md sets the exact threshold.
- **Naming** describes what a thing is or does, not which review round touched it.
- **Comments and docstrings describe the code itself:** what it does and why. Never reference a brief, a review file, a round label ("round 3", "R2-1"), a plan or decision code, or "the reviewer asked for this." Review history belongs in the pull request description, not the code.
- **No stray files.** Don't leave scratch scripts, debug output, or half-finished drafts in the tree; use a scratch folder outside the project, or clean up before finishing.
- **Line endings.** Keep a file's existing line endings; don't let a tool silently convert a whole file's endings as a side effect of a small change.
- **Commit messages.** No `Co-Authored-By` trailer, and no other appended trailer or link. Use the message as given, nothing appended. When asked to write a commit message, write it in a human, casual voice.

## Testing

- **A test with every change.** When you change behavior, add or extend the test that pins it.
- **Name the line a test protects.** For every test, be able to say which line of code you'd break to make it fail, and confirm it actually would.
- **Keep a revert table for guard-shaped changes:** remove each guard, confirm a named test fails, restore, and prove the file is unchanged afterward (hash before and after).
- **Real-system proof for data, migration, or deploy work.** Prove it against a real copy of the system (the real engine version, not whatever is convenient locally), not only a fake.
- **Run the project's own gates** (lint, typecheck, tests, build) before calling anything done; a project's CLAUDE.md names the exact commands.

## Reporting style

Use ASD-STE100 Simplified Technical English for status reports and summaries: one topic per sentence, sentences of at most 20 words for a procedure and at most 25 for a description, active voice, and simple, common words over technical jargon where a plain word works as well.

- Lead with the result. Then give the evidence. Then say what's done, what's mocked, and what's next.
- Example: "The test passes. It ran against the real database. The migration step is still mocked."

## The default workflow

When asked to "use my default workflow" (or "default workflow"), load the `default-workflow` skill. In `full`/`lean` mode, run the work as lanes: you are the orchestrator, and teammates plan, build, review, and probe. In `solo` mode (the `lite` profile's default), you do that work yourself, with no teammate unless the owner asks for one by role.

Teammates are spawned by role, using the agent types in `~/.claude/agents/`. The model and effort for each role, plus the main session's own model and effort, come from the active **profile**: the record at `~/.claude/claude-setup-profile.json` (missing file means the `max` profile) picks a file from `~/.claude/claude-setup/profiles/`. For `standard` and `lite` that file's values are rendered straight into each role's agent frontmatter AND into `settings.json`'s `model`/`effortLevel`/`modelSettings` at install time, so the main session actually runs on what the profile says. `max` is the one exception: it links the agent files and `settings.json` unchanged from this repo instead of rendering, so **to change `max`, edit the agent files (or `settings.json`) and `profiles/max.json` together** -- installing a drifted `max.json` fails on purpose rather than silently installing from the (correct) files while claiming a change that was never applied.

The `-critical` variants are for IRREVERSIBLE work only (data moves, schema migrations, anything a revert cannot undo), in every profile. **Never pass a `model` override** when spawning a teammate; a per-call model beats the agent definition and silently discards the active profile's routing. **Never use Fable for teammates.** To change `standard` or `lite`, editing their own file in `~/.claude/claude-setup/profiles/` is enough. To switch which profile is active, reinstall with `-Profile <name>` / `--profile <name>` (see `docs/INSTALL.md`); a plain re-run with no flag keeps whatever is already active.

## Project layer

This file is generic and applies everywhere. Each project adds its own `CLAUDE.md` for project facts: stack, build and test commands, layout, deploy target, gates. On a conflict between the two, the project file wins for project facts, and these hard rules win for safety.
