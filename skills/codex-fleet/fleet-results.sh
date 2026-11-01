#!/usr/bin/env bash
set -euo pipefail

# Run-dir resolution: explicit env > newest run (current symlink) > legacy flat dir.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi

usage() {
  echo "usage: fleet-results.sh upsert <round> <project> <branch> <commit> <note> <status>" >&2
  exit 2
}

sanitize_field() {
  # TSV is a one-record-per-line interchange surface. Preserve content while
  # preventing a note or command output from creating extra rows or columns.
  printf '%s' "$1" | tr '\t\r\n' '   '
}

upsert_result() (
  [ "$#" -eq 6 ] || usage
  local round="$1" project="$2" branch="$3" commit="$4" note="$5" status="$6"
  local results lock_dir tmp attempt lock_owned=false

  case "$round" in
    ''|*[!0-9]*) echo "ERR: round must be a positive integer (got '$round')" >&2; exit 1 ;;
  esac
  [ "$round" -gt 0 ] || { echo "ERR: round must be positive" >&2; exit 1; }
  [ -n "$project" ] || { echo "ERR: project must be non-empty" >&2; exit 1; }

  project="$(sanitize_field "$project")"
  branch="$(sanitize_field "$branch")"
  commit="$(sanitize_field "$commit")"
  note="$(sanitize_field "$note")"
  status="$(sanitize_field "$status")"

  mkdir -p "$G"
  results="$G/results.tsv"
  lock_dir="$G/results.tsv.lock"
  attempt=0
  until mkdir "$lock_dir" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 200 ]; then
      echo "ERR: timed out waiting for results lock: $lock_dir" >&2
      exit 1
    fi
    sleep 0.05
  done
  lock_owned=true
  trap 'exit 130' HUP INT TERM
  trap 'if $lock_owned; then rmdir "$lock_dir" 2>/dev/null || true; fi' EXIT

  if [ ! -f "$results" ]; then
    printf 'round\tproject\tbranch\tcommit\tnote\tstatus\n' > "$results"
  fi

  export FLEET_ROW_ROUND="$round"
  export FLEET_ROW_PROJECT="$project"
  export FLEET_ROW_BRANCH="$branch"
  export FLEET_ROW_COMMIT="$commit"
  export FLEET_ROW_NOTE="$note"
  export FLEET_ROW_STATUS="$status"

  tmp="$(mktemp "$G/results.tsv.XXXXXX")"
  awk -F '\t' -v OFS='\t' '
    BEGIN {
      target_round = ENVIRON["FLEET_ROW_ROUND"]
      target_project = ENVIRON["FLEET_ROW_PROJECT"]
      branch = ENVIRON["FLEET_ROW_BRANCH"]
      commit = ENVIRON["FLEET_ROW_COMMIT"]
      note = ENVIRON["FLEET_ROW_NOTE"]
      status = ENVIRON["FLEET_ROW_STATUS"]
    }
    NR == 1 {
      print "round", "project", "branch", "commit", "note", "status"
      next
    }
    $1 == target_round && $2 == target_project {
      if (!found) {
        print target_round, target_project, branch, commit, note, status
        found = 1
      }
      next
    }
    { print }
    END {
      if (!found) print target_round, target_project, branch, commit, note, status
    }
  ' "$results" > "$tmp"
  mv "$tmp" "$results"
)

[ "$#" -ge 1 ] || usage
command="$1"
shift
case "$command" in
  upsert) upsert_result "$@" ;;
  *) usage ;;
esac
