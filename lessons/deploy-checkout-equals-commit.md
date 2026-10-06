# An ops script's checkout must equal the deployed commit, proven, not assumed

**Rule:** When an operational script (a health check, a data run, a report) depends on specific application code, verify that the checkout it ran against (or the running artifact's version) equals the commit that was actually deployed, by comparing an explicit identifier (a commit hash, a build tag), not by assuming the deploy pipeline finished because it was started, or because "enough time has passed."

**Why:** A deploy that is still rolling out, failed partway, or was superseded by a later push leaves old code running under a deceptively current-looking label. A proof, report, or health check run against the wrong checkout gives a confident, wrong answer about the new code's behavior.

**How to apply:** Before trusting any ops script's output, fetch the running artifact's actual version identifier (image tag, deployed commit SHA) and compare it to the commit you intended to verify. Record this comparison, not just "the script ran," as part of the evidence.
