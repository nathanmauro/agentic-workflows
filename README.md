# Agentic Workflows

A practical operating system for working with multiple coding agents: fleet execution, cross-agent handoffs, living specs, council review, and durable memory.

This is Nathan Mauro's public field manual and working kit for agentic software development. It is not a vendor SDK and it is not a prompt dump. It is a set of patterns, skills, templates, and examples for coordinating coding agents as a real engineering system.

## What This Is

- A workflow kit for running multiple coding agents without losing context.
- A set of skills and templates you can copy into Claude Code, Codex, or another agent harness.
- A field manual for living specs, handoffs, review gates, and durable memory.
- A public version of patterns developed in a private local control-plane repo.

## Core Ideas

- Agent quality is mostly harness quality: context, tools, gates, and feedback loops.
- The real craft is direction, verification, and continuity.
- A coding agent should leave a branch, a spec update, a verification record, and a handoff.
- Multi-agent work needs explicit roles: conductor, implementer, reviewer, memory, and human owner.
- Durable memory should capture decisions and handoffs, not raw private logs.

## Start Here

1. Read `docs/concepts/agentic-operating-system.md`.
2. Copy `templates/AGENTS.md` into a project and adapt it.
3. Try one small handoff using `templates/HANDOFF.md`.
4. Study `examples/fleet-round/` before running a fleet-style workflow.

## What's Included

- `skills/`: portable skill drafts and workflow instructions.
- `templates/`: project instructions, handoffs, living specs, and local adapter examples.
- `examples/`: sanitized examples of a fleet round, handoff, and council review.
- `docs/`: concepts and workflow explanations.

## What Is Not Included

This repo intentionally omits private machine wiring: real account IDs, local launch agents, Gmail or Todoist structures, raw session transcripts, personal project inventories, and private memory stores. See `docs/private-public-boundary.md`.

## Status

This is an early public release. Expect opinionated patterns, not a turnkey product. Copy what helps, adapt it to your harness, and keep your own private control plane private.

## License

MIT.
