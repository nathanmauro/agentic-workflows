#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/fleet-state.sh"
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

seed_run() {
  local run="$1"
  mkdir -p "$run"
  printf 'ROUND=1\nTOTAL_ROUNDS=3\nMODE=PLAN\nPHASE=REVIEW\nFLEET_SKILL_DIR=/tmp/fleet\\ skill\nCUSTOM=keep-me\n' > "$run/state.env"
  printf '[{"name":"alpha"},{"name":"beta"}]\n' > "$run/projects.json"
  printf '{"project":"alpha","current_round":2,"status":"planned"}\n' > "$run/alpha.spec.json"
  printf '{"project":"beta","current_round":2,"status":"planned"}\n' > "$run/beta.spec.json"
}

hash_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

RUN="$TMP/success"
seed_run "$RUN"
CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2
[ "$(awk -F= '$1 == "ROUND" { print $2 }' "$RUN/state.env")" = 2 ] || fail "global round was not advanced"
[ "$(awk -F= '$1 == "PHASE" { print $2 }' "$RUN/state.env")" = RECON ] || fail "global phase was not reset"
grep -qx 'MODE=PLAN' "$RUN/state.env" || fail "mode was not preserved"
grep -qx 'FLEET_SKILL_DIR=/tmp/fleet\\ skill' "$RUN/state.env" || fail "escaped state value was not preserved"
grep -qx 'CUSTOM=keep-me' "$RUN/state.env" || fail "custom state key was not preserved"
pass "complete mirrors transition global state while preserving other keys"

before="$(hash_file "$RUN/state.env")"
CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "successful retry rewrote state"
pass "successful transition is idempotent"

RUN="$TMP/concurrent"
seed_run "$RUN"
CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 > "$TMP/transition-one.log" &
pid_one=$!
CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 > "$TMP/transition-two.log" &
pid_two=$!
wait "$pid_one" || fail "first concurrent transition failed"
wait "$pid_two" || fail "second concurrent transition failed"
[ "$(grep -c '^ROUND=2$' "$RUN/state.env")" -eq 1 ] || fail "concurrent transition corrupted ROUND"
[ "$(grep -c '^PHASE=RECON$' "$RUN/state.env")" -eq 1 ] || fail "concurrent transition corrupted PHASE"
pass "run-scoped lock serializes concurrent retry"

RUN="$TMP/partial"
seed_run "$RUN"
printf '{"project":"beta","current_round":1,"status":"review"}\n' > "$RUN/beta.spec.json"
before="$(hash_file "$RUN/state.env")"
if CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "partial mirror advance was accepted"
fi
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "partial mirror failure changed global state"
pass "partial mirror advance fails closed"

RUN="$TMP/pending-merge"
seed_run "$RUN"
printf '%s\n' '{"project":"alpha","current_round":2,"status":"planned","branch_lineage":[{"round":1,"status":"review","merge_state":"pending"}]}' > "$RUN/alpha.spec.json"
before="$(hash_file "$RUN/state.env")"
if CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "pending merge allowed the global round to advance"
fi
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "pending merge failure changed global state"
pass "pending queue merge holds the global REVIEW state"

RUN="$TMP/submitting-merge"
seed_run "$RUN"
printf '%s\n' '{"project":"alpha","current_round":2,"status":"planned","branch_lineage":[{"round":1,"status":"review","merge_state":"submitting"}]}' > "$RUN/alpha.spec.json"
before="$(hash_file "$RUN/state.env")"
if CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "write-ahead merge submission allowed the global round to advance"
fi
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "submitting merge failure changed global state"
pass "write-ahead merge submission holds the global REVIEW state"

RUN="$TMP/inconsistent"
seed_run "$RUN"
printf 'ROUND=1\nROUND=2\nTOTAL_ROUNDS=3\nMODE=PLAN\nPHASE=REVIEW\n' > "$RUN/state.env"
before="$(hash_file "$RUN/state.env")"
if CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "duplicate global state key was accepted"
fi
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "inconsistent state failure changed state.env"

seed_run "$RUN"
sed 's/PHASE=REVIEW/PHASE=RUNNING/' "$RUN/state.env" > "$RUN/state.env.next"
mv "$RUN/state.env.next" "$RUN/state.env"
if CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "wrong global phase was accepted"
fi
pass "duplicate keys and wrong phase fail closed"

RUN="$TMP/crash"
seed_run "$RUN"
before="$(hash_file "$RUN/state.env")"
mkdir -p "$TMP/fail-bin"
printf '%s\n' '#!/usr/bin/env bash' "kill -TERM \"\$PPID\"" 'exit 97' > "$TMP/fail-bin/mv"
chmod +x "$TMP/fail-bin/mv"
if PATH="$TMP/fail-bin:$PATH" CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null 2>&1; then
  fail "injected pre-rename crash unexpectedly succeeded"
fi
[ "$(hash_file "$RUN/state.env")" = "$before" ] || fail "pre-rename crash exposed a partial state file"
[ ! -e "$RUN/fleet-state.lock" ] || fail "pre-rename crash leaked the state lock"
if find "$RUN" -maxdepth 1 -name 'state.env.*' -print -quit | grep -q .; then
  fail "pre-rename crash leaked a temporary state file"
fi
pass "pre-rename crash leaves the original state intact and retryable"

CODEX_GOALS_DIR="$RUN" bash "$SCRIPT" 1 2 >/dev/null
[ "$(awk -F= '$1 == "ROUND" { print $2 }' "$RUN/state.env")" = 2 ] || fail "retry after pre-rename crash did not advance"
pass "transition recovers after an interrupted atomic rewrite"
