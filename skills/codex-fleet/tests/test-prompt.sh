#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/fleet-prompt.sh"
SPEC="$ROOT/fleet-spec.sh"
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

# Two seeded mirrors: one production, one prototype with a long name + danger.
bash "$SPEC" init alpha "$TMP/alpha" production "npm test" true "" main >/dev/null
bash "$SPEC" init verylongprojectname "$TMP/vlpn" prototype "make check" false "origin is PUBLIC" main >/dev/null

cat > "$CODEX_GOALS_DIR/recon-round-1.json" <<'JSON'
[
  {
    "project": "alpha",
    "path": "/tmp/alpha",
    "tier": "production",
    "sliceSummary": "server emit + client reconnect + test",
    "nextTask": {
      "title": "Add SSE reconnect",
      "why": "PLAN.md calls it next.",
      "acceptanceCriteria": ["reconnects within 2s", "test added", "no regressions", "docs updated"],
      "keyFiles": ["server.ts"]
    }
  },
  {
    "project": "verylongprojectname",
    "path": "/tmp/vlpn",
    "tier": "prototype",
    "sliceSummary": "add a flag",
    "nextTask": {
      "title": "Add --json flag",
      "why": "README roadmap.",
      "acceptanceCriteria": ["flag parsed"],
      "keyFiles": ["cli.js"]
    }
  }
]
JSON

# ---- approval ----
OUT="$(bash "$SCRIPT" approval 1)"
printf '%s' "$OUT" | jq -e . >/dev/null || fail "approval did not emit valid JSON"
[ "$(printf '%s' "$OUT" | jq '[.batches[] | length] | max // 0')" -le 4 ] || fail "an approval batch exceeded 4 questions"
[ "$(printf '%s' "$OUT" | jq '[.batches[][]] | length')" -eq 2 ] || fail "expected exactly 2 approval questions"
[ "$(printf '%s' "$OUT" | jq '[.batches[][] | (.header | length)] | max')" -le 12 ] || fail "an approval header exceeded 12 chars (AskUserQuestion limit)"
if printf '%s' "$OUT" | jq -e '.batches[][] | select((.options | length) < 2 or (.options | length) > 4)' >/dev/null; then
  fail "an approval question had options outside the 2..4 range"
fi
if printf '%s' "$OUT" | jq -e '.batches[][] | .options[] | select((.label | length) == 0 or (.description | length) == 0)'  >/dev/null; then
  fail "an approval option had an empty label or description"
fi
if printf '%s' "$OUT" | jq -e '.batches[][] | select(.multiSelect != false)' >/dev/null; then
  fail "an approval question was multiSelect (should be single-select)"
fi
[ "$(printf '%s' "$OUT" | jq -r '.batches[0][0].options[0].label')" = "Approve (Recommended)" ] || fail "first approval option was not 'Approve (Recommended)'"
printf '%s' "$OUT" | jq -e '.batches[][] | select(.header == "alpha") | .options[] | select(.label == "Approve as prototype")' >/dev/null \
  || fail "alpha (production) is missing the one-tap tier-flip to prototype"
printf '%s' "$OUT" | jq -e '.batches[][] | select(.header == "alpha") | select((.question | test("alpha")) and (.question | test("Other")))' >/dev/null \
  || fail "alpha question is missing the project name or the freeform 'Other' affordance"
pass "approval builds native AskUserQuestion batches within all tool constraints"

# A skipped/decided project is not re-proposed.
bash "$SPEC" set alpha '.status="skipped"' >/dev/null
[ "$(bash "$SCRIPT" approval 1 | jq '[.batches[][]] | length')" -eq 1 ] || fail "approval re-proposed a non-planned project"
bash "$SPEC" set alpha '.status="planned"' >/dev/null
pass "approval only proposes projects still awaiting a decision (status=planned)"

# ---- clarify ----
cat > "$CODEX_GOALS_DIR/alpha.question.json" <<'JSON'
{ "status": "open", "round": 1, "question": "Use WebSocket or SSE?", "context": "Client needs live updates.", "options": ["WebSocket", "SSE", "Long-poll"] }
JSON
cat > "$CODEX_GOALS_DIR/verylongprojectname.question.json" <<'JSON'
{ "status": "answered", "round": 1, "question": "already answered", "context": "", "options": ["a", "b"] }
JSON

COUT="$(bash "$SCRIPT" clarify)"
printf '%s' "$COUT" | jq -e . >/dev/null || fail "clarify did not emit valid JSON"
[ "$(printf '%s' "$COUT" | jq '[.batches[][]] | length')" -eq 1 ] || fail "clarify did not exclude the answered question"
[ "$(printf '%s' "$COUT" | jq -r '.batches[0][0].header')" = "alpha" ] || fail "clarify built the wrong project header"
[ "$(printf '%s' "$COUT" | jq '.batches[0][0].options | length')" -eq 3 ] || fail "clarify did not map the 3 Codex options"
printf '%s' "$COUT" | jq -e '.batches[0][0] | select(.question | test("Other"))' >/dev/null || fail "clarify question is missing the freeform 'Other' affordance"
if printf '%s' "$COUT" | jq -e '.batches[][] | .options[] | select((.label | length) == 0 or (.description | length) == 0)' >/dev/null; then
  fail "a clarify option had an empty label or description"
fi
pass "clarify builds a native prompt from open question files and excludes answered ones"

# notified questions are still awaiting an answer -> still surfaced.
cat > "$CODEX_GOALS_DIR/alpha.question.json" <<'JSON'
{ "status": "notified", "round": 1, "question": "Proceed?", "context": "", "options": ["Yes", "No"] }
JSON
rm -f "$CODEX_GOALS_DIR/verylongprojectname.question.json"
[ "$(bash "$SCRIPT" clarify | jq '[.batches[][]] | length')" -eq 1 ] || fail "clarify did not surface a notified question"
pass "clarify surfaces notified (pushed, not-yet-answered) questions"

# Degenerate (<2) Codex option set is padded to satisfy AskUserQuestion's minimum.
cat > "$CODEX_GOALS_DIR/alpha.question.json" <<'JSON'
{ "status": "open", "round": 1, "question": "Proceed?", "context": "", "options": ["Yes"] }
JSON
[ "$(bash "$SCRIPT" clarify | jq '.batches[0][0].options | length')" -ge 2 ] || fail "clarify did not pad a <2 option set to the 2-option minimum"
pass "clarify pads degenerate (<2) option sets to satisfy the prompt minimum"
