# claude-setup

A portable, personal Claude Code setup: a team of pinned teammate roles (planner, builder, reviewer, probe), a default workflow for running them as lanes (or just the main session alone, on the lightest profile), generic lessons earned the hard way, templates for plans and briefs, slash commands, an MCP server list, and an optional quality-gate harness for any project. Install it once per laptop; it links straight back into this repo, so one `git pull` updates every device.

No company or project-specific information lives here. Everything is generic on purpose, written to be pushed to a (private or public) repo and reused across unrelated projects, including sharing it with someone else.

## Quick start

1. Clone this repo somewhere on the machine (for example `~/dev/claude-setup`).
2. `cd` into it.
3. Open Claude Code in that folder.
4. Say: "Read SETUP-WITH-CLAUDE.md and install this setup for me."

Claude Code will check prerequisites, ask which plan you have, show exactly what it is about to link, copy, and back up, and wait for a yes before touching anything. See `SETUP-WITH-CLAUDE.md` for the full steps it follows.

## Install it yourself (manual route)

1. Clone this repo somewhere on the machine (for example `~/dev/claude-setup`).
2. Run the installer for your OS from inside the repo:
   - Windows: `powershell -File install.ps1`
   - Mac/Linux: `bash install.sh`

   On a first-time install, with a real terminal attached, it asks which Claude plan you have, to pick a profile (see "Pick a profile" below); pass `-Profile <name>` / `--profile <name>` to skip the question. Running it non-interactively (a script, or `-Yes` / `--yes`) with no profile given and none recorded yet now STOPS instead of picking one for you -- there is no safe default profile, and installing the heaviest one (`max`) for someone who said nothing would be exactly backwards.
3. Open a new Claude Code session anywhere and confirm it picks up the global `CLAUDE.md` and the agent roles (ask it "what model do you use for the builder role" and check the answer matches the active profile; see `~/.claude/claude-setup-profile.json`).

See `docs/INSTALL.md` for exactly what gets linked, backed up, and left alone, and for the `-DryRun`/`-Update`/`-Yes` flags. Both installers also link the repo itself to a stable path, `~/.claude/claude-setup`, so skills and commands can find templates, lessons, and the harness after install, regardless of where you cloned it.

## Prerequisites

- **git**, to clone and update this repo.
- **bash** (Git Bash on Windows; already present on Mac/Linux), since `install.sh`/`uninstall.sh` and the coordination hooks run under it even on Windows.
- **A working `python3` or `python`** on `PATH` -- not just present, but able to actually run (`python3 -c 1` or `python -c 1` exits 0). The installer itself does not need Python, but the two hooks it wires (the git-write guard, and the session-start context injector) do; both already fall back to a safe default on their own if neither interpreter works, so a missing or broken Python degrades gracefully rather than breaking anything, but the guard in particular is weaker without it (see "What this changes on your machine" below).

## What this changes on your machine

Everything lands under `~/.claude` (pass `-Target <dir>` / `--target DIR` to use somewhere else, mainly for testing):

- `~/.claude/claude-setup` -- a link back to wherever you cloned this repo, so everything else below can find templates, lessons, and the harness at a stable path.
- `~/.claude/CLAUDE.md` -- linked straight from this repo, the same content regardless of profile (never rendered; a copy with a WARNING if a real link cannot be made, e.g. no admin rights/Developer Mode on Windows).
- `~/.claude/settings.json` -- linked straight from this repo for `max`; for `standard`/`lite`, rendered with that profile's model/effort first and then installed as a tracked copy (never a link); see "Pick a profile" below.
- `~/.claude/agents/`, `~/.claude/commands/`, `~/.claude/hooks/`, the statusline folder, and each skill under `~/.claude/skills/` -- linked from this repo (directory junctions on Windows, no admin rights needed).
- `~/.claude/claude-setup-profile.json` -- a small record of which profile is active, read by the `default-workflow` skill and the session-start hook.

**Anything already sitting at one of those paths -- your own `settings.json`, `CLAUDE.md`, `agents/`, `commands/` -- is moved aside (backed up), not merged, the FIRST time it is taken over (never again after that): none of it is active while this is installed, and `uninstall.ps1` / `uninstall.sh` restores it exactly as it was, later (unless you hand-edit the installed `settings.json`, see below).** If you had your own `settings.json`, the installer (and a `-DryRun`/`--dry-run` beforehand) prints which of its top-level keys -- a `permissions` allowlist, `env` vars, your own `hooks` -- would be added, removed, or changed, so you know what stops applying while this is installed. Do NOT hand-edit the installed `~/.claude/settings.json` to bring any of that back: this installer then treats it as changed since it last wrote it, so every later `-Update`/`--update` and profile switch refuses and leaves it alone (by design, so a hand-edit is never silently clobbered) until you restore it or uninstall, and uninstall leaves the hand-edited file in place (so your edit is not lost) while your ORIGINAL file stays in the backup folder, where you can restore it by hand. A `permissions` allowlist almost always belongs in a PROJECT's own `.claude/settings.local.json` instead (per-project, untouched by this installer); something that must be a personal global default for you specifically means forking this repo and putting it in the fork's own `global/settings.json` (see "What's personal vs generic" below). Two hooks then run inside every Claude Code session: the git-write guard (`hooks/git_guard.sh`/`.py`) fires on every Bash/PowerShell tool call that mentions `git` or `gh`, to stop a teammate or subagent from committing or pushing; the session-start hook (`hooks/session_context.sh`/`.py`) fires once at the start of a session (and again after a compaction) to inject any handoff, freeze-window, or decision-log context from the current project's `briefs/` folder, if it has one -- nothing to inject means nothing happens, silently.

## Pick a profile

A **profile** picks the model and effort for the main session and for every teammate role, plus the workflow's mode (full, lean, or solo -- see below) and how many teammates run in parallel, all in one flag. Pick the one that matches your plan's usage headroom:

```
# Windows (PowerShell)
.\install.ps1 -Profile standard

# Mac/Linux (or Git Bash on Windows)
./install.sh --profile standard
```

Leave the flag out on a first-time install and the installer asks which plan you have (see "Install it yourself" above for what happens instead when it cannot ask). Leave it out on a later run and it keeps whatever profile is already installed, silently -- there is no default it switches to on its own.

| Role | `max` | `standard` | `lite` |
|---|---|---|---|
| Main session | Opus, xhigh | Sonnet, high | Sonnet, medium |
| Planner | Opus, medium | Sonnet, high | Sonnet, medium |
| Plan reviewer | Sonnet, high | Sonnet, medium | Sonnet, medium |
| Builder | Sonnet, high | Sonnet, high | Sonnet, medium |
| Adversarial reviewer | Opus, high | Opus, high | Sonnet, medium |
| Probe | Sonnet, medium | Sonnet, medium | Haiku, medium |
| Plan reviewer, critical | Opus, high | Opus, high | Sonnet, high |
| Builder, critical | Opus, high | Opus, high | Sonnet, high |
| Workflow mode | full | lean | solo |
| Max parallel teammates | 3 | 2 | 1 |
| Session-start context cap | 8000 chars | 6000 chars | 3000 chars |

**Workflow mode**, in one line each: **full** runs the whole orchestrator-and-teammates sequence (plan, plan review, build, adversarial review); **lean** trims planning for a slice simple enough to brief in one page, but still keeps a builder and reviewer as separate roles; **solo** goes further still -- the main session plans, builds, and tests by itself, with no teammates at all unless you ask for one by name. See `skills/default-workflow/SKILL.md` for the full rules each mode follows, including the review-loop cap (`lean`/`solo` stop and report after one fix round instead of looping) and that irreversible work (data moves, migrations, production deletes, an undoable deploy) always gets a full review pair, in every mode.

- **`max`**: the most usage headroom. Best when your plan gives Opus plenty of room and you want the deepest review on every slice: the main session and four roles (planner, adversarial reviewer, both critical roles) run on Opus.
- **`standard`**: a middle ground. Sonnet carries most of the work; Opus is kept for three roles (adversarial review and both critical roles), the ones where it tends to earn back its cost. The `lean` workflow skips planning and plan review for a slice simple enough to brief in one page. Trades some review depth and planning rigor for meaningfully less usage.
- **`lite`**: the lightest weight, and **the one to pick on the cheapest paid plan** -- see "On the cheapest plan" below. Sonnet throughout (Haiku for the probe), the `solo` workflow (no teammates unless you ask), and a smaller session-start context cap. Trades planning rigor and parallelism for the lowest usage.

Plans and what model access they include change over time; check your own plan rather than assuming a profile name maps to a specific tier -- when unsure, pick the cheaper profile.

This table is what actually gets installed, not just a target: for `standard`/`lite` the main session's `model`/`effortLevel` (and the `modelSettings` block) are rendered straight into the installed `settings.json`, the same way the agent roles are rendered into the installed `agents/`. `max` is the one exception -- it links `agents/` and `settings.json` straight from this repo, unchanged, so there is nothing to render; a check at install time fails loudly if `profiles/max.json` ever drifts from what `agents/*.md` or `global/settings.json` actually say. **To change `max`, edit the agent files (or `global/settings.json`) and `profiles/max.json` together**; to change `standard` or `lite`, editing their own `profiles/*.json` is enough, since those ARE rendered.

Switch profiles any time with `-Profile <name>` (PowerShell) or `--profile <name>` (Mac/Linux) -- no `-Update` needed, that flag only refreshes a fallback copy, never which profile is active; see `docs/INSTALL.md` for exactly what switching re-renders and re-links.

## On the cheapest plan

`lite` works solo by design: the main session handles a slice by itself rather than spinning up teammates, which is both the point (less usage per slice) and the right call when a plan's headroom is tight. A few habits that help regardless of profile, but matter most here:

- **Compact early.** Don't let a conversation run long before compacting; a long history costs more every single turn, not just at the end.
- **`/clear` between unrelated tasks.** Starting fresh for a new task is cheaper than carrying an old one's full context into it.
- **One session at a time.** Running several Claude Code sessions in parallel multiplies usage; on a tight plan, finish one thing before starting the next.
- **Point Claude at specific files** rather than "explore the repo" or "figure out how this works" -- an open-ended search burns far more than a named file or two.
- **Check the usage display before a big task**, so a long build or a wide refactor is a choice, not a surprise.

Also enable only the MCP servers you actually use (see `mcp/README.md`): each one enabled adds its whole tool list to every session's context, whether you use it that session or not.

## Start a new project

Open a session in the project's folder and say "set this project up with my claude-setup" (or run `/new-project`); it asks a few questions and creates the project's own `CLAUDE.md`, a `briefs/` coordination folder, and offers the optional harness.

## Update

`git pull` in this repo. Because the install uses live links (symlinks or directory junctions) rather than copies, every linked file picks up the change immediately; no re-install needed for those. Re-run the installer with `-Update`/`--update` (same profile, no need to pass `-Profile`/`--profile` again) to refresh whatever fell back to a plain COPY instead, after a pull that changed it:
- `standard`/`lite`: `settings.json` and the rendered agent files are always a tracked copy, on every platform, so re-run with `-Update` after any pull touching `agents/`, `profiles/`, or `global/settings.json`.
- On Windows WITHOUT Developer Mode (file symlinks need admin rights or Developer Mode there), `CLAUDE.md` falls back to a copy on EVERY profile, and `settings.json` falls back to a copy on `max` too -- re-run with `-Update` after any pull that changed `global/CLAUDE.md`, or `global/settings.json` on `max`.
A brand-new top-level file or skill being added also needs a re-run (any flags), since nothing links a path that was never there to link.

## Uninstall

Run `uninstall.ps1` (Windows) or `uninstall.sh` (Mac/Linux) from the repo. It restores whatever the installer last backed up and removes the links this repo created. It never touches anything the installer did not itself create or back up.

## What's personal vs generic

- **Generic** (safe to reuse across any project, any laptop, or to share with someone else): everything in `agents/`, `skills/`, `lessons/`, `templates/`, `commands/`, `mcp/`, `harness/`, `profiles/`, and the hard rules in `global/CLAUDE.md`.
- **Personal choices, called out in `docs/INSTALL.md`**: `global/settings.json` carries a theme, a status line command, and an experimental env flag on top of the two hook wirings every install needs; each is documented there as a personal default you are free to change. Treat `global/settings.json` as a starting point; keep your own copy's personal choices if you fork this for someone else.

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

## License

MIT, see LICENSE.
