# Fleet Round Example

This example shows one round of a fleet workflow across two fictional projects.

## Projects

- `example-api` - production tier, verify with `pytest`.
- `example-ui` - prototype tier, verify with `npm test`.

## Round

The conductor proposes one vertical slice per project, the human owner approves, each agent works on a separate branch, and completed branches move to review.

## Files

- [`project.spec.md`](project.spec.md) - living spec snapshot for one project.
- [`board.txt`](board.txt) - terminal board after the round.
