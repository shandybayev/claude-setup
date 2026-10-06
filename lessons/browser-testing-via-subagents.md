# Browser testing goes through a dedicated subagent

**Rule:** All browser testing (navigation, clicks, screenshots, eyeball checks, scripted UI flows that need reading screenshots) goes through a dedicated subagent (the `probe` role). The main session only receives the subagent's written result: pass/fail lines, the finding, and screenshot file paths. It never receives the screenshots or the click-by-click transcript.

**Why:** The main session is the orchestrator and has to stay lean across many parallel efforts. Loading screenshots and browser transcripts into its context burns the budget that orchestration needs.

**How to apply:**
- When a review, a gate, or a question needs a browser look, spawn a `probe` teammate with the exact URL, login persona, route, and what to assert, and ask for a text verdict plus file paths.
- Builder teammates may still take a single eyeball screenshot inside their own context when it helps them build; the rule is about the main session, not every agent.
- Prefer the project's own scripted acceptance flows over manual click-throughs where they exist.
- If the browser tool connects to a remote browser that cannot reach a local dev server, say so in the probe's brief up front, so it does not burn a round discovering it, and have the probe drive a local browser instead when that is what the task needs.
- A remote-debugging port shared between agents belongs to everyone: close only the contexts and processes you opened yourself. See [[probe-chrome-kill-by-pid]].
