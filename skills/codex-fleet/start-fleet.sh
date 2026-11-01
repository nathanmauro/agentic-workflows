#!/usr/bin/env bash
# start-fleet.sh
# Interactive launcher for codex-fleet, fired from the agentic-workflows repo.
# Asks which projects + how many iterations.
# Runs health checks on each.
# Seeds state, writes projects.json, prepares ready-to-paste loop instruction for Claude's /loop.
#
# Usage (recommended):
#   cd <agentic-workflows-repo>
#   ./skills/codex-fleet/start-fleet.sh
#
# An installed or symlinked copy should auto-resolve to this source tree.

set -euo pipefail

# Fire off from the public workflow repo. Follow a symlinked script file to its
# source, then let `cd -P` resolve a symlinked skill directory. Plain readlink
# keeps this portable to macOS, which lacks `readlink -f` on older releases.
src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  link_dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in
    /*) ;;
    *) src="$link_dir/$src" ;;
  esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
WORKFLOWS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)" # skills/codex-fleet -> repo root

echo "Firing codex-fleet from workflow repo: $WORKFLOWS_DIR"
cd "$WORKFLOWS_DIR"

# Each invocation gets a fresh, archived run dir. Ignore an inherited
# CODEX_GOALS_DIR so starting a fleet from inside another fleet cannot reset or
# reuse that live run's state.
GOALS_ROOT="$HOME/.codex-goals"
if [ -n "${CODEX_GOALS_DIR:-}" ]; then
  echo "NOTE: ignoring inherited CODEX_GOALS_DIR=$CODEX_GOALS_DIR; every fleet gets a fresh run dir."
fi
CURRENT_LINK="$GOALS_ROOT/current"
if [ -e "$CURRENT_LINK" ] && [ ! -L "$CURRENT_LINK" ]; then
  echo "ERR: $CURRENT_LINK exists but is not a symlink; refusing to overwrite it." >&2
  exit 1
fi
RUN_PARENT="$GOALS_ROOT/runs/$(date +%Y/%m)"
mkdir -p "$RUN_PARENT"
CODEX_GOALS_DIR="$(mktemp -d "$RUN_PARENT/$(date +%d-%H%M%S).XXXXXX")"
export CODEX_GOALS_DIR

# A legacy flat-layout fleet may still call helpers without an env prefix.
# Refuse to repoint `current` while that fleet is unfinished unless the human
# explicitly accepts the collision risk.
if [ -f "$GOALS_ROOT/state.env" ] && ! grep -q '^PHASE=DONE' "$GOALS_ROOT/state.env"; then
  echo "WARNING: legacy flat-layout state at $GOALS_ROOT/state.env is not PHASE=DONE."
  echo "Starting a run-scoped fleet could redirect that run's unpinned helper calls."
  read -r -p "Continue anyway? (y/N): " legacy_ok
  [[ "$legacy_ok" =~ ^[Yy] ]] || {
    echo "Aborted."
    exit 1
  }
fi

echo "Run state dir: $CODEX_GOALS_DIR"

FLEET_SKILL_DIR="$SCRIPT_DIR" # the codex-fleet dir

PROBE_TIMEOUT="${CODEX_FLEET_PROBE_TIMEOUT:-45}"
case "$PROBE_TIMEOUT" in
  '' | *[!0-9]*) PROBE_TIMEOUT=45 ;;
esac

# Run a verify command with a wall-clock bound and report its real exit status
# (124 on timeout, matching coreutils). Stock macOS ships no `timeout`, so fall
# back to a background job plus a watchdog that kills it at the deadline.
run_probe() {
  local cmd="$1" probe_pid watchdog_pid rc timed_out_marker

  # stdin is the setup prompt stream; a probe must never consume its answers.
  if command -v timeout > /dev/null 2>&1; then
    timeout "${PROBE_TIMEOUT}s" bash -c "$cmd" < /dev/null
    return
  fi
  if command -v gtimeout > /dev/null 2>&1; then
    gtimeout "${PROBE_TIMEOUT}s" bash -c "$cmd" < /dev/null
    return
  fi

  timed_out_marker="$CODEX_GOALS_DIR/.probe-timed-out"
  rm -f "$timed_out_marker"
  # Job control puts the probe in its own process group, so a timeout can stop the whole
  # verify command (npm, make, and their children), as GNU timeout does.
  set -m
  bash -c "$cmd" < /dev/null &
  probe_pid=$!
  set +m
  (
    sleep_pid=""
    # Reap the sleep when the probe finishes first, so no stray timer lingers.
    trap '[ -z "$sleep_pid" ] || kill "$sleep_pid" 2> /dev/null; exit 0' TERM
    sleep "$PROBE_TIMEOUT" &
    sleep_pid=$!
    wait "$sleep_pid"
    if kill -TERM -- "-$probe_pid" 2> /dev/null; then
      : > "$timed_out_marker"
    fi
  ) &
  watchdog_pid=$!

  rc=0
  wait "$probe_pid" || rc=$?
  kill -TERM "$watchdog_pid" 2> /dev/null || true
  wait "$watchdog_pid" 2> /dev/null || true
  if [ -f "$timed_out_marker" ]; then
    rm -f "$timed_out_marker"
    rc=124
  fi
  return "$rc"
}

echo "=== Codex Fleet Interactive Setup ==="
echo

# Prompt 1: which projects
echo "Which projects should this fleet run on?"
echo

# Auto-discover candidate projects only when the caller supplies a local root.
PROJ_ROOT="${CODEX_FLEET_PROJECT_ROOT:-}"
CANDIDATES=()
if [ -n "$PROJ_ROOT" ] && [ -d "$PROJ_ROOT" ]; then
  while IFS= read -r d; do
    CANDIDATES+=("$(basename "$d")")
  done < <(find "$PROJ_ROOT" -maxdepth 1 -mindepth 1 -type d -exec test -e '{}/.git' ';' -print 2> /dev/null | sort)
else
  echo "Set CODEX_FLEET_PROJECT_ROOT to enable numbered project discovery."
  echo
fi

if [ ${#CANDIDATES[@]} -gt 0 ]; then
  echo "Available projects (git repos under $PROJ_ROOT):"
  cols=3
  i=0
  for c in "${CANDIDATES[@]}"; do
    printf "  %3d) %-26s" "$((i + 1))" "$c"
    i=$((i + 1))
    [ $((i % cols)) -eq 0 ] && echo
  done
  [ $((i % cols)) -ne 0 ] && echo
  echo
fi

echo "Select by number (e.g. '1 3 5' or a range '1-4'), and/or type names/paths."
echo "Mix freely, space- or comma-separated:  '1 3 example-repo /abs/path/to/repo'"
read -r -p "Projects: " PROJECTS_INPUT

# Expand numbers + ranges against the candidate list; pass names/paths through verbatim.
PROJECTS_INPUT="${PROJECTS_INPUT//,/ }"
RAW_PROJECTS=()
for tok in $PROJECTS_INPUT; do
  if [[ "$tok" =~ ^[0-9]+-[0-9]+$ ]]; then
    lo="${tok%-*}"
    hi="${tok#*-}"
    for ((n = lo; n <= hi; n++)); do
      idx=$((n - 1))
      if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#CANDIDATES[@]}" ]; then RAW_PROJECTS+=("${CANDIDATES[$idx]}"); fi
    done
  elif [[ "$tok" =~ ^[0-9]+$ ]]; then
    idx=$((tok - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#CANDIDATES[@]}" ]; then RAW_PROJECTS+=("${CANDIDATES[$idx]}"); fi
  else
    RAW_PROJECTS+=("$tok")
  fi
done

PROJECTS_JSON='[]'
PROJECTS_ARRAY=()
SELECTED_PROJECT_NAMES=()
SELECTED_PROJECT_PATHS=()

for raw in "${RAW_PROJECTS[@]}"; do
  raw=$(echo "$raw" | xargs) # trim
  if [ -z "$raw" ]; then continue; fi

  if [[ "$raw" == /* ]]; then
    candidate_path="$raw"
  elif [[ "$raw" == ./* || "$raw" == ../* ]]; then
    # Explicit relative paths are relative to the workflow repo, even when a
    # discovery root is configured for bare project names.
    candidate_path="$raw"
  elif [ -n "$PROJ_ROOT" ]; then
    candidate_path="$PROJ_ROOT/$raw"
  else
    candidate_path="$raw"
  fi

  if [ ! -d "$candidate_path" ]; then
    echo "WARNING: $candidate_path does not exist. Skipping $raw"
    continue
  fi

  # Canonicalize before the project identity is used in projects.json, state
  # mirrors, log names, or launch/session handoffs. A raw path must never be
  # able to become a state filename.
  if ! path="$(cd "$candidate_path" 2> /dev/null && pwd -P)"; then
    echo "WARNING: cannot resolve $candidate_path. Skipping $raw" >&2
    continue
  fi
  name="$(basename "$path")"
  case "$name" in
    '' | . | .. | */*)
      echo "ERR: canonical project path '$path' has an unsafe basename '$name'." >&2
      exit 1
      ;;
  esac

  duplicate_selection=false
  for selected_idx in "${!SELECTED_PROJECT_NAMES[@]}"; do
    if [ "${SELECTED_PROJECT_NAMES[$selected_idx]}" != "$name" ]; then
      continue
    fi
    if [ "${SELECTED_PROJECT_PATHS[$selected_idx]}" = "$path" ]; then
      echo "(already selected $name at $path, skipping duplicate selection)"
      duplicate_selection=true
      break
    fi
    echo "ERR: project name '$name' resolves from multiple paths:" >&2
    echo "  ${SELECTED_PROJECT_PATHS[$selected_idx]}" >&2
    echo "  $path" >&2
    echo "Use projects with distinct canonical basenames in one fleet run." >&2
    exit 1
  done
  if $duplicate_selection; then
    continue
  fi
  SELECTED_PROJECT_NAMES+=("$name")
  SELECTED_PROJECT_PATHS+=("$path")

  # Ask for optional hint for this project
  read -r -p "Any special hint for $name? (e.g. 'focus on TUI subdir; origin PUBLIC' or leave empty): " hint
  hint=$(echo "$hint" | xargs)

  read -r -p "Tier for $name? [production] full gates / [prototype] light  (default production): " tier
  tier=$(printf '%s' "${tier:-production}" | tr '[:upper:]' '[:lower:]')
  [ "$tier" = prototype ] || tier=production

  # Build json entry
  entry=$(jq -n --arg name "$name" --arg path "$path" --arg hint "$hint" --arg tier "$tier" \
    '{name: $name, path: $path, hint: $hint, tier: $tier}')

  PROJECTS_ARRAY+=("$entry")
done

if [ ${#PROJECTS_ARRAY[@]} -eq 0 ]; then
  echo "No valid projects selected. Aborting."
  exit 1
fi

# Join into json array
PROJECTS_JSON=$(printf '%s\n' "${PROJECTS_ARRAY[@]}" | jq -s '.')

echo "$PROJECTS_JSON" > "$CODEX_GOALS_DIR/projects.json"
echo "Wrote projects list to $CODEX_GOALS_DIR/projects.json"

read -r -p "Mode? [PLAN] interactive planning / [DO] auto-run / [FULL_AUTO] auto-run + gated auto-merge  (default PLAN): " MODE
MODE=$(printf '%s' "${MODE:-PLAN}" | tr '[:lower:]' '[:upper:]')
case "$MODE" in
  DO) MODE=DO ;;
  FULL_AUTO | FULLAUTO) MODE=FULL_AUTO ;;
  *) MODE=PLAN ;;
esac

# Prompt 2: how many iterations
echo
read -r -p "How many iterations (rounds) should the fleet run? [default 3]: " N
N="${N:-3}"
case "$N" in *[!0-9]* | '')
  echo "ERR: iterations must be positive integer"
  exit 1
  ;;
esac
# The loop only terminates at ROUND == TOTAL_ROUNDS, so zero rounds would never end.
[ "$N" -gt 0 ] || {
  echo "ERR: iterations must be >= 1"
  exit 1
}

# General health check on each project before beginning
echo
echo "=== Pre-flight Health Checks ==="
HEALTH_OK=true
SPEC_SEEDS_ARRAY=()

for entry in "${PROJECTS_ARRAY[@]}"; do
  name=$(echo "$entry" | jq -r '.name')
  path=$(echo "$entry" | jq -r '.path')
  hint=$(echo "$entry" | jq -r '.hint')
  tier=$(echo "$entry" | jq -r '.tier')

  echo "--- Health: $name ($path) ---"
  cd "$path" || {
    echo "FAIL: cannot cd"
    HEALTH_OK=false
    continue
  }

  # Basic git health
  git status -sb || true
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2> /dev/null | sed 's@.*/@@' || echo "main")

  # Check for dirty state
  if [ -n "$(git status --porcelain)" ]; then
    echo "NOTE: working tree is dirty. Fleet will be careful."
  fi

  # Discover verify / build commands
  VERIFY_CMD=""
  BUILD_CMD=""
  if [ -f package.json ]; then
    if grep -q '"test"' package.json; then VERIFY_CMD="npm test"; fi
    if grep -q '"build"' package.json; then BUILD_CMD="npm run build"; fi
  elif [ -f Makefile ]; then
    if grep -q '^test:' Makefile; then VERIFY_CMD="make test"; fi
    if grep -q '^build:' Makefile; then BUILD_CMD="make build"; fi
  fi

  echo "  Verify suggestion: ${VERIFY_CMD:-'(none detected)'}"
  echo "  Build suggestion:  ${BUILD_CMD:-'(none)'}"

  origin_ok=false
  if git remote get-url origin > /dev/null 2>&1; then origin_ok=true; fi
  gh_ok=false
  if command -v gh > /dev/null 2>&1; then gh_ok=true; fi
  danger_blocks=false
  if printf '%s\n' "$hint" | grep -Eiq 'PUBLIC|never push|do not push'; then danger_blocks=true; fi
  push_allowed=false
  if $origin_ok && $gh_ok && ! $danger_blocks; then push_allowed=true; fi
  if $push_allowed; then
    read -r -p "Allow this fleet run to push $name branches and open draft PRs? (y/N): " push_grant
    case "$push_grant" in
      [Yy] | [Yy][Ee][Ss]) ;;
      *) push_allowed=false ;;
    esac
  fi
  echo "  Default branch: ${DEFAULT_BRANCH:-main}"
  echo "  Push allowed:   $push_allowed (explicit grant required; origin=$origin_ok gh=$gh_ok danger_blocks=$danger_blocks)"

  # Quick non-destructive health probe, bounded so a hanging suite cannot stall
  # setup. The result is advisory; a failing probe never blocks the fleet.
  if [ -n "$VERIFY_CMD" ]; then
    probe_log="$CODEX_GOALS_DIR/health-$name.log"
    echo "  Quick health probe (timeout ${PROBE_TIMEOUT}s, log $probe_log)..."
    probe_rc=0
    run_probe "$VERIFY_CMD" > "$probe_log" 2>&1 || probe_rc=$?
    case "$probe_rc" in
      0) echo "  Probe: OK" ;;
      124) echo "  Probe: timed out after ${PROBE_TIMEOUT}s (non-fatal for fleet start)" ;;
      *) echo "  Probe: failed with exit $probe_rc (non-fatal for fleet start)" ;;
    esac
  fi

  # Detect reviewable app support
  REVIEW_MODE=""
  if [ -f package.json ] && (grep -q '"start"' package.json || grep -q '"dev"' package.json); then
    REVIEW_MODE="web/dev-server (can leave running for review on unique port if desired)"
  elif [ -d app ] || [ -f index.html ] \
    || compgen -G 'vite.config.*' > /dev/null \
    || compgen -G 'next.config.*' > /dev/null; then
    REVIEW_MODE="frontend app (build artifacts reviewable)"
  fi
  [ -n "$REVIEW_MODE" ] && echo "  Reviewable artifacts: $REVIEW_MODE"

  seed_entry=$(jq -n \
    --arg name "$name" \
    --arg path "$path" \
    --arg tier "$tier" \
    --arg verify_cmd "$VERIFY_CMD" \
    --argjson push_allowed "$push_allowed" \
    --arg hint "$hint" \
    --arg default_branch "${DEFAULT_BRANCH:-main}" \
    '{
      name: $name,
      path: $path,
      tier: $tier,
      verify_cmd: $verify_cmd,
      push_allowed: $push_allowed,
      hint: $hint,
      default_branch: $default_branch
    }')
  SPEC_SEEDS_ARRAY+=("$seed_entry")

  echo "  Health check complete for $name."
  echo
done

if ! $HEALTH_OK; then
  echo "Some health issues noted above. Continue anyway? (y/N)"
  read -r cont
  if [[ ! "$cont" =~ ^[Yy] ]]; then
    echo "Aborted by user."
    exit 1
  fi
fi

echo "All pre-flight health checks done."

echo
echo "=== Seeding Fleet Spec Mirrors ==="
for seed in "${SPEC_SEEDS_ARRAY[@]}"; do
  name=$(echo "$seed" | jq -r '.name')
  path=$(echo "$seed" | jq -r '.path')
  tier=$(echo "$seed" | jq -r '.tier')
  VERIFY_CMD=$(echo "$seed" | jq -r '.verify_cmd')
  push_allowed=$(echo "$seed" | jq -r '.push_allowed')
  hint=$(echo "$seed" | jq -r '.hint')
  DEFAULT_BRANCH=$(echo "$seed" | jq -r '.default_branch')
  bash "$FLEET_SKILL_DIR/fleet-spec.sh" init "$name" "$path" "$tier" "$VERIFY_CMD" "$push_allowed" "$hint" "$DEFAULT_BRANCH"
done

# Seed the fleet state (iterations). init-fleet.sh records FLEET_SKILL_DIR.
bash "$FLEET_SKILL_DIR/init-fleet.sh" "$N" "$MODE" --reset

# Prepare the ready-to-paste Claude /loop instruction
LOOP_INSTRUCTION="$CODEX_GOALS_DIR/loop-instruction.txt"

PROJECTS_BLOCK=$(cat "$CODEX_GOALS_DIR/projects.json")
if [ "$MODE" = PLAN ]; then
  MODE_EXPLANATION="PLAN mode runs RECON -> APPROVAL -> RUNNING -> REVIEW for each round; the human owner approves, redirects, or skips each proposed slice through a native option prompt (AskUserQuestion) on terminal or phone before launch."
elif [ "$MODE" = FULL_AUTO ]; then
  MODE_EXPLANATION="FULL_AUTO mode runs RECON -> RUNNING -> REVIEW like DO, then auto-merges only PRs that pass fleet-merge.sh's fail-closed gates. Gated or failed slices remain in review."
else
  MODE_EXPLANATION="DO mode runs RECON -> RUNNING -> REVIEW for each round; it skips only APPROVAL and otherwise keeps clarification (native option prompts), spec, board, and PR/review gates."
fi

cat > "$LOOP_INSTRUCTION" << EOF
# codex-fleet (generated by start-fleet.sh from the agentic-workflows repo)

Use Claude as the orchestrator with its native /loop (dynamic mode, ScheduleWakeup, no fixed interval).

**Projects (from projects.json):**
${PROJECTS_BLOCK}

**State already initialized for ${N} rounds** (ROUND=1, projects.json + health checks done by this script).
**MODE=${MODE}**
${MODE_EXPLANATION}

**RUN_DIR = ${CODEX_GOALS_DIR}**
This run's state, prompts, questions, board, results, and archived instruction
file all live under RUN_DIR. Wherever loop-prompt.md says \$GOALS, use this
concrete directory. Prefix every helper call with
CODEX_GOALS_DIR="${CODEX_GOALS_DIR}", and pass
"goalsDir": "${CODEX_GOALS_DIR}" to the recon Workflow. This is what isolates
concurrent fleets.

Read ${CODEX_GOALS_DIR}/state.env at the start of every turn.

Use FLEET_SKILL_DIR from state.env for helper scripts in this run:
${FLEET_SKILL_DIR}

Follow ${FLEET_SKILL_DIR}/loop-prompt.md as the authority for the MODE/PHASE machine, including APPROVAL, clarification polling, board refresh, REVIEW, and DONE handling. Pass both this FLEET_SKILL_DIR and RUN_DIR into the recon Workflow args so cold Codex prompts receive portable helper paths and the pinned state dir.

**Fleet rules (embed in all reasoning):**
- Branches must be fleet/round-N-...
- Codex commits autonomously.
- Approvals and mid-flight clarifying questions surface as native option prompts (AskUserQuestion), built by fleet-prompt.sh; the typed reply grammar is a non-interactive fallback only.
- Artifacts left behind for review are cleaned only on the subsequent RECON.
- Use the exact guardrails from the recon-workflow (human owner author, selective stage, green verify only; fleet-open-pr.sh owns push/PR decisions and only FULL_AUTO may call fleet-merge.sh).

Now start the cycle: read state, enter PHASE==RECON logic for ROUND 1.
EOF

# Publish `current` only after the run is fully seeded. A cancelled or failed
# setup must not redirect unpinned helpers away from the last usable run.
ln -sfn "$CODEX_GOALS_DIR" "$CURRENT_LINK"

echo
echo "=== Fleet ready (fired from the workflow repo) ==="
echo "Projects: $(echo "$PROJECTS_JSON" | jq -r '.[].name' | tr '\n' ' ')"
echo "Iterations: $N"
echo "Mode: $MODE"
echo "Run dir: $CODEX_GOALS_DIR (archived; ~/.codex-goals/current points here)"
echo
echo "Next step in Claude Code:"
echo "  Paste the *entire* contents of this file as the prompt to /loop (dynamic):"
echo "    $LOOP_INSTRUCTION"
echo
echo "Claude will orchestrate using its loop function + Workflow tool."
echo "Codex will use fleet/round-N specific branches and manage reviewable artifacts."
echo
echo "Run this script again from the workflow repo for a new fleet with different projects/rounds."
