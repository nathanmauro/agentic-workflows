# Changelog

All notable changes to this repo are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Entries are dated by commit date.
Entries before 2026-10-31 were backfilled from the git history. On 2026-11-01 the history was
squashed into a single sanitized root commit, so this file is now the change record.

## 2026-11-10

November stack refresh: stateless specialist routing, `herdr-core` session placement, read-only
`explore` mode, queue backpressure, and zero-model handoff summary reuse.

### Added

- Stateless specialist oracle stage and engine path in
  [`docs/concepts/execution-path-triage.md`](docs/concepts/execution-path-triage.md),
  [`docs/workflows/codex-led-session.md`](docs/workflows/codex-led-session.md), and
  [`docs/diagrams.md`](docs/diagrams.md): strip tool/MCP schemas and session boilerplate when
  querying a 2x-cost deep-reasoning specialist for physics/math derivations, mechanism design, or
  adversarial red-teaming.
- `explore` work mode, an anti-rabbit-hole gate for mid-task tangents, queue backpressure caps for
  unattended background pipelines, and out-of-band learning capture in
  [`templates/portable-policy.md`](templates/portable-policy.md) and
  [`docs/concepts/execution-path-triage.md`](docs/concepts/execution-path-triage.md).
- Multi-ring downstream drift verification and MCP/skill startup pruning guidance in
  [`docs/concepts/one-policy-two-engines.md`](docs/concepts/one-policy-two-engines.md).
- Read-to-write handoff discipline and zero-model summary reuse (reusing a standing closeout
  handoff directly as the session summary in Black Box) in
  [`docs/concepts/handoffs-and-continuity.md`](docs/concepts/handoffs-and-continuity.md).

### Changed

- [`README.md`](README.md) stack block updated for November 2026: interactive session drivers at
  `medium` effort by default, dedicated fast/standard tiers for delegated and fleet builds, the
  2x-cost specialist isolated behind a stateless zero-tool oracle CLI rather than used as a
  multi-turn bash driver, and Gemini included under the shared rendered policy.
- [`skills/claude-remote/SKILL.md`](skills/claude-remote/SKILL.md) and
  [`docs/workflows/claude-from-codex.md`](docs/workflows/claude-from-codex.md) migrated from the
  retired single-binary `herdr` subcommands to `herdr-app` (`tab.new` / `space.new`) plus `hc`
  (`herdr-core` `get` / `read` / `send` / `run --bg`).
- [`skills/claude-remote/scripts/start-claude-remote`](skills/claude-remote/scripts/start-claude-remote)
  accepts `--effort` / `CLAUDE_EFFORT` (defaulting to `medium` instead of hardcoded `max`).

## 2026-11-01

A full audit of the October refresh, every finding adversarially verified before it was fixed.

### Changed

- Hero plate retitled to the two-engine thesis ("Claude Code + Codex / one team, one policy"),
  with a Claude ⇄ Codex strand on the delegate-to-verify step and every label collision cleared.
  The README alt text now describes the plate.
- Diagram gallery aligned with the contracts it draws: the supervised sequence only verifies and
  commits on exit 0, the operating-system diagram shows both engines and the shared policy, the
  fleet diagram shows the three modes and the fail-closed merge, and the authorization record
  shows all five fields.
- The codex-fleet launcher passes its sandbox explicitly (`workspace-write` plus the repo's git
  dir, the run dir, and network) instead of inheriting it from the user's Codex config.
- The public audit fails closed: a crashing placeholder check, a missing required local
  denylist, and invalid SVG assets now fail it. Private names moved out of the tracked script
  into the gitignored local denylist; CI checks generic shapes (home paths, personal email,
  token prefixes, private link shapes).
- The hybrid and lean workflow templates and the council skill carry the authorization record.

### Fixed

- codex-runner: `watch` no longer reports a turn that finished during the scan as gone; `stop`
  takes the record lock for the whole stop; read-only polls no longer block `send`; `start`
  claims agent names atomically.
- codex-fleet: `FULL_AUTO` refuses to merge a slice stacked on a non-default branch; a refused
  `gh pr merge` no longer holds the fleet in REVIEW; symlinked installs resolve to the right
  directory; the health probe reports real outcomes and stops the whole verify command on
  timeout; zero-round fleets are refused; local-only slices stack and hand off correctly.
- claude-remote: a failed `--settings-extra` merge stops the launch instead of dropping hooks;
  `--dry-run` works without tmux or claude installed; the prompt follows `--`.
- council: the run command no longer depends on an unset `$PACK`.
- Docs: a broken sentence in codex-from-claude, commit/push rules in codex-led-session matching
  the portable policy, kindred-systems no longer claiming vendored skills live here, a recall
  verb in the adapter template, and the durable-handoff example matching its template.

## 2026-10-31

The repo was last refreshed on 2026-08-19. This pass brings it back in line with the system as
it runs in October 2026, with Codex as a first-class engine beside Claude Code.

### Added

- README rewritten in the owner's voice as a dated portfolio: a "Current stack (as of October
  2026)" block, "What it demonstrates" with links to evidence, and "See one run".
- Supervised delegation contract
  ([`docs/concepts/supervised-delegation.md`](docs/concepts/supervised-delegation.md)) and the
  public reference adapter [`scripts/codex-runner`](scripts/codex-runner) with an offline test
  ([`scripts/tests/test-codex-runner.sh`](scripts/tests/test-codex-runner.sh)).
- A recorded supervised turn, including its failure, in
  [`examples/supervised-delegation/`](examples/supervised-delegation/).
- One policy, two engines
  ([`docs/concepts/one-policy-two-engines.md`](docs/concepts/one-policy-two-engines.md)) with the
  portable policy template ([`templates/portable-policy.md`](templates/portable-policy.md)).
- Authorization provenance
  ([`docs/concepts/authorization-provenance.md`](docs/concepts/authorization-provenance.md)) and an
  "Authorization Carried" section in [`templates/HANDOFF.md`](templates/HANDOFF.md).
- Execution-path triage
  ([`docs/concepts/execution-path-triage.md`](docs/concepts/execution-path-triage.md)): stage,
  then engine, before anything heavy runs.
- Skill registry template ([`templates/skill-registry.md`](templates/skill-registry.md)).
- Codex-led session workflow
  ([`docs/workflows/codex-led-session.md`](docs/workflows/codex-led-session.md)).
- Codex fleet: fail-closed merge of green PRs (`FULL_AUTO`), run-scoped state directories for
  concurrent fleets, a stale-lineage guard, and the extra helper tests. Written on 2026-07-22 and
  landed here.
- CI: [`.github/workflows/audit.yml`](.github/workflows/audit.yml) runs
  [`scripts/audit-public.sh`](scripts/audit-public.sh) on every push and pull request.
- Boundary doc sections "Published Elsewhere" and "How This Repo Stays Current".

### Changed

- Herdr is the default host for interactive sessions; tmux is the fallback. `claude-remote`
  carries the authorization record.
- The hybrid and lean skills run every Codex turn over the supervised channel instead of a raw
  sandbox-bypassing `codex exec` call.
- Model names removed from skills, docs, and templates. They appear only in the README's dated
  stack block. Scripts take env knobs with no default model.
- Black Box is named and linked as the durable memory adapter and is no longer on the audit's
  private-name denylist; the tracked denylist gained identifier shapes, and machine-local private names load from an
  untracked file.
- The audit's placeholder check skips fenced and inline code
  ([`scripts/prose-placeholders.py`](scripts/prose-placeholders.py)).
- Kindred systems records the eleven vendored and adapted skills with a per-skill ledger.

## 2026-08-19

### Added

- Kindred systems map ([`docs/kindred-systems.md`](docs/kindred-systems.md)), starting with
  Skills For Real Engineers.

### Changed

- Hero image redrawn as a field-manual plate.

## 2026-08-17

### Added

- Project trajectory and possible futures pattern
  ([`docs/concepts/project-trajectory.md`](docs/concepts/project-trajectory.md)).

## 2026-07-09

### Changed

- README polished as the repo's front door, with links to every referenced repo path.

## 2026-07-08

### Added

- Initial public export: sanitized workflow skills, reusable templates, core concept docs, and
  sanitized examples.
- Workflow diagram gallery ([`docs/diagrams.md`](docs/diagrams.md)).
- Public release audit ([`scripts/audit-public.sh`](scripts/audit-public.sh)).
