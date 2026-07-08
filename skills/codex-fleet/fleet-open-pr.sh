#!/usr/bin/env bash
set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_SPEC="$SCRIPT_DIR/fleet-spec.sh"

usage() {
  echo "usage: fleet-open-pr.sh <name> <round> <branch>" >&2
  exit 2
}

append_lineage() {
  local name="$1" round="$2" branch="$3" base="$4" pr="$5" commit="$6" status="$7" note="$8"
  local entry
  entry="$(jq -nc \
    --argjson round "$round" \
    --arg branch "$branch" \
    --arg base "$base" \
    --arg pr "$pr" \
    --arg commit "$commit" \
    --arg status "$status" \
    --arg note "$note" \
    '{round:$round,branch:$branch,base:$base,pr:$pr,commit:$commit,status:$status,note:$note}')"
  bash "$FLEET_SPEC" set "$name" ".status=\"review\" | .branch_lineage += [$entry]"
}

local_only() {
  local name="$1" round="$2" branch="$3" base="$4" reason="$5"
  local cmd note commit
  cmd="gh pr create --draft --base $base --head $branch --title \"fleet r$round: $branch\""
  note="push blocked; run gh manually ($reason): $cmd"
  # Capture the slice commit even on the local-only path so the ledger/board never
  # show an empty commit (this runs from the repo right after Codex's commit).
  commit="$(git rev-parse --short HEAD 2>/dev/null || printf '')"
  append_lineage "$name" "$round" "$branch" "$base" "local-only" "$commit" "review" "$note"
  echo "LOCAL-ONLY: $cmd"
}

[ "$#" -eq 3 ] || usage

name="$1"
round="$2"
branch="$3"

case "$round" in
  ''|*[!0-9]*) echo "ERR: round must be a positive integer (got '$round')" >&2; exit 1 ;;
esac

spec="$G/$name.spec.json"
if [ ! -f "$spec" ]; then
  echo "ERR: spec mirror not found: $spec" >&2
  exit 1
fi

push_allowed="$(jq -r '.push_allowed // false' "$spec")"
danger="$(jq -r '.danger // ""' "$spec")"
default_branch="$(jq -r '.default_branch // "main"' "$spec")"
base="$(jq -r '[.branch_lineage[]? | select(.status!="skipped" and .status!="blocked")] | last | .branch // empty' "$spec")"
[ -n "$base" ] || base="$default_branch"

if [ "$push_allowed" != "true" ]; then
  local_only "$name" "$round" "$branch" "$base" "push_allowed is not true"
  exit 0
fi

if printf '%s\n' "$danger" | grep -Eiq 'PUBLIC|never push|do not push'; then
  local_only "$name" "$round" "$branch" "$base" "danger hint blocks push"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  local_only "$name" "$round" "$branch" "$base" "gh is not on PATH"
  exit 0
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  local_only "$name" "$round" "$branch" "$base" "origin remote is missing"
  exit 0
fi

prefix="fleet/round-$round-"
case "$branch" in
  "$prefix"*) title_tail="${branch#"$prefix"}" ;;
  *) title_tail="$branch" ;;
esac
git push -u origin "$branch"
pr_url="$(gh pr create --draft --base "$base" --head "$branch" \
  --title "fleet r$round: $title_tail" \
  --body "Automated fleet slice (round $round). Stacked on \`$base\`. Review and merge the top branch to integrate. Human owner sole author; no merge performed.")"
commit="$(git rev-parse --short HEAD 2>/dev/null || printf '')"
append_lineage "$name" "$round" "$branch" "$base" "$pr_url" "$commit" "review" ""
echo "DRAFT PR: $pr_url"
