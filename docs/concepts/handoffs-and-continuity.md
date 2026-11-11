# Handoffs And Continuity

## The Problem

Agent sessions end because of context limits, time limits, interruptions, or a natural stopping
point. Without enough state to resume, the next session must infer the branch, touched files,
verification status, live effects, and next useful action from incomplete evidence. With two
engines in play, the next session may not even be the same client: Codex picks up what Claude Code
left, or the reverse.

## The Pattern

Write a compact handoff that captures repo state, files changed, verification run, live effects,
known gaps, the authorization the work carries, and the next useful step. The goal is not to
preserve the whole conversation; it is to make the next responsible action obvious.

Store handoffs behind a durable memory adapter, not in either client's private session history, so
any engine can read what any other engine left. The adapter is an abstraction: a small set of
capture and recall verbs (see
[`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)). Any store
that implements them works.

[Black Box](https://github.com/nathanmauro/black-box) is the reference implementation used here.
It records typed decisions with their rejected alternatives, handoffs with exactly one next
action, observations, and projections (a recorded guess about where the work goes next when the
path genuinely forks). Codex and Claude Code both reach it over MCP, so a handoff written by one is
recall for the other.

## How To Apply It

Use [`templates/HANDOFF.md`](../../templates/HANDOFF.md) at closeout or whenever work remains.
Include the repository, branch, commit or dirty state, changed files, verification commands and
results, live-system effects, what was not done, and the smallest concrete resume step. When the
work was delegated, include the quoted authorization record from
[authorization provenance](authorization-provenance.md) so the next agent neither re-asks nor
broadens it.

If a durable memory adapter is available, store the same compact handoff there. If not, keep a
handoff file or repo note close to the work, and list any decision that is still pending capture
rather than inventing a record for it.

Write when state would otherwise be lost, not by reflex on every trivial turn. When a clean commit
and `git log -1` already explain a finished one-shot fix, skip the prose ceremony; capture a
handoff when rejected alternatives, open loops, dirty trees, cross-session blockers, or live-system
side effects matter to the next session. On the store side, a session that closes with a standing
handoff already wrote its own best summary: [Black Box](https://github.com/nathanmauro/black-box)
reuses that handoff directly as the session summary without spending an extra model call, falling
back to model summarization only if substantial new work happened after the handoff.

Compact captures compound. Over time, decisions, handoffs, observations, and projections can be
assembled into a [project trajectory](project-trajectory.md): where the work has been, where it
stands, and the plausible futures ahead of it.

## Failure Modes

Transcript dumps are too noisy to use as handoffs and can expose private data. Indiscriminate
writes on every turn create a write-only graveyard that drowns out real decisions at recall time. A
handoff without a branch or dirty-state summary makes the next session guess where the work lives.
A handoff without a next action preserves history but does not support progress. A handoff kept
only in one client's session history strands the other engine. Secrets, tokens, raw logs, and
private account data do not belong in a handoff.

## Related Templates

- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
- [Authorization provenance](authorization-provenance.md)
- [Closeout and handoff](../workflows/closeout-and-handoff.md)
