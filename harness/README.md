# The harness

A small, generic quality-gate kit for any project. It checks the SAME rules at
four layers, cheapest first, by calling one script everywhere so the layers
cannot drift apart.

| Layer | Fires on | Scope | Calls |
| --- | --- | --- | --- |
| Edit time | a Claude Code `Edit`/`Write` | one file | `harness/edit-check.sh` |
| Commit | `git commit` | the staged diff | `harness/gates.sh commit` |
| Push | `git push` | the commits being pushed | `harness/gates.sh push` |
| CI | a GitHub Actions run | same diff as push (`GATE_BASE_REF`) | `harness/gates.sh push` |

Commit, push, and CI all run `harness/gates.sh`. There is one gate list. Add a
gate once and every layer that should see it does.

## Installing the harness into a project

```
harness/install.sh [--target DIR] [--dry-run] [--verify]
harness/install.ps1 [-Target <dir>] [-DryRun] [-Verify]
```

- `--target DIR` / `-Target` : the project root. Default is the current
  directory.
- `--dry-run` / `-DryRun` : print what would change, change nothing.
- `--verify` / `-Verify` : run the self-check only (see below), install
  nothing.

What install does, in order:
1. Copies `harness/` (this folder: `gates.sh`, `gates.ps1`, `edit-check.sh`,
   `lib/scope.sh`, `harness.config.example`) into `<target>/harness/`, unless
   a `harness/` already exists there, in which case it leaves the existing
   `harness.config` alone and only refreshes the scripts.
2. Writes `.githooks/pre-commit`, `.githooks/pre-push`, and
   `.githooks/commit-msg` in the target repo. Each is a few lines that call
   `harness/gates.sh` with the right mode.
3. Sets `core.hooksPath` to `.githooks` in the target repo's git config, so a
   fresh clone still needs one `git config core.hooksPath .githooks` (or a
   re-run of install) to pick the hooks up. Install prints that reminder.
4. Adds three lines to the target's `.gitattributes` (creating the file if it
   does not exist, appending to it and keeping everything else if it does):
   `*.sh text eol=lf`, `.githooks/* text eol=lf`, `harness/** text eol=lf`.
   Forces LF on the scripts and hooks this kit ships, so a commit made on
   Windows (no execute bit either way, and CRLF if the committer's git
   `core.autocrlf` mangled it) still runs on Mac/Linux/CI, which does not
   tolerate CRLF shell scripts the way Git Bash does. Idempotent: a line
   already present is never duplicated.
5. Merges a `PostToolUse` entry for `Edit|Write` into the project's
   `.claude/settings.json`, pointing at `"$CLAUDE_PROJECT_DIR"/harness/edit-check.sh`
   (not a path relative to the shell's own cwd, which breaks the moment Claude
   Code runs a tool from a subdirectory). Existing keys are left alone; only
   the hook entry is added if missing.
6. Copies `templates/ci/gates.yml` into `.github/workflows/gates.yml`, unless
   that file already exists.
7. Writes `harness.config` from `harness.config.example` if one does not
   already exist. **Never commits anything.**

Run it again any time to refresh the scripts without losing a project's own
`harness.config`.

## The self-check

```
harness/install.sh --verify
harness/install.ps1 -Verify
```

Prints OK or FAIL for:
- `core.hooksPath` is set to `.githooks`;
- `.githooks/pre-commit`, `pre-push`, and `commit-msg` exist and are
  executable (on POSIX);
- `harness/gates.sh` and `harness/edit-check.sh` exist and are executable;
- `git` is on PATH;
- `bash` is on PATH (needed on Windows too: the hooks and `edit-check.sh` run
  under Git Bash there).

Exit code is 0 only when every check passes, so a CI step or a human can use
it as a gate on its own.

## `harness/gates.sh <mode> [commit-msg-file]`

One script, three scopes plus a fourth entry point for the commit message:

| Mode | Scope | Used by |
| --- | --- | --- |
| `commit` | the staged diff (the git index) | `.githooks/pre-commit` |
| `push` | the commits about to be pushed: the upstream (or `GATE_BASE_REF`) to `HEAD` | `.githooks/pre-push`, CI |
| `all` | the working tree against `HEAD` (tracked edits plus new files) | a developer running the full set by hand |
| `commit-msg <file>` | the message file git just wrote | `.githooks/commit-msg` |

`commit` runs only the fast, diff-scoped checks (file size, debug leftovers),
so a commit never waits on a test suite. `push` and `all` run those same
checks plus the project's own format, lint, typecheck and test commands from
`harness.config`, plus the ratchet check if one is configured. `commit-msg`
checks only the message shape.

In CI, set `GATE_BASE_REF` to the real base commit (the PR base SHA, or the
previous tip on a push to the default branch) before calling
`harness/gates.sh push`; a shallow or single-branch checkout cannot work the
base out on its own. `templates/ci/gates.yml` already does this.

A PowerShell wrapper, `harness/gates.ps1`, takes the same arguments and shells
out to `bash harness/gates.sh` (Windows users of this kit are assumed to have
Git Bash, the same assumption the global statusline and git guard make).

## `harness.config`

Plain `key=value`, one per line. Blank lines and lines starting with `#` are
ignored. Chosen over JSON on purpose: no parser needed in bash or PowerShell,
and a project only ever edits a handful of keys.

| Key | Meaning | Default |
| --- | --- | --- |
| `LOC_WARN` | file-size warn threshold (lines) | `500` |
| `LOC_BLOCK` | file-size block threshold (lines) | `700` |
| `LOC_EXCLUDE` | extra comma-separated globs the file-size gate never counts, added to the built-in lockfile defaults (`package-lock.json`, `yarn.lock`, `*.min.js`, etc.) and to the automatic binary skip | (the built-in defaults only) |
| `FORMAT_CMD` | whole-project format-check command, run at push/all | (none, skipped) |
| `LINT_CMD` | whole-project lint command, run at push/all | (none, skipped) |
| `TYPECHECK_CMD` | whole-project typecheck command, run at push/all | (none, skipped) |
| `TEST_CMD` | whole-project test command, run at push/all | (none, skipped) |
| `COMMIT_MSG_MAX` | block the commit subject line over this many chars | `100` |
| `COMMIT_MSG_WARN` | warn (non-blocking) over this many chars | `72` |
| `RATCHET_CMD` | a command that prints one integer (an issue count) | (none, skipped) |
| `RATCHET_FILE` | where the baseline count is stored | `harness/ratchet-baseline.json` |
| `FORMAT_<ext>` | per-extension edit-time formatter, e.g. `FORMAT_py=ruff format` | (none, skipped) |
| `LINT_<ext>` | per-extension edit-time linter, e.g. `LINT_py=ruff check` | (none, skipped) |
| `DEBUG_PATTERN_<ext>` | the debug-leftover regex for that extension, read by `gates.sh` only (`edit-check.sh` does not use it) | a built-in default for `py`/`js`/`jsx`/`ts`/`tsx`/`mjs`/`cjs`; any other extension is skipped unless this is set |

An empty `FORMAT_CMD`/`LINT_CMD`/`TYPECHECK_CMD`/`TEST_CMD` means "this project
has none configured yet": the gate prints a one-line skip note and passes, it
never blocks on a command nobody set up.

## `harness/edit-check.sh`

Called as a Claude Code `PostToolUse` hook on `Edit|Write`. Reads the hook's
JSON payload from stdin (or takes a file path as `$1` when run by hand), finds
the file's extension, and:
1. runs `FORMAT_<ext>` if one is configured (never blocks, best effort);
2. runs `LINT_<ext>` if one is configured, and blocks (exit `2`, message on
   stderr, which is how Claude Code sees the failure in-turn) only when that
   command exits non-zero.

An extension with neither key configured is skipped silently, so adding the
harness to a new language is "add two config lines", not "edit the script".

## The ratchet helper

For a metric that should only ever go down (a dead-code count, a lint-warning
count, anything counted rather than diffed), set `RATCHET_CMD` to a command
that prints one integer. At `push`/`all`, `gates.sh`:
1. runs it, reads the current count;
2. compares it to the number stored in `RATCHET_FILE`;
3. blocks if the count went up, passes (and, if it went down, rewrites the
   baseline to the new, lower number) otherwise.

There is no ratchet by default. An empty `RATCHET_CMD` skips the step.

## Adding a gate

1. Decide the cheapest layer it can run at (edit time only catches one file
   and must stay fast; commit should stay fast too; push and CI can afford a
   slower check).
2. If it is diff-scoped, write it using `harness/lib/scope.sh`'s helpers
   (`scope_files`, `scope_grep`, see that file's comments) so it automatically
   gets the staged/push/worktree behavior for free.
3. Call it from `gates.sh` in the modes where it should run.
4. Add its row to `templates/project/HARNESS.md` in the project that adopts
   it.

## Bypass policy

`git commit --no-verify` or `git push --no-verify` skip the local hooks. That
is fine occasionally, with a reason in the commit message or the PR. CI still
runs `harness/gates.sh push` on every push and pull request regardless, so a
bypass is never the last check, only a faster first one.
