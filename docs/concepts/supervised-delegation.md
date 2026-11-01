# Supervised Delegation

## The Problem

Handing a coding task to a second agent is easy. Knowing what happened to it is not. A raw
`codex exec` or `claude -p` call blocks the caller for the whole turn, dies with the caller's
shell, and returns a screen's worth of text that the caller then has to interpret. Workflows built
on that shape overrun: the wrapper gives up waiting, reports "still running", and verification
starts on a half-written tree. The opposite failure is just as common: the caller watches a quiet
log, decides the worker is hung, and starts a second writer on the same checkout.

## The Pattern

Put a thin channel between the conductor and the worker, and give it four properties.

1. **Send and wait are separate.** `send` returns a turn record immediately. `watch <turn>` is a
   separate, restartable observation that records only the worker's thread id. Any process can
   pick up a turn from its record alone, so a killed caller loses nothing and a long turn costs
   nothing to supervise.
2. **The worker's own transcript is the data plane.** Completion and payload are read from the
   worker's rollout or session log, never scraped from a terminal screen. Screens wrap, truncate,
   and decorate; the log is exact.
3. **The result is a one-line envelope.** The worker ends its final message with a single line,
   `ENVELOPE {"status":"done|question|failed",...}`, set once in the first turn and honored on
   every later turn. A question and a completion look identical in process state; only the
   envelope tells them apart.
4. **Attention is bounded and explicit.** The watcher checks for a terminal result first, then
   warns after a fixed quiet interval or a total budget. A warning is a request for a human or
   conductor to look, not proof of a hang. Nothing restarts automatically.

The worker runs in a sandbox that can write the working tree but not `.git`. The reference runner
defaults to the `workspace-write` sandbox, which enforces that rather than leaving it to convention.
Widening the sandbox for one worker (`danger-full-access`) is an explicit, deliberate opt-out that
drops the guarantee and moves git protection back to the prompt and to the conductor's review. The
conductor reviews, re-verifies, and commits, so the human stays the sole author of every change.

## The Contract

A channel that implements this pattern exposes four verbs and one exit-code table.

```text
start  --cwd <repo> --label <task> [--effort <level>] [--tier <service-tier>]   -> {name, transport}
send   <name> - <<'TASK' ... TASK                      -> {turn}
watch  <turn> --timeout <seconds>                      -> exit code + envelope JSON
stop   <name>
```

| Exit | Result          | Conductor action                                                                            |
| ---- | --------------- | ------------------------------------------------------------------------------------------- |
| 0    | `done`          | Read the envelope and move to verification.                                                 |
| 10   | `question`      | Surface the worker's question to the human.                                                 |
| 11   | `failed`        | Report the observed reason; inspect before retrying.                                        |
| 2    | timeout         | No terminal result yet. Repeat the same watch. Never resend.                                |
| 3    | blocked or gone | Inspect the runner or pane; do not assume a specific cause.                                 |
| 4    | aborted         | Report the interrupted turn.                                                                |
| 12   | attention       | Quiet too long, budget exceeded, or completed without a valid envelope. Notify and inspect. |
| 1    | error           | The observation itself failed.                                                              |

Rules the conductor follows:

- Save the exact `turn` that `send` returned. One worker can run many turns, so "latest" is
  not a safe target.
- Exit 2 means "observe again", not "progress". Exit 12 means "a person should look", not "kill
  it". Never start a second writer while the first may still be working.
- Liveness comes from the runner. A memory system's `last_seen` timestamp, a file mtime, or a
  quiet log is evidence history, not a heartbeat.
- A fix pass goes to the same worker, which still holds the implementation context.

Two transports satisfy the same contract. An interactive one places the worker in a visible
terminal pane (the author uses Herdr) so a human can watch or take over. A headless one uses the
worker CLI's non-interactive mode with a resumable session id. The conductor's code is identical
for both; only `start` knows which it got.

## How To Apply It

Use the channel from inside a deterministic orchestrator. Each implementation step is a thin
relay agent whose entire job is one `send`, a bounded `watch` loop, and a structured report of the
envelope and the resulting `git status`. Verification runs only after `done`, as separate
reviewers, ideally on a different model than the one that wrote the code. The
[Codex from Claude](../workflows/codex-from-claude.md) workflow and the
[`codex-workflow-hybrid`](../../skills/codex-workflow-hybrid/SKILL.md) skill are built on this
shape.

Put the envelope instruction and the git prohibition in every task prompt. Tell the worker what
to build and what proves it worked; do not dictate tool timeouts, which a worker cannot honor and
will refuse.

## Failure Modes

A wrapper that blocks on the worker's whole turn cannot outlive its shell, so a long turn turns
into an overrun or a duplicate run. Reading results from the screen loses lines silently. A
watcher that treats silence as failure launches a second writer into a tree the first is still
editing. A watcher with no attention budget waits forever and the human finds out hours later.
Pinning a model in the channel's documentation makes the document wrong within a month; pin it in
configuration and name only the service tier and reasoning effort the workflow depends on.

## Related

- [Codex from Claude](../workflows/codex-from-claude.md)
- [`skills/codex-workflow-hybrid`](../../skills/codex-workflow-hybrid/SKILL.md)
- [`skills/codex-workflow-lean`](../../skills/codex-workflow-lean/SKILL.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
