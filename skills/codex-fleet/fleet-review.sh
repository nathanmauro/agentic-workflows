#!/usr/bin/env bash
set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_SPEC="$SCRIPT_DIR/fleet-spec.sh"
FLEET_BOARD="$SCRIPT_DIR/fleet-board.sh"

usage() {
  echo "usage: fleet-review.sh <name> <round>" >&2
  exit 2
}

patch_results() {
  local name="$1" round="$2" branch="$3" commit="$4" note="$5"
  local results="$G/results.tsv" tmp

  mkdir -p "$G"
  if [ ! -f "$results" ]; then
    printf 'round\tproject\tbranch\tcommit\tnote\tstatus\n' > "$results"
  fi

  tmp="$(mktemp "$G/results.tsv.XXXXXX")"
  awk -F '\t' -v OFS='\t' \
    -v target_round="$round" \
    -v target_project="$name" \
    -v branch="$branch" \
    -v commit="$commit" \
    -v note="$note" '
    NR == 1 {
      print "round", "project", "branch", "commit", "note", "status"
      next
    }
    $1 == target_round && $2 == target_project {
      $3 = ($3 == "" ? branch : $3)
      $4 = ($4 == "" ? commit : $4)
      $5 = ($5 == "" ? note : $5)
      $6 = "done"
      found = 1
    }
    { print }
    END {
      if (!found) {
        print target_round, target_project, branch, commit, note, "done"
      }
    }
  ' "$results" > "$tmp"
  mv "$tmp" "$results"
}

[ "$#" -eq 2 ] || usage

name="$1"
round="$2"

case "$round" in
  ''|*[!0-9]*) echo "ERR: round must be a positive integer (got '$round')" >&2; exit 1 ;;
esac

spec="$G/$name.spec.json"
if [ ! -f "$spec" ]; then
  echo "ERR: spec mirror not found: $spec" >&2
  exit 1
fi

status="$(jq -r '.status' "$spec")"
if [ "$status" != "review" ]; then
  echo "ERR: $name is not in review (status=$status)" >&2
  exit 1
fi

current_round="$(jq -r '.current_round' "$spec")"
if [ "$current_round" != "$round" ]; then
  echo "ERR: $name current_round=$current_round does not match requested round $round" >&2
  exit 1
fi

lineage_count="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | length' "$spec")"
if [ "$lineage_count" -eq 0 ]; then
  echo "ERR: $name has no branch_lineage entry for round $round" >&2
  exit 1
fi

branch="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .branch // ""' "$spec")"
commit="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .commit // ""' "$spec")"
note="$(jq -r --argjson round "$round" '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last | .note // ""' "$spec")"

bash "$FLEET_SPEC" set "$name" ".status=\"done\" | .branch_lineage = (.branch_lineage | map(if (.round | tonumber) == $round then .status=\"done\" else . end))"
patch_results "$name" "$round" "$branch" "$commit" "$note"
bash "$FLEET_BOARD" build
echo "ACKED: $name round $round -> done"
