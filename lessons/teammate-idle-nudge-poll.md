# A teammate waiting on a background notification never restarts itself

**Rule:** A teammate that kicks off a background run and then ends its turn to wait for it does not wake itself up when the run finishes. Left alone, it stalls indefinitely. Watch its background work from the orchestrating side (poll until the process or job exits) and re-prompt the teammate once it is done, rather than assuming a quiet teammate is still busy.

**Why:** A teammate has been found still sitting idle, waiting on a notification that already arrived, days after the work it was waiting on had actually finished.

**How to apply:** Whenever you spawn a teammate to do something with a background component, track that background work yourself and nudge the teammate the moment it completes. Never leave a teammate's turn open on the assumption it will notice on its own. See [[orchestration-workflow]].
