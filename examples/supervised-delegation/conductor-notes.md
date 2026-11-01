# Conductor Notes

What the conductor did between the `failed` result and the decision. Times are local.

## 17:01 Send

Worker started in its own worktree (`--sandbox workspace-write`, `--effort high`). Task sent from
stdin. Turn record saved. A background `watch <turn> --timeout 900` started. The conductor moved
on to writing docs in the main checkout.

## 17:09 Result

Watch exited 11. Envelope: `failed`, "Execution tool unavailable; no edits made and verification
could not run." `git status` in the worktree: clean. Verification stage not started.

## 17:09 Inspect, do not retry

Exit 11 means report and inspect; it does not mean resend.

1. **Runner status.** `status <name>` showed one turn, last result `failed`, pane still alive.
2. **The pane.** The visible screen showed the worker's own account: "The execution tool has
   timed out before starting on three attempts ... I'll try once more". Readable, but not the
   source of truth.
3. **The rollout.** Four tool calls, each answered with the same single line:
   `timed out negotiating with the code-mode host`. No file edits, no shell output.
4. **Transport check.** Stopped the pane worker. Started a fresh worker on the headless
   transport in the same worktree and sent a probe (`pwd`, `ls`). Same failure, so not the pane.
5. **Worktree check.** Ran the bare worker CLI in an empty scratch directory with the same probe.
   Same failure, so not the worktree or the task.
6. **Feature toggle.** Disabled the host feature by flag. The CLI then said the execution tool
   was disabled and named the missing component, so the feature is required and the component is
   absent.
7. **Doctor.** The CLI's diagnostic reported its runtime CDN unreachable (an HTTP 404 on the
   endpoint that serves the component). Everything else was healthy, including model
   connectivity. The fault is upstream of this machine.

Total inspection time: about nine minutes, most of it waiting on probe timeouts.

## 17:18 Decision

- Route the mechanical port to the other engine for this pass. The task spec is unchanged; only
  the worker differs. The cross-model verification stage stays as planned.
- Keep the worker stopped. Do not install anything or restart daemons on the owner's machine to
  work around a vendor-side fault; report it instead.
- Retry the worker later for the live adapter smoke test, and record the outcome either way.
- Record this turn as the example, because a failed turn that cost nothing is the clearest
  demonstration of why the channel exists.
