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

## Profiles

Pass `-Profile <max|standard|lite>` / `--profile <name>` to pick which
`profiles/*.json` file sets the model and effort for the main session and
for every teammate role, plus the workflow's mode (`full`, `lean`, or
`solo`), its `maxParallelTeammates` cap, and the session-start hook's
context cap (`sessionContextChars`). See the README's "Pick a profile"
table for what each one sets.

### First-time install: the plan question, or a hard stop

Leave the flag out on a FIRST-TIME install (nothing recorded yet at
`<target>/claude-setup-profile.json`) with a real terminal on stdin, and the
installer asks which plan you have instead of silently assuming one: a
first-time user should not need to already know about `-Profile` to get a
profile that fits their plan. All three of these must hold before it asks:

- no `-Profile` / `--profile` was given;
- no profile is recorded yet for this target (a plain re-run on a target
  that already has one ALWAYS keeps it, silently, whether or not
  `-Update` is given -- `-Update` has no effect on which profile is
  active; see "Switching profiles" below for the only way to change it);
- stdin is a real terminal: PowerShell checks `[Environment]::UserInteractive`
  AND that `[Console]::IsInputRedirected` is false; `install.sh` checks
  `[ -t 0 ]`; and `-Yes` / `--yes` was NOT given (see below).

**There is no silent default profile.** When `-Profile`/`--profile` is not
given, nothing is recorded yet, AND the run cannot ask (stdin is not a real
terminal -- a script or CI run -- OR `-Yes`/`--yes` was given), the installer
stops: non-zero exit, nothing linked, copied, or written, before it has
touched anything. It prints the three profile names with their own
`description` field (never duplicated by hand), the exact command for each
shell, and one line addressed to an AI assistant running the installer on
someone else's behalf, asking it to get the plan from the person and re-run
with `-Profile <name>`. This replaced an earlier version that defaulted
silently to `max` in this situation -- the heaviest profile is exactly the
wrong thing to install for someone who gave no answer at all, which matters
most for a first-time install run by an assistant on a stranger's machine,
where no answer very much does not mean "give me the most expensive option."
A SCRIPTED install that wants a specific profile must now always pass
`-Profile`/`--profile` explicitly; there is no flag that both skips the
question and picks something for you.

`-DryRun` / `--dry-run` does NOT suppress the question, or the hard stop --
a dry run is exploring what a real run would do, and a real run would ask
(or stop) here too -- it only suppresses the actual install that follows
once a profile is settled.

The menu (when it does ask) reads each profile's own `description` field
(never duplicated by hand), accepts a number (`1`-`3`), a profile name
(case-insensitive), or an empty line for the default (the menu's first
entry, `max`); an invalid entry re-prompts up to three times, after which
the installer exits non-zero having changed nothing.

**What a profile changes, mechanically:**

- **`max`** links `agents/` and `settings.json` straight from the repo,
  exactly as every install did before profiles existed. Nothing is
  rendered for `max`, which means nothing enforces that `profiles/max.json`
  still matches those files on its own -- so the installer checks by hand
  (see "The max consistency check" below) and refuses to install if they
  have drifted apart, rather than silently installing the (correct) files
  while claiming a change from `max.json` that was never applied.
- **`standard`** and **`lite`** render the 7 agent files from `agents/`
  into `<repo>/.profile-build/<profile>/agents/` (a folder OF ITS OWN per
  profile, never shared with another profile's install), with only each
  file's `model:` and `effort:` frontmatter lines replaced -- the body,
  every line ending, and any OTHER `*.md` file in `agents/` that is not
  one of the 7 fixed roles, all pass through byte for byte unchanged --
  then link `agents` to that rendered folder instead. The same two
  profiles also render `global/settings.json` into
  `<repo>/.profile-build/<profile>/settings.json`, replacing ONLY the
  top-level `model` and `effortLevel` values and, inside `modelSettings`,
  only the `effortLevel` of entries named after a known model id (every
  other entry there, known or not, passes through unchanged) -- both set
  to the profile's own `main.effortLevel`. Unlike `agents`, this rendered
  file is then installed at `<target>/settings.json` as a plain tracked
  COPY (checksum recorded), never a link into `.profile-build/`: that
  folder is gitignored and meant to be deleted and regenerated, and a
  link from the live `settings.json` into it would leave every hook it
  wires -- the git guard included -- dangling the moment the folder is
  deleted, until the next install. The main session's model and effort
  really do come from the profile for these two, not just the teammates'.
  `.profile-build/` is gitignored: it is a build output, never
  hand-edited and never committed, regenerated from `agents/`,
  `global/settings.json`, and `profiles/*.json` on every install.
  Both renders are built in a sibling temp folder first and swapped into
  place only on complete success; a render failure (a malformed agent
  file, an unexpected `settings.json` shape) exits non-zero BEFORE
  anything is linked or written, and before an earlier successful render
  at that same path is touched -- it is never left half-overwritten.
- The chosen profile's own JSON is copied whole to
  `<target>/claude-setup-profile.json`, a plain file this installer owns
  (never a symlink, since each install target can pick its own profile),
  with the same checksum/hand-edit protection every other copy-kind path
  gets: if you edit the record directly, the installer leaves it alone
  rather than overwriting your edit on the next run. The `default-workflow`
  skill reads this record to pick up the workflow mode and parallel cap;
  a missing record means `max`.

**The max consistency check.** Because `max` is never rendered, editing
`agents/*.md` or `global/settings.json` without also updating
`profiles/max.json` (or the reverse) leaves the two disagreeing with
nothing to notice. Every install on the `max` profile checks, before
touching anything, that each of the 7 roles' `model`/`effort` in
`max.json` matches that role's own agent file frontmatter, and that
`main.model`/`main.effortLevel` matches `settings.json`'s top-level
`model`/`effortLevel`. A mismatch exits non-zero, names the role or field
that drifted, and touches nothing. **To change `max`, edit the agent
files (or `settings.json`) and `max.json` together**; `standard` and
`lite` have no such constraint, since editing their own `profiles/*.json`
is what gets rendered.

**Switching profiles.** An explicit `-Profile <name>` that actually changes
which profile is active (it differs from what is recorded, or from what
the live files carry) is treated as a deliberate instruction to make
EVERY profile-derived file match that profile right now: it re-renders
`.profile-build/<name>/agents` and (for `standard`/`lite`)
`.profile-build/<name>/settings.json`, re-points `agents`, re-installs
`settings.json` (whether it was a link, for `max`, or a tracked copy, for
`standard`/`lite`), and rewrites the record -- all in the same run, with
no `-Update` needed. There is no stale content left behind in either
rendered folder (each is regenerated in full) or at the live `agents` /
`settings.json` path (the installer's own previous link or copy there is
simply replaced, never left stale).

Before any of that happens, the installer checks whether `settings.json`
is a copy you hand-edited since it was last written (its checksum no
longer matches what was recorded). If so, the WHOLE run stops with a
non-zero exit and a message telling you to restore the installer's copy
or drop `-Profile`, before anything -- including the record -- is
changed; a hand-edit is never silently overwritten by a profile switch.
The profile record itself (`claude-setup-profile.json`) is an exception:
if you hand-edited that file and then pass `-Profile`, the installer
backs up your edited record into the usual backup folder and writes the
new one in its place, in the same step as the rest of the switch -- the
record is bookkeeping the installer owns, and an explicit `-Profile` is
treated as clear enough intent to override it.

The installer never claims a change took effect that did not: after
writing `settings.json`, it reads the file back and only prints
"applied to settings.json" if the model and effort on disk now actually
match the profile; otherwise it prints what is actually on disk and why
(most often, a hand-edited copy that was correctly left alone).

A plain re-run with no `-Profile` flag NEVER switches profiles on its
own -- it always keeps whichever one is already recorded, with or
without `-Update`; only an explicit `-Profile` that changes something
switches.

**`-Update` and profiles.** `-Update` / `--update` does not affect which
profile is active at all -- a plain re-run already keeps the recorded one
(see above). What `-Update` actually does is refresh a path that had to
fall back to a plain copy because a real link could not be made (see
"Links vs. copies"), INCLUDING the `standard`/`lite` `settings.json`
copy when it is unmodified but stale against a freshly pulled render
(the render folders themselves are rebuilt from the current repo content
on every run, `-Update` or not; `-Update` is what pushes that fresh
render on to the live, already-installed copy). After a `git pull` that
changed anything under `agents/`, `profiles/`, or `global/settings.json`,
re-run the installer; on a `standard` or `lite` install, pass `-Update`
in that same run so the live `settings.json` copy picks up the pulled
content too (`max` always links straight from the repo, so a plain
`git pull` already covers it the same way it always did).

An unknown profile name, or a `profiles/*.json` file that fails validation
(a missing or unexpected key, or JSON that will not parse), exits non-zero
and leaves the target untouched; the message names the problem.

### What happens, in order

1. `claude-setup` itself is linked at `<target>/claude-setup`, so this repo
   is reachable at a stable absolute path regardless of where it was cloned.
2. Anything already at a path the installer is about to replace gets backed
   up, but only the FIRST time that path is taken over: once a path is
   ours, a later run (including `-Update`) never backs it up again. That
   matters for `-Update`/`--update` specifically: refreshing our own copy is
   not a new takeover, so it does not touch the backup that holds your real
   original.
3. `CLAUDE.md` is linked as a file (see "Links vs. copies" above for what
   happens when a real link is not possible). `settings.json` is linked
   the same way to `global/settings.json` itself for `max`; for
   `standard`/`lite` it is instead always installed as a plain tracked
   copy of that profile's own rendered `.profile-build/<name>/settings.json`
   (see "Profiles" above for why it is never a link there).
4. `agents` is linked as a whole directory, using a directory junction on
   Windows (no admin rights needed for a junction, unlike a symlink) -- to
   `agents/` itself for the `max` profile, or to that profile's own
   rendered `.profile-build/<name>/agents` otherwise (see "Profiles"
   above). `commands/`, `hooks/`, and `statusline/` are always linked
   straight from the repo, the same way regardless of profile.
5. The chosen profile's own JSON is copied whole to
   `<target>/claude-setup-profile.json`.
6. Every skill under `skills/` in this repo is linked individually. A skill
   you already had under `~/.claude/skills/` that is not part of this repo is
   never touched.
7. For `settings.json` specifically, if one already existed there (and is
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

This also removes `<target>/claude-setup-profile.json` (a plain file,
restored from backup the same way any other copy-kind path is) and
`agents` and `settings.json`, both resolved against whichever profile
that record names right before anything is removed (each may be the
repo's own file/folder, or that profile's own `.profile-build/<name>/`,
depending on the profile; see "Profiles" above) -- `agents` as a link,
`settings.json` as either a link (`max`) or a tracked copy
(`standard`/`lite`), matching however that path was actually installed.
A link whose target is already gone (a dangling link -- `.profile-build/`
is gitignored and meant to be deleted and regenerated) is still removed,
and its own backup, if any, still restored; uninstall never reports a
restore that did not actually happen, and keeps that one manifest line on
a failed restore so a later run can retry. Uninstall may leave
`.profile-build/` itself behind in the repo -- it is gitignored, and
nothing needs it removed for the target to be clean.

Running uninstall with no manifest present (nothing was installed here, or a
previous uninstall already finished) is a safe no-op: it says so and exits,
rather than falling back to deleting anything that happens to sit at one of
the well-known names.

## What's personal vs generic

`global/settings.json` carries a few personal choices on top of the parts
every install needs (the two hook wirings). Edit `global/settings.json` in
this repo (or, for `max`, the linked copy at `~/.claude/settings.json`,
which is the same file -- for `standard`/`lite`, edit the profile's own
`profiles/*.json` instead, since that is what gets rendered) to change any
of these:

- **`model` / `effortLevel`** (top-level): personal default, change it if
  you like -- this is the main session's model and effort for the `max`
  profile specifically (see "Pick a profile" in `README.md`; `standard`
  and `lite` get theirs from their own `profiles/*.json` instead).
- **`modelSettings`**: personal default, change it if you like -- per-model
  effort overrides, the same mechanism the profile render touches for
  `standard`/`lite`.
- **`theme`**: personal default, change it if you like -- cosmetic only,
  no effect on anything else here.
- **`statusLine.command`**: personal default, change it if you like --
  points at `statusline/context-bar.sh`, itself a generic (non-personal)
  script; swap in your own command, or remove the key, with no effect on
  the installer or the hooks.
- **`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`**: REQUIRED by the `full`
  and `lean` workflow modes -- it is what lets Claude Code spawn
  teammates at all, which the orchestrator-and-teammates sequence those
  two modes run depends on. Turning it off loses the ability to run any
  teammate role in this setup, in every mode, not just those two; `solo`
  mode (see `skills/default-workflow/SKILL.md`) does not normally need a
  teammate, but the flag still has to be on for the rare case where you
  ask it to spawn one anyway ("get a reviewer on this").

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
