# Project Agent Guide

This file tells coding agents (Claude Code, Codex, or any other client) how to work in this
repository. Rules that apply across every repository belong in a shared operating policy instead;
see [`portable-policy.md`](portable-policy.md).

## Operating Defaults

- Read this file before changing code.
- Prefer small, verifiable changes.
- Preserve unrelated dirty files.
- Use existing project patterns before adding new abstractions.
- For changed behavior, update repo-owned docs.
- Claims about what a screen, terminal, browser, or IDE shows need an observation (a screenshot
  or an equivalent probe) before "done". This is the class of claim most often reported as fixed
  when it is not.
- Ask the system that owns the state: memory for history, the runner for live status, the
  reviewers once implementation is finished. Quiet logs or recent memory activity are not a
  completion or health signal.
- Raise a materially better option early, with its tradeoff. Do not reopen settled choices
  without new evidence, and do not turn a suggestion into a permission gate.

## Mutation Tiers

- Free: read, inspect, dry-run, and edit locally in your own checkout.
- Proactive: commit a complete, verified unit (stage exact paths, keep unrelated dirty work) and
  push to the branch's existing upstream after inspecting the outgoing range.
- Explicit direction only: creating or changing remotes or upstreams, publishing a branch, PRs,
  merges, force-push, history rewrites, external messages, purchases, and access changes.
- A named workflow can carry that direction. Selecting `FULL_AUTO` for a fleet run is the
  explicit direction to merge green, push-allowed, non-danger PRs through its fail-closed gate,
  and nothing broader. See [Codex fleet](../docs/workflows/codex-fleet.md).
- Concurrent writers never share a checkout; use separate worktrees or serialize. A delegated
  worker inherits the authorization it was handed and no more; see
  [authorization provenance](../docs/concepts/authorization-provenance.md).

## Method

1. Recall: read local docs and inspect real files before assuming.
2. Frame: state the current slice and what is out of scope.
3. Plan: split substantial work into independently verifiable tasks.
4. Fake first: prefer fixtures and dry-runs before live systems.
5. Gate mutations: require explicit flags or approval for live writes.
6. Verify: run targeted checks, then exercise the real CLI, UI, or app path, and state what
   passed.
7. Handoff: leave branch, files changed, verification, and next action.

## Continuity

Use a durable memory adapter for decisions, handoffs, and observations when available. If no
adapter exists yet, write a compact handoff with [`HANDOFF.md`](HANDOFF.md) or a repo note. Do not
store secrets, raw logs, or private account data there.
