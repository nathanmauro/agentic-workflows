# Fleet Execution

## The Problem

Multiple repositories often need progress at the same time, but one giant context window becomes slow, fragile, and hard to review. A single agent carrying every project detail can mix state, miss dirty files, and lose the thread on individual branches.

## The Pattern

Use a conductor plus one agent per project, with one vertical slice per round. The conductor owns prioritization, review, and integration decisions. Project agents own narrow implementation or reconnaissance work inside their assigned repository.

## How To Apply It

Start from a project registry that lists each project path, tier, current goal, and risk hints. Keep a living spec per project so each session can recover intent, acceptance criteria, and current run state.

Give every fleet invocation its own atomically allocated archived state directory and pin that physical path into every worker. Publish a `current` pointer only after successful initialization; live workers must not follow that movable pointer. Make worker/session identifiers run-scoped and serialize shared state updates. Separate run directories permit concurrent fleets; the same project still must not appear in two live fleets because its repository remains a shared resource.

Choose the mode once per fleet run; it applies to every project and round. Use PLAN when slices need framing, risk review, or task breakdown. Use DO only when scope and gates are already clear. Capability is not authority: remote and CLI availability never substitutes for an explicit push grant. FULL_AUTO is a separate merge grant: only a mode/phase/round-checked helper may merge, and only after selected-repository identity, recorded PR identity and head, danger, and tooling gates pass and a bounded, ready-triggered CI wait passes; every non-CI gate is re-checked after CI and again immediately before merge. The helper writes an unresolved state before submission, so a crash or transient read cannot let the loop advance. GitHub queue or auto-merge submission is not completion; the current REVIEW phase holds until GitHub reports it merged or the human explicitly closes the review item. The merge helper never requests branch deletion. PLAN and DO retain human merge ownership; every gated or failed FULL_AUTO slice remains in review.

## Failure Modes

Sharing one dirty worktree or one mutable run directory across agents creates merge risk and unclear ownership. An unpinned `current` pointer can silently retarget a live worker. Unreviewed branches can accumulate implementation choices that no conductor has accepted. Stale reconnaissance makes a later implementation plan look current when the repo has moved on. Auto-push or auto-merge without fail-closed gates turns coordination failure into public history.

## Related Templates

- [`templates/fleet-projects.json`](../../templates/fleet-projects.json)
- [`templates/project-spec.md`](../../templates/project-spec.md)
