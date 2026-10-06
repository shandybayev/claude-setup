<!--
Pull request body template. Fill every section; delete none of them, even
if a section is short ("None." is a valid answer for Known limits).
No em dashes or en dashes anywhere in this file.
-->

## The problem

What was broken, missing, or needed, in plain terms. One or two short paragraphs; link an issue if there is one.

## The change

What the change actually does, file by file or area by area. Not a diff restatement; the reasoning behind the approach, and any option considered and rejected.

## Verification

What was run, and what passed: tests (counts), gates, a real-system proof if this touches data or a deploy. Name the revision these numbers describe.

## Known limits

What this change does not cover, any carried issue, anything mocked or deferred. "None." is fine if there genuinely are none.

## When it is safe to merge

Any precondition: another PR that must land first, a freeze window that must have passed, an owner check that must complete.

## After deploy

What to verify once this is live (the running artifact matches this commit, a schedule that must fire once under the new code, a flag that must be confirmed off or on), and who is watching for it.
