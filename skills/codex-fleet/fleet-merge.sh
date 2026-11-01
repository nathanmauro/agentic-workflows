#!/usr/bin/env bash
set -euo pipefail

# fleet-merge.sh <name> <round>
# FULL_AUTO-only: merge the round's draft PR only after every gate below passes.
# A blocked gate, failed check, or timeout leaves the slice in review; this
# helper never forces a merge.

# Run-dir resolution: explicit env > newest run (current symlink) > legacy flat dir.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then
  G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then
  G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_SPEC="$SCRIPT_DIR/fleet-spec.sh"
FLEET_BOARD="$SCRIPT_DIR/fleet-board.sh"
FLEET_RESULTS="$SCRIPT_DIR/fleet-results.sh"

usage() {
  echo "usage: fleet-merge.sh <name> <round>" >&2
  exit 2
}

json_quote() {
  jq -n --arg v "$1" '$v'
}

repo_identity_from_remote() {
  local url="$1" rest host path
  case "$url" in
    *://*)
      rest="${url#*://}"
      rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      ;;
    *@*:*)
      rest="${url#*@}"
      host="${rest%%:*}"
      path="${rest#*:}"
      ;;
    *) return 1 ;;
  esac
  path="${path%/}"
  path="${path%.git}"
  [ -n "$host" ] && [ -n "$path" ] && [ "$path" != "$rest" ] || return 1
  printf '%s/%s\n' "$host" "$path" | tr '[:upper:]' '[:lower:]'
}

repo_identity_from_pr_url() {
  local url="$1" repo_url
  case "$url" in
    *://*/pull/*) repo_url="${url%/pull/*}" ;;
    *) return 1 ;;
  esac
  repo_identity_from_remote "$repo_url"
}

noop() {
  echo "NOOP: $1"
  exit 0
}

[ "$#" -eq 2 ] || usage

name="$1"
round="$2"

case "$round" in
  '' | *[!0-9]*)
    echo "ERR: round must be a positive integer (got '$round')" >&2
    exit 1
    ;;
esac
[ "$round" -gt 0 ] || {
  echo "ERR: round must be a positive integer (got '$round')" >&2
  exit 1
}

spec="$G/$name.spec.json"

# Re-run this complete gate immediately before every merge attempt. The CI wait
# can last many minutes, during which the human may revoke authority or move the
# run/project out of review.
load_gates() {
  local mode="" phase="" current_round="" project_path origin_url last_round

  # A newer slice may have been recorded since this round's PR. Only the newest
  # lineage entry is mergeable, so a stale requested round is a no-op before any
  # other gate runs.
  if [ -f "$spec" ]; then
    last_round="$(jq -r '[.branch_lineage[]?] | last | (.round // "") | tostring' "$spec")"
    [ "$last_round" = "$round" ] || noop "no PR for round $round"
  fi

  if [ -f "$G/state.env" ]; then
    mode="$(awk -F= '$1 == "MODE" { value=$2 } END { print value }' "$G/state.env")"
    phase="$(awk -F= '$1 == "PHASE" { value=$2 } END { print value }' "$G/state.env")"
    current_round="$(awk -F= '$1 == "ROUND" { value=$2 } END { print value }' "$G/state.env")"
  fi
  [ "$mode" = "FULL_AUTO" ] || noop "merge blocked: run mode is ${mode:-unknown}, not FULL_AUTO"
  [ "$phase" = "REVIEW" ] || noop "merge blocked: run phase is ${phase:-unknown}, not REVIEW"
  [ "$current_round" = "$round" ] || noop "merge blocked: current round is ${current_round:-unknown}, not $round"

  [ -f "$spec" ] || {
    echo "ERR: spec mirror not found: $spec" >&2
    exit 1
  }
  entry="$(jq -c --argjson round "$round" \
    '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last // empty' "$spec")"
  [ -n "$entry" ] || noop "no PR to merge for round $round"

  spec_status="$(jq -r '.status // ""' "$spec")"
  spec_round="$(jq -r '.current_round // ""' "$spec")"
  push_allowed="$(jq -r '.push_allowed // false' "$spec")"
  danger="$(jq -r '.danger // ""' "$spec")"
  project_path="$(jq -r '.path // ""' "$spec")"
  default_branch="$(jq -r '.default_branch // "main"' "$spec")"
  pr="$(printf '%s' "$entry" | jq -r '.pr // ""')"
  branch="$(printf '%s' "$entry" | jq -r '.branch // ""')"
  base="$(printf '%s' "$entry" | jq -r '.base // ""')"
  commit="$(printf '%s' "$entry" | jq -r '.commit // ""')"
  entry_status="$(printf '%s' "$entry" | jq -r '.status // ""')"
  merge_state="$(printf '%s' "$entry" | jq -r '.merge_state // ""')"

  [ "$spec_status" = "review" ] || noop "merge blocked: project status is ${spec_status:-unknown}, not review"
  [ "$spec_round" = "$round" ] || noop "merge blocked: project current_round is ${spec_round:-unknown}, not $round"
  [ "$entry_status" = "review" ] || noop "merge blocked: round status is ${entry_status:-unknown}, not review"
  [ "$push_allowed" = "true" ] || noop "merge blocked: push not allowed"
  if printf '%s\n' "$danger" | grep -Eiq 'PUBLIC|never push|do not push'; then
    noop "merge blocked: danger hint blocks push"
  fi
  if [ -z "$pr" ] || [ "$pr" = "local-only" ]; then noop "no PR to merge"; fi
  # A slice stacked on a still-open fleet branch would squash into that branch,
  # not the default branch, and then be recorded as merged. Leave it for a human.
  [ "$base" = "$default_branch" ] \
    || noop "merge blocked: slice is stacked on ${base:-unknown}, not $default_branch"

  case "$commit" in
    '' | *[!0-9a-fA-F]*) noop "merge blocked: recorded head commit is missing or invalid" ;;
  esac
  if [ "${#commit}" -lt 7 ] || [ "${#commit}" -gt 40 ]; then
    noop "merge blocked: recorded head commit is not a usable Git SHA"
  fi

  [ -n "$project_path" ] || noop "merge blocked: project path is missing"
  git -C "$project_path" rev-parse --is-inside-work-tree > /dev/null 2>&1 \
    || noop "merge blocked: project path is not a Git worktree"
  origin_url="$(git -C "$project_path" remote get-url origin 2> /dev/null)" \
    || noop "merge blocked: project origin is missing"
  expected_repo_identity="$(repo_identity_from_remote "$origin_url")" \
    || noop "merge blocked: project origin cannot be mapped to a repository identity"
}

load_gates
initial_pr="$pr"
initial_branch="$branch"
initial_base="$base"
initial_commit="$commit"
initial_repo_identity="$expected_repo_identity"

command -v gh > /dev/null 2>&1 || noop "merge blocked: gh not on PATH"

CONFIRM_TIMEOUT="${FLEET_MERGE_CONFIRM_TIMEOUT:-300}"
CONFIRM_INTERVAL="${FLEET_MERGE_CONFIRM_INTERVAL:-15}"
case "$CONFIRM_TIMEOUT:$CONFIRM_INTERVAL" in
  *[!0-9:]*) noop "merge blocked: confirmation settings must be non-negative integers" ;;
esac

inspect_pr() {
  local json rc actual_repo_identity
  set +e
  json="$(gh pr view "$pr" --json state,isDraft,headRefName,headRefOid,baseRefName,url,mergedAt,autoMergeRequest \
    2> /dev/null)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || noop "merge blocked: unable to inspect PR"
  printf '%s' "$json" | jq -e \
    '.state and (.isDraft != null) and .headRefName and .headRefOid and .baseRefName and .url' \
    > /dev/null 2>&1 || noop "merge blocked: PR metadata is incomplete"

  pr_state="$(printf '%s' "$json" | jq -r '.state')"
  pr_is_draft="$(printf '%s' "$json" | jq -r '.isDraft')"
  pr_head_branch="$(printf '%s' "$json" | jq -r '.headRefName')"
  pr_head_oid="$(printf '%s' "$json" | jq -r '.headRefOid')"
  pr_base="$(printf '%s' "$json" | jq -r '.baseRefName')"
  pr_url="$(printf '%s' "$json" | jq -r '.url')"
  pr_merged_at="$(printf '%s' "$json" | jq -r '.mergedAt // ""')"
  pr_auto_merge="$(printf '%s' "$json" | jq -r 'if .autoMergeRequest then "true" else "false" end')"

  actual_repo_identity="$(repo_identity_from_pr_url "$pr_url")" \
    || noop "merge blocked: PR URL cannot be mapped to a repository identity"
  [ "$actual_repo_identity" = "$expected_repo_identity" ] \
    || noop "merge blocked: PR repository does not match selected project origin"
  case "$pr_state" in
    OPEN) ;;
    MERGED) [ -n "$pr_merged_at" ] || noop "merge blocked: PR reports MERGED without mergedAt" ;;
    *) noop "merge blocked: PR state is $pr_state, not OPEN or MERGED" ;;
  esac
  [ "$pr_head_branch" = "$branch" ] || noop "merge blocked: PR head branch does not match recorded lineage"
  [ -z "$base" ] || [ "$pr_base" = "$base" ] || noop "merge blocked: PR base does not match recorded lineage"
  [ "$pr_base" = "$default_branch" ] \
    || noop "merge blocked: PR base is $pr_base, not $default_branch"
  case "$pr_head_oid" in
    "$commit"*) ;;
    *) noop "merge blocked: PR head commit does not match recorded lineage" ;;
  esac
}

finalize_merged() {
  local merge_note="$1" note_json
  note_json="$(json_quote "$merge_note")"
  # Write the independently repairable ledger first. If the process stops
  # before the mirror update, a retry still sees review + remote MERGED and can
  # finish; the reverse order would strand an incomplete ledger behind done.
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$merge_note" "done"
  bash "$FLEET_SPEC" set "$name" \
    ".status=\"done\" | .branch_lineage |= map(if (.round | tonumber) == $round then .note=$note_json | .status=\"done\" | .merge_state=\"merged\" else . end)" > /dev/null
  bash "$FLEET_BOARD" build > /dev/null
  echo "MERGED: $pr ($merge_note)"
  exit 0
}

record_pending() {
  local pending_note pending_json
  pending_note="merge submitted; PR remains open (queued or auto-merge pending)"
  pending_json="$(json_quote "$pending_note")"
  bash "$FLEET_SPEC" set "$name" \
    ".branch_lineage |= map(if (.round | tonumber) == $round then .note=$pending_json | .merge_state=\"pending\" else . end)" > /dev/null
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$pending_note" review
  bash "$FLEET_BOARD" build > /dev/null
  echo "MERGE-PENDING: $pr ($pending_note) — REVIEW must hold and retry"
  exit 0
}

record_rejected() {
  local reject_tail reject_note reject_json
  reject_tail="$(printf '%s\n' "$1" | tail -n 1)"
  reject_note="merge rejected${reject_tail:+: $reject_tail}"
  reject_json="$(json_quote "$reject_note")"
  bash "$FLEET_SPEC" set "$name" \
    ".branch_lineage |= map(if (.round | tonumber) == $round then .note=$reject_json | .merge_state=\"rejected\" else . end)" > /dev/null
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$reject_note" review
  bash "$FLEET_BOARD" build > /dev/null
  noop "$reject_note — left in review for manual merge"
}

mark_submitting() {
  local submitting_note submitting_json
  submitting_note="merge submission started; awaiting GitHub result"
  submitting_json="$(json_quote "$submitting_note")"
  # Write ahead of the external mutation. A crash, transient command failure, or
  # transient post-submit read therefore leaves REVIEW held in a retryable state.
  bash "$FLEET_SPEC" set "$name" \
    "if .status == \"review\" and .current_round == $round and
        any(.branch_lineage[]?; (.round | tonumber) == $round and .status == \"review\")
     then .branch_lineage |= map(if (.round | tonumber) == $round then .note=$submitting_json | .merge_state=\"submitting\" else . end)
     else error(\"merge submission gate changed\") end" > /dev/null
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$submitting_note" review
}

confirm_or_record_pending() {
  local confirmed_note="${1:-merge confirmed after queue/auto-merge}" confirm_deadline confirm_poll
  confirm_deadline=$(($(date +%s) + CONFIRM_TIMEOUT))
  confirm_poll="$CONFIRM_INTERVAL"
  [ "$confirm_poll" -gt 0 ] || confirm_poll=1
  while :; do
    inspect_pr
    if [ "$pr_state" = "MERGED" ]; then finalize_merged "$confirmed_note"; fi
    [ "$(date +%s)" -ge "$confirm_deadline" ] && break
    sleep "$confirm_poll"
  done
  record_pending
}

# Draft-to-ready transitions can start CI. Verify identity first, make the PR
# ready only when needed, then re-read metadata before polling those checks.
became_ready=false
inspect_pr
if [ "$pr_state" = "MERGED" ]; then finalize_merged "merge confirmed"; fi
if [ "$merge_state" = "pending" ]; then confirm_or_record_pending "merge confirmed after queue/auto-merge"; fi
# A refusal sticks for the rest of the round. A human merge is still picked up by
# the MERGED check above; otherwise the helper does not re-submit the same refusal.
if [ "$merge_state" = "rejected" ]; then noop "merge previously rejected; left in review for manual merge"; fi
if [ "$pr_is_draft" = "true" ]; then
  gh pr ready "$pr"
  became_ready=true
  inspect_pr
  if [ "$pr_state" = "MERGED" ]; then finalize_merged "merge confirmed"; fi
fi

# Poll `gh pr checks` without `--watch`, bounded by a wall-clock deadline.
CHECKS_TIMEOUT="${FLEET_MERGE_CHECKS_TIMEOUT:-1800}"
POLL_INTERVAL="${FLEET_MERGE_POLL_INTERVAL:-30}"
CHECK_REGISTRATION_GRACE="${FLEET_MERGE_CHECK_REGISTRATION_GRACE:-60}"
case "$CHECKS_TIMEOUT:$POLL_INTERVAL:$CHECK_REGISTRATION_GRACE" in
  *[!0-9:]*) noop "merge blocked: check timeout settings must be non-negative integers" ;;
esac
deadline=$(($(date +%s) + CHECKS_TIMEOUT))
registration_deadline=$(($(date +%s) + CHECK_REGISTRATION_GRACE))
registration_poll="$POLL_INTERVAL"
[ "$registration_poll" -gt 0 ] || registration_poll=1

no_checks=false
timed_out=false
checks_out=""
checks_rc=1

while :; do
  set +e
  checks_out="$(gh pr checks "$pr" 2>&1)"
  checks_rc=$?
  set -e

  [ "$checks_rc" -eq 0 ] && break

  if printf '%s\n' "$checks_out" | grep -Eiq 'no checks reported|no checks configured|no status checks'; then
    if $became_ready && [ "$(date +%s)" -lt "$registration_deadline" ]; then
      sleep "$registration_poll"
      continue
    fi
    no_checks=true
    break
  fi

  if [ "$checks_rc" -eq 8 ]; then
    if [ "$(date +%s)" -ge "$deadline" ]; then
      timed_out=true
      break
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  break
done

if $timed_out; then
  note="checks timeout after ${CHECKS_TIMEOUT}s"
  note_json="$(json_quote "$note")"
  bash "$FLEET_SPEC" set "$name" \
    ".branch_lineage |= map(if (.round | tonumber) == $round then .note=$note_json else . end)" > /dev/null
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$note" review
  bash "$FLEET_BOARD" build > /dev/null
  echo "CHECKS-TIMEOUT: $pr ($note) — left in review for manual merge"
  exit 0
fi

if [ "$checks_rc" -ne 0 ] && ! $no_checks; then
  fail_line="$(printf '%s' "$checks_out" | tail -n 1)"
  note="checks failed on $pr${fail_line:+: $fail_line}"
  note_json="$(json_quote "$note")"
  bash "$FLEET_SPEC" set "$name" \
    ".branch_lineage |= map(if (.round | tonumber) == $round then .note=$note_json else . end)" > /dev/null
  bash "$FLEET_RESULTS" upsert "$round" "$name" "$branch" "$commit" "$note" review
  bash "$FLEET_BOARD" build > /dev/null
  echo "CHECKS-FAILED: $pr ($note) — left in review for manual merge"
  exit 0
fi

if $no_checks; then
  merge_note="merged without CI checks"
else
  merge_note="auto-merged (squash)"
fi

# The state and authority observed before CI are stale by definition. Re-read
# every run/spec gate and require the lineage/repository identity to be exactly
# the one whose checks were just observed.
load_gates
[ "$pr" = "$initial_pr" ] \
  && [ "$branch" = "$initial_branch" ] \
  && [ "$base" = "$initial_base" ] \
  && [ "$commit" = "$initial_commit" ] \
  && [ "$expected_repo_identity" = "$initial_repo_identity" ] \
  || noop "merge blocked: recorded PR lineage changed during checks"
inspect_pr
if [ "$pr_state" = "MERGED" ]; then finalize_merged "merge confirmed during checks"; fi

mark_submitting
# Re-read the complete authority/identity gate after the write-ahead state and
# immediately before the external mutation.
load_gates
[ "$pr" = "$initial_pr" ] \
  && [ "$branch" = "$initial_branch" ] \
  && [ "$base" = "$initial_base" ] \
  && [ "$commit" = "$initial_commit" ] \
  && [ "$expected_repo_identity" = "$initial_repo_identity" ] \
  || noop "merge blocked: recorded PR lineage changed before submission"
inspect_pr
if [ "$pr_state" = "MERGED" ]; then finalize_merged "merge confirmed before submission retry"; fi

# Only a recognised GitHub refusal (review, protection, rules, conflict, head moved,
# permissions) is final. Any other failure may be a network error, timeout, rate
# limit, or 5xx, possibly after GitHub already queued the merge or enabled
# auto-merge, so it must never be recorded as a refusal.
merge_refusal_pattern='not mergeable|conflict|approving review|review is required|reviews? required'
merge_refusal_pattern+='|changes requested|required status check|branch protection|protected branch'
merge_refusal_pattern+='|rule violation|head branch was modified|not allowed|not accessible'
merge_refusal_pattern+='|permission|admin rights'

set +e
merge_err="$(gh pr merge "$pr" --squash --match-head-commit "$pr_head_oid" 2>&1 > /dev/null)"
merge_rc=$?
set -e
if [ "$merge_rc" -ne 0 ]; then
  inspect_pr
  if [ "$pr_state" = "MERGED" ]; then finalize_merged "$merge_note"; fi
  if printf '%s\n' "$merge_err" | grep -Eiq "$merge_refusal_pattern"; then
    record_rejected "$merge_err"
  fi
  if [ "$pr_auto_merge" = "true" ]; then record_pending; fi

  # Unclassified failure: keep the write-ahead `submitting` hold so the next
  # REVIEW tick retries the head-bound submission.
  echo "ERR: gh pr merge failed (rc=$merge_rc); merge_state stays submitting for retry" >&2
  printf '%s\n' "$merge_err" | tail -n 1 >&2
  exit 1
fi

# Exit zero can mean an actual merge, merge queue enrollment, or enabled
# auto-merge. Poll to a bounded confirmation deadline; only remote MERGED +
# mergedAt is terminal. The persisted pending state makes later REVIEW ticks
# confirmation-only, so they never submit the merge twice.
confirm_or_record_pending "$merge_note"
