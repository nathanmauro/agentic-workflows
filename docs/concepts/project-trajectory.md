# Project Trajectory And Possible Futures

## The Problem

A durable memory full of decisions, handoffs, and observations answers "what happened" but not "where is this project and where could it go." The forward-looking state is captured—next actions in the latest handoff, open loops, blocked tasks, alternatives a decision rejected—but it is scattered across entries, and a flat timeline buries it under history. A resuming agent reads a list when it needs a position and a direction.

## The Pattern

Assemble the same capture stream into a trajectory: the past collapsed into bursts of activity, the current state as a head node, and a fan of possible futures ahead of it. Two kinds of futures stay visually and semantically distinct:

- **Derived futures** come from captured facts: the latest handoff's next action, still-open loops, and open or blocked tasks. Within each thread of work, the most recent handoff supersedes older ones—the last agent to leave the room listed what was open—while concurrent threads each contribute their own latest state.
- **Projections** are speculation an agent writes down deliberately, usually at closeout: one to five plausible futures, each with a short title, a one-line description, and a confidence. They render as ghost branches—clearly speculative, never dressed as fact. Each new projection set replaces the last, and stale sets expire rather than linger.

Alternatives a decision explicitly rejected are roads not taken. They belong on the trail as dead stubs, not ahead of the head as futures—placing them forward would misrepresent captured intent.

## How To Apply It

Keep capturing compact decisions, handoffs, and observations as usual; the trajectory is a view over those captures, not a new writing burden. At closeout, when the future genuinely forks, record a projection alongside the handoff: the paths you can see, a confidence for each, and the basis—what current work makes them plausible.

Keep the view honest. Show staleness when the head is old instead of implying momentum. Never mark a future resolved just because it stopped appearing—absence is not resolution. If a memory adapter supports a projection verb, wire it next to the decision, handoff, and observation verbs (see [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)).

## Failure Modes

Speculation presented in the same visual and semantic register as captured fact poisons trust in the whole view. Projections without expiry or supersession accumulate into a fog of stale futures nobody believes. Treating rejected alternatives as open options re-litigates settled decisions. Building the trajectory from raw event noise instead of curated captures produces a graph nobody can read. And a trajectory view is not a substitute for the handoff itself—the compact state record remains the unit of continuity.

## Related Templates

- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
