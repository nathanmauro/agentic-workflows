#!/usr/bin/env bash
# init-fleet.sh <total-rounds> [--reset] — seed the codex-fleet state machine.
# Writes the round-0 state + persisted round count under ~/.codex-goals/.
# Run once before starting a codex-fleet /loop. A non-empty results.tsv is kept
# unless --reset is passed. State lives in $CODEX_GOALS_DIR (default ~/.codex-goals).
#
#   bash init-fleet.sh 5            # 5-round run, keep any existing ledger
#   bash init-fleet.sh 3 --reset    # 3-round run, fresh ledger
set -euo pipefail

G="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"
TOTAL="${1:-1}"
RESET=""
MODE="PLAN"

for arg in "${@:2}"; do
  upper="$(printf '%s' "$arg" | tr '[:lower:]' '[:upper:]')"
  case "$upper" in
    --RESET) RESET="--reset" ;;
    PLAN|DO) MODE="$upper" ;;
    '') ;;
    *) echo "ERR: unknown arg '$arg' (expected --reset, PLAN, or DO)" >&2; exit 1 ;;
  esac
done

case "$TOTAL" in (*[!0-9]*|'') echo "ERR: total-rounds must be a positive integer (got '$TOTAL')" >&2; exit 1;; esac

mkdir -p "$G"

# state machine — ROUND counts UP from 1; loop stops after ROUND == TOTAL_ROUNDS.
printf 'ROUND=1\nTOTAL_ROUNDS=%s\nMODE=%s\nPHASE=RECON\n' "$TOTAL" "$MODE" > "$G/state.env"

# ledger — (re)create the header only if missing or --reset
if [ "$RESET" = "--reset" ] || [ ! -s "$G/results.tsv" ]; then
  printf 'round\tproject\tbranch\tcommit\tnote\tstatus\n' > "$G/results.tsv"
  echo "wrote fresh ledger: $G/results.tsv"
else
  echo "kept existing ledger: $G/results.tsv ($(($(wc -l < "$G/results.tsv") - 1)) rows)"
fi

echo "seeded codex-fleet state in $G (ROUND=1 TOTAL_ROUNDS=$TOTAL MODE=$MODE PHASE=RECON)"
echo "next: drive it via /loop with loop-prompt.md, or run recon-workflow.js + launch.sh per project manually."
