#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="$ROOT/fleet-results.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

export CODEX_GOALS_DIR="$TMP/goals"
mkdir -p "$CODEX_GOALS_DIR"

pids=()
i=1
while [ "$i" -le 20 ]; do
  bash "$RESULTS" upsert 1 "project-$i" "fleet/round-1-$i" "commit-$i" "note-$i" review &
  pids+=("$!")
  i=$((i + 1))
done
for pid in "${pids[@]}"; do wait "$pid"; done

[ "$(wc -l < "$CODEX_GOALS_DIR/results.tsv" | tr -d ' ')" -eq 21 ] \
  || fail "concurrent distinct rows were lost"
awk -F '\t' 'NF != 6 { exit 1 }' "$CODEX_GOALS_DIR/results.tsv" \
  || fail "concurrent output contains malformed TSV rows"
pass "concurrent distinct-project upserts preserve every row"

pids=()
i=1
while [ "$i" -le 12 ]; do
  bash "$RESULTS" upsert 2 shared "branch-$i" "commit-$i" "note-$i" "status-$i" &
  pids+=("$!")
  i=$((i + 1))
done
for pid in "${pids[@]}"; do wait "$pid"; done

[ "$(awk -F '\t' '$1 == 2 && $2 == "shared" { count++ } END { print count+0 }' "$CODEX_GOALS_DIR/results.tsv")" -eq 1 ] \
  || fail "same-key upserts produced duplicates"
shared_row="$(awk -F '\t' '$1 == 2 && $2 == "shared" { print $0 }' "$CODEX_GOALS_DIR/results.tsv")"
shared_n="$(printf '%s' "$shared_row" | awk -F '\t' '{ sub(/^branch-/, "", $3); print $3 }')"
printf '%s' "$shared_row" | awk -F '\t' -v n="$shared_n" \
  '$3 == "branch-" n && $4 == "commit-" n && $5 == "note-" n && $6 == "status-" n { ok=1 } END { exit !ok }' \
  || fail "same-key winner was assembled from multiple writers"
pass "same-key races leave one complete winning row"

printf '2\tshared\tstale-branch\tstale-commit\tstale-note\tstale-status\n' >> "$CODEX_GOALS_DIR/results.tsv"
bash "$RESULTS" upsert 2 shared repaired-branch repaired-commit repaired-note repaired-status
[ "$(awk -F '\t' '$1 == 2 && $2 == "shared" { count++ } END { print count+0 }' "$CODEX_GOALS_DIR/results.tsv")" -eq 1 ] \
  || fail "upsert preserved pre-existing duplicate keys"
grep -q $'^2\tshared\trepaired-branch\trepaired-commit\trepaired-note\trepaired-status$' "$CODEX_GOALS_DIR/results.tsv" \
  || fail "duplicate repair did not preserve the new complete row"
pass "upsert repairs pre-existing duplicate keys"

bash "$RESULTS" upsert 3 sanitized branch commit $'line one\tline two\nline three' review
awk -F '\t' '$1 == 3 && $2 == "sanitized" && NF == 6 && $5 == "line one line two line three" { ok=1 } END { exit !ok }' \
  "$CODEX_GOALS_DIR/results.tsv" || fail "tabs/newlines were not sanitized"
pass "TSV fields cannot inject rows or columns"
