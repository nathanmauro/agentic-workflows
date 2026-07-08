#!/usr/bin/env bash
set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"

usage() {
  echo "usage: fleet-board.sh build|show|text" >&2
  exit 2
}

board_file() {
  printf '%s/board.json\n' "$G"
}

build_board() {
  local round="1" tmp
  mkdir -p "$G"
  if [ -f "$G/state.env" ]; then
    # shellcheck disable=SC1090,SC1091
    . "$G/state.env"
    round="${ROUND:-1}"
  fi

  tmp="$(mktemp "$G/board.json.XXXXXX")"
  shopt -s nullglob
  {
    for spec in "$G"/*.spec.json; do
      jq -c '
        (.branch_lineage[-1]? // {}) as $last |
        {
          name: .project,
          round: .current_round,
          column: (if .status == "blocked" or .status == "skipped" then "blocked" else .status end),
          branch: ($last.branch // ""),
          pr: ($last.pr // ""),
          note: (($last.note // "") as $note | if $note != "" then $note else (.pending_question.question? // "") end)
        }
      ' "$spec"
    done
  } | jq -s --argjson round "$round" '{generated_round:$round, projects:.}' > "$tmp"
  mv "$tmp" "$(board_file)"
}

cell_marker() {
  local round="$1" branch="$2" pr="$3" token marker
  token="$pr"
  if [ -z "$token" ]; then
    token="${branch##*/}"
  fi
  marker="R$round"
  if [ -n "$token" ]; then
    marker="$marker $token"
  fi
  printf '%.12s\n' "$marker"
}

show_board() {
  local name round column branch pr marker planned doing review done_cell blocked
  build_board
  printf '%-16.16s | %-12.12s | %-12.12s | %-12.12s | %-12.12s | %-12.12s\n' \
    PROJECT PLANNED DOING REVIEW DONE BLOCKED
  printf '%-16.16s-+-%-12.12s-+-%-12.12s-+-%-12.12s-+-%-12.12s-+-%-12.12s\n' \
    ---------------- ------------ ------------ ------------ ------------ ------------

  while IFS=$'\t' read -r name round column branch pr; do
    planned=""; doing=""; review=""; done_cell=""; blocked=""
    marker="$(cell_marker "$round" "$branch" "$pr")"
    case "$column" in
      planned) planned="$marker" ;;
      doing) doing="$marker" ;;
      review) review="$marker" ;;
      done) done_cell="$marker" ;;
      blocked) blocked="$marker" ;;
    esac
    printf '%-16.16s | %-12.12s | %-12.12s | %-12.12s | %-12.12s | %-12.12s\n' \
      "$name" "$planned" "$doing" "$review" "$done_cell" "$blocked"
  done < <(jq -r '.projects[] | [.name, .round, .column, .branch, .pr] | @tsv' "$(board_file)")
}

text_board() {
  local name round column branch pr token
  build_board
  while IFS=$'\t' read -r name round column branch pr; do
    token="$pr"
    [ -n "$token" ] || token="${branch##*/}"
    printf '%-12.12s r%-3s %-7.7s %s\n' "$name" "$round" "$(printf '%s' "$column" | tr '[:lower:]' '[:upper:]')" "$token"
  done < <(jq -r '.projects[] | [.name, .round, .column, .branch, .pr] | @tsv' "$(board_file)")
}

main() {
  [ "$#" -eq 1 ] || usage
  case "$1" in
    build) build_board ;;
    show) show_board ;;
    text) text_board ;;
    *) usage ;;
  esac
}

main "$@"
