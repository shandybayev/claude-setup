# claude-setup

A portable, personal Claude Code setup: a team of pinned teammate roles (planner, builder, reviewer, probe), a default workflow for running them as lanes, generic lessons earned the hard way, templates for plans and briefs, slash commands, an MCP server list, and an optional quality-gate harness for any project. Install it once per laptop; it links straight back into this repo, so one `git pull` updates every device.

No company or project-specific information lives here. Everything is generic on purpose, written to be pushed to a private repo and reused across unrelated projects.

## Install on a new laptop

1. Clone this repo somewhere on the machine (for example `~/dev/claude-setup`).
2. Run the installer for your OS from inside the repo:
   - Windows: `powershell -File install.ps1`
   - Mac/Linux: `bash install.sh`
3. Open a new Claude Code session anywhere and confirm it picks up the global `CLAUDE.md` and the agent roles (ask it "what model do you use for the builder role" and check the answer matches the table in `global/CLAUDE.md`).

See `docs/INSTALL.md` for exactly what gets linked, backed up, and left alone, and for the `-DryRun`/`-Update` flags. Both installers also link the repo itself to a stable path, `~/.claude/claude-setup`, so skills and commands can find templates, lessons, and the harness after install, regardless of where you cloned it.

## Start a new project

Open a session in the project's folder and say "set this project up with my claude-setup" (or run `/new-project`); it asks a few questions and creates the project's own `CLAUDE.md`, a `briefs/` coordination folder, and offers the optional harness.

## Update

`git pull` in this repo. Because the install uses live links (symlinks or directory junctions) rather than copies, every linked file picks up the change immediately; no re-install needed unless a brand-new top-level file or skill was added, in which case re-run the installer.

## Uninstall

Run `uninstall.ps1` (Windows) or `uninstall.sh` (Mac/Linux) from the repo. It restores whatever the installer last backed up and removes the links this repo created. It never touches anything the installer did not itself create or back up.

## What's personal vs generic

- **Generic** (safe to reuse across any project, any laptop): everything in `agents/`, `skills/`, `lessons/`, `templates/`, `commands/`, `mcp/`, `harness/`, and the hard rules in `global/CLAUDE.md`.
- **Personal choices, called out in `~/.claude/claude-setup/docs/INSTALL.md`**: the specific statusline command, the default model and effort settings in `global/settings.json`, and which keys the installer merges versus leaves alone. Treat `global/settings.json` as a starting point; keep your own copy's personal choices if you fork this for someone else.

## Add a project rule

Project-specific facts (stack, test commands, deploy target) never go in this repo. They go in the project's own `CLAUDE.md`, created from `~/.claude/claude-setup/templates/project/CLAUDE.md.template` by the `new-project` skill. On a conflict between that file and the generic global `CLAUDE.md`, the project file wins for project facts, and the global file's hard rules (git discipline, no secrets, confirm before destructive actions) win for safety.

## Add a lesson

Write a new file in `~/.claude/claude-setup/lessons/`, one lesson per file, with a `Rule`, a `Why`, and a `How to apply` section (see any existing file for the shape). Add a one-line pointer to `~/.claude/claude-setup/lessons/README.md`. Keep it generic: no company names, hosts, IPs, or incident-specific detail that would only make sense to one project. Link related lessons with `[[their-file-name]]`.

## Troubleshooting

- **Windows directory junctions.** The installer links folders (`agents/`, `skills/<each>`, `commands/`, `hooks/`, the statusline folder) as directory junctions, which need no admin rights. If a junction fails to create for any reason, the installer falls back to a plain copy and prints a warning; re-run with `-Update` after pulling new changes to refresh those copies.
- **Git Bash path on Windows.** `install.sh` and the harness's hooks expect to run under Git Bash. If `bash` is not on `PATH`, install Git for Windows (which includes Git Bash) and re-open your terminal.
- **PowerShell 5.1 and `${var}:`.** A variable immediately followed by a colon inside a double-quoted string (`"$var:something"`) is parsed as a drive reference in Windows PowerShell 5.1, not as the variable's value plus a literal colon. Use the brace form (`"${var}:something"`) in any script you write for this setup; see `~/.claude/claude-setup/lessons/powershell-var-colon-drive.md`.
- **Nothing happened after `git pull`.** Confirm the installer used links, not copies, for the file in question (`~/.claude/claude-setup/docs/INSTALL.md` shows how to check). A plain copy (the symlink-not-allowed fallback) needs `-Update` to pick up new content.

See `~/.claude/claude-setup/docs/INSTALL.md` for the full installer contract and `~/.claude/claude-setup/harness/README.md` for the quality-gate kit's CLI and config.
