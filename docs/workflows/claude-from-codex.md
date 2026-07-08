# Claude From Codex

## When To Use It

Use this workflow when a Codex-led session needs Claude for bounded review, planning, debugging, or second-opinion work. It is useful for hard design choices, unfamiliar code paths, or cases where independent critique is more valuable than another implementation pass.

## Inputs

- A bounded Claude prompt with the question, repo path, constraints, relevant files, and expected output.
- A tmux or remote-control environment capable of launching and monitoring the Claude session.
- Any project instructions, living spec, handoff, or context pack needed for the review.
- The public path `skills/claude-remote/scripts/start-claude-remote`.

## Steps

1. Codex prepares a concise prompt that asks Claude for review, planning, or a second opinion rather than open-ended ownership.
2. Codex launches or requests a Claude remote/control session using the available tmux or remote-control setup.
3. Claude performs the bounded task and returns findings, a plan, or a recommendation.
4. Codex evaluates the response against local repo evidence and decides what to implement or ignore.
5. Codex records any accepted decision in the living spec, handoff, or durable memory adapter.

## Outputs

- Claude's bounded review, plan, or second-opinion result.
- Codex's decision on what changes, if any, to make.
- Updated project state when the result affects future work.

## Verification

Codex must verify any accepted implementation with a concrete command in the target repo. A remote opinion is useful input, but it is not a substitute for local proof.

## Safety Gates

- Preserve unrelated dirty files.
- Do not publish private data.
- Verify with a concrete command.
- Record a handoff when work remains.
- Treat tmux or remote-control availability as a prerequisite, not an assumption.
- Keep the Claude request bounded to review, planning, debugging, or second-opinion work unless the conductor explicitly expands scope.
