# Lessons index

One file per lesson, each with a Rule, a Why, and a How to apply. These are generic write-ups of mistakes made and fixed on real projects; no company names, hosts, or incident-specific detail. The `default-workflow` skill links here; the `/lessons` command searches this folder.

## Workflow and orchestration

- [orchestration-workflow](orchestration-workflow.md): running multi-lane work with an orchestrator and teammates; ten earned corrections.
- [verify-dont-relay](verify-dont-relay.md): re-check a teammate's claim before relaying it.
- [freeze-before-verifying](freeze-before-verifying.md): freeze a tree before measuring it.
- [teammate-idle-nudge-poll](teammate-idle-nudge-poll.md): a waiting teammate never restarts itself.
- [reviewer-forks-race](reviewer-forks-race.md): a reviewer's own sub-agents must be read-only.
- [ask-branch-before-code](ask-branch-before-code.md): ask which branch before the first edit.
- [consult-sibling-session](consult-sibling-session.md): ask a sibling session instead of guessing.
- [one-merge-at-a-time-announced](one-merge-at-a-time-announced.md): coordinate merges across sessions.
- [deploy-freeze-windows](deploy-freeze-windows.md): respect declared no-merge windows.

## Testing and review rigor

- [fake-must-model-the-system](fake-must-model-the-system.md): a fake must model reality, not echo the code under test.
- [parallel-path-invariants](parallel-path-invariants.md): a new path must keep every guarantee the old one had.
- [reachability-needs-contents-not-columns](reachability-needs-contents-not-columns.md): reachability arguments need values, not schema.
- [test-patches-globals-must-restore](test-patches-globals-must-restore.md): always restore patched global state.
- [code-comments-no-review-refs](code-comments-no-review-refs.md): comments describe the code, not the review.

## Checklists, browser testing, and PRs

- [read-rules-files-first](read-rules-files-first.md): read a repo's rules files at session start.
- [checklist-preconditions-verified](checklist-preconditions-verified.md): walk a checklist's entry points yourself first.
- [browser-testing-via-subagents](browser-testing-via-subagents.md): delegate browser testing, keep screenshots out of the main context.
- [probe-chrome-kill-by-pid](probe-chrome-kill-by-pid.md): close only the browser process you launched.
- [pr-ui-screenshots](pr-ui-screenshots.md): UI pull requests include screenshots, by default.

## Infra and data

- [windows-docker-build-crlf](windows-docker-build-crlf.md): Windows container builds can inject CRLF and break startup.
- [deploy-checkout-equals-commit](deploy-checkout-equals-commit.md): prove an ops script's checkout matches the deployed commit.
- [deploy-restart-refires-jobs](deploy-restart-refires-jobs.md): a deploy restart can re-fire scheduled jobs.
- [cache-key-on-data-stamp](cache-key-on-data-stamp.md): key a cache on a data stamp, not time alone.
- [replace-write-empty-response-guard](replace-write-empty-response-guard.md): don't let an empty upstream response erase good data.
- [db-session-rollback-after-error](db-session-rollback-after-error.md): roll back a shared DB session after an error before reuse.

## Tooling quirks

- [powershell-var-colon-drive](powershell-var-colon-drive.md): PowerShell 5.1 misparses `"$var:"` as a drive.
