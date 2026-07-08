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
