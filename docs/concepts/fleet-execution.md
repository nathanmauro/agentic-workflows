# Fleet Execution

## The Problem

Multiple repositories often need progress at the same time, but one giant context window becomes slow, fragile, and hard to review. A single agent carrying every project detail can mix state, miss dirty files, and lose the thread on individual branches.

## The Pattern

Use a conductor plus one agent per project, with one vertical slice per round. The conductor owns prioritization, review, and integration decisions. Project agents own narrow implementation or reconnaissance work inside their assigned repository.

## How To Apply It

Start from a project registry that lists each project path, tier, current goal, and risk hints. Keep a living spec per project so each session can recover intent, acceptance criteria, and current run state.

Run agents in PLAN mode when the next slice needs framing, risk review, or task breakdown. Run agents in DO mode only after scope and gates are clear. Require a review acknowledgement before advancing a branch, merging, publishing, or starting the next round.

## Failure Modes

Sharing one dirty worktree across multiple agents creates merge risk and unclear ownership. Unreviewed branches can accumulate implementation choices that no conductor has accepted. Stale reconnaissance makes a later implementation plan look current when the repo has moved on. Auto-push without gates turns coordination failure into public history.

## Related Templates

- `templates/fleet-projects.json`
- `templates/project-spec.md`
