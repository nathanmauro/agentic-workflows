#!/usr/bin/env bash
# Fixture: run allocation is unique and aborted setup never republishes current.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
START="$ROOT/start-fleet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

export HOME="$TMP/home"
unset CODEX_GOALS_DIR CODEX_FLEET_PROJECT_ROOT
mkdir -p "$HOME/.codex-goals/prior"
ln -s "$HOME/.codex-goals/prior" "$HOME/.codex-goals/current"

pids=()
for n in 1 2 3; do
  printf 'missing-project-%s\n' "$n" | bash "$START" > "$TMP/start-$n.log" 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  if wait "$pid"; then fail "invalid setup unexpectedly succeeded"; fi
done

run_count="$(find "$HOME/.codex-goals/runs" -type d -name '*.*' | wc -l | tr -d ' ')"
[ "$run_count" -eq 3 ] || fail "concurrent starts did not allocate three unique dirs (got $run_count)"
[ "$(readlink "$HOME/.codex-goals/current")" = "$HOME/.codex-goals/prior" ] || fail "aborted setup repointed current"
echo "PASS: concurrent starts allocate unique dirs and aborted setup preserves current"

repo="$TMP/project"
git init -q "$repo"
git -C "$repo" branch -M main
git -C "$repo" remote add origin git@example.test:owner/project.git
if ! printf '%s\n\n\nPLAN\n1\nn\n' "$repo" | bash "$START" > "$TMP/success.log" 2>&1; then
  cat "$TMP/success.log" >&2
  fail "valid setup failed"
fi
published="$(readlink "$HOME/.codex-goals/current")"
[ -f "$published/state.env" ] && [ -f "$published/loop-instruction.txt" ] || fail "successful setup published an incomplete run"
[ "$(jq -r '.push_allowed' "$published/project.spec.json")" = false ] || fail "declined push grant was inferred from capability"
echo "PASS: successful setup publishes current only after seed and preserves a declined push grant"

# Use a disposable workflow tree so literal ./repo and ../repo inputs resolve
# against the directory start-fleet.sh intentionally changes into.
fixture_root="$TMP/path-fixture"
fixture_workflows="$fixture_root/workflows"
mkdir -p "$fixture_workflows/skills"
cp -R "$ROOT" "$fixture_workflows/skills/codex-fleet"
fixture_start="$fixture_workflows/skills/codex-fleet/start-fleet.sh"

relative_repo="$fixture_workflows/repo"
git init -q "$relative_repo"
git -C "$relative_repo" branch -M main
if ! printf './repo\n\n\nPLAN\n1\n' | bash "$fixture_start" > "$TMP/relative-dot.log" 2>&1; then
  cat "$TMP/relative-dot.log" >&2
  fail "./repo setup failed"
fi
dot_published="$(readlink "$HOME/.codex-goals/current")"
dot_canonical="$(cd "$relative_repo" && pwd -P)"
[ "$(jq -r '.[0].path' "$dot_published/projects.json")" = "$dot_canonical" ] || fail "./repo was not canonicalized"
[ "$(jq -r '.[0].name' "$dot_published/projects.json")" = repo ] || fail "./repo did not derive the canonical basename"
[ -f "$dot_published/repo.spec.json" ] || fail "./repo did not keep its spec inside the run dir"

parent_repo="$fixture_root/repo"
git init -q "$parent_repo"
git -C "$parent_repo" branch -M main
if ! printf '../repo\n\n\nPLAN\n1\n' | bash "$fixture_start" > "$TMP/relative-parent.log" 2>&1; then
  cat "$TMP/relative-parent.log" >&2
  fail "../repo setup failed"
fi
parent_published="$(readlink "$HOME/.codex-goals/current")"
parent_canonical="$(cd "$parent_repo" && pwd -P)"
[ "$(jq -r '.[0].path' "$parent_published/projects.json")" = "$parent_canonical" ] || fail "../repo was not canonicalized"
[ "$(jq -r '.[0].name' "$parent_published/projects.json")" = repo ] || fail "../repo leaked traversal into the project name"
[ -f "$parent_published/repo.spec.json" ] || fail "../repo escaped the run dir when naming its spec"
case "$(jq -r '.[0].name' "$parent_published/projects.json")" in
  '' | */*) fail "canonical project name is empty or contains a slash" ;;
esac
echo "PASS: explicit relative paths canonicalize and traversal never reaches state filenames"

first_same="$fixture_root/first/same"
second_same="$fixture_root/second/same"
git init -q "$first_same"
git init -q "$second_same"
before_duplicate="$(readlink "$HOME/.codex-goals/current")"
if printf '%s %s\n\n\n' "$first_same" "$second_same" | bash "$fixture_start" > "$TMP/duplicate-name.log" 2>&1; then
  fail "distinct paths with the same canonical basename unexpectedly succeeded"
fi
grep -q "project name 'same' resolves from multiple paths" "$TMP/duplicate-name.log" || fail "duplicate basename failure was not explicit"
[ "$(readlink "$HOME/.codex-goals/current")" = "$before_duplicate" ] || fail "duplicate basename failure repointed current"
echo "PASS: distinct canonical paths cannot silently collapse onto one project name"

# An installed copy is usually a symlink to the skill directory or to the script
# itself. Both must resolve back to the source tree, not to its parent.
fixture_skill_canonical="$(cd -P "$fixture_workflows/skills/codex-fleet" && pwd)"
fixture_workflows_canonical="$(cd -P "$fixture_workflows" && pwd)"
mkdir -p "$TMP/installed" "$TMP/linked-bin"
ln -s "$fixture_workflows/skills/codex-fleet" "$TMP/installed/codex-fleet"
(cd "$TMP/linked-bin" && ln -s ../path-fixture/workflows/skills/codex-fleet/start-fleet.sh start-fleet)
symlink_repo="$TMP/symlink-project"
git init -q "$symlink_repo"
git -C "$symlink_repo" branch -M main
for launcher in "$TMP/installed/codex-fleet/start-fleet.sh" "$TMP/linked-bin/start-fleet"; do
  if ! printf '%s\n\n\nPLAN\n1\n' "$symlink_repo" | bash "$launcher" > "$TMP/symlink.log" 2>&1; then
    cat "$TMP/symlink.log" >&2
    fail "setup through $launcher failed"
  fi
  grep -q "workflow repo: $fixture_workflows_canonical\$" "$TMP/symlink.log" \
    || fail "$launcher resolved the wrong workflow repo"
  symlink_published="$(readlink "$HOME/.codex-goals/current")"
  grep -qx "FLEET_SKILL_DIR=$fixture_skill_canonical" "$symlink_published/state.env" \
    || fail "$launcher recorded the wrong FLEET_SKILL_DIR"
done
echo "PASS: symlinked skill dirs and script links resolve to the source tree"

# Zero rounds has no terminal branch in the loop, so setup must refuse it.
before_zero="$(readlink "$HOME/.codex-goals/current")"
if printf '%s\n\n\nPLAN\n0\n' "$symlink_repo" | bash "$fixture_start" > "$TMP/zero.log" 2>&1; then
  fail "a zero-round fleet unexpectedly started"
fi
grep -q 'iterations must be >= 1' "$TMP/zero.log" || fail "zero-round refusal was not explicit"
[ "$(readlink "$HOME/.codex-goals/current")" = "$before_zero" ] || fail "zero-round setup repointed current"
zero_goals="$TMP/zero-goals"
if CODEX_GOALS_DIR="$zero_goals" bash "$ROOT/init-fleet.sh" 0 > "$TMP/zero-init.log" 2>&1; then
  fail "init-fleet.sh accepted zero rounds"
fi
[ ! -f "$zero_goals/state.env" ] || fail "init-fleet.sh wrote state for zero rounds"
echo "PASS: a zero-round fleet is refused before seeding"

# The health probe must report the verify command's real outcome and stay
# bounded without a timeout binary.
probe_repo="$TMP/probe-project"
git init -q "$probe_repo"
git -C "$probe_repo" branch -M main
printf 'test:\n\t@exit 3\n' > "$probe_repo/Makefile"
if ! printf '%s\n\n\nPLAN\n1\n' "$probe_repo" | bash "$fixture_start" > "$TMP/probe.log" 2>&1; then
  cat "$TMP/probe.log" >&2
  fail "setup with a failing probe failed"
fi
grep -q 'Probe: failed with exit' "$TMP/probe.log" \
  || fail "failing verify was not reported: $(grep Probe "$TMP/probe.log")"
probe_published="$(readlink "$HOME/.codex-goals/current")"
[ -f "$probe_published/health-probe-project.log" ] || fail "probe log was not kept in the run dir"

# The verify command forks a grandchild; a timeout must stop it too.
printf 'test:\n\t@sleep 47 & sleep 30; wait\n' > "$probe_repo/Makefile"
probe_started="$(date +%s)"
if ! printf '%s\n\n\nPLAN\n1\n' "$probe_repo" \
  | CODEX_FLEET_PROBE_TIMEOUT=1 bash "$fixture_start" > "$TMP/probe-slow.log" 2>&1; then
  cat "$TMP/probe-slow.log" >&2
  fail "setup with a hanging probe failed"
fi
[ $(($(date +%s) - probe_started)) -lt 20 ] || fail "hanging probe was not bounded"
grep -q 'Probe: timed out after 1s' "$TMP/probe-slow.log" || fail "hanging probe not reported as a timeout"
sleep 1
if pgrep -f 'sleep 47' > /dev/null; then
  fail "timed-out probe left its child processes running"
fi
echo "PASS: the health probe reports real failures and timeouts in the run dir"

rm "$HOME/.codex-goals/current"
mkdir "$HOME/.codex-goals/current"
before_count="$(find "$HOME/.codex-goals/runs" -type d -name '*.*' | wc -l | tr -d ' ')"
if printf 'missing-project\n' | bash "$START" > "$TMP/real-current.log" 2>&1; then
  fail "setup overwrote a real current directory"
fi
after_count="$(find "$HOME/.codex-goals/runs" -type d -name '*.*' | wc -l | tr -d ' ')"
[ "$after_count" -eq "$before_count" ] || fail "allocator ran before rejecting a non-symlink current"
[ -d "$HOME/.codex-goals/current" ] && [ ! -L "$HOME/.codex-goals/current" ] || fail "real current directory changed"
echo "PASS: a non-symlink current path fails closed before allocation"
