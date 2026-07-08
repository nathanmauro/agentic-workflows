#!/usr/bin/env bash
# launch.sh <project-name> <working-dir> <prompt-file>
# Creates a dedicated tmux session `codex-<project-name>` and starts an
# interactive Codex session there, auto-submitting the goal prompt from the file.
#
# Autonomy: launches Codex with `-a never` — it runs its own commands WITHOUT
# pausing for approval (full local autonomy). The safety net is the goal prompt,
# which constrains all work to a NEW feature branch with PR handling delegated
# to fleet-open-pr.sh and no merge.
# Only use when Nathan has authorized unattended execution for this fleet run.
# Model / reasoning / tier are gpt-5.5 / xhigh / priority by default; override with
# CODEX_MODEL / CODEX_EFFORT / CODEX_TIER env vars if needed.
#
# Continuation relaunch contract: to resume after a clarifying question, the
# loop overwrites ~/.codex-goals/<name>.md with the original goalPrompt plus:
#   --- CONTINUATION ---
#   Earlier you asked: <Q>
#   Nathan answered: <A>
#   Continue the slice from where you left off; do not restart.
# Then it calls launch.sh again with the same three arguments. No signature
# change is required because the prompt file carries the continuation context.
set -euo pipefail

NAME="$1"; DIR="$2"; PROMPT="$3"
SESS="codex-${NAME}"
MODEL="${CODEX_MODEL:-gpt-5.5}"
EFFORT="${CODEX_EFFORT:-xhigh}"
TIER="${CODEX_TIER:-priority}"

if ! command -v codex >/dev/null 2>&1; then echo "ERR: codex CLI not in \$PATH" >&2; exit 1; fi
if [ ! -d "$DIR" ]; then echo "ERR: dir not found: $DIR" >&2; exit 1; fi
if [ ! -f "$PROMPT" ]; then echo "ERR: prompt not found: $PROMPT" >&2; exit 1; fi

# Fresh session each time
tmux kill-session -t "$SESS" 2>/dev/null || true
tmux new-session -d -s "$SESS" -c "$DIR" -x 220 -y 50

# Launch interactive Codex; prompt fed via "$(cat ...)" so multi-line content
# needs no shell escaping. -a never = no approval pauses (autonomy on a branch).
tmux send-keys -t "$SESS" \
  "codex -m $MODEL -c model_reasoning_effort='\"$EFFORT\"' -c service_tier='\"$TIER\"' -a never \"\$(cat '$PROMPT')\"" \
  Enter

echo "LAUNCHED session=$SESS dir=$DIR prompt=$PROMPT model=$MODEL effort=$EFFORT tier=$TIER"
