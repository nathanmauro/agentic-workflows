# Handoffs And Continuity

## The Problem

Agent sessions end because of context limits, time limits, interruptions, or a natural stopping point. Without enough state to resume, the next session must infer the branch, touched files, verification status, live effects, and next useful action from incomplete evidence.

## The Pattern

Write a compact handoff that captures repo state, files changed, verification run, live effects, known gaps, and the next useful step. The goal is not to preserve the whole conversation; it is to make the next responsible action obvious.

## How To Apply It

Use [`templates/HANDOFF.md`](../../templates/HANDOFF.md) at closeout or whenever work remains. Include the repository, branch, commit or dirty state, changed files, verification commands and results, live-system effects, what was not done, and the smallest concrete resume step.

If a durable memory adapter is available, store the same compact handoff there. If not, keep a handoff file or repo note close to the work.

## Failure Modes

Transcript dumps are too noisy to use as handoffs and can expose private data. A handoff without a branch or dirty-state summary makes the next session guess where the work lives. A handoff without a next action preserves history but does not support progress. Secrets, tokens, raw logs, and private account data do not belong in a handoff.

## Related Templates

- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
