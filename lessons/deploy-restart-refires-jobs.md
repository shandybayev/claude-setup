# A deploy restart can re-fire scheduled jobs

**Rule:** When a deploy restarts a process that owns scheduled or periodic jobs (a cron-like scheduler, an in-process timer), check whether the restart itself causes any job to fire immediately or twice, rather than assuming it resumes cleanly at the next scheduled time.

**Why:** Many in-process schedulers run a job immediately on startup if they missed its last scheduled time, or if they are configured to run once at boot. A deploy that restarts such a process during the day can trigger a job meant only to run overnight, with effects (duplicate writes, duplicate notifications, double-counted aggregates) that are easy to miss because the job "ran successfully."

**How to apply:** Before deploying a change to a service that owns scheduled jobs, check the scheduler's restart behavior (does it run missed jobs on startup, does it debounce against a last-run timestamp) and confirm what happens if the restart lands mid-day. After any deploy that restarts such a service, check whether a job fired that should not have, not just whether the service came back up.
