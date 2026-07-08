#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/fleet-spec.sh"
SCRIPT="$ROOT/fleet-open-pr.sh"
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

make_spec() {
  local name="$1" push_allowed="$2" danger="$3"
  bash "$SPEC" init "$name" "$TMP/repo-$name" production "echo ok" "$push_allowed" "$danger" main
}

assert_local_only() {
  local name="$1" round="$2" branch="$3"
  local out
  out="$(bash "$SCRIPT" "$name" "$round" "$branch")"
  case "$out" in
    LOCAL-ONLY:*) ;;
    *) fail "$name did not use LOCAL-ONLY fallback: $out" ;;
  esac
  [ "$(jq -r '.branch_lineage[-1].pr' "$CODEX_GOALS_DIR/$name.spec.json")" = "local-only" ] || fail "$name did not record local-only lineage"
  [ "$(jq -r '.branch_lineage[-1].status' "$CODEX_GOALS_DIR/$name.spec.json")" = "review" ] || fail "$name lineage status was not review"
}

export CODEX_GOALS_DIR="$TMP/goals"
mkdir -p "$CODEX_GOALS_DIR" "$TMP/bin"

link_tool() {
  local tool="$1" path
  path="$(command -v "$tool")" || fail "required tool not found for fixture PATH: $tool"
  ln -sf "$path" "$TMP/bin/$tool"
}

for tool in bash jq mktemp mv dirname grep tr mkdir rm; do
  link_tool "$tool"
done

cat > "$TMP/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "push" ]; then
  echo "FAIL: git push was attempted" >&2
  exit 99
fi
if [ "${1:-}" = "remote" ] && [ "${2:-}" = "get-url" ] && [ "${3:-}" = "origin" ]; then
  echo "origin should not be queried for fail-closed local-only cases" >&2
  exit 2
fi
echo "unexpected git call: $*" >&2
exit 98
SH
chmod +x "$TMP/bin/git"

cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "FAIL: gh was called" >&2
exit 97
SH
chmod +x "$TMP/bin/gh"

PATH="$TMP/bin"
export PATH

make_spec nopush false ""
assert_local_only nopush 1 "fleet/round-1-nopush"
pass "push_allowed=false never pushes"

make_spec public true "origin is PUBLIC"
assert_local_only public 1 "fleet/round-1-public"
pass "danger override never pushes"

rm -f "$TMP/bin/gh"
make_spec nogh true ""
assert_local_only nogh 1 "fleet/round-1-nogh"
pass "missing gh never pushes"
