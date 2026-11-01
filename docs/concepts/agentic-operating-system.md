# Agentic Operating System

## The Problem

Coding agents fail when context, gates, memory, and verification are assembled ad hoc for each
run. A strong model can still make poor changes if it cannot see the project intent, does not know
which mutations are allowed, has no reliable place to leave state, or finishes without concrete
proof.

## The Pattern

Treat the harness as the product. The useful system is not only the model prompt; it is the
complete operating layer around the model: project instructions, scoped tools, specs, review gates,
memory, and verification habits that make each run resumable and inspectable.

## How To Apply It

Start with project instructions that define local rules, mutation boundaries, verification
commands, and handoff expectations. Keep a living spec for active work so a cold agent can recover
the project intent, current round, acceptance bar, decisions, and deferred work. Require handoffs
at meaningful stopping points, especially when a branch is left dirty or live systems were
touched. When more than one client runs against the same projects, the cross-project rules live
in one shared policy rendered into each client; see
[one policy, two engines](one-policy-two-engines.md).

Separate authority from execution. Delegating a task never expands its mutation or publication
authority, and the authorization travels with the work as a quoted record (see
[authorization provenance](authorization-provenance.md)). Proactively fan out bounded read-only
research, review, and output triage when it improves latency or context quality. Give mutating
workers separate writable checkouts with disjoint ownership; if isolation is unavailable,
serialize the writes.

Gate by reversibility. Verified local commits and pushes to an existing upstream are routine.
Publication, merges, history rewrites, deployments, external messages, and access changes need
explicit human direction, which a named workflow can carry within its stated bounds. Use a durable
memory adapter to record decisions, observations, and handoffs without storing secrets or raw
private logs.

Ask the system that owns the state. Every fact an agent reports has an owner: the memory store
owns history, the runner owns live execution status, the reviewers own whether finished work is
acceptable, and the issue tracker owns priority. Reading a proxy instead (a quiet log, a recent
memory write, an agent's own summary) produces confident reports that are wrong in exactly the
cases that matter. When a question comes up, name the owner first, then query it directly; do not
make the human relay state between systems.

Verify from small to real: run targeted checks first, then exercise the actual CLI, UI, or
application path. Unit tests and screenshot smokes are supporting evidence, not proof that an
interactive workflow works end to end.

## Failure Modes

A prompt pile is not an operating system; long instruction dumps without state, tools, and gates
become hard to audit and easy to ignore. Shared-tree writers create ambiguous ownership and lost
work. Runs that end without use-level verification leave confidence instead of evidence. Runs that
end without state force the next agent to rediscover the same context. Hidden live mutations are
especially dangerous because they change the world without a reviewable record.

## Related Templates

- [`templates/AGENTS.md`](../../templates/AGENTS.md)
- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
- [`templates/project-spec.md`](../../templates/project-spec.md)
- [`templates/local-adapters.example.json`](../../templates/local-adapters.example.json)
- [`templates/portable-policy.md`](../../templates/portable-policy.md)
- [`templates/skill-registry.md`](../../templates/skill-registry.md)
- [One policy, two engines](one-policy-two-engines.md)
- [Supervised delegation](supervised-delegation.md)
- [Authorization provenance](authorization-provenance.md)
