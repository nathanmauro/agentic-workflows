# Agentic Operating System

## The Problem

Coding agents fail when context, gates, memory, and verification are assembled ad hoc for each run. A strong model can still make poor changes if it cannot see the project intent, does not know which mutations are allowed, has no reliable place to leave state, or finishes without concrete proof.

## The Pattern

Treat the harness as the product. The useful system is not only the model prompt; it is the complete operating layer around the model: project instructions, scoped tools, specs, review gates, memory, and verification habits that make each run resumable and inspectable.

## How To Apply It

Start with project instructions that define local rules, mutation boundaries, verification commands, and handoff expectations. Keep a living spec for active work so a cold agent can recover the project intent, current round, acceptance bar, decisions, and deferred work. Require handoffs at meaningful stopping points, especially when a branch is left dirty or live systems were touched.

Add review gates before commit, push, deployment, or other irreversible actions. Use a durable memory adapter to record decisions, observations, and handoffs in a searchable place without storing secrets or raw private logs.

## Failure Modes

A prompt pile is not an operating system; long instruction dumps without state, tools, and gates become hard to audit and easy to ignore. Runs that end without verification leave only confidence instead of evidence. Runs that end without state force the next agent to rediscover the same context. Hidden live mutations are especially dangerous because they change the world without a reviewable record.

## Related Templates

- [`templates/AGENTS.md`](../../templates/AGENTS.md)
- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
- [`templates/project-spec.md`](../../templates/project-spec.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
