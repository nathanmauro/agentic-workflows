# Supervised Delegation Example

A real turn, recorded on 2026-10-31 while this repository was being updated. Claude Code was the
conductor. Codex was the worker, running in a Herdr pane through the owner's private adapter,
which implements the [supervised delegation](../../docs/concepts/supervised-delegation.md)
contract. The public reference adapter is [`scripts/codex-runner`](../../scripts/codex-runner).

The turn failed. That is why it is the example. The channel's job is not to make the worker
succeed; it is to make the outcome unambiguous, keep the tree safe, and stop the conductor from
guessing. Here is what that looked like.

## What happened

1. The conductor started a worker in a dedicated git worktree and sent one bounded task
   ([`task.md`](task.md)). `send` returned a turn record immediately ([`send.json`](send.json)).
2. The conductor ran a bounded `watch` on that exact turn in the background and kept working.
3. Seven minutes later the watch exited with code 11, `failed`, and the worker's envelope
   ([`watch.json`](watch.json)): its execution tool had timed out before starting, four times,
   so it had edited nothing and run no verification.
4. The conductor inspected before acting ([`conductor-notes.md`](conductor-notes.md)): the
   worker's pane, its rollout, a probe on the headless transport, a probe of the bare CLI in a
   scratch directory, and the CLI's own diagnostic. The fault was outside the task: the worker's
   runtime could not fetch a component it needed.
5. The conductor stopped the worker, did not resend, did not start a second writer on the same
   checkout, and routed the mechanical work to the other engine for this pass. Nothing was
   committed from the failed turn because there was nothing to commit, and the verification stage
   never started because the status was not `done`.

## Why this is the pattern working

- **Send and wait were separate.** The conductor did other work for seven minutes and lost
  nothing when the result arrived.
- **The envelope told the truth.** A screen read would have shown a tidy summary; the envelope
  said `failed` with a reason, and the exit code made the next step mechanical.
- **No silent waiting, no duplicate writer.** Exit 11 is a report, not a retry. The conductor
  read the runner's own evidence instead of a memory timestamp or a quiet log.
- **Git was never at risk.** The worker ran in a workspace-write sandbox where `.git` is
  read-only, in its own worktree. The conductor owned every commit before and after.

## Reproduced with the public adapter

Later the same afternoon the public adapter was pointed at the same Codex install from an empty
scratch directory:

```text
codex-runner start --cwd . --label smoke --effort low
codex-runner send smoke-cff8 - <<'TASK'
Smoke test. Run the shell command `pwd` and reply with its output only.
TASK
codex-runner watch smoke-cff8-t01 --timeout 150
```

`watch` exited 11 after 70 seconds with the worker's envelope: "Could not run pwd: tool host
negotiation timed out twice." Same fault, same shape of answer, from a single stdlib Python script
instead of the private adapter. That is what a contract is for.

## Files

- [`task.md`](task.md): the task as sent, condensed and sanitized.
- [`send.json`](send.json): the turn record `send` returned.
- [`watch.json`](watch.json): the terminal result `watch` returned, with its exit code.
- [`conductor-notes.md`](conductor-notes.md): the inspection the conductor did before deciding.

The worker session id is redacted and the task text is sanitized. In `watch.json`, `command` and `exit_code` were added by the conductor; every other field is the adapter's output as recorded.
