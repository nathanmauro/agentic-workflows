#!/usr/bin/env bash
# launch.sh <project-name> <working-dir> <prompt-file>
# Creates a run-scoped tmux session `codex-<project-name>-<run-tag>` and starts an
# interactive Codex session there, auto-submitting the goal prompt from the file.
#
# Autonomy: launches Codex with `-a never`, so it runs its own commands without
# pausing for approval. The sandbox is passed explicitly rather than inherited from
# ~/.codex/config.toml: workspace-write over the project, plus the repo's git dir (so
# the worker can branch and commit), the run dir, and network (push, gh). Codex
# keeps .git read-only under plain workspace-write, so the git dir must be named.
# The remaining safety net is the goal prompt,
# which constrains all work to a NEW feature branch with PR handling delegated
# to fleet-open-pr.sh; FULL_AUTO merge handling stays in fleet-merge.sh.
# Only use when the human owner has authorized unattended execution for this fleet run.
#
# Model knobs (all env-overridable):
#   CODEX_MODEL   no default; when unset, the Codex client default model applies.
#   CODEX_EFFORT  reasoning effort; defaults to xhigh because unattended fleet
#                 rounds run at the highest effort tier. Set it empty to defer to
#                 the client default.
#   CODEX_TIER    service tier; no default, so the client default (standard)
#                 applies. Unattended rounds should stay on the standard tier.
# State dir: explicit CODEX_GOALS_DIR > current symlink > legacy flat dir.
#
# Continuation relaunch contract: to resume after a clarifying question, the
# loop overwrites <run-dir>/<name>.md with the original goalPrompt plus:
#   --- CONTINUATION ---
#   Earlier you asked: <Q>
#   The human owner answered: <A>
#   Continue the slice from where you left off; do not restart.
# Then it calls launch.sh again with the same three arguments. No signature
# change is required because the prompt file carries the continuation context.
set -euo pipefail

NAME="$1"
DIR="$2"
PROMPT="$3"
case "$NAME" in
  '' | */*)
    echo "ERR: project name must be non-empty and contain no slash" >&2
    exit 1
    ;;
esac

# Resolve and physically pin this run. A later start-fleet invocation may
# repoint `current`; an unresolved symlink would silently move a live session.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then
  G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then
  G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi
[ -d "$G" ] || {
  echo "ERR: goals dir not found: $G" >&2
  exit 1
}
G="$(cd "$G" && pwd -P)"
NAME_TAG="$(printf '%s' "$NAME" | tr -c '[:alnum:]_-' '-')"
NAME_HASH="$(printf '%s' "$NAME" | cksum | awk '{print $1}')"
RUN_TAG="$(printf '%s' "$G" | cksum | awk '{print $1}')"
SESS="codex-${NAME_TAG}-${NAME_HASH}-${RUN_TAG}"

MODEL="${CODEX_MODEL:-}"
EFFORT="${CODEX_EFFORT-xhigh}"
TIER="${CODEX_TIER:-}"

if ! command -v codex > /dev/null 2>&1; then
  echo "ERR: codex CLI not in \$PATH" >&2
  exit 1
fi
if [ ! -d "$DIR" ]; then
  echo "ERR: dir not found: $DIR" >&2
  exit 1
fi
if [ ! -f "$PROMPT" ]; then
  echo "ERR: prompt not found: $PROMPT" >&2
  exit 1
fi

# The common dir covers linked worktrees too: their per-worktree git dir lives under it.
if ! GIT_DIR_ABS="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2> /dev/null)"; then
  echo "ERR: not a git repository: $DIR" >&2
  exit 1
fi

# Fresh session each time
tmux kill-session -t "$SESS" 2> /dev/null || true
tmux new-session -d -s "$SESS" -c "$DIR" -x 220 -y 50
session_tmp="$(mktemp "$G/$NAME.session.XXXXXX")"
printf '%s\n' "$SESS" > "$session_tmp"
mv "$session_tmp" "$G/$NAME.session"

# Launch interactive Codex; prompt fed via "$(cat ...)" so multi-line content
# needs no shell escaping. -a never = no approval pauses (autonomy on a branch).
# Export the physical run dir into the tmux shell so every helper resolves this
# run even when another fleet starts concurrently.
MODEL_ARG=""
[ -n "$MODEL" ] && MODEL_ARG=" -m $(printf %q "$MODEL")"
EFFORT_ARG=""
if [ -n "$EFFORT" ]; then
  EFFORT_ARG=" -c $(printf '%q' "model_reasoning_effort=\"$EFFORT\"")"
fi
TIER_ARG=""
if [ -n "$TIER" ]; then
  TIER_ARG=" -c $(printf '%q' "service_tier=\"$TIER\"")"
fi

toml_string() {
  local escaped="${1//\\/\\\\}"
  printf '"%s"' "${escaped//\"/\\\"}"
}

ROOTS="[$(toml_string "$GIT_DIR_ABS"), $(toml_string "$G")]"
SANDBOX_ARG=" -s workspace-write"
SANDBOX_ARG+=" -c $(printf %q "sandbox_workspace_write.writable_roots=$ROOTS")"
SANDBOX_ARG+=" -c sandbox_workspace_write.network_access=true"

GQ="$(printf %q "$G")"
PQ="$(printf %q "$PROMPT")"
CODEX_ARGS="$MODEL_ARG$EFFORT_ARG$TIER_ARG$SANDBOX_ARG -a never"
tmux send-keys -t "$SESS" \
  "export CODEX_GOALS_DIR=$GQ; codex$CODEX_ARGS \"\$(cat $PQ)\"" \
  Enter

echo "LAUNCHED session=$SESS dir=$DIR prompt=$PROMPT goals=$G" \
  "model=${MODEL:-client-default} effort=${EFFORT:-client-default}" \
  "tier=${TIER:-client-default} sandbox=workspace-write+git+run-dir+network"
