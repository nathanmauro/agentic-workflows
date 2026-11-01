# One Policy, Two Engines

## The Problem

Running two coding agents on one machine means two global instruction files, two skill
directories, two sets of hooks, and two places for a rule to drift. The rules that matter most
(who commits, what needs a gate, where decisions get recorded) are exactly the ones that quietly
diverge, because each client's guide gets edited in the moment, for the agent that was open.

## The Pattern

Write the operating policy once, in a client-neutral file. A client that supports imports (Claude
Code) imports it directly; a client that does not (Codex) gets it rendered into its global guide as
a managed block with a content hash. A check command fails when a rendered block does not match
the source or when the import is missing or duplicated. Skills follow the same rule: one tracked source directory per skill,
symlinked into each client's skill path, with a small per-client metadata file where a client needs
one. Everything else that is client-specific (keybindings, hooks, slash-command wrappers) stays in
that client's own directory and says so.

```text
agents/
├── shared/
│   ├── portable-policy.md        one source of truth
│   └── skills/<name>/            one source per skill, linked into both clients
├── claude/   CLAUDE.md imports the policy; commands/, hooks/, settings
├── codex/    AGENTS.md carries a rendered, hash-marked managed block; prompts/, skills metadata
└── gemini/   same managed block, when a third client is in play
```

```text
<!-- BEGIN PORTABLE POLICY source=agents/shared/portable-policy.md sha256=<hash> -->
...rendered policy...
<!-- END PORTABLE POLICY -->
```

## How To Apply It

Start with the policy sections that cause the most damage when they drift: authorship and git
authority, mutation gates, where decisions and handoffs are recorded, and how delegated work
carries authorization. [`templates/portable-policy.md`](../../templates/portable-policy.md) is a
working example. Keep it short enough to live in every session's context; move conditional
mechanics (how to debug the capture system, how to run a fleet) into skills that load on demand.

Give the render step a `check` mode and run it in the repo's test suite, so an edit to the source
that was not rendered, or a hand edit to a rendered block, fails loudly. Install skills by
symlink from one tracked source, never by copying, so an improvement made while working in one
client is immediately live in the other.

Keep a registry entry for each skill: owner or upstream, pinned provenance, what it can reach
(credentials, external writes, subprocesses), its trigger boundary with positive and negative
examples, validation evidence, last meaningful use, and status. An install is not validation.
[`templates/skill-registry.md`](../../templates/skill-registry.md) has the contract. When a skill
is vendored from someone else's repository, record the upstream commit, the licence, and every
local modification per file, so the next upstream pull is a diff and not an archaeology project.

## Failure Modes

A policy that is pasted rather than rendered is already two policies. A rendered block without a
hash is a paste with better manners. Skills copied into each client fork within a week. A policy
that grows to hold every rule becomes the prompt pile it replaced; conditional mechanics belong in
skills. A registry that records install dates but not uses carries dead prompt surface forever.

## Related

- [`templates/portable-policy.md`](../../templates/portable-policy.md)
- [`templates/skill-registry.md`](../../templates/skill-registry.md)
- [Agentic operating system](agentic-operating-system.md)
- [Kindred systems](../kindred-systems.md), for how vendored upstream skills are tracked
