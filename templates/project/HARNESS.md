# The harness

This project uses the shared harness kit for quality gates. This page is the
one-pager: what fires where, what each gate enforces, how to bypass one on
purpose, and how to add a new one. Full mechanics live in `harness/README.md`
in the claude-setup repo this was installed from.

## The layers

| Layer | Fires on | Scope | Calls |
| --- | --- | --- | --- |
| Edit time | a Claude Code `Edit`/`Write` | one file | `harness/edit-check.sh` |
| Commit | `git commit` | the staged diff | `harness/gates.sh commit` |
| Push | `git push` | the commits being pushed | `harness/gates.sh push` |
| CI | a push or pull request | same diff as push | `harness/gates.sh push` |

Commit, push, and CI all call `harness/gates.sh`. There is one gate list, in
that one script; nothing here can drift out of sync with CI.

## The gates

| Gate | Enforces | Fires at |
| --- | --- | --- |
| File size | warn over `LOC_WARN`, block over `LOC_BLOCK` lines (only if the file is new or grew) | commit, push, CI |
| Debug leftovers | no stray debug statements in changed lines | commit, push, CI |
| Commit message | `type(scope): subject`, a max length, no em or en dash | commit-msg |
| Format | `FORMAT_CMD` from `harness/harness.config` | push, CI |
| Lint | `LINT_CMD` from `harness/harness.config` | push, CI |
| Typecheck | `TYPECHECK_CMD` from `harness/harness.config` | push, CI |
| Tests | `TEST_CMD` from `harness/harness.config` | push, CI |
| Ratchet (optional) | `RATCHET_CMD`'s count may fall, never rise | push, CI |
| Edit-time format/lint (optional) | `FORMAT_<ext>` / `LINT_<ext>` for the file just edited | edit time |

Project-specific values live in `harness/harness.config`, not in this file or
in `harness/gates.sh`. Edit that file to point the format, lint, typecheck,
and test gates at this project's real commands.

## Bypassing a gate

`git commit --no-verify` or `git push --no-verify` skip the local hooks.
State the reason in the commit message or the pull request when you do. CI
still runs `harness/gates.sh push` on every push and pull request regardless,
so a bypass only skips the fast, local copy of the check, never the final one.

## Adding a gate

1. Pick the cheapest layer that can catch it. Edit time only ever sees one
   file and must stay fast; commit should stay fast too; push and CI can
   afford something slower.
2. If it reads changed files, use the diff-scope helpers in
   `harness/lib/scope.sh` so it gets the staged/push/worktree behavior for
   free.
3. Wire it into `harness/gates.sh`, in the modes where it should run.
4. Add its row to the table above.
