#!/usr/bin/env bash
# Offline tests for the audit's own patterns and for prose-placeholders.py exit codes.
set -euo pipefail

# The require-denylist case below runs the audit, which runs this test; stop the recursion if
# that case ever regresses and the audit carries on.
if [ "${AUDIT_PUBLIC_SELFTEST:-0}" = "1" ]; then
  echo "audit tests skipped inside a nested audit"
  exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AUDIT="$ROOT/scripts/audit-public.sh"
PLACEHOLDERS="$ROOT/scripts/prose-placeholders.py"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# Read the pattern straight from the audit so this test cannot drift from what CI runs.
audit_pattern() {
  sed -n "s/^$1='\\(.*\\)'\$/\\1/p" "$AUDIT"
}

SECRET_RE="$(audit_pattern SECRET_DENYLIST_RE)"
if [ -z "$SECRET_RE" ]; then
  fail "could not read SECRET_DENYLIST_RE from the audit"
fi

expect_secret() {
  local label="$1"
  local want="$2"
  local text="$3"
  local got=clean
  if printf '%s\n' "$text" | rg -q -e "$SECRET_RE"; then
    got=flagged
  fi
  if [ "$got" = "$want" ]; then
    pass "$label is $want"
  else
    fail "$label: want $want, got $got"
  fi
}

# Words that merely contain the token prefix must not fail the audit.
expect_secret "task-runner" clean "run the task-runner first"
expect_secret "risk-based" clean "a risk-based review"
expect_secret "desk- prefix" clean "desk-check the output"

# Built at runtime so this file never holds a string the audit itself would flag.
fake_key="sk-$(printf 'x%.0s' {1..20})"
expect_secret "token-shaped key" flagged "key=$fake_key"
expect_secret "key at line start" flagged "$fake_key"
expect_secret "home path" flagged "$(printf '/%s/%s/notes' Users someone)"
expect_secret "bare home dir" flagged "$(printf 'cd /%s/%s' Users someone)"
expect_secret "linux home dir" flagged "$(printf 'path="/%s/%s"' home someone)"
expect_secret "personal email" flagged "$(printf '%s@%s.com' someone gmail)"
expect_secret "noreply email" clean "Co-maintained via noreply@example.test"

run_placeholders() {
  set +e
  python3 "$PLACEHOLDERS" "$@" > /dev/null 2>&1
  PLACEHOLDER_RC=$?
  set -e
}

expect_placeholder_rc() {
  local label="$1"
  local want="$2"
  shift 2
  run_placeholders "$@"
  if [ "$PLACEHOLDER_RC" -eq "$want" ]; then
    pass "$label (exit $want)"
  else
    fail "$label: want exit $want, got $PLACEHOLDER_RC"
  fi
}

printf 'Fill in the %s later.\n' '<value>' > "$TMP/match.md"
printf 'Nothing to see; `<repo>` is code.\n' > "$TMP/clean.md"
printf 'hello \xff there\n' > "$TMP/bad-bytes.md"

expect_placeholder_rc "placeholder found" 0 "$TMP/match.md"
expect_placeholder_rc "clean prose" 1 "$TMP/clean.md"
expect_placeholder_rc "missing root is an error" 2 "$TMP/missing-dir"
expect_placeholder_rc "invalid utf-8 is an error" 2 "$TMP/bad-bytes.md"

set +e
AUDIT_PUBLIC_SELFTEST=1 \
  AUDIT_PRIVATE_DENYLIST="$TMP/missing-denylist" \
  AUDIT_REQUIRE_LOCAL_DENYLIST=1 \
  bash "$AUDIT" > /dev/null 2> "$TMP/require.err"
require_rc=$?
set -e
# Assert the reason too: any unrelated audit failure also exits 1.
if [ "$require_rc" -eq 1 ] \
  && grep -q 'local private denylist .* is missing or empty' "$TMP/require.err"; then
  pass "required local denylist missing fails the audit"
else
  fail "required local denylist missing: audit exited $require_rc"
fi

if [ "$failures" -ne 0 ]; then
  echo "audit tests: $failures failure(s)" >&2
  exit 1
fi
echo "audit tests ok"
