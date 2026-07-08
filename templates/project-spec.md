---
project: example-project
tier: production
status: planned
current_round: 1
verify_cmd: "npm test"
push_allowed: false
danger: "No remote push until reviewed."
branch_lineage: []
---

# example-project - Living Spec

## Intent

Describe what this project is trying to become.

## Stakes

Explain what can break, who uses it, and how strict verification should be.

## Acceptance Bar

- Verification command: `npm test`
- User-visible behavior must be documented.
- No live writes without an explicit gate.

## Decided

- YYYY-MM-DD: Record decisions here.

## Deferred

- Record useful ideas that are intentionally out of scope.

## Rounds

### Round 1 - Example Slice

why: Why this slice is next.
acceptance: What proves it worked.
outcome: Branch, commit, PR, tests, and review state.
