# Private/Public Boundary

This repo is a public, curated export of workflow patterns from a private local control plane.
The private source repo remains private because it contains machine-specific automation and
personal operating context.

## Published

- Agent workflow skills and instructions.
- Reusable templates.
- Sanitized examples.
- Conceptual docs explaining the operating model.
- Adapter shapes for memory, notifications, session launchers, and project registries.

## Not Published

- Real account IDs, tokens, OAuth scopes, or credentials.
- Personal productivity wiring (mail rules, issue-tracker workspace, team, or issue IDs,
  notification routing) and any personal operating context.
- Launchd plists and local daemon wiring tied to one machine.
- Raw [Black Box](https://github.com/nathanmauro/black-box), session, or transcript data.
- Private project inventories and private repo names unless intentionally public.

## Published Elsewhere

Some companion systems are public repos by the same author and may be named and linked:

- [Black Box](https://github.com/nathanmauro/black-box): the durable memory adapter.
- [Agent Island](https://github.com/nathanmauro/agent-island-public).
- [Agent Observatory](https://github.com/nathanmauro/agent-observatory).

Herdr, Linear, and Obsidian are third-party tools. They are named as tools, never with
workspace, team, issue, vault, or note identifiers.

## Pattern Over Infrastructure

The public pattern is durable continuity: agents should record decisions, observations, handoffs,
and parked tangents in a searchable place. The implementation can be a local service, a database,
markdown, a notes vault, a hosted app, or anything else. This repo uses the phrase "durable memory
adapter" for that role. The owner's own adapter is
[Black Box](https://github.com/nathanmauro/black-box), which is open source.

## How This Repo Stays Current

- A private drift detector compares each private source's last commit with the last commit of its
  public counterpart and reports the pairs that have fallen behind.
- Ports are manual, sanitized rewrites, not copies. Every port is checked by
  [`scripts/audit-public.sh`](../scripts/audit-public.sh), which fails on private paths, a tracked
  list of private implementation names, secrets, and broken syntax or tests. Names that would leak
  by being listed load from an untracked local denylist, so only the owner's local run checks them;
  CI checks the tracked list alone. Both passes scan the working tree, not history.
- Freshness is judged by commit time. When a drifted pair is reviewed and needs no public change,
  the review is still recorded as a commit, so the detector sees it as current.

## Publication Rule

Every file must be readable by a stranger without requiring the human owner's machine, accounts,
or private history. If a file needs those things, publish a template or adapter boundary instead
of the private implementation.
