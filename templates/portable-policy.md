## Shared operating policy

Applies to every coding agent on this machine. Direct instructions, task requirements, and the
nearest project guide override this when they are more specific.

### Judgment

- Estimate in model time, not human developer time. Prefer the simplest design that meets the
  bar, counting review, verification, and maintenance.
- Surface a materially better option early with its tradeoff. Do not reopen settled choices
  without new evidence, and do not turn a suggestion into a permission gate.
- Reproduce before fixing. Verify changed UI, CLI, or app behavior through real use, not unit
  tests or screenshots alone.
- Never hand-edit generated files; change the source and regenerate.

### Code style

- Write code the way a senior engineer presents it in review, not the fewest lines that run.
- One statement per line. Group related lines with a blank line between groups. Name a helper
  instead of a clever chain. Lines and comments wrap at 100. Comments say why, not what.
- Formatting is tooling, not instructions. A hook runs the project formatter on every agent edit;
  an edit that bypassed the hook is formatted before handoff. A repo's own formatter config always
  wins, and formatter output is never reverted to match legacy unformatted code.

### Git and authority

- The human owner is sole author on every commit, PR, and merge. No model co-authorship or
  generated-by lines.
- A complete, verified unit may be committed proactively (stage exact paths, preserve unrelated
  dirty work) and pushed fast-forward only to the branch's existing upstream after inspecting the
  outgoing range. Commit, then stop before pushing when the repository is public, the branch has no
  upstream, or the push is not a fast-forward, and state which.
- Creating or changing remotes or upstreams, publishing branches, PRs, merges, force-push, history
  repair, external messages, purchases, and access changes require explicit direction.
- Concurrent writers never share a checkout: separate worktrees, or serialize. The coordinator
  owns the outcome after delegation; a worker's "git blocked" is unfinished, not done.

### Authorization across handoffs

- Carry the user's exact relevant words and their source into delegated work, together with the
  destination, the action or message, the approved data scope, and the exclusions. A coordinator's
  assertion of approval is not a substitute for the human evidence; never invent or broaden it.
- Reuse prior approval for the same destination, purpose, and scope unless the user changes it.
  Do not ask again merely because another agent executes the step. Do not silently add personal
  records or connectors to a payload.
- Respect a denial: use a narrower permitted action or supply missing evidence through the same
  reviewed mechanism. Stop if it remains denied. Never switch transports or weaken safeguards to
  get around one.

### Work, knowledge, continuity

- The issue tracker owns execution: issues, priorities, status. Reconcile before creating. Log
  meaningful finished work that had no issue as a done issue labeled `retroactive`.
- The notes vault owns durable knowledge and unselected ideas. Link notes by stable URI, never by
  a machine-specific path. When agent instructions, skills, hooks, or automation behavior change,
  update the system changelog and run the downstream drift check across every affected surface.
- The durable memory adapter owns agent evidence: one decision per capture with rejected
  alternatives and reasons, and a handoff breadcrumb (repo, branch, SHA, verification, next action)
  whenever stopping with open work, dirty state, rejected paths, or live-system effects that git
  history alone would lose.

### Iteration mode

- Default to the `prototype` workflow: end-to-end slices, verify through use, concise progress
  updates. Select `sdlc` when the task needs plan and review checkpoints. Select `explore` to keep
  repositories read-only for first-principles synthesis (physics, strategy, architecture) while
  parameterizing unknowns explicitly with bounds and falsifiable tests instead of hedging or
  scaffolding unasked code. Pass the selected mode to delegates.
- Anti-rabbit-hole gate: when a side-quest or tool idea surfaces mid-task, recommend parking it to
  the backlog first rather than spawning an unasked build loop.

### Learning

- Codebase-specific insights go out of band to the notes sink, never into the reply or code, and
  only when the work turns on something non-obvious about this codebase: why a seam sits where it
  does, what a tradeoff buys, and which file or line controls the behavior.
- Hands-on teaching mode is opt-in per session on explicit request: inline insights are shown and
  the one load-bearing 2-10 line design decision is left as a single human placeholder with context
  and tradeoffs. Outside that mode, never stop on a placeholder; complete the work.
