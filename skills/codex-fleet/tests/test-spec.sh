#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/fleet-spec.sh"
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
REPO="$TMP/demo"
mkdir -p "$CODEX_GOALS_DIR" "$REPO"

bash "$SCRIPT" init demo "$REPO" prototype "echo ok" true "" main
[ -f "$CODEX_GOALS_DIR/demo.spec.json" ] || fail "spec mirror was not created"
[ "$(jq -r .tier "$CODEX_GOALS_DIR/demo.spec.json")" = "prototype" ] || fail "tier was not prototype"
pass "init creates the spec mirror"

bash "$SCRIPT" set demo '.status="doing"'
[ "$(jq -r .status "$CODEX_GOALS_DIR/demo.spec.json")" = "doing" ] || fail "set did not update status"
pass "set updates the mirror atomically"

bash "$SCRIPT" render demo
[ -f "$REPO/docs/fleet/spec.md" ] || fail "render did not create docs/fleet/spec.md"
grep -q '^status: doing$' "$REPO/docs/fleet/spec.md" || fail "rendered frontmatter did not contain status: doing"
grep -q '^# demo — fleet spec$' "$REPO/docs/fleet/spec.md" || fail "rendered spec did not contain the expected title"
pass "render writes frontmatter and title"

awk '
  { print }
  /^## Decided$/ {
    print "- Keep this human decision."
  }
' "$REPO/docs/fleet/spec.md" > "$REPO/docs/fleet/spec.md.tmp"
mv "$REPO/docs/fleet/spec.md.tmp" "$REPO/docs/fleet/spec.md"

bash "$SCRIPT" render demo
grep -q 'Keep this human decision' "$REPO/docs/fleet/spec.md" || fail "render did not preserve the human-edited Decided block"
pass "render preserves human-edited body blocks"

bash "$SCRIPT" set demo \
  '.status="done" | .approved_story={title:"round one"} |
   .pending_question={status:"answered"} |
   .branch_lineage=[{round:1,branch:"fleet/round-1-one",status:"done"}]'
bash "$SCRIPT" advance demo 2
[ "$(jq -r .current_round "$CODEX_GOALS_DIR/demo.spec.json")" = 2 ] || fail "advance did not update current_round"
[ "$(jq -r .status "$CODEX_GOALS_DIR/demo.spec.json")" = planned ] || fail "advance did not reset status"
[ "$(jq -r '.approved_story == null and .pending_question == null' "$CODEX_GOALS_DIR/demo.spec.json")" = true ] || fail "advance did not clear per-round state"
[ "$(jq -r '.branch_lineage | length' "$CODEX_GOALS_DIR/demo.spec.json")" = 1 ] || fail "advance lost lineage"
bash "$SCRIPT" advance demo 2
bash "$SCRIPT" set demo '.status="doing"'
if bash "$SCRIPT" advance demo 2 >/dev/null 2>&1; then fail "advance reset an active round"; fi
if bash "$SCRIPT" advance demo 4 >/dev/null 2>&1; then fail "advance accepted a skipped round"; fi
pass "advance is one-step, lineage-preserving, and retry-safe"

bash "$SCRIPT" set demo '.status="planned" | .counter=0'
pids=()
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  bash "$SCRIPT" set demo '.counter = (.counter + 1)' &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail "concurrent spec update failed"
done
[ "$(jq -r .counter "$CODEX_GOALS_DIR/demo.spec.json")" = 12 ] || fail "concurrent spec updates were lost"
pass "concurrent mirror updates serialize without lost writes"
