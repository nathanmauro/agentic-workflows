#!/usr/bin/env bash
# init-fleet.sh <total-rounds> [PLAN|DO|FULL_AUTO] [--reset] — seed the codex-fleet
# state machine. Writes the ROUND=1 state, mode, and persisted round count into the
# run directory.
# Run once before starting a codex-fleet /loop. A non-empty results.tsv is kept
# unless --reset is passed. State lives in $CODEX_GOALS_DIR (usually a
# run-scoped dir created by start-fleet.sh; otherwise current, then legacy flat).
#
#   bash init-fleet.sh 5            # 5-round run, keep any existing ledger
#   bash init-fleet.sh 3 --reset    # 3-round run, fresh ledger
#   bash init-fleet.sh 2 DO --reset # 2-round DO run, fresh ledger
set -euo pipefail

# Run-dir resolution: explicit env > newest run (current symlink) > legacy flat dir.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then
  G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then
  G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi
TOTAL="${1:-1}"
RESET=""
MODE="PLAN"

for arg in "${@:2}"; do
  upper="$(printf '%s' "$arg" | tr '[:lower:]' '[:upper:]')"
  case "$upper" in
    --RESET) RESET="--reset" ;;
    PLAN | DO | FULL_AUTO) MODE="$upper" ;;
    '') ;;
    *)
      echo "ERR: unknown arg '$arg' (expected --reset, PLAN, DO, or FULL_AUTO)" >&2
      exit 1
      ;;
  esac
done

case "$TOTAL" in *[!0-9]* | '')
  echo "ERR: total-rounds must be a positive integer (got '$TOTAL')" >&2
  exit 1
  ;;
esac
# The loop only terminates at ROUND == TOTAL_ROUNDS, so zero rounds would never end.
[ "$TOTAL" -gt 0 ] || {
  echo "ERR: total-rounds must be >= 1 (got '$TOTAL')" >&2
  exit 1
}

mkdir -p "$G"

# state machine — ROUND counts UP from 1; loop stops after ROUND == TOTAL_ROUNDS.
printf 'ROUND=1\nTOTAL_ROUNDS=%s\nMODE=%s\nPHASE=RECON\n' "$TOTAL" "$MODE" > "$G/state.env"
# Record the helper dir here so a standalone init gets the same state.env as
# start-fleet.sh. `cd -P` pins the source tree when the skill dir is a symlink.
printf 'FLEET_SKILL_DIR=%q\n' "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)" >> "$G/state.env"

# ledger — (re)create the header only if missing or --reset
if [ "$RESET" = "--reset" ] || [ ! -s "$G/results.tsv" ]; then
  printf 'round\tproject\tbranch\tcommit\tnote\tstatus\n' > "$G/results.tsv"
  echo "wrote fresh ledger: $G/results.tsv"
else
  echo "kept existing ledger: $G/results.tsv ($(($(wc -l < "$G/results.tsv") - 1)) rows)"
fi

echo "seeded codex-fleet state in $G (ROUND=1 TOTAL_ROUNDS=$TOTAL MODE=$MODE PHASE=RECON)"
echo "next: drive it via /loop with loop-prompt.md, or run recon-workflow.js + launch.sh per project manually."
