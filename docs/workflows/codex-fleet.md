# Codex Fleet

## When To Use It

Use this workflow when several projects need bounded progress and each project can move through a narrow vertical slice. It works best when a conductor can coordinate scope, review, and next-round decisions while separate Codex sessions handle project-local work.

## Inputs

- A project registry such as `templates/fleet-projects.json`.
- A living spec for each project that names intent, stakes, current round, and verification.
- A conductor prompt that defines the round objective and review gates.
- Access to the public runner path `skills/codex-fleet/start-fleet.sh`.

## Steps

1. The conductor selects the projects for the round and confirms each repo is in an acceptable starting state.
2. The conductor assigns one Codex session per project.
3. Each project session uses the launch mode that matches the round. `PLAN` includes an approval step before implementation. `DO` skips that approval step, but still keeps clarification, spec, board, and review gates.
4. After approval in PLAN mode, the project session runs one vertical slice.
5. The project session updates the living spec or handoff with files changed, verification, remaining work, and any live effects.
6. The conductor performs review acknowledgement before treating the slice as done, merging, publishing final artifacts, or advancing reviewed work.

## Outputs

- One scoped project result per Codex session.
- Updated living specs or handoffs for work that remains.
- A conductor summary of slices, blocked slices, verification, and review state.
- Optional commits or gated draft pull requests when allowed by the round configuration.

## Verification

Each project must verify with the concrete command named in its living spec or conductor prompt. The conductor should also run a repo status check for each project before accepting the round result.

## Safety Gates

- Preserve unrelated dirty files.
- Do not publish private data.
- Verify with a concrete command.
- Record a handoff when work remains.
- Keep one agent per project unless the conductor explicitly assigns a shared branch strategy.
- In `PLAN`, do not run the vertical slice until approval is recorded.
- In `DO`, keep clarification, spec, board, and review gates even though initial approval is skipped.
- Commits and gated draft pull requests can happen before the human `REVIEW -> DONE` acknowledgement when the round allows them.
- Push and draft pull request creation are controlled by fail-closed `fleet-open-pr.sh`.
- Require human `REVIEW -> DONE` acknowledgement before treating the slice as done, merging, publishing final artifacts, or advancing reviewed work.
