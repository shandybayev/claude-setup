# A new path beside an old one must keep every guarantee the old one had

**Rule:** When you add a code path beside an existing one that answers the same question, list every filter, join and guard the old path applies, and prove the new one applies each of them, or states explicitly why not.

**Why:** On a real project, a new lookup was added beside an existing one that answered the same question a different way. The old path filtered on a type and joined through an owning record; the new one did neither, so a row from an entirely different kind of record could be returned as if it were the thing being looked up, and several callers would have stored it unguarded. Review and all automated gates passed it, because each one reasoned about the new code on its own rather than against the code sitting next to it.

**How to apply:**
1. When adding a path beside an existing one, write down the old path's filters, joins and guards, and check the new path against that exact list.
2. After fixing a defect of this shape, grep for the same call pattern elsewhere before declaring it fixed; the identical hole can sit one call site over, sometimes in a path that writes rather than one that only reads, which is the more dangerous half.
3. A test fixture that omits the fields a real path filters on will pass tests that the real path would fail. If a new guard refuses an existing fixture, that is evidence the fixture is unreal; complete the fixture, never weaken the guard to match it.

See [[fake-must-model-the-system]] and [[orchestration-workflow]] for the review pattern this sits inside.
