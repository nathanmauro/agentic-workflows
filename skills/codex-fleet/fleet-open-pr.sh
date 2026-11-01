#!/usr/bin/env bash
set -euo pipefail

# Run-dir resolution: explicit env > newest run (current symlink) > legacy flat dir.
if [ -n "${CODEX_GOALS_DIR:-}" ]; then
  G="$CODEX_GOALS_DIR"
elif [ -d "$HOME/.codex-goals/current" ]; then
  G="$HOME/.codex-goals/current"
else G="$HOME/.codex-goals"; fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_SPEC="$SCRIPT_DIR/fleet-spec.sh"

usage() {
  echo "usage: fleet-open-pr.sh <name> <round> <branch>" >&2
  exit 2
}

append_lineage() {
  local name="$1" round="$2" branch="$3" base="$4" pr="$5" commit="$6" status="$7" note="$8"
  local entry
  entry="$(jq -nc \
    --argjson round "$round" \
    --arg branch "$branch" \
    --arg base "$base" \
    --arg pr "$pr" \
    --arg commit "$commit" \
    --arg status "$status" \
    --arg note "$note" \
    '{round:$round,branch:$branch,base:$base,pr:$pr,commit:$commit,status:$status,note:$note}')"
  bash "$FLEET_SPEC" set "$name" ".status=\"review\" | .branch_lineage += [$entry]"
}

# A local-only slice may stack on the previous local-only slice, since that
# branch was never pushed or merged and still carries unreviewed work.
local_only_base() {
  local previous previous_branch
  previous="$(jq -c '[.branch_lineage[]?] | last // empty' "$spec")"
  if [ -n "$previous" ] && [ "$(printf '%s' "$previous" | jq -r '.pr // ""')" = "local-only" ]; then
    previous_branch="$(printf '%s' "$previous" | jq -r '.branch // ""')"
    if [ -n "$previous_branch" ] && [ "$previous_branch" != "$branch" ] \
      && git rev-parse --verify --quiet "$previous_branch" > /dev/null 2>&1 \
      && git merge-base --is-ancestor "$previous_branch" "$branch" 2> /dev/null; then
      printf '%s\n' "$previous_branch"
      return 0
    fi
  fi
  printf '%s\n' "$default_branch"
}

local_only() {
  local name="$1" round="$2" branch="$3" reason="$4"
  local base cmd note push_refs

  base="$(local_only_base)"

  # The hand-off must push before `gh pr create --head`, which never pushes for
  # you. A stacked local-only base was never pushed either, so it goes too.
  push_refs="$(printf '%q' "$branch")"
  if [ "$base" != "$default_branch" ]; then
    push_refs="$(printf '%q %q' "$base" "$branch")"
  fi
  cmd="$(printf 'git push -u origin %s && gh pr create --draft --base %q --head %q --title %q' \
    "$push_refs" "$base" "$branch" "fleet r$round: $title_tail")"
  if [ "$reason" = "origin remote is missing" ]; then
    cmd="add an origin remote, then: $cmd"
  fi
  note="push blocked; open the PR by hand ($reason): $cmd"
  append_lineage "$name" "$round" "$branch" "$base" "local-only" "$head_commit" "review" "$note"
  echo "LOCAL-ONLY: $cmd"
}

[ "$#" -eq 3 ] || usage

name="$1"
round="$2"
branch="$3"

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
case "$name" in
  '' | */*)
    echo "ERR: project name must be non-empty and contain no slash" >&2
    exit 1
    ;;
esac

spec="$G/$name.spec.json"
if [ ! -f "$spec" ]; then
  echo "ERR: spec mirror not found: $spec" >&2
  exit 1
fi

spec_round="$(jq -r '.current_round // ""' "$spec")"
spec_status="$(jq -r '.status // ""' "$spec")"
project_path="$(jq -r '.path // ""' "$spec")"
push_allowed="$(jq -r '.push_allowed // false' "$spec")"
danger="$(jq -r '.danger // ""' "$spec")"
default_branch="$(jq -r '.default_branch // "main"' "$spec")"
base="$default_branch"

[ "$spec_round" = "$round" ] || {
  echo "ERR: mirror current_round=$spec_round does not authorize round $round" >&2
  exit 1
}

prefix="fleet/round-$round-"
case "$branch" in
  "$prefix"?*) title_tail="${branch#"$prefix"}" ;;
  *)
    echo "ERR: branch must match ${prefix}<non-empty-slug>" >&2
    exit 1
    ;;
esac

[ -n "$project_path" ] || {
  echo "ERR: project path is missing from mirror" >&2
  exit 1
}
current_root="$(git rev-parse --show-toplevel 2> /dev/null)" \
  || {
    echo "ERR: helper must run inside the selected Git worktree" >&2
    exit 1
  }
expected_root="$(git -C "$project_path" rev-parse --show-toplevel 2> /dev/null)" \
  || {
    echo "ERR: mirror project path is not a Git worktree" >&2
    exit 1
  }
current_root="$(cd "$current_root" && pwd -P)"
expected_root="$(cd "$expected_root" && pwd -P)"
[ "$current_root" = "$expected_root" ] || {
  echo "ERR: current repository does not match the selected project mirror" >&2
  exit 1
}

current_branch="$(git symbolic-ref --quiet --short HEAD 2> /dev/null)" \
  || {
    echo "ERR: detached HEAD cannot open a fleet PR" >&2
    exit 1
  }
[ "$current_branch" = "$branch" ] || {
  echo "ERR: requested branch $branch is not checked out (current=$current_branch)" >&2
  exit 1
}
head_commit="$(git rev-parse HEAD 2> /dev/null)" \
  || {
    echo "ERR: unable to resolve HEAD" >&2
    exit 1
  }
branch_commit="$(git rev-parse "$branch^{commit}" 2> /dev/null)" \
  || {
    echo "ERR: unable to resolve requested branch tip" >&2
    exit 1
  }
[ "$head_commit" = "$branch_commit" ] || {
  echo "ERR: requested branch tip does not match HEAD" >&2
  exit 1
}

existing_entry="$(jq -c --argjson round "$round" \
  '[.branch_lineage[]? | select((.round | tonumber) == $round)] | last // empty' "$spec")"
if [ -n "$existing_entry" ]; then
  existing_branch="$(printf '%s' "$existing_entry" | jq -r '.branch // ""')"
  [ "$existing_branch" = "$branch" ] || {
    echo "ERR: round $round already records a different branch" >&2
    exit 1
  }
  echo "ALREADY RECORDED: $(printf '%s' "$existing_entry" | jq -r '.pr // "unknown"')"
  exit 0
fi

[ "$spec_status" = "doing" ] || {
  echo "ERR: project status is $spec_status, not doing" >&2
  exit 1
}

if [ "$push_allowed" != "true" ]; then
  local_only "$name" "$round" "$branch" "push_allowed is not true"
  exit 0
fi

if printf '%s\n' "$danger" | grep -Eiq 'PUBLIC|never push|do not push'; then
  local_only "$name" "$round" "$branch" "danger hint blocks push"
  exit 0
fi

if ! command -v gh > /dev/null 2>&1; then
  local_only "$name" "$round" "$branch" "gh is not on PATH"
  exit 0
fi

if ! origin_url="$(git remote get-url origin 2> /dev/null)"; then
  local_only "$name" "$round" "$branch" "origin remote is missing"
  exit 0
fi

revalidate_push_context() {
  local now_round now_status now_path now_push now_danger now_default
  local now_root now_expected_root now_branch now_head now_branch_head now_origin now_existing

  [ -f "$spec" ] || {
    echo "ERR: spec mirror disappeared before push" >&2
    exit 1
  }
  now_round="$(jq -r '.current_round // ""' "$spec")"
  now_status="$(jq -r '.status // ""' "$spec")"
  now_path="$(jq -r '.path // ""' "$spec")"
  now_push="$(jq -r '.push_allowed // false' "$spec")"
  now_danger="$(jq -r '.danger // ""' "$spec")"
  now_default="$(jq -r '.default_branch // "main"' "$spec")"
  [ "$now_round" = "$round" ] || {
    echo "ERR: round authority changed before push" >&2
    exit 1
  }
  [ "$now_status" = "doing" ] || {
    echo "ERR: project left doing state before push" >&2
    exit 1
  }
  [ "$now_path" = "$project_path" ] || {
    echo "ERR: project path changed before push" >&2
    exit 1
  }
  [ "$now_push" = "true" ] || {
    echo "ERR: push authority was revoked before push" >&2
    exit 1
  }
  [ "$now_default" = "$default_branch" ] || {
    echo "ERR: default branch changed before push" >&2
    exit 1
  }
  if printf '%s\n' "$now_danger" | grep -Eiq 'PUBLIC|never push|do not push'; then
    echo "ERR: danger hint changed to block push" >&2
    exit 1
  fi

  now_existing="$(jq -r --argjson round "$round" \
    '[.branch_lineage[]? | select((.round | tonumber) == $round)] | length' "$spec")"
  [ "$now_existing" -eq 0 ] || {
    echo "ERR: round lineage appeared before push" >&2
    exit 1
  }

  now_root="$(git rev-parse --show-toplevel 2> /dev/null)" \
    || {
      echo "ERR: current Git worktree disappeared before push" >&2
      exit 1
    }
  now_expected_root="$(git -C "$project_path" rev-parse --show-toplevel 2> /dev/null)" \
    || {
      echo "ERR: selected Git worktree disappeared before push" >&2
      exit 1
    }
  now_root="$(cd "$now_root" && pwd -P)"
  now_expected_root="$(cd "$now_expected_root" && pwd -P)"
  [ "$now_root" = "$current_root" ] && [ "$now_expected_root" = "$expected_root" ] \
    || {
      echo "ERR: selected repository changed before push" >&2
      exit 1
    }

  now_origin="$(git remote get-url origin 2> /dev/null)" \
    || {
      echo "ERR: origin disappeared before push" >&2
      exit 1
    }
  [ "$now_origin" = "$origin_url" ] || {
    echo "ERR: origin changed before push" >&2
    exit 1
  }
  now_branch="$(git symbolic-ref --quiet --short HEAD 2> /dev/null)" \
    || {
      echo "ERR: HEAD became detached before push" >&2
      exit 1
    }
  [ "$now_branch" = "$branch" ] || {
    echo "ERR: checked-out branch changed before push" >&2
    exit 1
  }
  now_head="$(git rev-parse HEAD 2> /dev/null)" \
    || {
      echo "ERR: HEAD disappeared before push" >&2
      exit 1
    }
  now_branch_head="$(git rev-parse "$branch^{commit}" 2> /dev/null)" \
    || {
      echo "ERR: branch tip disappeared before push" >&2
      exit 1
    }
  [ "$now_head" = "$head_commit" ] && [ "$now_branch_head" = "$head_commit" ] \
    || {
      echo "ERR: branch or HEAD changed before push" >&2
      exit 1
    }
  command -v gh > /dev/null 2>&1 || {
    echo "ERR: gh disappeared before push" >&2
    exit 1
  }
}

# Stack only on a real, still-open remote PR whose head is the recorded branch
# and whose branch is an ancestor of this slice. A merely local ancestor may be
# the deleted head of an already squash-merged round and is not a valid PR base.
previous="$(jq -c \
  '[.branch_lineage[]? | select((.pr // "") != "" and .pr != "local-only")] | last // empty' \
  "$spec")"
if [ -n "$previous" ]; then
  base_candidate="$(printf '%s' "$previous" | jq -r '.branch // ""')"
  base_pr="$(printf '%s' "$previous" | jq -r '.pr // ""')"
  previous_pr_json=""
  if [ -n "$base_candidate" ] \
    && git rev-parse --verify --quiet "$base_candidate" > /dev/null 2>&1 \
    && git merge-base --is-ancestor "$base_candidate" "$branch" 2> /dev/null \
    && git ls-remote --exit-code --heads origin "refs/heads/$base_candidate" > /dev/null 2>&1 \
    && previous_pr_json="$(gh pr view "$base_pr" --json state,headRefName 2> /dev/null)" \
    && printf '%s' "$previous_pr_json" | jq -e --arg branch "$base_candidate" \
      '.state == "OPEN" and .headRefName == $branch' > /dev/null 2>&1; then
    base="$base_candidate"
  fi
fi

revalidate_push_context
git push origin "$head_commit:refs/heads/$branch"
revalidate_push_context
pr_url="$(gh pr create --draft --base "$base" --head "$branch" \
  --title "fleet r$round: $title_tail" \
  --body "Automated fleet slice (round $round). Stacked on \`$base\`. Review and merge the top branch to integrate. Human owner sole author. This PR-opening step does not merge.")"
append_lineage "$name" "$round" "$branch" "$base" "$pr_url" "$head_commit" "review" ""
echo "DRAFT PR: $pr_url"
