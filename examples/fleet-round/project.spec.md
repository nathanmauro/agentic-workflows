---
project: example-api
tier: production
status: review
current_round: 1
verify_cmd: "pytest"
push_allowed: false
danger: "Example repo; do not push."
branch_lineage:
  - round: 1
    branch: fleet/round-1-health-check
    pr: null
    commit: abc1234
    status: review
---

# example-api - Living Spec

## Intent

Provide a small API that exposes reliable health and status endpoints.

## Stakes

Production tier because downstream services depend on the health endpoint.

## Acceptance Bar

- `pytest` passes.
- Health response includes service name, version, and dependency status.

## Decided

- 2026-07-08: Health status should fail closed when dependencies are unknown.

## Deferred

- Authenticated admin status is out of scope for round 1.

## Rounds

### Round 1 - Health Check

why: The service needs a reliable readiness signal before more features land.
acceptance: `/health` returns structured status and tests cover degraded dependencies.
outcome: branch `fleet/round-1-health-check`, commit `abc1234`, tests passed, awaiting review.
