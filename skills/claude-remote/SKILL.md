---
name: claude-remote
description: Use when Nathan asks to fire up, start, or launch a Claude Code remote-control session from Codex, especially Opus 4.8 or Fable, max effort, ultracode, mobile-visible, detached tmux, seeded prompts, or "remote Claude" requests.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Replace model names, paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Claude Remote

## Overview

Launch a mobile-visible Claude Code session from Codex without rebuilding the tmux
command by hand. The helper defaults to Claude Opus 4.8, max effort, ultracode
settings, and Remote Control enabled in a detached tmux session. It can also
start a named model such as Fable and pass an initial prompt into the new
session.

## Quick Start

From the repo or directory the user wants Claude to work in:

```bash
/Users/nathan/Developer/proj/cockpit/agents/codex/skills/claude-remote/scripts/start-claude-remote \
  --cwd "$PWD"
```

Then report the tmux attach command and Remote Control URL from the script
output. Add `--model claude-fable-5` when the user asks for Fable, or `--prompt
"..."` when the remote session should start with handoff context.

## Workflow

1. Use the user's current project directory unless they name another cwd.
2. Run the bundled script. It starts a detached tmux session and prints:
   - tmux session name
   - attach command
   - Claude Remote Control URL, when the terminal exposes it
   - model label when Claude prints it
3. Verify the pane if needed:

```bash
tmux capture-pane -pt <session-name> -S -200
```

The pane should show max effort plus Remote Control active; the model line should
match the requested model.

## Details

- Ultracode is a settings boolean: `--settings '{"ultracode":true}'`.
- Do not use `--effort ultracode`; the effort remains `--effort max`.
- The model defaults to `claude-opus-4-8`; pass `--model <model-id>` for Fable
  or another explicit Claude model.
- `--prompt <text>` appends the initial prompt to the Claude command. Use it for
  compact handoff seeds, not large transcripts.
- Remote Control is explicit: `--remote-control <label>`.
- If no label is supplied, the helper derives one from the cwd and model slug.
- Detached tmux keeps the mobile-visible session alive after Codex finishes.

## Killing A Session

When the user asks to kill the launched session:

```bash
tmux kill-session -t <session-name>
```

Confirm it is gone:

```bash
tmux has-session -t <session-name>; echo $?
```

Exit code `1` means tmux cannot find the session.
