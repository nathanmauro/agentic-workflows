# Project Agent Guide

This file tells coding agents how to work in this repository.

## Operating Defaults

- Read this file before changing code.
- Prefer small, verifiable changes.
- Preserve unrelated dirty files.
- Use existing project patterns before adding new abstractions.
- Do not commit, push, merge, or publish unless explicitly asked.
- For changed behavior, update repo-owned docs.

## Method

1. Recall: read local docs and inspect real files before assuming.
2. Frame: state the current slice and what is out of scope.
3. Plan: split substantial work into independently verifiable tasks.
4. Fake first: prefer fixtures and dry-runs before live systems.
5. Gate mutations: require explicit flags or approval for live writes.
6. Verify: run targeted checks and state what passed.
7. Handoff: leave branch, files changed, verification, and next action.

## Continuity

Use a durable memory adapter for decisions, handoffs, and observations when available. If no adapter exists yet, write a compact handoff with templates/HANDOFF.md or a repo note. Do not store secrets, raw logs, or private account data there.
