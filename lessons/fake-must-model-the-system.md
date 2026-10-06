# A fake must model the real system, not the code under test

**Rule:** A test fake must model what the real system would DO, never what the code under test ASKED FOR. A gate or comparison must check the thing itself, not merely that it exists.

**Why:** A migration test fake once echoed back the exact statement the code under test had sent, instead of re-rendering it the way the real database would. Because the gate under test compared that echoed rendering, it could never catch a disagreement between what the code asked for and what the database would actually record. Several real fidelity gaps hid behind that one fake, each a different way the fake's behavior diverged from what the real database would actually do with the same statement.

**How to apply:**
1. Whenever a fake exists, ask what it is being KINDER about than reality would be, and treat the answer as a first-class review question.
2. Enumerate what the object could be that is NOT what you want, and check against that full list, not just containment or existence. A containment check that only asks "is the expected text present" can pass an object that is the expected text PLUS something unwanted (for example, an extra narrowing condition that defeats the intent while still containing the substring).
3. Require a revert table: remove each guard one at a time, confirm a named test fails, and record what failed, because a revert that silently misses looks identical to a test that never bites. Be suspicious of a mutation that fails FEWER tests than expected.
4. Ask whether the code you are relying on has ever actually RUN. A harness that monkeypatches the real call and asserts only the request as text never executes the logic it claims to verify.
5. When reproducing "the real system" for a proof, match its real version (engine version, runtime version), not whatever is convenient locally.
6. A mock that records a MUTABLE argument by reference can be asserted against after the calling code has already mutated that same object, so the assertion reads the post-mutation state even when the real write path would have captured the value earlier. Give such a double a snapshot-at-call-time behavior, or the assertion pins nothing.
7. Count the vacuous tests you find as you find them, and sweep for more once the count climbs. A test suite that only ever gets watched passing, never watched failing, accumulates these silently.
8. Any gate that resolves a name through a lookup needs a companion check that fails when the lookup itself resolves nothing, so "the lookup found nothing" and "the lookup never ran" are different, visible outcomes rather than the same blank result.
9. A mutation caught only by a check on the SOURCE TEXT of a message is not evidence of behavior. A text check shows the code changed; it cannot show behavior broke. Give each such test a behavioral or real-system oracle, or write down why no legal path can observe the difference.

See [[parallel-path-invariants]] and [[reachability-needs-contents-not-columns]] for the sibling rules this one extends.
