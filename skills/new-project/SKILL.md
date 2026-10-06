---
name: new-project
description: Set a project up with the owner's personal claude-setup. Triggered by "set this project up with my claude-setup", "set up my claude-setup here", or /new-project. Creates the project's CLAUDE.md, briefs folder, and gitignore additions from templates, and offers to install the harness.
---

# New project setup

This skill wires a project to use the owner's personal `claude-setup` conventions: a project `CLAUDE.md`, a `briefs/` coordination folder, and optionally the quality-gate harness. It never commits anything.

Both installers link the repo itself to a stable path, `~/.claude/claude-setup`. Every source file this skill reads is under that path, not a relative one, since this skill runs from inside whatever project is being set up, not from inside the claude-setup repo.

## Steps

1. **Ask only the needed questions**, in one batch, and accept "skip" or "none" for any of them:
   - What is the stack (language, framework, package manager)?
   - What command runs tests? What command runs lint? What command runs a typecheck (if the language has one)?
   - What is the deploy target (or "none yet")?
   - Does this project have a database? If so, which kind, and is there a safe local or throwaway instance to test against?
   - Does this project have a git remote already, and if so, is it private?

2. **Create the project `CLAUDE.md`** from `~/.claude/claude-setup/templates/project/CLAUDE.md.template`, filling in the answers above. Leave any unanswered placeholder in `<angle brackets>` rather than guessing.

3. **Create the `briefs/` folder** with:
   - `briefs/README.md` from `~/.claude/claude-setup/templates/project/briefs/README.md`.
   - `briefs/COORDINATION.md` from `~/.claude/claude-setup/templates/project/COORDINATION.md.template`.
   - `briefs/HANDOFF.md` from `~/.claude/claude-setup/templates/project/HANDOFF.md.template`.

4. **Suggest `.gitignore` additions** from `~/.claude/claude-setup/templates/project/gitignore-additions.txt`: print them and ask whether to append them to the project's existing `.gitignore`, or append them yourself if asked to.

5. **Offer the harness.** Ask whether to install the generic quality-gate kit (`~/.claude/claude-setup/harness/`: an edit-time hook, a pre-commit and pre-push git hook, and a matching CI workflow, all calling one script so the layers cannot drift). If yes:
   - Ask for the format, lint, typecheck, and test commands if not already given in step 1, and whether any file-size thresholds should differ from the defaults (warn 500 lines, block 700).
   - The harness reads its config from `<project root>/harness/harness.config`, next to `gates.sh`, never from the project root itself. Create `<project root>/harness/` if it does not exist yet, and write `<project root>/harness/harness.config` from `~/.claude/claude-setup/harness/harness.config.example`'s key list (`LOC_WARN`, `LOC_BLOCK`, `FORMAT_CMD`, `LINT_CMD`, `TYPECHECK_CMD`, `TEST_CMD`, and any per-extension `FORMAT_<ext>`/`LINT_<ext>` pairs the stack needs) with the owner's answers filled in, BEFORE running the installer: the installer only writes this file from the example when one is not already there, and leaves an existing one alone, so writing it first is what makes the answers stick.
   - Run `~/.claude/claude-setup/harness/install.sh --target <project root>` (or `~/.claude/claude-setup/harness/install.ps1 -Target <project root>` on Windows) to finish wiring it: that step copies the harness scripts into the project, sees `harness/harness.config` already present and leaves it untouched, writes `.githooks/pre-commit`, `pre-push` and `commit-msg`, sets `core.hooksPath` to `.githooks` in the project's git config, merges the Claude Code edit-time hook into the project's `.claude/settings.json`, and copies `~/.claude/claude-setup/templates/ci/gates.yml` into `.github/workflows/`. It never commits anything. Run `~/.claude/claude-setup/harness/install.sh --verify --target <project root>` (or the `.ps1` equivalent) right after, and report its OK/FAIL lines.
   - **Prove the gate actually blocks**, do not just trust that the config was read: in the target project, make one throwaway change that the configured commands should reject (for example a file with a debug leftover, or one that fails the configured `LINT_CMD`), run `<project root>/harness/gates.sh all` from the project root, and confirm it reports `BLOCK` and exits non-zero. Then remove the throwaway change and re-run `gates.sh all` to confirm it passes clean. Report both runs; a skipped step here is how a misconfigured or misplaced `harness.config` goes unnoticed (see `~/.claude/claude-setup/templates/docs/revert-table.md` for the same shape of proof).
   - Point at `~/.claude/claude-setup/templates/project/HARNESS.md` as the one-page reference to drop into the project's docs, and at `~/.claude/claude-setup/harness/README.md` for the full CLI contract (`harness/gates.sh <commit|push|all|commit-msg FILE>`, the config keys, the bypass policy).

6. **List every file created or written** (including `harness.config` and everything the installer wired, and every file whose change is only suggested, like `.gitignore`), and stop. Never run `git add`, `git commit`, `git push`, or open a pull request on the owner's behalf; the harness installer's `core.hooksPath` config write is not a commit or a push, so running it as part of setup is fine, but every other git action stays the owner's call.

## Notes

- If the project already has a `CLAUDE.md`, do not overwrite it; show the template's content and ask whether to merge it in by hand instead.
- If a `briefs/` folder already exists, do not overwrite its files; point out what is already there.
- This skill is about the PROJECT layer. The global, generic rules in `~/.claude/CLAUDE.md` already apply everywhere; the project `CLAUDE.md` created here is where project-specific facts live.
