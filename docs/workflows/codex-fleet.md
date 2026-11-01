# Codex Fleet

## When To Use It

Use this workflow when several projects need bounded progress and each project can move through a narrow vertical slice. It works best when a conductor can coordinate scope, review, and next-round decisions while separate Codex sessions handle project-local work.

## Inputs

- A project registry such as [`templates/fleet-projects.json`](../../templates/fleet-projects.json).
- A living spec for each project that names intent, stakes, current round, and verification.
- A conductor prompt that defines the round objective and review gates.
- Access to the public runner path [`skills/codex-fleet/start-fleet.sh`](../../skills/codex-fleet/start-fleet.sh).

## Steps

1. The conductor selects the projects for the round and confirms each repo is in an acceptable starting state.
2. The conductor assigns one Codex session per project.
3. The launcher atomically creates and archives a unique run-specific state directory, publishes `current` only after successful initialization, and records run-scoped worker session names. The conductor pins that directory into recon and every helper call; it never relies on a movable `current` pointer during a live run.
4. The launcher sets one mode for the whole run, and every project session uses it in every round. `PLAN` includes an approval step before implementation. `DO` skips that approval step but keeps clarification, spec, board, and review gates. `FULL_AUTO` behaves like DO until REVIEW, then invokes the mode-checked merge helper.
5. After approval in PLAN mode, the project session runs one vertical slice.
6. The project session updates the living spec or handoff with files changed, verification, remaining work, and any live effects.
7. In PLAN/DO, the conductor performs review acknowledgement before treating a slice as done. In FULL_AUTO, a successful helper merge becomes done automatically; every gated slice remains in review until the human resolves or explicitly acknowledges it. Acknowledgement is not proof of merge.

## Outputs

- One scoped project result per Codex session.
- Updated living specs or handoffs for work that remains.
- A conductor summary of slices, blocked slices, verification, and review state.
- Optional commits or gated draft pull requests when allowed by the round configuration.
- An archived run directory containing the exact instruction, state, questions, board, and ledger for that invocation.

## Verification

Each project must verify with the concrete command named in its living spec or conductor prompt. The conductor should also run a repo status check for each project before accepting the round result.

## Safety Gates

- Preserve unrelated dirty files.
- Do not publish private data.
- Verify with a concrete command.
- Record a handoff when work remains.
- Keep one agent per project unless the conductor explicitly assigns a shared branch strategy.
- Never place one project in two live fleets, even though separate run directories allow unrelated fleets to run concurrently.
- Require an explicit per-project push/draft-PR grant; installed remotes and CLIs establish capability, not authority.
- In `PLAN`, do not run the vertical slice until approval is recorded.
- In `DO` and `FULL_AUTO`, keep clarification, spec, board, and review gates even though initial approval is skipped.
- Commits and gated draft pull requests can happen before the human `REVIEW -> DONE` acknowledgement when the round allows them.
- Push and draft pull request creation are controlled by fail-closed [`fleet-open-pr.sh`](../../skills/codex-fleet/fleet-open-pr.sh).
- PLAN/DO never call the merge helper and require human `REVIEW -> DONE` acknowledgement.
- FULL_AUTO is an explicit merge grant. `fleet-merge.sh` must confirm mode, REVIEW phase, current round, selected repository, and recorded PR head/base, then repeat those gates immediately before merge. It fails closed on missing or revoked permission, danger hints, missing PR/tooling, a changed identity/head, red checks, or a timeout. It marks drafts ready before polling so ready-triggered checks are included, writes a `submitting` state before the external call, and marks done only after GitHub reports `MERGED`; unresolved or queued/auto-merge submissions hold the current REVIEW phase for bounded confirmation or a later retry. The helper never requests branch deletion.
