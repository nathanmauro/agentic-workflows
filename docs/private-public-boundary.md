# Private/Public Boundary

This repo is a public, curated export of workflow patterns from a private local control plane. The private source repo remains private because it contains machine-specific automation and personal operating context.

## Published

- Agent workflow skills and instructions.
- Reusable templates.
- Sanitized examples.
- Conceptual docs explaining the operating model.
- Adapter shapes for memory, notifications, session launchers, and project registries.

## Not Published

- Real account IDs, tokens, OAuth scopes, or credentials.
- Gmail labels, Gmail filters, Todoist project IDs, or personal task structure.
- Launchd plists and local daemon wiring tied to one machine.
- Telegram, phone, or notification routing tied to a real account.
- Raw [Black Box](https://github.com/nathanmauro/black-box), session, or transcript data.
- Family, career, finance, health, or other personal operating context.
- Private project inventories and private repo names unless intentionally public.

## Pattern Over Infrastructure

The public pattern is durable continuity: agents should record decisions, observations, handoffs, and parked tangents in a searchable place. The private implementation can be a local service, a database, markdown, Obsidian, a hosted app, or anything else. This repo uses the phrase "durable memory adapter" for that role.

## Publication Rule

Every file must be readable by a stranger without requiring Nathan's machine, accounts, or private history. If a file needs those things, publish a template or adapter boundary instead of the private implementation.
