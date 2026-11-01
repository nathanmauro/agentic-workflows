#!/usr/bin/env bash
# Fixture: explicit CODEX_GOALS_DIR > current symlink > legacy flat dir.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/fleet-spec.sh"
LAUNCH="$ROOT/launch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TMP/home"
mkdir -p "$HOME"

seed_spec() {
  mkdir -p "$1"
  jq -n --arg marker "$2" '{marker:$marker}' > "$1/alpha.spec.json"
}

seed_spec "$HOME/.codex-goals" legacy
unset CODEX_GOALS_DIR || true
[ "$(bash "$SPEC" get alpha '.marker')" = legacy ] || fail "legacy fallback"
echo "PASS: falls back to legacy flat state"

RUN_A="$HOME/.codex-goals/runs/a"
seed_spec "$RUN_A" run-a
ln -sfn "$RUN_A" "$HOME/.codex-goals/current"
[ "$(bash "$SPEC" get alpha '.marker')" = run-a ] || fail "current symlink"
echo "PASS: current symlink wins over legacy state"

RUN_B="$HOME/.codex-goals/runs/b"
seed_spec "$RUN_B" run-b
[ "$(CODEX_GOALS_DIR="$RUN_B" bash "$SPEC" get alpha '.marker')" = run-b ] || fail "explicit env"
echo "PASS: explicit run dir wins over current symlink"

ln -sfn "$HOME/.codex-goals/runs/gone" "$HOME/.codex-goals/current"
[ "$(bash "$SPEC" get alpha '.marker')" = legacy ] || fail "dangling current fallback"
echo "PASS: dangling current symlink falls back to legacy state"

mkdir -p "$TMP/bin" "$TMP/project"
git -C "$TMP/project" init -q
printf 'test prompt\n' > "$TMP/prompt.md"
cat > "$TMP/bin/codex" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$TMP/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_CALLS"
exit 0
SH
chmod +x "$TMP/bin/codex" "$TMP/bin/tmux"
export TMUX_CALLS="$TMP/tmux-calls"
PATH="$TMP/bin:$PATH"
export PATH

CODEX_GOALS_DIR="$RUN_A" bash "$LAUNCH" alpha "$TMP/project" "$TMP/prompt.md" >/dev/null
session_a="$(cat "$RUN_A/alpha.session")"
CODEX_GOALS_DIR="$RUN_B" bash "$LAUNCH" alpha "$TMP/project" "$TMP/prompt.md" >/dev/null
session_b="$(cat "$RUN_B/alpha.session")"
[ "$session_a" != "$session_b" ] || fail "different runs reused one tmux session"
case "$session_a:$session_b" in codex-alpha-*':codex-alpha-'*) ;; *) fail "unexpected session names" ;; esac
echo "PASS: identical project names use distinct run-scoped tmux sessions"

launch_line="$(grep 'send-keys' "$TMUX_CALLS" | tail -1)"
git_dir="$(git -C "$TMP/project" rev-parse --path-format=absolute --git-common-dir)"
case "$launch_line" in *"-s workspace-write"*) ;; *) fail "sandbox not passed explicitly" ;; esac
case "$launch_line" in *"$git_dir"*) ;; *) fail "git dir not writable for the worker" ;; esac
case "$launch_line" in *network_access=true*) ;; *) fail "network not enabled for push" ;; esac
echo "PASS: launch passes workspace-write with the git dir, run dir, and network"

if CODEX_GOALS_DIR="$RUN_A" bash "$LAUNCH" alpha "$TMP" "$TMP/prompt.md" >/dev/null 2>&1; then
  fail "launch accepted a non-git working dir"
fi
echo "PASS: launch refuses a working dir that is not a git repository"

CODEX_GOALS_DIR="$RUN_A" bash "$LAUNCH" foo.bar "$TMP/project" "$TMP/prompt.md" >/dev/null
session_dot="$(cat "$RUN_A/foo.bar.session")"
CODEX_GOALS_DIR="$RUN_A" bash "$LAUNCH" foo+bar "$TMP/project" "$TMP/prompt.md" >/dev/null
session_plus="$(cat "$RUN_A/foo+bar.session")"
[ "$session_dot" != "$session_plus" ] || fail "normalized project names collided within one run"
echo "PASS: original-name checksum prevents same-run normalization collisions"
