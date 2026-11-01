# Council Transcript

## Opinions

Advisor A: Include the protocol now and defer the runner. A broken runner is worse than a clear adapter boundary.

Advisor B: Include a minimal runner only if it can be tested without private credentials.

Advisor C: Make the v0 honest: publish the workflow and artifact contract, then add a runner in v1.

## Cross-Review

The advisors agreed that pretending the private runner is portable would damage trust. The main disagreement was whether a minimal runner belongs in v0.

## Moderator Read

The best v0 choice is protocol plus adapter boundary. It preserves the idea and avoids publishing brittle private infrastructure.

## Decision

Document the council workflow in v0 and defer a portable runner until v1.
