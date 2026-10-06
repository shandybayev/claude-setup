# Walk a checklist's entry points yourself before handing it over

**Rule:** A checklist handed to a human is a contract. Every "open X" step needs X reachable by the exact path described, verified by actually doing it, not inferred from a green automated flow or from reading the code. Before handing a checklist over, walk its entry-point preconditions yourself under conditions matching the human's real ones (their clock, their login, their persisted local state). Probe every variant the checklist uses (each account, each mode), not just the primary path.

**Why:** Two incidents, same shape. First, a versioned local data store was changed without bumping its version, so a tester's existing local state never picked up the new fixture, while every automated flow used a fresh environment and reseeded, so it looked fine everywhere except on a real device. Second, a multi-account walkthrough was probed only on a single account; a shared backing store that matched rows by a non-unique key let one account's action mutate another account's row, wedging the tester's local state in a way that looked like an application bug.

**How to apply:**
1. Any change to seeded or mock data needs a version bump (or equivalent cache-busting step) with a changelog line, if the project reseeds its local state only on a version change.
2. Before delivering a checklist, run its opening path AND one probe per account or mode it uses. Ask what differs between a fresh environment and the human's actual browser or device (local storage, cached state, login state), and state the fresh-state recipe in the checklist itself.
3. Treat any backing store shared across tenants or accounts (shared id space, first-match lookup across stores) as a standing suspect: check id uniqueness across tenants before any cross-account step.
