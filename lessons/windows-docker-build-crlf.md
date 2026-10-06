# Windows container builds can silently inject CRLF, which breaks startup

**Rule:** On a Windows machine with `core.autocrlf=true` and no `.gitattributes` pinning line endings, a plain `git archive` (or a zipped checkout) converts shell scripts to CRLF line endings before they reach a container build. A container's entrypoint script then fails at startup with an interpreter-not-found error, because `#!/usr/bin/env bash` cannot find a program literally named `bash\r`.

**Why:** On a real project, this caused a real outage of a running service. A pre-push check that only exercised a non-shell part of the codebase could not have caught it, because that check tolerates CRLF; the failure was in the shell entrypoint, a different code path entirely.

**How to apply:**
- Build the container context with line-ending conversion explicitly disabled (`git -c core.autocrlf=false archive <ref>`), not a plain local folder (which can carry gitignored secrets) and not a default `git archive` on an autocrlf-true machine.
- Scan the build context for CRLF bytes in shell scripts before building.
- Before any deploy, run the image's REAL startup command (not a proxy check like importing its code), side by side with the last known-good image and the new candidate. The known-good one should behave as expected; if the candidate fails differently from how a real change would make it fail, the test is not discriminating. Diff the two images' files with line endings stripped out; only intentionally changed files should differ.
- Tag a rebuilt image with a new, unused tag; never reuse a tag any host already has cached.
- When working in an interactive shell on a remote host: avoid pasting multi-line blocks that include `exit` or strict-mode guards that could abort and log the session out partway through, and be aware that common commands may be aliased to interactive-confirm variants in ways that break an unattended script.

See [[fake-must-model-the-system]] for the general principle (a check that exercises a proxy proves nothing about the real path).
