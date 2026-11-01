#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/fleet-board.sh"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

export CODEX_GOALS_DIR="$TMP/goals"
mkdir -p "$CODEX_GOALS_DIR"
printf 'ROUND=2\nTOTAL_ROUNDS=3\nMODE=PLAN\nPHASE=RUNNING\n' > "$CODEX_GOALS_DIR/state.env"

cat > "$CODEX_GOALS_DIR/alpha.spec.json" <<'JSON'
{
  "project": "alpha",
  "path": "/tmp/alpha",
  "tier": "prototype",
  "status": "planned",
  "current_round": 2,
  "verify_cmd": "echo ok",
  "push_allowed": false,
  "danger": "",
  "default_branch": "main",
  "approved_story": null,
  "branch_lineage": [],
  "pending_question": null
}
JSON

cat > "$CODEX_GOALS_DIR/bravo.spec.json" <<'JSON'
{
  "project": "bravo",
  "path": "/tmp/bravo",
  "tier": "production",
  "status": "review",
  "current_round": 2,
  "verify_cmd": "echo ok",
  "push_allowed": true,
  "danger": "",
  "default_branch": "main",
  "approved_story": null,
  "branch_lineage": [
    { "round": 2, "branch": "fleet/round-2-bravo", "base": "main", "pr": "#42", "commit": "abc123", "status": "review", "note": "" }
  ],
  "pending_question": null
}
JSON

cat > "$CODEX_GOALS_DIR/charlie.spec.json" <<'JSON'
{
  "project": "charlie",
  "path": "/tmp/charlie",
  "tier": "production",
  "status": "blocked",
  "current_round": 2,
  "verify_cmd": "echo ok",
  "push_allowed": false,
  "danger": "origin is PUBLIC",
  "default_branch": "main",
  "approved_story": null,
  "branch_lineage": [],
  "pending_question": null
}
JSON

bash "$SCRIPT" build
[ -f "$CODEX_GOALS_DIR/board.json" ] || fail "board.json was not created"
[ "$(jq -r '.projects[] | select(.name=="alpha") | .column' "$CODEX_GOALS_DIR/board.json")" = "planned" ] || fail "alpha was not in planned"
[ "$(jq -r '.projects[] | select(.name=="bravo") | .column' "$CODEX_GOALS_DIR/board.json")" = "review" ] || fail "bravo was not in review"
[ "$(jq -r '.projects[] | select(.name=="charlie") | .column' "$CODEX_GOALS_DIR/board.json")" = "blocked" ] || fail "charlie was not in blocked"
pass "build derives board columns"

SHOW="$(bash "$SCRIPT" show)"
printf '%s\n' "$SHOW" | grep -q '^alpha' || fail "show did not contain alpha"
printf '%s\n' "$SHOW" | grep -q '^bravo' || fail "show did not contain bravo"
printf '%s\n' "$SHOW" | grep -q '^charlie' || fail "show did not contain charlie"
printf '%s\n' "$SHOW" | awk 'length($0) > 100 { exit 1 }' || fail "show exceeded 100 columns"
pass "show prints a compact grid"

TEXT="$(bash "$SCRIPT" text)"
[ "$(printf '%s\n' "$TEXT" | sed '/^$/d' | wc -l | tr -d ' ')" = "3" ] || fail "text did not print one line per project"
pass "text prints one compact line per project"
