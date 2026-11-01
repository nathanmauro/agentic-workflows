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
  mkdir -p "$TMP/repo-$name"
  bash "$SPEC" init "$name" "$TMP/repo-$name" production "echo ok" "$push_allowed" "$danger" main
  bash "$SPEC" set "$name" '.status="doing"' > /dev/null
}

assert_local_only() {
  local name="$1" round="$2" branch="$3"
  local out
  out="$(CURRENT_BRANCH="$branch" bash "$SCRIPT" "$name" "$round" "$branch")"
  case "$out" in
    LOCAL-ONLY:*) ;;
    *) fail "$name did not use LOCAL-ONLY fallback: $out" ;;
  esac
  [ "$(jq -r '.branch_lineage[-1].pr' "$CODEX_GOALS_DIR/$name.spec.json")" = "local-only" ] || fail "$name did not record local-only lineage"
  [ "$(jq -r '.branch_lineage[-1].status' "$CODEX_GOALS_DIR/$name.spec.json")" = "review" ] || fail "$name lineage status was not review"
}

export CODEX_GOALS_DIR="$TMP/goals"
export FAKE_REPO_ROOT="$TMP/fake-repo"
mkdir -p "$CODEX_GOALS_DIR" "$TMP/bin" "$FAKE_REPO_ROOT"

link_tool() {
  local tool="$1" path
  path="$(command -v "$tool")" || fail "required tool not found for fixture PATH: $tool"
  ln -sf "$path" "$TMP/bin/$tool"
}

for tool in bash jq mktemp mv dirname grep tr mkdir rmdir rm cat chmod; do
  link_tool "$tool"
done

cat > "$TMP/bin/git" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "rev-parse" ] && [ "${2:-}" = "--show-toplevel" ]; then echo "$FAKE_REPO_ROOT"; exit 0; fi
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "rev-parse" ] && [ "${4:-}" = "--show-toplevel" ]; then echo "$FAKE_REPO_ROOT"; exit 0; fi
if [ "${1:-}" = "symbolic-ref" ]; then echo "${CURRENT_BRANCH:-fleet/round-1-slice}"; exit 0; fi
if [ "${1:-}" = "rev-parse" ] && [ "${2:-}" = "HEAD" ]; then echo abc1234deadbeef00000000000000000000000000; exit 0; fi
if [ "${1:-}" = "rev-parse" ]; then echo "${BRANCH_COMMIT:-abc1234deadbeef00000000000000000000000000}"; exit 0; fi
if [ "${1:-}" = "merge-base" ] && [ "${2:-}" = "--is-ancestor" ]; then exit 0; fi
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

cat > "$TMP/bin/gh" << 'SH'
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
nopush_note="$(jq -r '.branch_lineage[-1].note' "$CODEX_GOALS_DIR/nopush.spec.json")"
case "$nopush_note" in
  *"git push -u origin fleet/round-1-nopush && gh pr create --draft --base main --head fleet/round-1-nopush"*) ;;
  *) fail "local-only hand-off does not push before gh pr create: $nopush_note" ;;
esac
pass "push_allowed=false never pushes"

# A later local-only round stacks on the unpushed previous slice, so the hand-off
# must push both branches and target the previous one.
make_spec stacklocal false ""
CURRENT_BRANCH=fleet/round-1-first bash "$SCRIPT" stacklocal 1 fleet/round-1-first > /dev/null
bash "$SPEC" set stacklocal '.current_round=2 | .status="doing"' > /dev/null
out="$(CURRENT_BRANCH=fleet/round-2-second bash "$SCRIPT" stacklocal 2 fleet/round-2-second)"
[ "$(jq -r '.branch_lineage[-1].base' "$CODEX_GOALS_DIR/stacklocal.spec.json")" = fleet/round-1-first ] \
  || fail "local-only slice did not stack on the previous local-only branch"
case "$out" in
  *"git push -u origin fleet/round-1-first fleet/round-2-second && gh pr create --draft --base fleet/round-1-first"*) ;;
  *) fail "stacked local-only hand-off is wrong: $out" ;;
esac
pass "local-only slices stack on the previous local-only branch"

make_spec public true "origin is PUBLIC"
assert_local_only public 1 "fleet/round-1-public"
pass "danger override never pushes"

rm -f "$TMP/bin/gh"
make_spec nogh true ""
assert_local_only nogh 1 "fleet/round-1-nogh"
pass "missing gh never pushes"

# Authoritative base selection: stack only on a still-open remote PR. A local
# ancestor from a merged/deleted round must fall back to the default branch.
export GIT_CALLS="$TMP/git-calls"
export GH_CALLS="$TMP/gh-calls"
cat > "$TMP/bin/git" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$GIT_CALLS"
if [ "${1:-}" = "rev-parse" ] && [ "${2:-}" = "--show-toplevel" ]; then echo "$FAKE_REPO_ROOT"; exit 0; fi
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "rev-parse" ] && [ "${4:-}" = "--show-toplevel" ]; then echo "${SPEC_REPO_ROOT:-$FAKE_REPO_ROOT}"; exit 0; fi
if [ "${1:-}" = "symbolic-ref" ]; then echo "${CURRENT_BRANCH:-fleet/round-2-next}"; exit 0; fi
case "${1:-} ${2:-}" in
  "remote get-url") echo git@example.test:owner/repo.git ;;
  "rev-parse --verify") exit 0 ;;
  "rev-parse HEAD") echo abc1234deadbeef00000000000000000000000000 ;;
  "rev-parse "*) echo "${BRANCH_COMMIT:-abc1234deadbeef00000000000000000000000000}" ;;
  "merge-base --is-ancestor") exit 0 ;;
  "ls-remote --exit-code") [ "${REMOTE_BASE_EXISTS:-1}" = 1 ] ;;
  "push origin") exit 0 ;;
  *) echo "unexpected git call: $*" >&2; exit 98 ;;
esac
SH
chmod +x "$TMP/bin/git"

cat > "$TMP/bin/gh" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr view")
    if [ -n "${REVOKE_DURING_PROBE:-}" ]; then
      tmp="${REVOKE_DURING_PROBE}.tmp"
      jq '.push_allowed=false' "$REVOKE_DURING_PROBE" > "$tmp"
      mv "$tmp" "$REVOKE_DURING_PROBE"
    fi
    jq -nc --arg state "${PREVIOUS_PR_STATE:-OPEN}" \
      --arg branch "${PREVIOUS_PR_BRANCH:-fleet/round-1-base}" \
      '{state:$state,headRefName:$branch}'
    ;;
  "pr create") echo https://example.test/pr/new ;;
  *) echo "unexpected gh call: $*" >&2; exit 97 ;;
esac
SH
chmod +x "$TMP/bin/gh"

add_previous_pr() {
  local name="$1" status="$2"
  bash "$SPEC" set "$name" \
    ".current_round=2 | .status=\"doing\" | .branch_lineage += [{round:1,branch:\"fleet/round-1-base\",base:\"main\",pr:\"https://example.test/pr/old\",commit:\"abc1234\",status:\"$status\",note:\"\"}]" \
    > /dev/null
}

reset_calls() {
  : > "$GIT_CALLS"
  : > "$GH_CALLS"
  export REMOTE_BASE_EXISTS=1
  export PREVIOUS_PR_STATE=OPEN
  export PREVIOUS_PR_BRANCH=fleet/round-1-base
  export CURRENT_BRANCH=fleet/round-2-next
  export BRANCH_COMMIT=abc1234deadbeef00000000000000000000000000
  unset SPEC_REPO_ROOT REVOKE_DURING_PROBE
}

reset_calls
make_spec openbase true "" > /dev/null
add_previous_pr openbase review
bash "$SCRIPT" openbase 2 fleet/round-2-next > /dev/null
grep -q '^pr create .*--base fleet/round-1-base ' "$GH_CALLS" || fail "open remote PR was not used as stacked base"
grep -q '^push origin abc1234deadbeef00000000000000000000000000:refs/heads/fleet/round-2-next$' "$GIT_CALLS" \
  || fail "push was not bound to the captured head SHA and fleet ref"
pass "an open remote ancestor PR remains the stacked base"

reset_calls
make_spec mergedbase true "" > /dev/null
add_previous_pr mergedbase "done"
export PREVIOUS_PR_STATE=MERGED
bash "$SCRIPT" mergedbase 2 fleet/round-2-next > /dev/null
grep -q '^pr create .*--base main ' "$GH_CALLS" || fail "merged PR branch was reused as base"
pass "a merged prior PR falls back to the default base"

reset_calls
make_spec deletedbase true "" > /dev/null
add_previous_pr deletedbase review
export REMOTE_BASE_EXISTS=0
bash "$SCRIPT" deletedbase 2 fleet/round-2-next > /dev/null
grep -q '^pr create .*--base main ' "$GH_CALLS" || fail "deleted remote branch was reused as base"
pass "a missing prior remote branch falls back to the default base"

reset_calls
make_spec revokedprobe true "" > /dev/null
add_previous_pr revokedprobe review
export REVOKE_DURING_PROBE="$CODEX_GOALS_DIR/revokedprobe.spec.json"
if bash "$SCRIPT" revokedprobe 2 fleet/round-2-next > /dev/null 2>&1; then
  fail "push proceeded after authority was revoked during remote probes"
fi
! grep -q '^push ' "$GIT_CALLS" || fail "revoked branch was pushed"
pass "push authority is revalidated immediately before mutation"

# The external push grant is scoped to this project, round, checked-out fleet
# branch, and exact HEAD. Invalid arguments must fail before git push or gh.
reset_calls
make_spec wrongprefix true "" > /dev/null
if CURRENT_BRANCH=main bash "$SCRIPT" wrongprefix 1 main > /dev/null 2>&1; then fail "non-fleet branch was accepted"; fi
! grep -q '^push ' "$GIT_CALLS" || fail "non-fleet branch was pushed"
pass "non-fleet branch is rejected before push"

reset_calls
make_spec wrongmirrorround true "" > /dev/null
if CURRENT_BRANCH=fleet/round-2-wrong bash "$SCRIPT" wrongmirrorround 2 fleet/round-2-wrong > /dev/null 2>&1; then fail "wrong mirror round was accepted"; fi
! grep -q '^push ' "$GIT_CALLS" || fail "wrong-round branch was pushed"
pass "mirror current_round must authorize the requested round"

reset_calls
make_spec wrongcheckout true "" > /dev/null
if CURRENT_BRANCH=fleet/round-1-other bash "$SCRIPT" wrongcheckout 1 fleet/round-1-requested > /dev/null 2>&1; then fail "non-checked-out branch was accepted"; fi
! grep -q '^push ' "$GIT_CALLS" || fail "non-checked-out branch was pushed"
pass "requested branch must be checked out"

reset_calls
make_spec wrongtip true "" > /dev/null
if CURRENT_BRANCH=fleet/round-1-wrongtip BRANCH_COMMIT=def5678deadbeef00000000000000000000000000 \
  bash "$SCRIPT" wrongtip 1 fleet/round-1-wrongtip > /dev/null 2>&1; then
  fail "branch tip different from HEAD was accepted"
fi
! grep -q '^push ' "$GIT_CALLS" || fail "mismatched branch tip was pushed"
pass "requested branch tip must equal HEAD"

reset_calls
make_spec wrongrepo true "" > /dev/null
mkdir -p "$TMP/other-repo"
if CURRENT_BRANCH=fleet/round-1-wrongrepo SPEC_REPO_ROOT="$TMP/other-repo" \
  bash "$SCRIPT" wrongrepo 1 fleet/round-1-wrongrepo > /dev/null 2>&1; then
  fail "wrong repository was accepted"
fi
! grep -q '^push ' "$GIT_CALLS" || fail "branch from the wrong repository was pushed"
pass "helper must run in the selected project worktree"
