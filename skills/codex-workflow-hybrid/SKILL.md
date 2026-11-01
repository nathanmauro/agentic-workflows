---
name: codex-workflow-hybrid
description: >
  Orchestrates a scoped build in which Claude conducts a background Workflow, Codex does the
  heavy implementation over a supervised channel, and Claude adversarially verifies every
  deliverable. Use when the user wants to delegate a build to Codex while keeping a
  cross-model verification pass. Triggers: "use codex", "delegate to codex", "defer to codex",
  "save claude tokens", "use codex for the heavy lifting", "codex workflow", "hybrid codex".
  This is the balanced variant: cross-model verification is the point. Use
  codex-workflow-lean only when deliberately accepting self-verification.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Set your models through the client or env knobs, and replace paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex-delegated workflow (hybrid: Claude orchestrates and verifies, Codex implements)

The pattern is a conductor/engine split. Claude is the conductor and the safety boundary. Codex
is the engine, reached through a supervised channel at high reasoning effort. Heavy generation
runs as Codex tokens; Claude pays only for orchestration and an adversarial verify pass.

## Why this shape

- **Codex writes the code.** Each implementation step is a thin Claude workflow agent whose
  entire job is to send one turn over the channel and relay the result envelope. Codex runs
  under `workspace-write`: it edits the working tree, but `.git` is read-only to it.
- **Claude verifies.** Verification is where Claude earns its tokens. A different model checking
  Codex's work catches what self-review misses.
- **The conductor owns git.** The sandbox enforces it: the main loop makes every commit, so the
  human owner stays sole author with no AI attribution.
- **Everything on a branch.** Fully reversible; the outer Claude session is the boundary.

## The channel

Every Codex turn goes through a runner that implements the
[supervised delegation](../../docs/concepts/supervised-delegation.md) contract. The public
reference adapter is [`scripts/codex-runner`](../../scripts/codex-runner); any CLI with the same
four verbs and exit codes works.

```bash
codex-runner start --cwd <repo> --label <feature> --effort high --tier fast  # -> {"name", "transport"}
codex-runner send <name> - <<'CODEX_TASK'                         # returns a turn record now
<task>
CODEX_TASK
codex-runner watch <turn> --timeout 60                           # the exact turn send returned
codex-runner stop <name>
```

- **Transport.** An interactive transport puts the worker in a visible terminal pane (for
  example a Herdr tab) that a human can watch or take over; a headless transport uses
  `codex exec` with a resumable session. The contract is identical, and only `start` knows which
  one it got.
- **Result.** The runner reads the result from the Codex session log, never from the screen.
  Codex ends its final message with one `ENVELOPE {"status":"done|question|failed",...}` line.
- **Save the exact turn.** Keep the `turn` that `send` returned and watch that turn, even after
  the same worker receives another task. "Latest" is not a safe target.
- **Model and tier.** The model is whatever the configured Codex client uses; this skill does not
  pin one. A conductor waits on every turn here, so attended delegation uses the fast service tier
  at high effort. Unattended fleet rounds are the opposite case and use the standard tier at
  `xhigh`.

### Acting on each exit code

| Exit | Result          | Conductor action                                                       |
| ---- | --------------- | ---------------------------------------------------------------------- |
| 0    | `done`          | Read the envelope and start the reviewers.                             |
| 10   | `question`      | Surface the question to the human owner; answer it to the same worker. |
| 11   | `failed`        | Report the observed reason verbatim; inspect before any retry.         |
| 2    | timeout         | No terminal result yet. Watch the same turn again. Never resend.       |
| 3    | blocked or gone | Inspect the runner or pane before sending anything; assume no cause.   |
| 4    | aborted         | Report the interrupted turn and its last known state.                  |
| 12   | attention       | Notify the human owner with reason and ages; inspect before restart.   |
| 1    | error           | The observation itself failed; report it and check the channel.        |

### Supervision rules

- **Bounded attention.** The runner checks for a terminal result first, then warns after a fixed
  quiet interval or a total turn budget. A turn that completes without a valid envelope also
  returns attention. On exit 12, return the exact turn, the reason, and the activity and elapsed
  ages to the main loop, and notify the human owner promptly through the configured notification
  channel. Never keep waiting silently.
- **A warning is not a hang.** Inspect before stopping or restarting anything, and never launch a
  second writer while the original may still be working.
- **No custom liveness probes.** Do not read a memory adapter's last-seen timestamp, scan file
  modification times, or write per-project watchdog scripts. The runner owns current turn
  status; completion always outranks a quiet log.
- **Follow the current phase.** Once implementation returns `done`, report "Codex finished;
  reviewers are running" and observe the reviewer tasks. Do not keep watching the completed
  implementation turn. Track each active worker, turn, and task ID with its purpose.
- **Supervision survives the response.** If work continues after control returns to the human
  owner, keep the relay inside the background Workflow with completion notification on. It
  repeats bounded watches and returns on completion or attention. Do not claim an unattended
  monitor exists unless one was actually started.
- **Fix pass to the same worker.** The worker that implemented still holds the context, so the
  fix is cheaper and less likely to regress.
- **Sandbox.** `workspace-write` is the default. If the build tool cannot run sandboxed, widen
  the sandbox deliberately for that worker, or leave the build to Claude's functional lens.

## Run it: three movements

### 1. Pre-flight (Claude main loop, cheap; do not delegate this)

1. **Lock the scope.** Reconcile any drift, define exactly what this phase delivers and what it
   explicitly defers. Show the human owner the shape; let them redirect.
2. **Persist the plan off-session** so it survives a context reset:
   - a repo doc (`ROADMAP.md` or `PLAN.md`), committed; and
   - the plan as a decision or handoff in a durable memory adapter, when the project has one.
3. **Branch** from the default branch (`git checkout -b <feature>`) and commit the plan.
4. **Start the worker** with
   `codex-runner start --cwd <repo> --label <feature> --effort high --tier fast` and put the
   printed `name` into the template's `AGENT`.

### 2. Execute (the Workflow tool; Codex does the work)

Customize [`templates/workflow.js`](templates/workflow.js) for the task and pass it inline to the
Workflow tool. Its pipeline:

- **Implement.** One (or a few) thin Claude agents, each sending one turn for a scoped task. Any
  outcome other than `done` stops the workflow and returns to the main loop instead of verifying
  a half-written tree. One coherent turn per cohesive unit beats many parallel turns that fight
  over the same files; run sequentially when tasks share files.
- **Verify.** Parallel Claude lenses with a structured schema:
  - _functional_: scope (no stray files), syntax, feature presence, build and tests green;
  - _editorial_: honesty and no overclaim, correctness, aesthetic constraints.
- **Gate.** A missing or malformed reviewer verdict stops the workflow; it never counts as a
  clean review.
- **Fix.** A conditional turn to the same worker, only for issues the lenses marked `real: true`.
  A fix counts as applied only when its own turn returns `done`.

### 3. Post-flight (Claude main loop)

1. For a running app or server, **rebuild, restart, and confirm the new assets are actually
   served** (a packaged binary serves stale files until rebuilt). Request a known new marker;
   watch for keep-alive daemons that respawn on kill.
2. **Review the diff scope** and re-run the proving command yourself. If it fails, send a fix
   turn to the same worker; a stopped worker refuses any later `send`.
3. `codex-runner stop <name>` once the re-run passes.
4. **Commit** as the human owner with no AI co-author or trailer.
5. Report the diff, the verdicts, and what was deliberately left to the human owner.

## Hard guardrails (put these in every Codex prompt)

- Edit ONLY the named paths. Never touch out-of-scope layers (for example data, API, or build
  files).
- Never run `git add`, `git commit`, or `git push`. Leave changes unstaged.
- No new runtime dependencies, no CDN; stay consistent with the existing stack.
- End with a terse summary of files changed and the envelope line; no reasoning traces.
- Say what to build and what proves it worked. Do not dictate tool timeouts; a worker cannot
  honor them and will refuse.

## Token economics

Heavy generation is Codex tokens. Claude pays for orchestration (small), the per-turn relay
(small, because the relay only sends and watches), and the verify reads (moderate, because the
lenses read diffs and run builds). The verification budget is the price of the cross-model check;
do not skip it to save tokens. The lean variant is an explicit lower-assurance alternative, not
an automatic fallback.

## On failure

Report the runner's observed reason without guessing a cause. On exit 3 or 4, inspect the runner
or pane before sending anything. On exit 12, return the attention report and notify the human
owner; do not stop or restart based on elapsed time alone. On exit 2, run the same bounded watch
for the same turn again. For an auth lapse or rate limit, surface the error verbatim and suggest
`codex login status`. Verification starts only after `done`, and every required reviewer must
return a valid verdict before the change is called passing.
