#!/usr/bin/env bash
set -euo pipefail

# Run-dir resolution: explicit env > newest run (current symlink) > legacy flat dir.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_SPEC="$SCRIPT_DIR/fleet-spec.sh"
FLEET_BOARD="$SCRIPT_DIR/fleet-board.sh"
FLEET_RESULTS="$SCRIPT_DIR/fleet-results.sh"

usage() {
  echo "usage: fleet-review.sh <name> <round>" >&2
  exit 2
}

# Make the target unmistakable: an unpinned invocation resolves the `current`
# symlink, which may not be the run being reviewed.
echo "fleet-review: run dir = $G"

[ "$#" -eq 2 ] || usage

name="$1"
round="$2"

case "$round" in
  ''|*[!0-9]*) echo "ERR: round must be a positive integer (got '$round')" >&2; exit 1 ;;
esac
[ "$round" -gt 0 ] || { echo "ERR: round must be a positive integer (got '$round')" >&2; exit 1; }

spec="$G/$name.spec.json"
if [ ! -f "$spec" ]; then
  echo "ERR: spec mirror not found: $spec" >&2
  exit 1
fi

current_round="$(jq -r '.current_round' "$spec")"
status="$(jq -r '.status' "$spec")"
if [ "$current_round" -lt "$round" ]; then
  echo "ERR: $name current_round=$current_round is before requested round $round" >&2
  exit 1
fi

lineage_count="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | length' "$spec")"
if [ "$lineage_count" -eq 0 ]; then
  echo "ERR: $name has no branch_lineage entry for round $round" >&2
  exit 1
fi

lineage_status="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .status // ""' "$spec")"
if [ "$lineage_status" != "review" ]; then
  echo "ERR: $name round $round is not in review (status=$lineage_status)" >&2
  exit 1
fi
if [ "$current_round" = "$round" ] && [ "$status" != "review" ]; then
  echo "ERR: $name current round is not in review (status=$status)" >&2
  exit 1
fi

branch="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .branch // ""' "$spec")"
commit="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .commit // ""' "$spec")"
note="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .note // ""' "$spec")"

bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$note" "done"
bash "$FLEET_SPEC" set "$name" \
  ".branch_lineage = (.branch_lineage | map(if (.round | tonumber) == $round then .status=\"done\" else . end)) |
   if .current_round == $round and .status == \"review\" then .status=\"done\" else . end"
bash "$FLEET_BOARD" build
echo "ACKED: $name round $round -> done"
