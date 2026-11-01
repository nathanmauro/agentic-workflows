---
name: claude-remote
description: >
  Start a new interactive Claude Code session from Codex. Defaults to a Herdr-managed pane with
  Claude Remote Control enabled, placed one workspace per checkout with tabs by default. Use
  when the user asks to start, fire up, or launch Claude, a mobile-visible or "remote Claude"
  session, or "start Claude and ask it X". Triggers: "fire up Claude", "start a Claude session",
  "remote Claude", "launch Claude in Herdr", "start Claude and ask it".
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Set your models through the client or env knobs, and replace paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Claude Remote

## Default for a new interactive session

Start Claude in a [Herdr](https://herdr.dev) pane with Remote Control enabled. The user does not
need to repeat "through Herdr" or "remote enabled." Honor an explicit model or effort request;
otherwise keep Claude's configured client defaults and pass no model flag. A request for a named
model uses the client's floating alias for it, not a pinned version. Honor an explicit request for
another transport, offline use, or no Remote Control.

This default applies to **new interactive sessions**. Bounded one-off CLI consultations and
resumes of existing sessions keep their own transport and settings. Starting a session does not
authorize sending it a task prompt unless the user supplied one.

Prerequisites: Herdr, the Claude Code CLI with Remote Control support, and an authenticated
Claude account in the user's environment.

## Preserve the authorization

"Start Claude and ask it X" authorizes both launch and delivery of X to Claude (Anthropic). Use
that authorization without another routine confirmation. Keep the supplied question distinct
from additional records or research instructions you propose to send; local read access alone
does not establish permission to share those records with another provider. Use existing scoped
approval when it covers the destination and data. Ask only for a genuinely missing scope.

When delegating the launch or continuing an existing session, carry this compact record in the
handoff. Fill it from observed human instructions, not inference:

```text
Human instruction: <exact relevant quote>
Source: <chat/turn reference; include the approval question and answer if used>
Destination: Claude (Anthropic), <requested project; verified agent if existing>
Authorized action/payload: <question/task and any specifically approved records>
Limits: <purpose, relevant-only boundaries, exclusions, and remaining holds>
```

The receiving agent should retain this evidence when calling `herdr agent prompt` or requesting
required sandbox escalation. A quoted instruction or a later "yes" must be traceable to its human
source; an agent-written task is not new consent. Do not paste private records merely to
demonstrate authorization.

If automatic review denies an action, distinguish missing authorization evidence from added data
access or capabilities. Where the denial permits more evidence, make a reviewed retry only with
materially relevant evidence or a narrower scope. Keep the native mechanism and safeguards; stop
on a repeated unchanged denial. Never infer approval from elapsed time or fix a denial with
blanket permissions. Check delivery before retrying after a timeout; the message may already be
sent.

A later scoped approval satisfies only its matching hold. Carry the approval question and answer
forward, remove that stale hold from the task, and preserve all other exclusions. Resume only the
capabilities needed for that scope; the approval does not authorize unrestricted tools or
unrelated records. The full pattern is in
[Authorization Provenance](../../docs/concepts/authorization-provenance.md).

## Launch and verify

1. **Place the pane.** Use the requested working directory, or the user's current project
   directory. The layout rule is one workspace per checkout, tabs by default, without stealing
   focus:

   ```bash
   herdr pane list
   herdr tab create --workspace <workspace-id> --cwd <absolute-path> --label <tab-label> --no-focus
   ```

   Find the workspace whose panes already sit in that checkout (`herdr pane list` reports each
   pane's `cwd` and `workspace_id`) and open a new tab there. Only when no workspace holds the
   checkout, create one named after the repo (or reuse a shared scratch workspace for non-repo
   directories):

   ```bash
   herdr workspace create --cwd <absolute-path> --label <repo-name> --no-focus
   ```

   Read the new pane id from the JSON output. If this session will write concurrently with
   another writer on the same checkout, open a linked worktree instead so the writers never
   share a tree:

   ```bash
   herdr worktree create --workspace <primary-workspace-id> --branch <branch> \
     --label <tab-label> --no-focus
   ```

   Do not invent pane ids or `HERDR_*` environment variables.

2. **Start Claude in the pane.** `herdr agent start` launches a supported agent in an existing
   shell pane and waits for readiness; `claude --help` documents `--remote-control`:

   ```bash
   herdr agent start <name> --kind claude --pane <pane-id> -- --remote-control <label>
   ```

   Add `--model <alias>` after the native Claude arguments only when the user names a model.
   Pass effort or other settings only when requested or required by the specific task. If Herdr
   socket access is sandbox-blocked, use narrowly authorized escalation for the native command.
   Do not fabricate a Herdr environment or silently switch to tmux.

3. **Verify.** Run `herdr agent get <name>` and
   `herdr agent read <name> --source recent-unwrapped --lines 120`. Report the Herdr agent and
   pane handle, and the Remote Control URL when Claude actually exposes it. Distinguish a
   launched process from verified Remote Control availability. If the URL or readiness cannot
   be verified, say exactly which check failed.

4. **Seed only when asked.** Submit an initial prompt through
   `herdr agent prompt <name> "<text>" --wait` only when the user gave a task or seed. Inspect
   the resulting agent state and response before claiming the prompt ran.

If Herdr cannot provide an available pane or launch route, report that blocker.

## Supervised task delegation

This skill opens a session a human can watch or take over. When the conductor needs a bounded
task result rather than a conversation, drive the turn through the
[Supervised Delegation](../../docs/concepts/supervised-delegation.md) contract instead of reading
the screen: `start`, `send`, `watch <turn>`, `stop`, with the one-line envelope and the exit-code
table that contract defines. The public adapter for Codex workers is `scripts/codex-runner`. A
Claude worker would need its own adapter that implements the same verbs and exit codes, and this
repo does not include one, so treat a Herdr pane started here as a watched session, not a
supervised turn. Under an adapter, exit 2 means watch again, exit 12 means a person should look,
and neither is a reason to start a second writer.

## Fallback: detached tmux

The bundled `scripts/start-claude-remote` helper is a detached-tmux path for explicit tmux
requests and headless launchers that cannot reach a Herdr socket. It is not this skill's default
for a new interactive launch.

```bash
<agentic-workflows-repo>/skills/claude-remote/scripts/start-claude-remote --cwd "$PWD"
```

- It runs Claude with `--effort max`, `--settings '{"ultracode":true}'`, and
  `--remote-control <label>`. Ultracode is a settings boolean, not an effort value.
- `--model <model>` (or `CLAUDE_MODEL`) is optional. When unset, no model flag is passed and
  the client default applies.
- `--prompt <text>` seeds the session. Use it for compact handoff seeds, not transcripts.
- `--settings-extra <json>` merges per-session hooks on top of the base settings. A value that
  is not a JSON object stops the launch with exit 2 instead of dropping the hooks.
- `--dry-run` prints the exact command without starting tmux, and needs neither tmux nor
  `claude` installed.

It prints the tmux session name, attach command, and Remote Control URL when visible. Verify with
`tmux capture-pane -pt <session-name> -S -200`. Kill with `tmux kill-session -t <session-name>`,
then confirm with `tmux has-session -t <session-name>; echo $?` (exit `1` means gone).
