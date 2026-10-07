# Setup, for the AI assistant running it

You are being asked to install this repo (claude-setup) for the person you are working with. Follow these steps in order. This file is written to you, not to them; speak to them in your own words, not by reading this file aloud.

## 1. Check prerequisites

Confirm each of these is present and actually working, not just installed:

- **git** -- needed to clone and later update this repo.
- **bash** -- Git Bash on Windows (ships with Git for Windows), already present on Mac/Linux.
- **A real Python interpreter on PATH** -- run `python3 -c 1` (Mac/Linux, Git Bash on Windows) or `python -c 1`; it must exit 0, not just exist. On Windows, a `python3`/`python` that resolves on PATH but does not actually run (a Microsoft Store placeholder) is common; check the real exit code, not just whether the command was found.

If anything is missing or does not actually run, STOP here and tell the person exactly what to install (Git from git-scm.com or your OS's package manager; Git for Windows for bash on Windows; Python from python.org or your OS's package manager) and why -- the installer itself does not strictly need Python, but the coordination hooks it wires (notably the git-write guard) are meaningfully weaker without one. Do not proceed past this step until every prerequisite actually works.

## 2. Ask which plan they have

Ask the person which Claude plan they are on. Use this as a starting suggestion, phrased as a suggestion, not a rule:

- Cheapest paid plan -> `lite`
- A mid tier -> `standard`
- The highest tier -> `max`

Plans and what model access they include change over time, so tell them this mapping is a starting point: check which models their specific plan actually allows before committing to one. When they are unsure, suggest the cheaper profile -- switching up later is one flag, and the cheaper profile costs them nothing to try first.

## 3. Dry run, then get an explicit yes

Run the installer with `-DryRun`/`--dry-run` and their chosen profile:

```
# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File install.ps1 -DryRun -Profile <name>

# Mac/Linux (or Git Bash on Windows)
./install.sh --dry-run --profile <name>
```

Show them, in your own words, what it says it will link, and what of theirs (if anything already exists at those paths) will be backed up and where. **Their own `settings.json`, `CLAUDE.md`, `agents/`, and `commands/` -- if they have any of these already -- are moved aside, not merged: none of it is active while this is installed, and it all comes back exactly as it was if they ever uninstall.**

If they already had a `settings.json`, the dry run prints which of its top-level keys would be added, removed, or changed (for example `permissions`, `env`, `hooks`). Read that line and tell them plainly which of their own settings (a permissions allowlist, an env var, a hook they had wired) would stop applying while this is installed -- NOT that they should hand-edit the installed copy to bring any of it back. Hand-editing `~/.claude/settings.json` after install makes this installer treat it as changed since it last wrote it: every later `-Update`/`--update` and profile switch then refuses and leaves it alone (by design, so a hand-edit is never silently clobbered), and uninstall leaves the hand-edited file in place rather than restoring the ORIGINAL, which stays in the backup folder for the user to restore by hand. If they want a setting like this active permanently:
- A `permissions` allowlist almost always belongs in a PROJECT's own `.claude/settings.local.json` instead (per-project, untouched by this installer) -- point them there rather than the global file.
- Something that must be global and personal to them (not per-project) means forking this repo and putting it in the fork's own `global/settings.json`, which this setup is built to let you fork for exactly that reason (see `README.md`'s "What's personal vs generic").

Get an explicit yes before running it for real. If they say no, or want to pick a different profile, go back to step 2.

## 4. Install, then verify

Run the same command without `-DryRun`/`--dry-run`. Then tell them to restart Claude Code (close and reopen it, or start a new session) so the new `settings.json` and hooks take effect.

To verify it worked, ask the restarted session "what model do you use for the builder role" and compare the answer against the profile table in `README.md`'s "Pick a profile" section. If it does not match, something did not install as expected; re-read the installer's own output for a WARNING line before troubleshooting further.

## 5. What they can do later

Tell them, briefly:

- **Switch profile**: re-run the installer with `-Profile <name>` / `--profile <name>` any time; no `-Update`/`--update` needed, that flag is for something else (see below).
- **Update**: `git pull` in the cloned repo. Because the install uses live links, most changes apply immediately with no re-install -- EXCEPT for whatever fell back to a plain copy instead of a real link, which only `-Update`/`--update` refreshes:
  - `standard`/`lite`, after a pull that changed `agents/`, `profiles/`, or `global/settings.json` -- `settings.json` (and the rendered agent files) are always a tracked copy there, on every platform, so always re-run with `-Update`/`--update` after such a pull, regardless of OS.
  - On Windows WITHOUT Developer Mode (the common case, and the likely one for a friend who has never heard of it), file symlinks cannot be created at all, so `CLAUDE.md` falls back to a copy on EVERY profile, and `settings.json` falls back to a copy on `max` too -- a pull that changed `global/CLAUDE.md` (any profile) or `global/settings.json` (`max`) needs `-Update` there as well. Tell them to just re-run the installer with `-Update` (same profile, no need to pass `-Profile` again) after any `git pull`, rather than trying to track which specific file changed.
- **Uninstall**: run `uninstall.ps1` (Windows) or `uninstall.sh` (Mac/Linux) from the repo; it restores whatever the installer backed up and removes only what it created.

## 6. What you must never do

- Never edit any file of theirs outside what the installer itself touches (see README.md's "What this changes on your machine").
- Never commit or push anything in this repo on their behalf. This installer never runs git itself; neither should you, here.
