# Installing claude-setup

## What "install" means here

This is a LINK install, not a copy. The installer makes `~/.claude/CLAUDE.md`,
`settings.json`, `agents/`, `commands/`, `hooks/`, `statusline/`, each skill
under `skills/`, and `claude-setup` itself (a link to this whole repo, so
anything installed can always find `templates/`, `lessons/`, `harness/`, and
`docs/` at `~/.claude/claude-setup/...` no matter where this repo was cloned)
point straight at this repo. `git pull` in this repo then updates every
device that ran the installer, for anything that is a REAL link; see
"Links vs. copies" below for the one case where that is not true and what
the installer does about it.

Everything else already in `~/.claude` (other skills, plugins, credentials,
project history, caches) is left exactly where it is. The installer never
even looks at `.credentials.json`, `history.jsonl`, `projects/`, `sessions/`,
or a cache folder: none of those names are in the list of things it manages.

## Links vs. copies

A real link (a symlink, a hardlink, or a Windows junction) is what you want:
reading it always reflects whatever is currently in the repo, so `git pull`
is the whole update story. Sometimes the platform cannot make one for a given
path (no admin rights or Developer Mode on Windows for a FILE symlink; one
specific Git Bash + Windows combination has also been seen to make `ln -s`
silently write a full copy instead of linking, with no error).

Both installers now PROVE a link really works before trusting it, instead of
trusting the tool's exit code:
- `install.ps1` checks that the link's own resolved target really points
  back into this repo (see "a user's own link" below for why that specific
  check matters).
- `install.sh` runs one throwaway, non-destructive test per run (never on
  real content) that creates a link, changes what it points at, and checks
  whether the read-back side actually sees the change. If it does not, every
  real path of that type (files, or directories) falls back to an honest
  copy for that run, with a WARNING printed, rather than being silently
  reported as a link that is not actually one.

A path that falls back to a copy is tracked in the manifest
(`.claude-setup-installed` under the target) along with a checksum of what
was written there. `--update` / `-Update` refreshes ONLY an unmodified copy
with the latest repo content; if you edited that file yourself since it was
written, the installer leaves it alone and says so, rather than overwriting
your change.

## A user's own link

If something is already at one of the paths above and it is itself a link
(a symlink, junction, or hardlink), it is only ever treated as already ours
when it resolves to the matching path INSIDE this repo. A link you made
yourself to something else of your own (a dotfiles repo, a Dropbox folder)
is backed up like any other pre-existing content and replaced; only the link
entity moves, which never touches whatever it used to point at.

## Install

```
# Windows (PowerShell)
.\install.ps1

# Mac / Linux (or Git Bash on Windows)
./install.sh
```

Both default to `~/.claude`. Pass `-Target <dir>` / `--target DIR` to install
somewhere else, which is mainly useful for testing against a throwaway
folder before pointing it at the real `~/.claude`.

Pass `-DryRun` / `--dry-run` first on a machine you are not sure about: it
prints exactly what would be linked, copied, or backed up, and changes
nothing.

### What happens, in order

1. `claude-setup` itself is linked at `<target>/claude-setup`, so this repo
   is reachable at a stable absolute path regardless of where it was cloned.
2. Anything already at a path the installer is about to replace gets backed
   up, but only the FIRST time that path is taken over: once a path is
   ours, a later run (including `-Update`) never backs it up again. That
   matters for `-Update`/`--update` specifically: refreshing our own copy is
   not a new takeover, so it does not touch the backup that holds your real
   original.
3. `CLAUDE.md` and `settings.json` are linked as files (see "Links vs.
   copies" above for what happens when a real link is not possible).
4. `agents/`, `commands/`, `hooks/`, and `statusline/` are linked as whole
   directories, using a directory junction on Windows (no admin rights
   needed for a junction, unlike a symlink).
5. Every skill under `skills/` in this repo is linked individually. A skill
   you already had under `~/.claude/skills/` that is not part of this repo is
   never touched.
6. For `settings.json` specifically, if one already existed there (and is
   not already one of our links or copies), the installer prints which
   top-level keys would be added, removed, or changed before linking (or
   copying) ours over it.

Running the installer again is safe. Anything already linked to this repo,
or already an unmodified copy of it, is left alone; nothing gets backed up
or re-linked a second time.

## Update

```
git pull
```

That is the whole update, for everything that is a real link. If a path had
to fall back to a copy, also run the installer again with `-Update` /
`--update` to refresh it (both platforms have this flag now; on Mac/Linux it
only matters for the rare case where a symlink could not be made).

## Uninstall

```
.\uninstall.ps1      # Windows
./uninstall.sh        # Mac / Linux
```

Driven entirely by the manifest the installer wrote
(`<target>/.claude-setup-installed`): only a path that manifest actually
lists is ever touched, and only after re-checking that it still looks like
ours (a link still resolving into this repo; a copy whose content still
matches what was written). Anything that no longer matches is left alone,
with a message saying so, rather than guessed at from a fixed list of
well-known names. Each path restores from the specific backup that holds
ITS own original, not just "the most recent backup folder", so an `-Update`
done in between does not make uninstall hand back a stale copy instead of
your real original. `-DryRun` / `--dry-run` works the same way as on
install. Nothing outside the manifest is ever touched.

Running uninstall with no manifest present (nothing was installed here, or a
previous uninstall already finished) is a safe no-op: it says so and exits,
rather than falling back to deleting anything that happens to sit at one of
the well-known names.

## What's personal vs generic

`global/settings.json` carries a few personal choices on top of the parts
every install needs (the two hook wirings): the default `model`,
`effortLevel`, the per-model `modelSettings` overrides, and `theme`. Edit
`global/settings.json` in this repo (or the linked copy at
`~/.claude/settings.json`, which is the same file) to change any of those;
they are not load-bearing for anything else here.

## The git guard's failure policy

`hooks/git_guard.py` (wired through `hooks/git_guard.sh`) denies a subagent's
state-changing `git`/`gh` commands; see `global/CLAUDE.md`'s "Git and GitHub"
section for the policy itself. This is about what it does when it CANNOT
reach that decision at all: the payload will not parse, it parses but is
not the shape expected, the one interpreter it needs is missing, or
something inside it raises.

**It fails CLOSED (blocks, exit 2) for a subagent. It fails OPEN (allows,
exit 0) for the main session.** A guard bug must never wedge the
orchestrator, which is why the main session still gets the open path; but
"could not tell" is exactly the situation a subagent-restraining control
cannot shrug off, since a subagent is the one population this guard exists
to restrain in the first place. When it cannot even tell which case applies
(no `agent_id` key found, but the payload does not look like a JSON object
either, or Python itself could not be started to check), it treats that as
a subagent too: the safe direction to be wrong in.

This two-layer failure (the Python script itself, and the bash wrapper that
starts it when no Python interpreter is available at all) is covered by
`hooks/test_git_guard.py`, which exercises both an unparseable payload and a
missing-interpreter run, each with and without an `agent_id`.

## Troubleshooting

**Windows: "could not create a symlink" / "could not create a real link"
warning.** Expected without admin rights or Developer Mode (for a file), or
on the one Git Bash + Windows combination where `ln -s` has been seen to
silently copy instead of link (see "Links vs. copies" above). The copy it
falls back to still works right now; re-run with `-Update` / `--update`
after a `git pull` to pick up later changes to that path. Turning on
Developer Mode is worth trying for a FILE symlink on `install.ps1`, but is
not confirmed to be enough on its own (PowerShell's `New-Item
-ItemType SymbolicLink` may still need an elevated shell even with it on);
directory junctions do not need either and almost always just work.

**Windows: a directory link shows up as a "junction" in File Explorer, not a
"shortcut."** That is correct and expected. A junction is a real reparse
point `cd` and every tool here can follow; it does not need admin rights the
way a directory symlink would.

**Git Bash path issues on Windows.** `install.sh` and `uninstall.sh` assume a
POSIX-ish `$HOME` and standard Unix tools (`ln`, `mv`, `find`, `date`,
`stat`, `cmd.exe` for `mklink`), which Git Bash provides. Run them from a Git
Bash prompt, not `cmd.exe`.

**PowerShell 5.1 and `"$var:"`.** PowerShell 5.1 parses `"$name:"` inside a
string as a request for the `name:` PSDrive, not as the variable `$name`
followed by a colon. Every script in this repo either avoids that shape or
uses `${name}:` instead; if you add to these scripts, do the same.

**PowerShell: "running scripts is disabled on this system."** Windows'
default Restricted execution policy blocks `.ps1` files entirely, including
this one. Run `powershell -ExecutionPolicy Bypass -File install.ps1` instead
of double-clicking or calling it plainly, or change the policy for your user
once with `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
