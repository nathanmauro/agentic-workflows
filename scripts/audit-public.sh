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
  python3 -m json.tool "$1" > /dev/null
}

xml_parse_quiet() {
  python3 -c 'import sys, xml.dom.minidom; [xml.dom.minidom.parse(p) for p in sys.argv[1:]]' "$@"
}

# Parse only; py_compile would leave a __pycache__ directory behind in the repo.
py_syntax() {
  python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$1"
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

# Generic shapes only: home-directory paths, personal-mail addresses, token prefixes, and
# private link shapes. Anything
# that names a specific person, repo, or tool belongs in the local denylist below instead.
# Dollar-prefixed path forms are literal regex targets, not shell expansions.
# shellcheck disable=SC2016
SECRET_DENYLIST_RE='/(Users|home)/[A-Za-z0-9._-]+|[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|live|icloud|me|yahoo|proton|protonmail|pm)\.[a-z]+|Label_[0-9]+|ghp_|(^|[^A-Za-z0-9])sk-[A-Za-z0-9_-]{16,}|CODEX_GITHUB_PERSONAL_ACCESS_TOKEN|OPENAI_API_KEY|GITHUB_PERSONAL_ACCESS_TOKEN|(\$HOME|\$\{HOME\}|~)/Developer/|claude\.ai/code/session_'
PRIVATE_IMPL_DENYLIST_RE='linear\.app/[A-Za-z0-9_-]+/issue|obsidian://open\?vault='

# Private repo, tool, and person names would themselves be a leak if this script named them, so
# they load from an untracked, gitignored file: one extended-regex term per line. CI never has
# that file and checks only the generic shapes above; AUDIT_REQUIRE_LOCAL_DENYLIST=1 makes a
# local pre-push run fail instead of passing without it.
LOCAL_DENYLIST_FILE="${AUDIT_PRIVATE_DENYLIST:-.audit-denylist.local}"
LOCAL_DENYLIST_RE=""
if [ -f "$LOCAL_DENYLIST_FILE" ]; then
  LOCAL_DENYLIST_RE="$(grep -v -E '^\s*(#|$)' "$LOCAL_DENYLIST_FILE" | paste -sd '|' - || true)"
fi
if [ -n "$LOCAL_DENYLIST_RE" ]; then
  PRIVATE_IMPL_DENYLIST_RE="$PRIVATE_IMPL_DENYLIST_RE|$LOCAL_DENYLIST_RE"
  echo "== local private denylist: loaded from $LOCAL_DENYLIST_FILE =="
elif [ "${AUDIT_REQUIRE_LOCAL_DENYLIST:-0}" = "1" ]; then
  echo "audit failed: local private denylist $LOCAL_DENYLIST_FILE is missing or empty" >&2
  exit 1
else
  echo "== local private denylist: not loaded (CI mode, generic patterns only) =="
fi

if [ "${AUDIT_REQUIRE_NO_REMOTES:-0}" = "1" ]; then
  run_check "release clean: no git remotes" assert_no_git_remotes
else
  echo "== release clean: no git remotes =="
  echo "skipped; set AUDIT_REQUIRE_NO_REMOTES=1 to enforce pre-publication export mode"
fi

AUDIT_ALLOWLIST_RE='^\./scripts/audit-public\.sh:[0-9]+:SECRET_DENYLIST_RE=' \
  run_no_match "high-risk secrets and private paths" \
  rg -n --hidden -g '!/.git' -g '!/.git/**' -g '!.audit-denylist.local' \
  "$SECRET_DENYLIST_RE" \
  .

AUDIT_ALLOWLIST_RE='^\./scripts/audit-public\.sh:[0-9]+:PRIVATE_IMPL_DENYLIST_RE=' \
  run_no_match "private implementation names outside boundary docs" \
  rg -n --hidden -g '!/.git' -g '!/.git/**' -g '!.audit-denylist.local' -g '!README.md' -g '!LICENSE' -g '!docs/private-public-boundary.md' \
  "$PRIVATE_IMPL_DENYLIST_RE" \
  .

# Keep placeholder detection in prose while allowing the small, intentional set of
# HTML layout tags used by the GitHub README. Fenced and inline code are skipped because
# angle-bracket placeholders are legitimate in command examples. SVG assets get an XML parse
# check below instead.
run_no_match "unresolved prose placeholders outside skills and templates" \
  python3 scripts/prose-placeholders.py README.md docs examples CHANGELOG.md

run_check "json validation: fleet projects" \
  json_tool_quiet templates/fleet-projects.json
run_check "json validation: local adapters" \
  json_tool_quiet templates/local-adapters.example.json
run_check "xml validation: svg assets" \
  xml_parse_quiet docs/assets/*.svg

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
run_check "bash syntax: codex fleet merge" \
  bash -n skills/codex-fleet/fleet-merge.sh
run_check "bash syntax: codex fleet results" \
  bash -n skills/codex-fleet/fleet-results.sh
run_check "bash syntax: codex fleet state" \
  bash -n skills/codex-fleet/fleet-state.sh
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
run_check "python syntax: codex runner" \
  py_syntax scripts/codex-runner
run_check "python syntax: prose placeholders" \
  py_syntax scripts/prose-placeholders.py

run_check "codex runner test: offline contract" \
  bash scripts/tests/test-codex-runner.sh
run_check "audit test: patterns and placeholder exits" \
  bash scripts/tests/test-audit-public.sh

run_check "codex fleet test: spec" \
  bash skills/codex-fleet/tests/test-spec.sh
run_check "codex fleet test: board" \
  bash skills/codex-fleet/tests/test-board.sh
run_check "codex fleet test: push gate" \
  bash skills/codex-fleet/tests/test-push-gate.sh
run_check "codex fleet test: prompt" \
  bash skills/codex-fleet/tests/test-prompt.sh
run_check "codex fleet test: run dir" \
  bash skills/codex-fleet/tests/test-run-dir.sh
run_check "codex fleet test: start" \
  bash skills/codex-fleet/tests/test-start.sh
run_check "codex fleet test: review" \
  bash skills/codex-fleet/tests/test-review.sh
run_check "codex fleet test: results" \
  bash skills/codex-fleet/tests/test-results.sh
run_check "codex fleet test: state" \
  bash skills/codex-fleet/tests/test-state.sh
run_check "codex fleet test: merge" \
  bash skills/codex-fleet/tests/test-merge.sh

# A bare whitespace diff sees only unstaged edits, which a clean CI checkout never has. Check
# every committed file against the empty tree, then staged and unstaged local edits.
EMPTY_TREE="$(git hash-object -t tree /dev/null)"
run_check "git whitespace: committed tree" git diff --check "$EMPTY_TREE" HEAD
run_check "git whitespace: local edits" git diff --check HEAD

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "audit ok"
