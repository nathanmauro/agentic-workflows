# Codex From Claude

## When To Use It

Use this workflow when a Claude-led conductor needs Codex to implement, review, debug, or verify a bounded piece of work. Claude keeps the wider plan and git ownership, while Codex works inside a clearly scoped prompt.

## Inputs

- A bounded Codex prompt with repository path, branch expectations, allowed files, task scope, verification command, and closeout format.
- Relevant project instructions, living spec, or handoff context.
- The conductor's rule for whether Codex may commit, or whether it must leave changes for review.

## Steps

1. Claude frames the implementation or review task and states what is out of scope.
2. Claude delegates to Codex through a bounded prompt that includes mutation limits and verification expectations.
3. Codex inspects the real repo state before editing and preserves unrelated dirty files.
4. Codex makes the scoped change, runs explicit verification, and reports files changed and command results.
5. Claude reviews the result, keeps ownership of final git decisions, and commits only after verification is explicit.

## Outputs

- A scoped Codex result with changed files, verification, and residual risk.
- A conductor decision to accept, revise, commit, or defer.
- A handoff when work remains or the branch is left in a non-final state.

## Verification

Codex must run the command named in the delegation prompt or explain why it could not run. Claude should inspect the resulting diff and run any final verification required before commit.

## Safety Gates

- Preserve unrelated dirty files.
- Do not publish private data.
- Verify with a concrete command.
- Record a handoff when work remains.
- Keep git ownership in the conductor unless the prompt explicitly grants Codex commit permission.
- Do not treat a summary as proof; require command output or another concrete verification artifact.
