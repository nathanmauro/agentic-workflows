# Closeout And Handoff

## When To Use It

Use this workflow at the end of a branch, round, review session, or interrupted work period. It is especially important when changes are not merged, verification is partial, live systems were affected, or another agent may need to resume.

## Inputs

- Current branch, commit, and dirty-state information.
- The diff or list of files changed.
- Verification commands and results.
- Notes on live-system effects, skipped work, and known risks.
- Access to a durable memory adapter or a handoff file fallback.

## Steps

1. Inspect branch and dirty-state information before summarizing.
2. Review the diff and identify only the files relevant to the current work.
3. Run the smallest meaningful verification command, then any broader command required by the project.
4. Record live-system effects, including services touched, processes restarted, data written, or external calls made.
5. State what was not done, including skipped tests, deferred scope, unpushed commits, or known limitations.
6. Write the next useful action as a concrete resume step.
7. If the path forward genuinely forks, record a projection: one to five plausible futures with a short title, a one-line description, a confidence, and the basis that makes them plausible. See [project trajectory](../concepts/project-trajectory.md).
8. Store the closeout in a durable memory adapter when available, or use [`templates/HANDOFF.md`](../../templates/HANDOFF.md) as the fallback.

## Outputs

- A branch closeout summary with files changed and verification.
- A record of live-system effects and what was not done.
- A compact next action for the next session.
- A projection of plausible futures when the path forward forks.
- A durable memory entry or handoff file when work remains.

## Verification

Run the project-specific verification command and a diff hygiene check such as `git diff --check` before final closeout. If a command cannot run, record the reason and the remaining risk.

## Safety Gates

- Preserve unrelated dirty files.
- Do not publish private data.
- Verify with a concrete command.
- Record a handoff when work remains.
- Do not claim live-system safety without checking what the session actually touched.
- Do not include secrets, raw logs, or private account data in the handoff.
