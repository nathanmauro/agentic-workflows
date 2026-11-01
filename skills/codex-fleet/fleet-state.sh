#!/usr/bin/env bash
set -euo pipefail

# Commit the fleet-wide REVIEW -> RECON handoff only after every project mirror
# has independently advanced. The transition is serialized and state.env is
# replaced atomically so readers see either the old or the new global state.

if [ -n "${CODEX_GOALS_DIR:-}" ]; then G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi

usage() {
  echo "usage: fleet-state.sh <expected-current-round> <next-round>" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
expected_round="$1"
next_round="$2"

case "$expected_round:$next_round" in
  *[!0-9:]*|:*|*:) echo "ERR: rounds must be positive integers" >&2; exit 1 ;;
esac
expected_round=$((10#$expected_round))
next_round=$((10#$next_round))
[ "$expected_round" -gt 0 ] && [ "$next_round" -eq $((expected_round + 1)) ] || {
  echo "ERR: next round must be exactly one greater than expected current round" >&2
  exit 1
}

state_file="$G/state.env"
projects_file="$G/projects.json"
lock_dir="$G/fleet-state.lock"
tmp=""
lock_owned=false

cleanup() {
  if [ -n "$tmp" ] && [ -e "$tmp" ]; then
    rm -f "$tmp"
  fi
  if $lock_owned; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

attempt=0
until mkdir "$lock_dir" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 200 ]; then
    echo "ERR: timed out waiting for fleet state lock: $lock_dir" >&2
    exit 1
  fi
  sleep 0.05
done
lock_owned=true

[ -f "$state_file" ] || { echo "ERR: state file not found: $state_file" >&2; exit 1; }
[ -f "$projects_file" ] || { echo "ERR: projects file not found: $projects_file" >&2; exit 1; }

read_state_key() {
  local key="$1"
  awk -v wanted="$key" '
    index($0, "=") {
      key = substr($0, 1, index($0, "=") - 1)
      if (key == wanted) {
        count++
        value = substr($0, index($0, "=") + 1)
      }
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$state_file"
}

if ! mode="$(read_state_key MODE)" ||
   ! current_round="$(read_state_key ROUND)" ||
   ! phase="$(read_state_key PHASE)"; then
  echo "ERR: state.env must contain exactly one MODE, ROUND, and PHASE" >&2
  exit 1
fi

case "$mode" in
  PLAN|DO|FULL_AUTO) ;;
  *) echo "ERR: invalid fleet mode in state.env: $mode" >&2; exit 1 ;;
esac

case "$current_round" in
  ''|*[!0-9]*) echo "ERR: invalid ROUND in state.env: $current_round" >&2; exit 1 ;;
esac

# A repeated call with the same arguments is a success only while the completed
# transition remains intact. Any other new-round state is an inconsistency.
already_transitioned=false
if [ "$current_round" -eq "$next_round" ] && [ "$phase" = RECON ]; then
  already_transitioned=true
elif [ "$current_round" -ne "$expected_round" ] || [ "$phase" != REVIEW ]; then
  echo "ERR: expected ROUND=$expected_round PHASE=REVIEW (or completed ROUND=$next_round PHASE=RECON); got ROUND=$current_round PHASE=$phase" >&2
  exit 1
fi

if ! jq -e '
  type == "array" and length > 0 and
  all(.[]; (.name | type == "string" and length > 0 and (contains("/") | not))) and
  ((map(.name) | unique | length) == length)
' "$projects_file" >/dev/null; then
  echo "ERR: projects.json must be a non-empty array with unique, slash-free names" >&2
  exit 1
fi

while IFS= read -r name; do
  mirror="$G/$name.spec.json"
  if [ ! -f "$mirror" ]; then
    echo "ERR: project mirror not found: $mirror" >&2
    exit 1
  fi
  if ! jq -e --arg name "$name" --argjson round "$next_round" '
    type == "object" and
    .project == $name and
    .current_round == $round and
    .status == "planned" and
    ([.branch_lineage[]? | select(((.merge_state // "") == "submitting" or (.merge_state // "") == "pending") and (.status // "") == "review")] | length == 0)
  ' "$mirror" >/dev/null; then
    echo "ERR: $name mirror must identify the project, be at round $next_round with status planned, and have no unresolved merge submission" >&2
    exit 1
  fi
done < <(jq -r '.[].name' "$projects_file")

if $already_transitioned; then
  echo "fleet state already at ROUND=$next_round PHASE=RECON"
  exit 0
fi

tmp="$(mktemp "$G/state.env.XXXXXX")"
awk -v round="$next_round" '
  index($0, "=") {
    key = substr($0, 1, index($0, "=") - 1)
    if (key == "ROUND") { print "ROUND=" round; next }
    if (key == "PHASE") { print "PHASE=RECON"; next }
  }
  { print }
' "$state_file" > "$tmp"

mv "$tmp" "$state_file"
tmp=""
echo "advanced fleet state: ROUND=$next_round PHASE=RECON"
