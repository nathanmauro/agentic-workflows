# Execution Path Triage

## The Problem

A coding agent with access to multi-agent orchestration tends to use it. Every task starts to
look like a reason for parallel research, a delegated build, and a verification fan-out, even
when the right move is a direct answer or a ten-line edit. The cost does not show up as a
failure; it shows up as tokens, time, and review load spent on paths that a moment of triage
would have ruled out.

The measured case behind this doc: one run that defaulted to the heaviest workflow used about
11.75M tokens across 317 agents and produced no diff. Research and verification accounted for 94%
of the agents and 86% of the output. Picking the right path, which is usually a leaner one, is the
largest cost lever in the system.

The same habit shows up in smaller choices: polling by hand instead of scheduling a check,
reading twenty files inline instead of asking one scoped subagent, or asking the human what a
memory store already knows.

## The Pattern

Put a near-free gate in the main loop before any non-trivial task. The gate does not spawn a
subagent to classify the work; classifying with a subagent costs more than most mistakes it
would prevent. It asks two questions, in order, and the human picks the answer.

### Question 1: Which stage?

Match the task to the discipline that fits where it is in its life. Work that is already
specified, or is not engineering work, matches nothing and goes straight to the engine question.

| Situation                                      | Discipline                                     |
| ---------------------------------------------- | ---------------------------------------------- |
| Fuzzy idea                                     | An interview that grills the plan              |
| Design question that needs something runnable  | A throwaway prototype                          |
| Multi-session build                            | A spec, then agent-ready tickets               |
| Something broken, failing, or slow             | A diagnosis loop                               |
| Concrete behavior to build test-first          | Test-driven development                        |
| Module shape, or where a seam goes             | Module design                                  |
| Fuzzy terminology, or a decision worth keeping | Domain modeling and a decision record          |
| A merge, rebase, or cherry-pick stopped        | Conflict resolution from hunks, not full files |

### Question 2: Which engine?

| Signal in the task                                            | Engine          |
| ------------------------------------------------------------- | --------------- |
| A question or conversation, no tools needed                   | just-answer     |
| Multi-source research, no code change                         | research        |
| Needs read-only investigation, then a plan the human approves | plan first      |
| Well-specified single-surface change, a small ticket          | direct build    |
| Multi-file build across disjoint surfaces                     | delegated build |
| A finished diff                                               | review          |

A delegated build means the configured Codex model implements over a
[supervised channel](supervised-delegation.md) and a model that did not write the code verifies
it. Either engine can run the gate; the question is the same in Claude Code and in Codex, only the
invocation syntax differs.

### The presentation

The gate shows the top two or three candidate paths, ranked, with the recommendation first. Each
carries a one-line reason it fits and a rough cost. A candidate can be a stage discipline, an
engine, or one followed by the other. One option is always present: **print the command, don't
run it**, which shows the exact invocation for the chosen path and stops so the human can run it
themselves. In a client with a structured question UI the options are selectable; otherwise they
are a numbered list.

The heavy path never runs without the human's pick. When two paths are close, the gate
recommends the leaner one and says why.

### Flow rules

- Keep the interview, the spec, and the tickets in one unbroken context window, so the tickets
  build on the conversation and not on a summary of it.
- Implement each ticket from a fresh context, working from the ticket alone.
- Tickets produced by the spec stage are already agent-ready. Hand each one straight to a build
  engine with its full text (identifier, acceptance criteria, allowed paths, verification
  command). Do not re-spec or re-triage it.
- A question that conversation cannot settle goes to a prototype, and the answer comes back to
  the thread.

## Phase Boundaries

A phase is a chunk of work inside a session: the interview, the build, the QA. Decide what to do
with the context at the gap between two phases, never mid-phase. Ask these in order; the first
yes wins.

1. **Continue.** Does the next phase need this one verbatim, or does it still fit in the window?
   Continuing costs nothing and loses nothing, so rule it out first. Interview to build is the
   standard yes.
2. **Clear.** Is everything here disposable for what comes next? Clearing is the cheapest move,
   but it is one-way: the reasons behind the work go with it.
3. **Handoff.** Is the work traveling to the other engine, another repo, or a later session?
   Write a handoff to the memory adapter and a seed for the next session. See
   [Handoffs and Continuity](handoffs-and-continuity.md).
4. **Subagent.** Is the next task scoped tightly enough to run unattended? Give it its own window
   and take back a report. Automated review is the standard case.
5. **Compact.** Otherwise compact, with an instruction that names what the next phase needs.
   It is the fallback, not the first reach: every earlier question is cheaper or more precise.

Clearing and compacting belong to the human. The agent recommends the move and stops; it runs a
handoff or a subagent itself.

## Reach For / Not

Beyond the gate, a short table of defaults covers the situations where habit picks the wrong
tool. It was derived from an audit of actual agent sessions, not written in advance.

| Situation                       | Reach for                        | Not                        |
| ------------------------------- | -------------------------------- | -------------------------- |
| Recurring check while working   | A session-scoped loop            | Polling by hand            |
| Recurring job, no live steering | A scheduled routine              | Doing it when remembered   |
| Answer spread across many files | An explore subagent              | Reading them all inline    |
| Build with independent parts    | Orchestrated delegated builds    | One long serial session    |
| Parallel agents that edit files | Separate worktrees, or serialize | Two writers, one tree      |
| Costly-if-wrong decision        | A [council](council-review.md)   | One model's opinion        |
| A branch is done                | Code review, then behavior check | Ad hoc checking            |
| Cleanup PR about to open        | A simplification pass            | The first working version  |
| Session ending with open work   | A handoff, one next action       | A quiet trail-off          |
| Resuming after a gap            | One anchor noun up front         | A bare "what's next"       |
| Where did this leave off?       | Query the memory adapter first   | Human as memory bus        |
| Has this turn finished?         | Ask the runner by turn id        | Reading timestamps or logs |

### Hard rules

1. **Environment-visible claims require observation.** A claim about what a screen, terminal,
   UI, or IDE shows needs a screenshot or an equivalent check before "done". This is the one
   verification class with a record of false successes.
2. **Ask the system that owns the state.** Continuity lives in the memory adapter; query it
   before claiming ignorance. Live execution lives in the runner; query it with the exact task or
   turn id. Memory activity is supporting evidence, not a completion or health signal. When
   implementation finishes, track the reviewers instead.
3. **End substantial sessions with a breadcrumb.** A handoff with the branch, the dirty state,
   and the next useful action. A resume anchored on a handoff starts quickly; a resume that has
   to reconstruct the state from git history does not.
4. **Loop or schedule, never babysit.** A loop recurs while the human is working and ends with
   the session. A schedule recurs whether or not anyone is there. Polling by hand is neither.

### Retirement cadence

The table is re-audited on a cadence. A tool that gets a written trigger rule and still has zero
uses two weeks later has either the wrong trigger or no remaining job. Fix the trigger or take
the tool off the active surface. A row nobody uses is noise that every agent still has to read.

## Work Modes

Triage picks the path; the work mode picks the ceremony around it. There are two, selected per
task and carried into handoffs, compaction summaries, and delegate prompts.

- **Prototype** (the default): work autonomously through the smallest useful end-to-end slice,
  make routine reversible decisions without asking, verify changed behavior through its real
  user path, and give progress updates at milestones. No extra human checkpoints.
- **SDLC**: make the plan and acceptance criteria reviewable before implementation, implement in
  verifiable slices, have a fresh reviewer assess the actual diff, then present the result for a
  delivery checkpoint. A general wish to move fast is not approval of an unseen result.

Neither mode grants permissions, waives required checks, or relaxes the
[shared operating policy](one-policy-two-engines.md). The fleet's PLAN mode is the same idea as
the SDLC plan gate, applied per project; see [Fleet Execution](fleet-execution.md).

## How To Apply It

Run the gate before any task that might reach for a multi-agent build, and before any task the
human asks "what's the best way to do this?" about. Keep the gate in the main loop. Present
ranked options with the print-only option included and wait for the pick.

Write the stage and engine tables in terms of the disciplines and engines the installed clients
actually provide, and keep one table for both engines rather than one per client. Start the
Reach For / Not table from an audit of real sessions, not from a wish list, and put the
retirement check on the calendar when a row is added.

State the work mode once when it changes, and pass it explicitly to every delegate.

## Failure Modes

A gate that spawns a classifier subagent costs more than the mistakes it prevents. A gate that
runs the heavy path without a pick is not a gate. Re-triaging tickets that are already
agent-ready repeats work and drifts from the spec. Compacting as the first reach, instead of the
last, throws away context that continuing or a handoff would have kept. A playbook written from
intuition instead of usage fills up with rows that never fire, and without a retirement cadence
it only grows. A work mode treated as a permission switch ends up waiving a check it was never
allowed to touch.

## Related

- [Supervised Delegation](supervised-delegation.md): the channel a delegated build runs over.
- [Council Review](council-review.md): the path for decisions that are costly if wrong.
- [Handoffs and Continuity](handoffs-and-continuity.md): what a phase-boundary handoff writes.
- [One Policy, Two Engines](one-policy-two-engines.md): the shared rules both engines triage under.
- [Fleet Execution](fleet-execution.md): PLAN, DO, and FULL_AUTO across several projects.
- [Codex from Claude](../workflows/codex-from-claude.md): the delegated-build workflow.
