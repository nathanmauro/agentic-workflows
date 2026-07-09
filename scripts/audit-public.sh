#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

assert_no_git_remotes() {
  if [ -n "$(git remote)" ]; then
    echo "audit failed: configured git remotes present" >&2
    git remote -v >&2
    return 1
  fi
}

json_tool_quiet() {
  python3 -m json.tool "$1" >/dev/null
}

run_no_match() {
  local label="$1"
  shift
  echo "== $label =="
  local output
  local rc
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    if [ -n "${AUDIT_ALLOWLIST_RE:-}" ]; then
      output="$(printf '%s\n' "$output" | awk -v re="$AUDIT_ALLOWLIST_RE" '$0 !~ re')"
    fi
    if [ -z "$output" ]; then
      return 0
    fi
    printf '%s\n' "$output"
    echo "audit failed: $label" >&2
    fail=1
  elif [ "$rc" -eq 1 ]; then
    return 0
  else
    printf '%s\n' "$output" >&2
    echo "audit failed: $label (command exited $rc)" >&2
    fail=1
  fi
}

run_check() {
  local label="$1"
  shift
  echo "== $label =="
  "$@"
}

SECRET_DENYLIST_RE='/Users/nathan|nathan@|Label_[0-9]+|ghp_|sk-[A-Za-z0-9_-]+|CODEX_GITHUB_PERSONAL_ACCESS_TOKEN|OPENAI_API_KEY|GITHUB_PERSONAL_ACCESS_TOKEN|(\$HOME|\$\{HOME\}|~)/Developer/proj'
PRIVATE_IMPL_DENYLIST_RE='cockpit|sba-agentic|Black Box|cockpit-council|mcp-memory-agent|dna-residual-memory|SessionsPage\.tsx|~/.claude/skills/codex-fleet'

if [ "${AUDIT_REQUIRE_NO_REMOTES:-0}" = "1" ]; then
  run_check "release clean: no git remotes" assert_no_git_remotes
else
  echo "== release clean: no git remotes =="
  echo "skipped; set AUDIT_REQUIRE_NO_REMOTES=1 to enforce pre-publication export mode"
fi

AUDIT_ALLOWLIST_RE='^\./scripts/audit-public\.sh:[0-9]+:SECRET_DENYLIST_RE=' \
run_no_match "high-risk secrets and private paths" \
  rg -n --hidden -g '!/.git/**' \
  "$SECRET_DENYLIST_RE" \
  .

AUDIT_ALLOWLIST_RE='^\./scripts/audit-public\.sh:[0-9]+:PRIVATE_IMPL_DENYLIST_RE=' \
run_no_match "private implementation names outside boundary docs" \
  rg -n --hidden -g '!/.git/**' -g '!README.md' -g '!LICENSE' -g '!docs/private-public-boundary.md' \
  "$PRIVATE_IMPL_DENYLIST_RE" \
  .

run_no_match "unresolved prose placeholders outside skills and templates" \
  rg -n -g '!/.git/**' -g '!skills/**' -g '!templates/**' \
  'TBD|TODO|FIXME|<[^>]+>' \
  README.md docs examples

run_check "json validation: fleet projects" \
  json_tool_quiet templates/fleet-projects.json
run_check "json validation: local adapters" \
  json_tool_quiet templates/local-adapters.example.json

run_check "bash syntax: claude remote" \
  bash -n skills/claude-remote/scripts/start-claude-remote
run_check "bash syntax: codex fleet launcher" \
  bash -n skills/codex-fleet/start-fleet.sh
run_check "bash syntax: codex fleet init" \
  bash -n skills/codex-fleet/init-fleet.sh
run_check "bash syntax: codex fleet launch" \
  bash -n skills/codex-fleet/launch.sh
run_check "bash syntax: codex fleet board" \
  bash -n skills/codex-fleet/fleet-board.sh
run_check "bash syntax: codex fleet open pr" \
  bash -n skills/codex-fleet/fleet-open-pr.sh
run_check "bash syntax: codex fleet prompt" \
  bash -n skills/codex-fleet/fleet-prompt.sh
run_check "bash syntax: codex fleet review" \
  bash -n skills/codex-fleet/fleet-review.sh
run_check "bash syntax: codex fleet spec" \
  bash -n skills/codex-fleet/fleet-spec.sh

run_check "node syntax: codex fleet recon" \
  node --check skills/codex-fleet/recon-workflow.js
run_check "node syntax: hybrid workflow" \
  node --check skills/codex-workflow-hybrid/templates/workflow.js
run_check "node syntax: lean workflow" \
  node --check skills/codex-workflow-lean/templates/workflow.js

run_check "codex fleet test: spec" \
  bash skills/codex-fleet/tests/test-spec.sh
run_check "codex fleet test: board" \
  bash skills/codex-fleet/tests/test-board.sh
run_check "codex fleet test: push gate" \
  bash skills/codex-fleet/tests/test-push-gate.sh
run_check "codex fleet test: prompt" \
  bash skills/codex-fleet/tests/test-prompt.sh

run_check "git whitespace" git diff --check

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "audit ok"
