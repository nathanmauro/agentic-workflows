# Living Specs

## The Problem

Cold agents rediscover scope when the current plan lives only in chat history. Over time, requirements drift, decisions are forgotten, and each new session spends context reconstructing what should have been written down.

## The Pattern

Use a versioned project spec plus live run state. The spec describes the durable intent and acceptance bar, while the run state captures the current round, branch posture, recent decisions, and what is intentionally deferred.

## How To Apply It

Write the project intent in plain language, including why the work matters and what the stakes are. Define an acceptance bar that names the concrete verification command or proof expected before closeout. Record decisions with dates, including tradeoffs and rejected approaches when they would help a future agent.

Track deferred work separately from current scope so useful ideas do not leak into the active slice. Organize implementation into rounds, where each round states the slice, acceptance criteria, outcome, and review state.

## Failure Modes

A stale spec can mislead an agent more efficiently than no spec at all. Generated requirements should be reviewed before they become authoritative, because the agent may invent scope or overstate certainty. If the spec is not committed with the work it describes, the next session may resume from an outdated version.

## Related Templates

- `templates/project-spec.md`
