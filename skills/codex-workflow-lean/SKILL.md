---
name: codex-workflow-lean
description: >
  The leanest Codex-delegated build: Claude is used ONLY for the Workflow orchestration
  engine (deterministic fan-out, pipelines, structured output) while the conductor owns git.
  EVERY agent, implementation AND review, sends its work to Codex over a supervised channel.
  Use when the user wants maximum Claude-token savings: "codex for everything", "leanest",
  "claude only for the workflow", "minimize claude tokens". Triggers: "codex only", "leanest
  codex workflow", "claude just for the workflow engine". Tradeoff vs codex-workflow-hybrid:
  Codex grades its own work (no cross-model check), so reserve for lower-risk or
  well-specified tasks, or add a human review gate after.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Set your models through the client or env knobs, and replace paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex-only workflow (Claude is the workflow engine; Codex does everything else)

Maximum leanness on Claude tokens. Claude contributes exactly two things: the **Workflow tool**
(deterministic background orchestration, pipelines, structured output, the agent budget) and
the **conductor's ownership of git** (the human owner stays sole author). Everything with real
token weight, implementation AND review, is a Codex turn wrapped in a thin Claude agent that
only relays.

## When to prefer this over the hybrid

- The user explicitly wants the leanest possible Claude footprint.
- The task is well-specified or lower-risk, OR a human will review the result before merge.

## The self-review tradeoff

If correctness is high-stakes, prefer [codex-workflow-hybrid](../codex-workflow-hybrid/SKILL.md):
its Claude verify lens is a _different model_ checking Codex, which catches what self-review
cannot. Here, Codex reviews its own diff: cheaper, but blind to its own blind spots. Mitigate by
(a) running the review on a _fresh_ Codex worker with an explicitly adversarial prompt ("try to
find what is wrong; default to flagging"), and/or (b) a human review gate before commit.

## The supervised Codex channel

Every implementation, review, and fix turn goes through a runner that implements the
[supervised delegation](../../docs/concepts/supervised-delegation.md) contract. The public
reference adapter is [`scripts/codex-runner`](../../scripts/codex-runner). Start an
implementation worker and a separate fresh review worker in pre-flight, and put both names in
the template.

```bash
codex-runner start --cwd <repo> --label implement --effort high --tier fast
codex-runner start --cwd <repo> --label review --effort high --tier fast
codex-runner send <name> - <<'CODEX_TASK'
<task>
CODEX_TASK
codex-runner watch <turn> --timeout 60
codex-runner stop <name>
```

The runner uses the configured model, transport, and sandbox; this skill does not pin a model.
A conductor waits on every turn, so attended delegation uses the fast service tier at high
effort. Unattended fleet rounds use the standard tier at `xhigh`.

### Acting on each exit code

| Exit | Result          | Conductor action                                                       |
| ---- | --------------- | ---------------------------------------------------------------------- |
| 0    | `done`          | Read the envelope and move to the next stage.                          |
| 10   | `question`      | Surface the question to the human owner; answer it to the same worker. |
| 11   | `failed`        | Report the observed reason verbatim; inspect before any retry.         |
| 2    | timeout         | No terminal result yet. Watch the same turn again. Never resend.       |
| 3    | blocked or gone | Inspect the runner or pane before sending anything; assume no cause.   |
| 4    | aborted         | Report the interrupted turn and its last known state.                  |
| 12   | attention       | Notify the human owner with reason and ages; inspect before restart.   |
| 1    | error           | The observation itself failed; report it and check the channel.        |

### Supervision rules

- **Save the exact turn** that `send` returned. One worker runs several turns, so "latest" is
  not a safe target.
- **Bounded attention.** On exit 12, return the turn, the reason, and the activity and elapsed
  ages, and notify the human owner promptly through the configured notification channel. Never
  keep waiting silently. Silence does not prove a hang: inspect before stopping or restarting,
  and never launch a second writer while the original may still be working.
- **No custom liveness probes.** Completion outranks activity timestamps. Do not read a memory
  adapter's last-seen time, scan file mtimes, or build a per-project watchdog.
- **Follow the current phase.** Once implementation returns `done`, report "Codex finished; the
  reviewer is running" and supervise the review turn, not the finished one. Keep the background
  relay's completion notification on when returning control to the human owner.
- **Fix pass to the same worker.** The implementation worker, not the reviewer, receives the
  fix turn, because it still holds the implementation context.
- **One writer at a time.** Review starts only after implementation finishes. It may run builds
  and tests that write generated artifacts under `workspace-write`, but its prompt forbids
  editing source files. Never run implementation, review builds, and fixes concurrently in the
  same checkout.
- **Sandbox.** `workspace-write` makes `.git` read-only to every worker, so the conductor owns
  git by construction.

## Run it

### Pre-flight (Claude main loop, same as hybrid)

Lock scope, persist the plan (a committed repo doc, plus a durable memory adapter when the
project has one), branch, commit the plan, then start both workers.

### Execute (Workflow tool; every agent wraps Codex)

Customize [`templates/workflow.js`](templates/workflow.js). Its pipeline:

- **Implement.** A thin Claude agent sends and watches one implementation turn. Any outcome
  other than `done` stops the workflow.
- **Review.** A thin Claude agent sends the fresh review worker an adversarial turn that inspects
  `git diff` and prints a JSON verdict before its envelope line; the agent's `schema` validates
  and relays it. No Claude reasoning is spent reviewing: Codex does it, Claude just shapes the
  output. A missing or malformed verdict stops the workflow.
- **Fix.** A conditional turn to the implementation worker for `real: true` issues only. A fix
  counts as applied only when its own turn returns `done`.

### Post-flight (Claude main loop)

Require every stage to return `done` and the review to contain a valid verdict. Then rebuild and
restart (if an app) and confirm the new assets are served, review scope, and re-run the proving
command. If it fails, send a fix turn to the implementation worker, which still accepts `send`
until it is stopped. Once the re-run passes, stop both workers, commit as the human owner, and
report. On attention or failure, return to the main loop without starting the next stage or
another writer.

## Hard guardrails (in every Codex prompt)

- Edit ONLY named paths; never touch out-of-scope layers.
- Never `git add`, `commit`, or `push`; the conductor owns git and authorship.
- No new runtime deps, no CDN.
- Implementation prompt: terse summary of files changed, then the envelope line. Review prompt:
  emit JSON matching the verdict schema before the final envelope line.
- Say what to build and what proves it worked; do not dictate tool timeouts.

## Token economics

Claude pays only for orchestration overhead, the per-turn relay, and JSON validation. All
generation and all review are Codex tokens. This is as lean as it gets while still using Claude's
Workflow engine. The cost is the lost cross-model verification; buy it back with an adversarial
review on a fresh worker or a human gate.
