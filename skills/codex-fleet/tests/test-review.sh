#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/fleet-spec.sh"
REVIEW="$ROOT/fleet-review.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export CODEX_GOALS_DIR="$TMP/goals"
mkdir -p "$CODEX_GOALS_DIR"

seed_review() {
  local name="$1"
  bash "$SPEC" init "$name" "$TMP/$name" production "echo ok" false "" main >/dev/null
  bash "$SPEC" set "$name" \
    '.status="review" | .branch_lineage=[{round:1,branch:"fleet/round-1-one",base:"main",pr:"local-only",commit:"abc1234",status:"review",note:""}]' \
    >/dev/null
}

seed_review current
bash "$REVIEW" current 1 >/dev/null
[ "$(jq -r .status "$CODEX_GOALS_DIR/current.spec.json")" = "done" ] || fail "current-round ack did not close project"
[ "$(jq -r '.branch_lineage[0].status' "$CODEX_GOALS_DIR/current.spec.json")" = "done" ] || fail "current-round lineage not acknowledged"
echo "PASS: current-round acknowledgement closes project and lineage"

seed_review late
bash "$SPEC" advance late 2 >/dev/null
bash "$SPEC" set late '.status="doing"' >/dev/null
bash "$REVIEW" late 1 >/dev/null
[ "$(jq -r .status "$CODEX_GOALS_DIR/late.spec.json")" = doing ] || fail "late ack clobbered active round status"
[ "$(jq -r '.branch_lineage[0].status' "$CODEX_GOALS_DIR/late.spec.json")" = "done" ] || fail "late lineage was not acknowledged"
if bash "$REVIEW" late 1 >/dev/null 2>&1; then fail "completed lineage accepted twice"; fi
if bash "$REVIEW" late 3 >/dev/null 2>&1; then fail "future round acknowledgement succeeded"; fi
echo "PASS: delayed acknowledgement updates only its lineage and is not repeatable"
