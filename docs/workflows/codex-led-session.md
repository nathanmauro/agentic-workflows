# Codex-Led Session

## When To Use It

Use this workflow when Codex is the coordinator for a whole working session: it opens the project,
decides how the work should run, delegates the parts another engine does better, and closes the
session so the next one can resume quickly. It is the counterpart to a Claude-led session. Either
engine can lead; the same operating policy governs both
(see [One policy, two engines](../concepts/one-policy-two-engines.md)).

## Inputs

- A project checkout with its own instructions, and an unfinished-work file such as `NEXT.md`.
- The shared operating policy, rendered into the Codex global guide as a hash-marked managed block.
- A durable memory adapter reachable over MCP. The reference is
  [Black Box](https://github.com/nathanmauro/black-box): typed decisions with rejected
  alternatives, handoffs with one next action, and projections, shared by Codex and Claude Code.
- An issue tracker for execution state. The reference setup uses Linear and logs finished work
  that had no issue as a `Done` issue labeled `retroactive`.
- Codex lifecycle hooks: a session-start hook that recalls context, prompt and tool recording, a
  debounced stop hook that finalizes the session record, and a formatter that runs on every patch.

### Prompt file plus one-line alias

Each `/prompts:*` command below is a prompt file in the client's prompts directory, and the same
text backs a one-line shell alias. The prompt file is what the TUI offers; the alias keeps the
command working when a client version drops or ignores prompt files, and from a plain shell. Most
run one client-tagged command (the baton lookup calls the same script from both clients), so Codex
and Claude Code produce the same report shape from the same underlying tool. The `$`-prefixed
commands (`$baton`, `$route`, `$work-mode`, `$council`) are skills, invoked the same way in both
clients.

## Steps

### Start

1. The session-start hook recalls recent context for this project from the memory adapter, so
   Codex opens with the last handoff instead of reconstructing it from git.
2. `$baton` answers "who touched this project last, and where does it stand?" It is a lookup, not
   judgment work, and it returns a fixed-format card:

   ```text
   -- BATON: <project> ---------------------------------
   WHO:   <agent/client> (<source>) · <date>
   STATE: <branch> @ <sha> · <clean / N dirty>
   LAST:  <one or two sentences on what was done and where it stands>
   OPEN:  • <open loop>  (up to three)
   NEXT:  <one concrete next action>
   ----------------------------------------------------
   ```

   Memory-adapter handoffs and decisions outrank the git log. When the adapter is unavailable, WHO
   comes from commit authors and cadence, and the card says so.

3. `/prompts:next` prints the project's unfinished-work file as startup context. If the session
   changes that work, Codex updates the file before closing.

### Work

4. `$route` is the triage gate, run in the main loop before any non-trivial task. It picks which
   stage skill fits, then which engine runs it: just answer, research, plan first, direct build,
   delegated build, or review. It presents ranked options, always including "print the command,
   don't run it", and the human owner picks. The gate exists because defaulting to the heaviest
   path is expensive: one such run burned about 11.75M tokens across 317 agents and produced no
   diff.
5. `$work-mode` selects prototype (end-to-end slices, verified through real use) or SDLC (plan and
   review checkpoints). The selection is passed to every delegate.
6. For a contested decision where being wrong costs more than an hour, `$council` runs independent
   opinions, anonymized cross-review, and a neutral synthesis
   (see [Council review](../concepts/council-review.md)).
7. For a bounded review, plan, or second opinion from the other model, Codex starts Claude in a
   managed pane with the `claude-remote` skill and carries the authorization record
   (see [Claude from Codex](claude-from-codex.md)).
8. When the work is a multi-piece build that should be orchestrated and cross-verified, Codex hands
   it back to a Claude conductor running the hybrid build, or the lean build when self-review is an
   accepted tradeoff (see [Codex from Claude](codex-from-claude.md)). Delegation over the
   supervised channel follows the same contract regardless of who leads
   (see [Supervised delegation](../concepts/supervised-delegation.md)).

### Resume

9. `/prompts:reseed` rebuilds working context from a prior session and always writes the same seed:
   last intent, decisions, state at end, open threads. Fast (the default) reads only the target
   transcript or an existing seed and stays short. Deep uses one background pass over the full
   transcript and any directly linked handoff or decision events. Observer queries session
   lineage and correlated events first, through
   [Agent Observatory](https://github.com/nathanmauro/agent-observatory), for cases with
   conflicting evidence, unclear authorship, or causes that span sessions; when that source is
   unavailable it says so and falls back to deep. Use it after a context reset, a crash, or a
   declared-messy restart where handing off and starting fresh beats fighting a polluted context.

### Close

10. `/prompts:handoff` captures the session to the memory adapter: branch, SHA, dirty state,
    verification run, live-system effects, and exactly one next action. It also prints a
    next-session seed to paste into the following session. When the adapter is unreachable, it
    reports the blocker and what is needed to retry
    (see [Closeout and handoff](closeout-and-handoff.md)).
11. `/prompts:ship` takes a verified branch to merged:
    1. Inspect `git status` and separate unrelated dirty files from this change.
    2. Run the project's tests and `git diff --check`.
    3. Stage exact paths and commit with the human owner as sole author.
    4. Push and open a PR with a test plan.
    5. Merge with a normal merge commit unless told otherwise. Never squash commits that are ahead
       without asking.
    6. Update the default branch locally and start the next working branch.
    7. Refresh the unfinished-work file.

## Outputs

- A baton card at the start and a memory-adapter handoff with one next action at the end.
- Decisions recorded with their rejected alternatives, from routing, council, or Claude review.
- Conductor-authored commits, and a merged PR when `/prompts:ship` ran.
- An updated unfinished-work file and, where relevant, tracker issues reconciled with what shipped.

## Verification

Each phase has its own proof. The baton card cites the handoff or commit it read. Delegated work is
verified by the model that did not write it, and accepted only after a concrete command passes in
the target repo. `/prompts:ship` instructs the agent to run the project tests and
`git diff --check` before merging; the merge is a checklist step, not a scripted gate. A handoff is
complete only when the adapter confirms the write; otherwise the report names the blocker and the
retry handle.

## Safety Gates

- A complete, verified unit may be committed and pushed to the branch's existing upstream after
  inspecting the outgoing range. PRs, merges, publishing a branch, creating or changing remotes,
  force-push, and history repair need `/prompts:ship` or explicit direction every time.
- Never share a checkout between concurrent writers; use separate worktrees or serialize.
- Environment-visible claims (a service is up, a turn finished) need observation, and the answer
  comes from the system that owns that state, not from a memory timestamp.
- Carry the human owner's exact words with any delegated request
  (see [Authorization provenance](../concepts/authorization-provenance.md)).
- End every substantial session with a breadcrumb, even when the work is unfinished.
- Preserve unrelated dirty files, and do not publish private data.

## Related

- [Codex from Claude](codex-from-claude.md)
- [Claude from Codex](claude-from-codex.md)
- [Closeout and handoff](closeout-and-handoff.md)
- [Handoffs and continuity](../concepts/handoffs-and-continuity.md)
- [One policy, two engines](../concepts/one-policy-two-engines.md)
- [`templates/portable-policy.md`](../../templates/portable-policy.md)
