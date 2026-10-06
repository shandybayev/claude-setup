# <Slice name> plan (<date>)

Written by the `planner` role. Covers one slice. Settle the forks in section 7 with the project owner before building starts. This document is frozen once a plan review begins; see the `reviewer-forks-race` lesson.

## 1. Findings, with evidence

State what the real code currently does, with file and line references, before proposing any change. A plan that cites code which is not there is the most common defect a reviewer finds.

### F1. <finding>
### F2. <finding>

(Number findings so later sections and review notes can refer to them directly.)

## 2. Options and recommendation

For each real fork, list the options considered and which one you recommend and why. Do not decide a product question yourself; flag it for section 7 instead.

## 3. Files and rough size

List every file the slice touches or creates, with a rough line-count estimate, split by lane if more than one builder will work in parallel.

## 4. Tests

List the tests the slice needs, split by what they pin.

### Revert table (each guard removed must make a named test fail)

| Guard removed | Expected failing test | Notes |
|---|---|---|
| <guard> | <test name> | |

### Real-system proof (before any merge, if this touches data, a migration, or a deploy)

Describe the proof: what real system (the real engine version, not a convenient local stand-in), what it measures, and what a pass looks like.

## 5. Production verification plan

If the change is irreversible or touches live data: describe how the owner verifies it on the real system after deploy, and what "safe to call this merged" means concretely.

### Owner checks before building (read-only)

Any read-only query or check that only the owner should run before building begins, wrapped in a read-only transaction where it touches a real database.

## 6. Deploy order and coordination

If this slice depends on, or blocks, another effort's deploy order, say so here, and note it in `briefs/COORDINATION.md`.

## 7. Forks for the owner (with recommendations)

Each item: the fork, the options, your recommendation, and why. The owner decides; you do not.

## 8. Out of scope

What this slice explicitly does not cover, and why it was left out.

## 9. Open questions

Anything unresolved that is not a decision fork: a fact nobody has confirmed yet, a dependency on another team or effort.
