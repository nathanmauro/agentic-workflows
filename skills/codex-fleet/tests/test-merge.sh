#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/fleet-spec.sh"
MERGE="$ROOT/fleet-merge.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "PASS: $*"; }

export CODEX_GOALS_DIR="$TMP/goals"
mkdir -p "$CODEX_GOALS_DIR" "$TMP/bin"
printf 'ROUND=1\nTOTAL_ROUNDS=1\nMODE=FULL_AUTO\nPHASE=REVIEW\n' > "$CODEX_GOALS_DIR/state.env"

make_spec() {
  bash "$SPEC" init "$1" "$TMP/repo-$1" production "echo ok" "$2" "$3" main > /dev/null
}

add_pr() {
  local entry
  entry="$(jq -nc --argjson round "$2" --arg pr "$3" --arg base "${4:-main}" \
    '{round:$round,branch:("fleet/round-"+($round|tostring)+"-slice"),base:$base,pr:$pr,commit:"abc1234",status:"review",note:""}')"
  bash "$SPEC" set "$1" ".status=\"review\" | .branch_lineage += [$entry]" > /dev/null
}

link_tool() {
  local path
  path="$(command -v "$1")" || fail "missing fixture tool: $1"
  ln -sf "$path" "$TMP/bin/$1"
}

for tool in bash jq mktemp mv dirname grep tr mkdir rmdir rm awk cat chmod head tail cut date sleep sed; do
  link_tool "$tool"
done

cat > "$TMP/bin/git" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "rev-parse" ] && [ "${4:-}" = "--is-inside-work-tree" ]; then
  echo true
  exit 0
fi
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "remote" ] && [ "${4:-}" = "get-url" ] && [ "${5:-}" = "origin" ]; then
  echo https://example.test/owner/repo.git
  exit 0
fi
echo "unexpected git call: $*" >&2
exit 98
SH
chmod +x "$TMP/bin/git"

install_gh_stub() {
  cat > "$TMP/bin/gh" << 'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$GH_CALLS"
case "$1 $2" in
  "pr view")
    if [ -f "$GH_MERGE_CALLED" ] && [ "${GH_FAIL_POST_SUBMIT_VIEW:-false}" = true ]; then
      exit 1
    fi
    draft="${GH_PR_DRAFT:-true}"
    [ -f "$GH_READY" ] && draft=false
    state="${GH_PR_STATE:-OPEN}"
    if [ -f "$GH_MERGE_CALLED" ]; then state="${GH_PR_POST_MERGE_STATE:-MERGED}"; fi
    merged_at=""
    [ "$state" = "MERGED" ] && merged_at="2026-07-22T20:00:00Z"
    jq -nc \
      --arg state "$state" \
      --argjson draft "$draft" \
      --arg head "${GH_PR_HEAD:-abc1234deadbeef00000000000000000000000000}" \
      --arg branch "${GH_PR_BRANCH:-fleet/round-1-slice}" \
      --arg base "${GH_PR_BASE:-main}" \
      --arg url "${GH_PR_URL:-https://example.test/owner/repo/pull/1}" \
      --arg merged_at "$merged_at" \
      --argjson auto "${GH_PR_AUTO_MERGE:-false}" \
      '{state:$state,isDraft:$draft,headRefOid:$head,headRefName:$branch,baseRefName:$base,url:$url,mergedAt:(if $merged_at == "" then null else $merged_at end),autoMergeRequest:(if $auto then {mergeMethod:"SQUASH"} else null end)}'
    ;;
  "pr checks")
    count=0
    [ -f "$GH_COUNTER" ] && count="$(cat "$GH_COUNTER")"
    count=$((count + 1))
    echo "$count" > "$GH_COUNTER"
    if [ "$count" -eq 1 ] && [ -n "${GH_SPEC_TO_REVOKE:-}" ]; then
      tmp="${GH_SPEC_TO_REVOKE}.tmp"
      jq '.push_allowed=false' "$GH_SPEC_TO_REVOKE" > "$tmp"
      mv "$tmp" "$GH_SPEC_TO_REVOKE"
    fi
    pending=0
    [ -f "$GH_PENDING" ] && pending="$(cat "$GH_PENDING")"
    if [ "$count" -le "$pending" ]; then
      echo "check pending"
      exit 8
    fi
    rc=0
    [ -f "$GH_RC" ] && rc="$(cat "$GH_RC")"
    [ -f "$GH_OUT" ] && cat "$GH_OUT"
    exit "$rc"
    ;;
  "pr ready") : > "$GH_READY" ;;
  "pr merge")
    if [ -n "${GH_MERGE_REJECT:-}" ]; then
      echo "$GH_MERGE_REJECT" >&2
      exit 1
    fi
    : > "$GH_MERGE_CALLED"
    ;;
  *) echo "unexpected gh call: $*" >&2; exit 97 ;;
esac
SH
  chmod +x "$TMP/bin/gh"
}

export GH_CALLS="$TMP/gh-calls"
export GH_COUNTER="$TMP/gh-counter"
export GH_PENDING="$TMP/gh-pending"
export GH_RC="$TMP/gh-rc"
export GH_OUT="$TMP/gh-out"
export GH_READY="$TMP/gh-ready"
export GH_MERGE_CALLED="$TMP/gh-merge-called"
install_gh_stub
PATH="$TMP/bin"
export PATH

reset_gh() {
  : > "$GH_CALLS"
  rm -f "$GH_COUNTER" "$GH_PENDING" "$GH_RC" "$GH_OUT" "$GH_READY" "$GH_MERGE_CALLED"
  export GH_PR_STATE=OPEN
  export GH_PR_DRAFT=true
  export GH_PR_HEAD=abc1234deadbeef00000000000000000000000000
  export GH_PR_BRANCH=fleet/round-1-slice
  export GH_PR_BASE=main
  export GH_PR_URL=https://example.test/owner/repo/pull/1
  unset GH_PR_POST_MERGE_STATE GH_SPEC_TO_REVOKE GH_FAIL_POST_SUBMIT_VIEW GH_MERGE_REJECT
  unset GH_PR_AUTO_MERGE
}

assert_no_merge() {
  ! grep -q '^pr merge ' "$GH_CALLS" || fail "merge was called: $(cat "$GH_CALLS")"
}

# The helper itself enforces the explicit FULL_AUTO trust boundary.
reset_gh
make_spec wrongmode true ""
add_pr wrongmode 1 https://example.test/pr/1
sed -i.bak 's/MODE=FULL_AUTO/MODE=DO/' "$CODEX_GOALS_DIR/state.env"
out="$(bash "$MERGE" wrongmode 1)"
case "$out" in NOOP:*"not FULL_AUTO"*) ;; *) fail "mode gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called outside FULL_AUTO"
mv "$CODEX_GOALS_DIR/state.env.bak" "$CODEX_GOALS_DIR/state.env"
pass "PLAN/DO cannot call the merge path"

reset_gh
make_spec wrongphase true ""
add_pr wrongphase 1 https://example.test/pr/phase
sed -i.bak 's/PHASE=REVIEW/PHASE=RUNNING/' "$CODEX_GOALS_DIR/state.env"
out="$(bash "$MERGE" wrongphase 1)"
case "$out" in NOOP:*"not REVIEW"*) ;; *) fail "phase gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called outside REVIEW"
mv "$CODEX_GOALS_DIR/state.env.bak" "$CODEX_GOALS_DIR/state.env"
pass "FULL_AUTO cannot merge before REVIEW"

reset_gh
make_spec wrongcurrentround true ""
add_pr wrongcurrentround 1 https://example.test/pr/current-round
sed -i.bak 's/ROUND=1/ROUND=2/' "$CODEX_GOALS_DIR/state.env"
out="$(bash "$MERGE" wrongcurrentround 1)"
case "$out" in NOOP:*"current round"*) ;; *) fail "current round gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called for a non-current round"
mv "$CODEX_GOALS_DIR/state.env.bak" "$CODEX_GOALS_DIR/state.env"
pass "only the global current round can merge"

reset_gh
make_spec blocked false ""
add_pr blocked 1 https://example.test/pr/2
out="$(bash "$MERGE" blocked 1)"
case "$out" in NOOP:*"push not allowed"*) ;; *) fail "push gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called when push was blocked"
pass "push gate fails closed"

reset_gh
make_spec danger true "origin is PUBLIC"
add_pr danger 1 https://example.test/pr/3
out="$(bash "$MERGE" danger 1)"
case "$out" in NOOP:*"danger hint"*) ;; *) fail "danger gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called for danger-marked repo"
pass "danger hints fail closed"

reset_gh
make_spec wronground true ""
add_pr wronground 1 https://example.test/pr/4
sed -i.bak 's/ROUND=1/ROUND=2/' "$CODEX_GOALS_DIR/state.env"
bash "$SPEC" set wronground '.current_round=2' > /dev/null
out="$(bash "$MERGE" wronground 2)"
case "$out" in NOOP:*"round 2"*) ;; *) fail "round selection: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called for missing round lineage"
mv "$CODEX_GOALS_DIR/state.env.bak" "$CODEX_GOALS_DIR/state.env"
pass "only the requested round can merge"

reset_gh
make_spec staleround true ""
add_pr staleround 1 https://example.test/owner/repo/pull/stale-1
add_pr staleround 2 https://example.test/owner/repo/pull/stale-2
out="$(bash "$MERGE" staleround 1)"
case "$out" in NOOP:*"no PR for round 1"*) ;; *) fail "stale-round lineage: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called for a stale-round lineage"
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/staleround.spec.json")" = review ] || fail "stale-round status"
pass "stale-round lineage is a no-op"

reset_gh
make_spec wrongstatus true ""
add_pr wrongstatus 1 https://example.test/pr/status
bash "$SPEC" set wrongstatus '.status="doing"' > /dev/null
out="$(bash "$MERGE" wrongstatus 1)"
case "$out" in NOOP:*"project status"*) ;; *) fail "project status gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called before project entered review"
pass "the mirror must be in review before merge"

reset_gh
make_spec wronghead true ""
add_pr wronghead 1 https://example.test/pr/head
export GH_PR_HEAD=def5678deadbeef00000000000000000000000000
out="$(bash "$MERGE" wronghead 1)"
case "$out" in NOOP:*"head commit"*) ;; *) fail "head gate: $out" ;; esac
assert_no_merge
! grep -q '^pr ready ' "$GH_CALLS" || fail "mismatched head was marked ready"
pass "recorded PR head must match before readiness or merge"

reset_gh
make_spec wrongbase true ""
add_pr wrongbase 1 https://example.test/pr/base
export GH_PR_BASE=develop
out="$(bash "$MERGE" wrongbase 1)"
case "$out" in NOOP:*"PR base"*) ;; *) fail "base gate: $out" ;; esac
assert_no_merge
pass "recorded PR base must match"

# FULL_AUTO can leave round N-1 open, so round N stacks on its branch. Squashing
# into that branch would land nothing on main yet record the slice as merged.
reset_gh
make_spec stacked true ""
add_pr stacked 1 https://example.test/owner/repo/pull/stacked fleet/round-0-prior
export GH_PR_BASE=fleet/round-0-prior
out="$(bash "$MERGE" stacked 1)"
case "$out" in NOOP:*"stacked on fleet/round-0-prior"*) ;; *) fail "stacked base gate: $out" ;; esac
[ ! -s "$GH_CALLS" ] || fail "gh called for a slice stacked on an open fleet branch"
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/stacked.spec.json")" = review ] || fail "stacked status"
pass "a slice stacked on another fleet branch never auto-merges"

reset_gh
make_spec wrongrepo true ""
add_pr wrongrepo 1 https://example.test/other/repo/pull/1
export GH_PR_URL=https://example.test/other/repo/pull/1
out="$(bash "$MERGE" wrongrepo 1)"
case "$out" in NOOP:*"repository"*) ;; *) fail "repository gate: $out" ;; esac
assert_no_merge
! grep -q '^pr ready ' "$GH_CALLS" || fail "wrong-repository PR was marked ready"
pass "recorded PR must belong to the selected project origin"

reset_gh
make_spec red true ""
add_pr red 1 https://example.test/pr/5
echo 1 > "$GH_RC"
echo "failing-test failed" > "$GH_OUT"
out="$(bash "$MERGE" red 1)"
case "$out" in CHECKS-FAILED:*) ;; *) fail "red checks: $out" ;; esac
assert_no_merge
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/red.spec.json")" = review ] || fail "red status"
pass "failed checks stay in review"

reset_gh
make_spec revoked true ""
add_pr revoked 1 https://example.test/owner/repo/pull/revoked
export GH_SPEC_TO_REVOKE="$CODEX_GOALS_DIR/revoked.spec.json"
out="$(bash "$MERGE" revoked 1)"
case "$out" in NOOP:*"push not allowed"*) ;; *) fail "mid-poll revocation gate: $out" ;; esac
assert_no_merge
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/revoked.spec.json")" = review ] || fail "revoked status"
pass "authority is re-read after checks before merge"

reset_gh
make_spec green true ""
add_pr green 1 https://example.test/pr/6
out="$(bash "$MERGE" green 1)"
case "$out" in MERGED:*"auto-merged"*) ;; *) fail "green merge: $out" ;; esac
grep -q '^pr ready ' "$GH_CALLS" || fail "draft was not marked ready"
grep -q '^pr merge .*--squash.*--match-head-commit abc1234deadbeef' "$GH_CALLS" || fail "expected squash merge bound to head"
! grep -q -- '--delete-branch' "$GH_CALLS" || fail "queue-incompatible branch deletion was requested"
ready_line="$(grep -n '^pr ready ' "$GH_CALLS" | cut -d: -f1)"
checks_line="$(grep -n '^pr checks ' "$GH_CALLS" | head -n 1 | cut -d: -f1)"
[ "$ready_line" -lt "$checks_line" ] || fail "checks were polled before draft readiness"
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/green.spec.json")" = "done" ] || fail "green status"
pass "draft readiness precedes checks and green checks merge the bound head"

reset_gh
make_spec alreadyready true ""
add_pr alreadyready 1 https://example.test/pr/ready
export GH_PR_DRAFT=false
out="$(bash "$MERGE" alreadyready 1)"
case "$out" in MERGED:*) ;; *) fail "already-ready merge: $out" ;; esac
! grep -q '^pr ready ' "$GH_CALLS" || fail "already-ready PR retried gh pr ready"
grep -q '^pr merge ' "$GH_CALLS" || fail "already-ready PR was not merged"
pass "already-ready retries skip the draft transition"

reset_gh
make_spec queued true ""
add_pr queued 1 https://example.test/owner/repo/pull/queued
export GH_PR_POST_MERGE_STATE=OPEN
out="$(FLEET_MERGE_CONFIRM_TIMEOUT=0 bash "$MERGE" queued 1)"
case "$out" in MERGE-PENDING:*) ;; *) fail "queued merge: $out" ;; esac
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/queued.spec.json")" = review ] || fail "queued merge was marked done"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$CODEX_GOALS_DIR/queued.spec.json")" = pending ] || fail "queued merge did not persist pending state"
grep -q '^pr merge ' "$GH_CALLS" || fail "queued merge was not submitted"
unset GH_PR_POST_MERGE_STATE
out="$(bash "$MERGE" queued 1)"
case "$out" in MERGED:*"confirmed"*) ;; *) fail "queued completion: $out" ;; esac
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 1 ] || fail "already-merged PR was submitted twice"
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/queued.spec.json")" = "done" ] || fail "confirmed queued merge not marked done"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$CODEX_GOALS_DIR/queued.spec.json")" = merged ] || fail "confirmed queued merge state not recorded"
pass "queue submission stays in review until GitHub confirms MERGED"

reset_gh
make_spec transientview true ""
add_pr transientview 1 https://example.test/owner/repo/pull/transient
export GH_FAIL_POST_SUBMIT_VIEW=true
out="$(FLEET_MERGE_CONFIRM_TIMEOUT=0 bash "$MERGE" transientview 1)"
case "$out" in NOOP:*"unable to inspect PR"*) ;; *) fail "post-submit transient read: $out" ;; esac
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/transientview.spec.json")" = review ] || fail "transient read changed review status"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$CODEX_GOALS_DIR/transientview.spec.json")" = submitting ] || fail "write-ahead submitting state was not preserved"
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 1 ] || fail "transient case did not submit exactly once"
unset GH_FAIL_POST_SUBMIT_VIEW
out="$(bash "$MERGE" transientview 1)"
case "$out" in MERGED:*"confirmed"*) ;; *) fail "transient retry confirmation: $out" ;; esac
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 1 ] || fail "confirmed transient submission was retried"
pass "write-ahead state survives a transient post-submit read failure"

reset_gh
make_spec pending true ""
add_pr pending 1 https://example.test/pr/7
echo 2 > "$GH_PENDING"
out="$(FLEET_MERGE_POLL_INTERVAL=0 bash "$MERGE" pending 1)"
case "$out" in MERGED:*) ;; *) fail "pending then green: $out" ;; esac
[ "$(grep -c '^pr checks ' "$GH_CALLS")" -eq 3 ] || fail "bounded poll count"
pass "pending checks are polled until green"

reset_gh
make_spec timeout true ""
add_pr timeout 1 https://example.test/pr/8
echo 999 > "$GH_PENDING"
out="$(FLEET_MERGE_CHECKS_TIMEOUT=0 FLEET_MERGE_POLL_INTERVAL=0 bash "$MERGE" timeout 1)"
case "$out" in CHECKS-TIMEOUT:*) ;; *) fail "timeout: $out" ;; esac
assert_no_merge
[ "$(jq -r '.status' "$CODEX_GOALS_DIR/timeout.spec.json")" = review ] || fail "timeout status"
pass "pending checks time out and stay in review"

reset_gh
make_spec nochecks true ""
add_pr nochecks 1 https://example.test/pr/9
echo 1 > "$GH_RC"
echo "no checks reported" > "$GH_OUT"
out="$(FLEET_MERGE_CHECK_REGISTRATION_GRACE=0 bash "$MERGE" nochecks 1)"
case "$out" in MERGED:*"without CI checks"*) ;; *) fail "no checks: $out" ;; esac
pass "an explicit no-checks result merges with a visible note"

reset_gh
make_spec rejected true ""
add_pr rejected 1 https://example.test/owner/repo/pull/rejected
export GH_MERGE_REJECT="GraphQL: At least 1 approving review is required (mergePullRequest)"
out="$(bash "$MERGE" rejected 1)"
case "$out" in NOOP:*"merge rejected"*"approving review"*) ;; *) fail "rejected merge: $out" ;; esac
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 1 ] || fail "rejected merge was not submitted once"
rejected_spec="$CODEX_GOALS_DIR/rejected.spec.json"
[ "$(jq -r '.status' "$rejected_spec")" = review ] || fail "rejected merge left review"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$rejected_spec")" = rejected ] \
  || fail "rejected merge kept the submitting hold"
grep -q 'merge rejected' "$CODEX_GOALS_DIR/results.tsv" || fail "rejected merge missing from the ledger"
pass "a rejected merge clears the submitting hold and stays in review"

unset GH_MERGE_REJECT
out="$(bash "$MERGE" rejected 1)"
case "$out" in NOOP:*"previously rejected"*) ;; *) fail "rejected retry: $out" ;; esac
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 1 ] || fail "a rejected merge was re-submitted"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$rejected_spec")" = rejected ] \
  || fail "a later tick overwrote the rejected state"
export GH_PR_STATE=MERGED
out="$(bash "$MERGE" rejected 1)"
case "$out" in MERGED:*) ;; *) fail "manual merge after rejection: $out" ;; esac
[ "$(jq -r '.status' "$rejected_spec")" = done ] || fail "manual merge after rejection not recorded"
pass "a rejection sticks for the round and a later manual merge is still recorded"

reset_gh
make_spec flaky true ""
add_pr flaky 1 https://example.test/owner/repo/pull/flaky
export GH_MERGE_REJECT="HTTP 502: Bad Gateway (https://api.github.com/graphql)"
set +e
out="$(bash "$MERGE" flaky 1 2> "$TMP/flaky-err")"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "transient merge failure exited zero: $out"
grep -q 'stays submitting' "$TMP/flaky-err" || fail "transient merge failure message: $(cat "$TMP/flaky-err")"
flaky_spec="$CODEX_GOALS_DIR/flaky.spec.json"
[ "$(jq -r '.status' "$flaky_spec")" = review ] || fail "transient merge failure left review"
[ "$(jq -r '.branch_lineage[-1].merge_state' "$flaky_spec")" = submitting ] \
  || fail "transient merge failure dropped the submitting hold"
unset GH_MERGE_REJECT
out="$(bash "$MERGE" flaky 1)"
case "$out" in MERGED:*) ;; *) fail "transient merge retry: $out" ;; esac
[ "$(grep -c '^pr merge ' "$GH_CALLS")" -eq 2 ] || fail "transient merge failure was not retried"
pass "a transient merge failure keeps the submitting hold and retries"

reset_gh
make_spec lateauto true ""
add_pr lateauto 1 https://example.test/owner/repo/pull/lateauto
export GH_MERGE_REJECT="Post https://api.github.com/graphql: net/http: request canceled (Client.Timeout exceeded)"
export GH_PR_AUTO_MERGE=true
out="$(bash "$MERGE" lateauto 1)"
case "$out" in MERGE-PENDING:*) ;; *) fail "timed-out auto-merge submission: $out" ;; esac
[ "$(jq -r '.branch_lineage[-1].merge_state' "$CODEX_GOALS_DIR/lateauto.spec.json")" = pending ] \
  || fail "timed-out auto-merge submission was not recorded pending"
pass "a timed-out submission that enabled auto-merge is recorded pending"
