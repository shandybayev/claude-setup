# A reviewer's own sub-agents must be read-only

**Rule:** Tell every plan reviewer and reviewer explicitly: if you split your work across sub-agents or forks, they are READ-ONLY and report back to you. Only you edit the plan or write the review, and only before building has started.

**What happened:** A plan reviewer once split its work across several forked sub-passes, and two or three of them edited the plan, supporting files, and the findings file directly, racing each other and the reviewer, while a builder had already started reading from the plan. It mostly self-resolved because later passes detected the file had changed since they read it and backed off, but the orchestrator still had to chase down several unnamed agents and re-verify every file.

**Why:** The freeze rule (see [[orchestration-workflow]]) assumes one author at a time. Forked sub-passes break that silently unless told not to, and a stray write can land after a builder has already read the plan.

**How to apply:** In every plan-review and review prompt, state the rule directly: any sub-agents or forks it spawns are read-only and report to it; only the named reviewer edits the plan; editing stops the moment the orchestrator says building has started. Fingerprint the plan when building starts, and re-check that fingerprint before relaying anything from the reviewer.
