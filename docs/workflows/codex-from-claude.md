# Codex From Claude

## When To Use It

Use this workflow when a Claude-led conductor hands a well-specified implementation, debug, or fix
task to Codex and keeps the plan, the verification, and git for itself. The split is deliberate:
Codex carries the generation, Claude spends its tokens on orchestration and on checking work it did
not write. The model that did not write the code verifies it.

Prefer it over a single-engine build when the task is bounded enough to state in one prompt and
correctness matters enough to want a second model's review. When the task is lower risk and a
human will review before merge, the lean variant
([`skills/codex-workflow-lean`](../../skills/codex-workflow-lean/SKILL.md)) lets Codex review its
own diff instead.

## Inputs

- A locked scope: what this step delivers, what it defers, and which paths it may touch.
- A task prompt with the repository path, allowed files, the command that proves the work, and the
  envelope instruction (see [Supervised delegation](../concepts/supervised-delegation.md)).
- A supervised Codex channel that implements the start/send/watch/stop contract.
  [`scripts/codex-runner`](../../scripts/codex-runner) is the public reference adapter: headless
  `codex exec --json` for the first turn and `codex exec resume` for later turns on the same
  session.
- A sandbox where the worker can edit the tree but not `.git`. Commits always belong to the
  conductor.
- An authorization record when the delegated work carries human-approved scope beyond the task
  itself (see [Authorization provenance](../concepts/authorization-provenance.md)).

## Steps

The work runs in three movements. Only the middle one is delegated.

### Pre-flight (Claude main loop)

1. Lock the scope. Reconcile drift between the request and the repo, then show the human owner the
   shape so they can redirect before any tokens are spent on generation.
2. Persist the plan outside the session: a committed repo doc, and the durable memory adapter when
   the project has one, so the plan survives a context reset.
3. Branch from the default branch and commit the plan.
4. Start one Codex worker for the task with
   `start --cwd <repo> --label <task> --effort high --tier fast`. The worker runs `workspace-write`,
   so the tree is editable and `.git` is read-only to it.

### Execute (a deterministic workflow)

5. A thin relay agent sends one bounded turn and saves the exact turn ID that `send` returned. The
   relay does no reasoning of its own; it only sends, watches, and reports.
6. The relay watches that turn in bounded intervals and acts on the exit code (table below). Any
   result other than `done` stops the workflow and returns to the conductor instead of verifying a
   half-written tree.
7. On `done`, parallel Claude reviewers verify the diff with a structured verdict: a functional
   lens (scope, syntax, the feature is present, build and tests pass) and an editorial lens
   (honesty, correctness, project constraints). A missing reviewer verdict blocks; it never counts
   as a clean review.
8. Issues the reviewers mark as real go back to the same worker as a fix turn. That worker still
   holds the implementation context, so the fix is cheaper and less likely to regress. A fix counts
   as applied only when its own turn returns `done`.

### Post-flight (Claude main loop)

9. For a running app or server, rebuild, restart, and confirm the new assets are actually served
   before trusting a green test run. A packaged binary serves stale files until rebuilt.
10. Stop the worker.
11. Review the diff scope, run the final verification, and commit as the human owner.
12. Report the diff, the reviewer verdicts, and what was deliberately left to the human owner.

### Hard guardrails in every Codex prompt

- Edit only the named paths. Do not touch out-of-scope layers such as data, API, or build files.
- Never run `git add`, `git commit`, or `git push`. Leave changes unstaged.
- No new runtime dependencies and no CDN; stay with the existing stack.
- End with a terse summary of files changed and the envelope line. No reasoning traces.
- Say what to build and what proves it worked. Do not dictate tool timeouts; a worker cannot honor
  them and will refuse.

### Acting on each exit code

| Exit | Result          | What the conductor does                                                |
| ---- | --------------- | ---------------------------------------------------------------------- |
| 0    | `done`          | Read the envelope and start the reviewers.                             |
| 10   | `question`      | Surface the question to the human owner; answer it to the same worker. |
| 11   | `failed`        | Report the observed reason verbatim; inspect before any retry.         |
| 2    | timeout         | No terminal result yet. Watch the same turn again. Never resend.       |
| 3    | blocked or gone | Inspect the runner or pane before sending anything; assume no cause.   |
| 4    | aborted         | Report the interrupted turn and its last known state.                  |
| 12   | attention       | Notify the human owner with reason and ages; inspect before restart.   |
| 1    | error           | The observation itself failed; report it and check the channel.        |

Exit 12 is a request for a person to look, not proof of a hang. Never start a second writer while
the first may still be working.

### Service tier and effort

A conductor is waiting on every turn in this workflow, so delegated turns use the fast service tier
at high reasoning effort. Unattended fleet rounds are the opposite case and use the standard tier
at `xhigh` (see [Codex fleet](codex-fleet.md)). The model itself is whatever the configured Codex
model is; this document does not pin one.

## Outputs

- A branch with the plan commit and one conductor-authored implementation commit.
- Each turn's envelope and the reviewer verdicts, kept as workflow artifacts.
- A status line that names the current owner. Once Codex finishes, report "Codex finished;
  functional and editorial reviewers are running" rather than re-diagnosing the finished worker.
- A handoff when work remains or the branch is left in a non-final state.

## Verification

Verification starts only after `done`. Every required reviewer must return a valid verdict before
the change is called passing. The conductor re-runs the task's proving command itself before
committing; a worker's summary and a reviewer's opinion are inputs, not proof.

## Safety Gates

- Commits belong to the conductor; the worker's sandbox makes `.git` read-only.
- Preserve unrelated dirty files.
- Do not publish private data.
- Read results from the worker's session log through the channel, never from a terminal screen.
- Do not build custom liveness probes. A memory adapter's last-seen timestamp or a quiet log is not
  a heartbeat; the runner owns turn status.
- If supervision continues after the conductor hands control back, keep the relay running in the
  background with completion notification on. Do not claim a monitor exists unless one was started.
- Record a handoff when work remains.

## Related

- [Supervised delegation](../concepts/supervised-delegation.md), the channel contract
- [Authorization provenance](../concepts/authorization-provenance.md)
- [One policy, two engines](../concepts/one-policy-two-engines.md)
- [`skills/codex-workflow-hybrid`](../../skills/codex-workflow-hybrid/SKILL.md)
- [Claude from Codex](claude-from-codex.md), the same split with the roles reversed
- [Codex-led session](codex-led-session.md)
