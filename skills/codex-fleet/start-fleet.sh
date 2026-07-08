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

# Fire off from the public workflow repo.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve to actual source if symlinked
if [ -L "$SCRIPT_DIR" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$(readlink "$SCRIPT_DIR")")" && pwd)"
fi
WORKFLOWS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # skills/codex-fleet -> repo root

echo "Firing codex-fleet from workflow repo: $WORKFLOWS_DIR"
cd "$WORKFLOWS_DIR"

CODEX_GOALS_DIR="${CODEX_GOALS_DIR:-$HOME/.codex-goals}"
mkdir -p "$CODEX_GOALS_DIR"

FLEET_SKILL_DIR="$SCRIPT_DIR"   # the codex-fleet dir

echo "=== Codex Fleet Interactive Setup ==="
echo

# Prompt 1: which projects
echo "Which projects should this fleet run on?"
echo

# Auto-discover candidate projects: git repos directly under ~/Developer/proj.
PROJ_ROOT="$HOME/Developer/proj"
CANDIDATES=()
while IFS= read -r d; do
  CANDIDATES+=("$(basename "$d")")
done < <(find "$PROJ_ROOT" -maxdepth 1 -mindepth 1 -type d -exec test -e '{}/.git' ';' -print 2>/dev/null | sort)

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
echo "Mix freely, space- or comma-separated:  '1 3 mycelium /abs/path/to/repo'"
read -r -p "Projects: " PROJECTS_INPUT

# Expand numbers + ranges against the candidate list; pass names/paths through verbatim.
PROJECTS_INPUT="${PROJECTS_INPUT//,/ }"
RAW_PROJECTS=()
for tok in $PROJECTS_INPUT; do
  if [[ "$tok" =~ ^[0-9]+-[0-9]+$ ]]; then
    lo="${tok%-*}"; hi="${tok#*-}"
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

for raw in "${RAW_PROJECTS[@]}"; do
  raw=$(echo "$raw" | xargs)  # trim
  if [ -z "$raw" ]; then continue; fi

  if [[ "$raw" == /* ]]; then
    path="$raw"
    name=$(basename "$path")
  else
    name="$raw"
    path="$HOME/Developer/proj/$name"
  fi

  if [ ! -d "$path" ]; then
    echo "WARNING: $path does not exist. Skipping $name"
    continue
  fi

  # Skip duplicate selections (e.g. picked by both number and name)
  case " ${SEEN_NAMES:-} " in *" $name "*) echo "(already selected $name, skipping dup)"; continue ;; esac
  SEEN_NAMES="${SEEN_NAMES:-} $name"

  # Ask for optional hint for this project
  read -r -p "Any special hint for $name? (e.g. 'focus on TUI subdir; origin PUBLIC' or leave empty): " hint
  hint=$(echo "$hint" | xargs)

  read -r -p "Tier for $name? [production] full gates / [prototype] light  (default production): " tier
  tier=$(printf '%s' "${tier:-production}" | tr '[:lower:]' '[:upper:]' | tr 'A-Z' 'a-z')
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

read -r -p "Mode? [PLAN] interactive planning / [DO] auto-run  (default PLAN): " MODE
MODE=$(printf '%s' "${MODE:-PLAN}" | tr '[:lower:]' '[:upper:]')
[ "$MODE" = DO ] || MODE=PLAN

# Prompt 2: how many iterations
echo
read -r -p "How many iterations (rounds) should the fleet run? [default 3]: " N
N="${N:-3}"
case "$N" in (*[!0-9]*|'') echo "ERR: iterations must be positive integer"; exit 1;; esac

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
  cd "$path" || { echo "FAIL: cannot cd"; HEALTH_OK=false; continue; }

  # Basic git health
  git status -sb || true
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@.*/@@' || echo "main")

  # Check for dirty state
  if [ -n "$(git status --porcelain)" ]; then
    echo "NOTE: working tree is dirty. Fleet will be careful."
  fi

  # Discover verify / build commands
  VERIFY_CMD=""
  BUILD_CMD=""
  DEV_CMD=""
  if [ -f package.json ]; then
    if grep -q '"test"' package.json; then VERIFY_CMD="npm test"; fi
    if grep -q '"build"' package.json; then BUILD_CMD="npm run build"; fi
    if grep -q '"dev"' package.json; then DEV_CMD="npm run dev"; fi
  elif [ -f Makefile ]; then
    if grep -q '^test:' Makefile; then VERIFY_CMD="make test"; fi
    if grep -q '^build:' Makefile; then BUILD_CMD="make build"; fi
  fi

  echo "  Verify suggestion: ${VERIFY_CMD:-'(none detected)'}"
  echo "  Build suggestion:  ${BUILD_CMD:-'(none)'}"

  origin_ok=false
  if git remote get-url origin >/dev/null 2>&1; then origin_ok=true; fi
  gh_ok=false
  if command -v gh >/dev/null 2>&1; then gh_ok=true; fi
  danger_blocks=false
  if printf '%s\n' "$hint" | grep -Eiq 'PUBLIC|never push|do not push'; then danger_blocks=true; fi
  push_allowed=false
  if $origin_ok && $gh_ok && ! $danger_blocks; then push_allowed=true; fi
  echo "  Default branch: ${DEFAULT_BRANCH:-main}"
  echo "  Push allowed:   $push_allowed (origin=$origin_ok gh=$gh_ok danger_blocks=$danger_blocks)"

  # Quick non-destructive health probe (timeout to avoid hanging)
  if [ -n "$VERIFY_CMD" ]; then
    echo "  Quick health probe (timeout 45s)..."
    if timeout 45s bash -c "$VERIFY_CMD --if-present || true" > /tmp/fleet-health-$name.log 2>&1; then
      echo "  Probe: OK (see log if needed)"
    else
      echo "  Probe: completed with issues (non-fatal for fleet start)"
    fi
  fi

  # Detect reviewable app support
  REVIEW_MODE=""
  if [ -f package.json ] && (grep -q '"start"' package.json || grep -q '"dev"' package.json); then
    REVIEW_MODE="web/dev-server (can leave running for review on unique port if desired)"
  elif [ -d app ] || [ -f index.html ] || [ -f vite.config.* ] || [ -f next.config.* ]; then
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

# Seed the fleet state (iterations)
bash "$FLEET_SKILL_DIR/init-fleet.sh" "$N" "$MODE" --reset
printf 'FLEET_SKILL_DIR=%q\n' "$FLEET_SKILL_DIR" >> "$CODEX_GOALS_DIR/state.env"

# Prepare the ready-to-paste Claude /loop instruction
LOOP_INSTRUCTION="$CODEX_GOALS_DIR/loop-instruction.txt"

PROJECTS_BLOCK=$(cat "$CODEX_GOALS_DIR/projects.json")
if [ "$MODE" = PLAN ]; then
  MODE_EXPLANATION="PLAN mode runs RECON -> APPROVAL -> RUNNING -> REVIEW for each round; the human owner approves, redirects, or skips each proposed slice through a native option prompt (AskUserQuestion) on terminal or phone before launch."
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

Read ~/.codex-goals/state.env at the start of every turn.

Use FLEET_SKILL_DIR from state.env for helper scripts in this run:
${FLEET_SKILL_DIR}

Follow ${FLEET_SKILL_DIR}/loop-prompt.md as the authority for the MODE/PHASE machine, including APPROVAL, clarification polling, board refresh, REVIEW, and DONE handling. Pass this same FLEET_SKILL_DIR into the recon Workflow args so cold Codex prompts receive repo-local helper paths.

**Fleet rules (embed in all reasoning):**
- Branches must be fleet/round-N-...
- Codex commits autonomously.
- Approvals and mid-flight clarifying questions surface as native option prompts (AskUserQuestion), built by fleet-prompt.sh; the typed reply grammar is a non-interactive fallback only.
- Artifacts left behind for review are cleaned only on the subsequent RECON.
- Use the exact guardrails from the recon-workflow (human owner author, selective stage, green verify only, no merge; fleet-open-pr.sh owns push/PR decisions).

Now start the cycle: read state, enter PHASE==RECON logic for ROUND 1.
EOF

echo
echo "=== Fleet ready (fired from the workflow repo) ==="
echo "Projects: $(echo "$PROJECTS_JSON" | jq -r '.[].name' | tr '\n' ' ')"
echo "Iterations: $N"
echo "Mode: $MODE"
echo
echo "Next step in Claude Code:"
echo "  Paste the *entire* contents of this file as the prompt to /loop (dynamic):"
echo "    $LOOP_INSTRUCTION"
echo
echo "Claude will orchestrate using its loop function + Workflow tool."
echo "Codex will use fleet/round-N specific branches and manage reviewable artifacts."
echo
echo "Run this script again from the workflow repo for a new fleet with different projects/rounds."
