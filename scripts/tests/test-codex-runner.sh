#!/usr/bin/env bash
# Offline tests for scripts/codex-runner against a fake codex executable.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/codex-runner"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home"
export CODEX_RUNNER_HOME="$TMP/runner"
export FAKE_CODEX_LOG="$TMP/codex-argv.log"
# The caller's own model knobs must not leak into the no-default-model assertions.
unset CODEX_MODEL CODEX_EFFORT CODEX_TIER
mkdir -p "$HOME" "$TMP/bin" "$TMP/repo"
export PATH="$TMP/bin:$PATH"

# The fake emits the same JSON event lines that `codex exec --json` writes to stdout.
cat > "$TMP/bin/codex" << 'FAKE'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_CODEX_LOG"

if [ "${2:-}" = "resume" ]; then
  thread="$3"
else
  thread="thread-$RANDOM$RANDOM"
fi
mode="${FAKE_CODEX_MODE:-done}"

event() {
  printf '%s\n' "$1"
}

# A worker that dies before thread.started leaves the agent with no thread to resume.
if [ "$mode" = "die" ]; then
  echo "fake codex: startup failure" >&2
  exit 1
fi

reply() {
  python3 - "$1" <<'PYEOF'
import json
import sys

status = sys.argv[1]
envelope = {"status": status, "summary": f"fake {status}", "question": ""}
text = "Worked on it.\nENVELOPE " + json.dumps(envelope)
item = {"id": "i1", "type": "agent_message", "text": text}
print(json.dumps({"type": "item.completed", "item": item}))
PYEOF
  event '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
}

event "{\"type\":\"thread.started\",\"thread_id\":\"$thread\"}"
event '{"type":"turn.started"}'

case "$mode" in
  done)
    warning='{"id":"e1","type":"error","message":"feature is under development"}'
    event "{\"type\":\"item.completed\",\"item\":$warning}"
    reply done
    ;;
  question | failed)
    reply "$mode"
    ;;
  crash)
    event '{"type":"turn.failed","error":{"message":"model unavailable"}}'
    ;;
  slow)
    sleep "${FAKE_CODEX_SLEEP:-3}"
    reply done
    ;;
  deprecated)
    warning='{"id":"e1","type":"error","message":"model_verbosity is deprecated"}'
    event "{\"type\":\"item.completed\",\"item\":$warning}"
    sleep 3
    reply done
    ;;
  hang)
    sleep 300
    ;;
  vanish)
    exit 0
    ;;
esac
FAKE
chmod +x "$TMP/bin/codex"

failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

# Prints one field from JSON on stdin; dotted keys walk nested objects, "#" means length.
json_field() {
  python3 -c '
import json
import sys

value = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    value = len(value) if key == "#" else value[key]
print(value)
' "$1"
}

# Every created name is also appended to STARTED so the final list check counts real starts.
STARTED="$TMP/started-agents"
: > "$STARTED"

start_agent() {
  "$RUNNER" start --cwd "$TMP/repo" "$@" | json_field name | tee -a "$STARTED"
}

send_task() {
  local agent="$1"
  local mode="$2"
  printf 'Do the thing.\n' | FAKE_CODEX_MODE="$mode" "$RUNNER" send "$agent" - | json_field turn
}

# Runs a watch, stores its stdout in WATCH_OUT and its exit code in WATCH_RC.
watch_turn() {
  set +e
  WATCH_OUT="$("$RUNNER" watch "$@")"
  WATCH_RC=$?
  set -e
}

expect_rc() {
  local label="$1"
  local want="$2"
  if [ "$WATCH_RC" -eq "$want" ]; then
    pass "$label (exit $want)"
  else
    fail "$label: want exit $want, got $WATCH_RC: $WATCH_OUT"
  fi
}

# Prompts span several lines, so each fake launch is counted by its leading `exec` line.
launch_lines() {
  grep '^exec ' "$FAKE_CODEX_LOG" || true
}

agent="$(start_agent --label done-case)"
turn="$(send_task "$agent" done)"
watch_turn "$turn" --timeout 10
expect_rc "done turn" 0
summary="$(printf '%s' "$WATCH_OUT" | json_field envelope.summary)"
if [ "$summary" = "fake done" ]; then
  pass "envelope parsed and under-development error item ignored"
else
  fail "envelope summary was '$summary'"
fi

thread="$("$RUNNER" status "$agent" | json_field thread_id)"
turn2="$(send_task "$agent" done)"
watch_turn "$turn2" --timeout 10
if grep -q "^exec resume $thread --json --skip-git-repo-check" "$FAKE_CODEX_LOG"; then
  pass "second send resumes thread $thread"
else
  fail "second send did not resume $thread"
fi
expect_rc "resumed turn" 0

if grep -q "model=" "$FAKE_CODEX_LOG"; then
  fail "a model was passed although none was configured"
else
  pass "no model flag without --model or CODEX_MODEL"
fi

agent="$(CODEX_EFFORT=high start_agent --model example-model)"
watch_turn "$(send_task "$agent" done)" --timeout 10
if grep -q 'model="example-model" -c model_reasoning_effort="high"' "$FAKE_CODEX_LOG"; then
  pass "model and effort knobs pass through as config overrides"
else
  fail "model or effort override missing from argv"
fi

agent="$(start_agent --label question-case)"
watch_turn "$(send_task "$agent" question)" --timeout 10
expect_rc "question turn" 10

agent="$(start_agent --label failed-case)"
watch_turn "$(send_task "$agent" failed)" --timeout 10
expect_rc "failed envelope" 11

agent="$(start_agent --label crash-case)"
watch_turn "$(send_task "$agent" crash)" --timeout 10
expect_rc "turn.failed event" 11

agent="$(start_agent --label vanish-case)"
watch_turn "$(send_task "$agent" vanish)" --timeout 10
expect_rc "worker gone without terminal event" 3

agent="$(start_agent --label slow-case)"
turn="$(send_task "$agent" slow)"
watch_turn "$turn" --timeout 1
expect_rc "slow turn first watch times out" 2
watch_turn "$turn" --timeout 10
expect_rc "slow turn second watch completes" 0

agent="$(start_agent --label hang-case)"
turn="$(send_task "$agent" hang)"
set +e
printf 'Again.\n' | "$RUNNER" send "$agent" - > /dev/null 2>&1
send_rc=$?
set -e
if [ "$send_rc" -eq 1 ]; then
  pass "send refused while a turn is live (exit 1)"
else
  fail "send while live returned $send_rc"
fi
sleep 2
watch_turn "$turn" --timeout 5 --idle-seconds 1
expect_rc "hung turn needs attention" 12

pid="$(cat "$CODEX_RUNNER_HOME/turns/$turn.pid")"
"$RUNNER" stop "$agent" > /dev/null
watch_turn "$turn" --timeout 5
expect_rc "stopped turn reports aborted" 4
sleep 0.5
if kill -0 "$pid" 2> /dev/null; then
  fail "worker pid $pid still alive after stop"
else
  pass "stop terminated worker pid"
fi

agent="$(start_agent --label deprecated-case)"
turn="$(send_task "$agent" deprecated)"
watch_turn "$turn" --timeout 1
expect_rc "non-fatal error item keeps the turn running" 2
watch_turn "$turn" --timeout 10
expect_rc "turn with a non-fatal error item completes" 0

agent="$(start_agent --label die-case)"
watch_turn "$(send_task "$agent" die)" --timeout 10
expect_rc "worker died before thread.started" 3
turn="$(send_task "$agent" done)"
if launch_lines | tail -n 1 | grep -q "^exec --json "; then
  pass "send after a threadless turn starts a fresh exec"
else
  fail "send after a threadless turn did not start a fresh exec"
fi
watch_turn "$turn" --timeout 10
expect_rc "fresh turn after a threadless turn" 0

agent="$(start_agent --label race-case)"
launches_before="$(launch_lines | wc -l)"
set +e
printf 'One.\n' | FAKE_CODEX_MODE=hang "$RUNNER" send "$agent" - > /dev/null 2>&1 &
first=$!
printf 'Two.\n' | FAKE_CODEX_MODE=hang "$RUNNER" send "$agent" - > /dev/null 2>&1 &
second=$!
wait "$first"
first_rc=$?
wait "$second"
second_rc=$?
set -e
successes=0
for rc in "$first_rc" "$second_rc"; do
  if [ "$rc" -eq 0 ]; then
    successes=$((successes + 1))
  fi
done
launches=$(($(launch_lines | wc -l) - launches_before))
turns="$("$RUNNER" status "$agent" | json_field 'turns.#')"
if [ "$successes" -eq 1 ] && [ "$launches" -eq 1 ] && [ "$turns" -eq 1 ]; then
  pass "concurrent sends launch exactly one worker"
else
  fail "concurrent sends: $successes ok, $launches launched, $turns turns recorded"
fi
"$RUNNER" stop "$agent" > /dev/null

agent="$(start_agent --label lock-case)"
turn="$(send_task "$agent" done)"
watch_turn "$turn" --timeout 10
expect_rc "lock-case setup turn" 0
# Hold the record lock from outside while a stop and a send race it: the stop must wait and
# still see the record, the send must refuse at once instead of blocking.
python3 - "$CODEX_RUNNER_HOME/agents/$agent.lock" << 'PYEOF' &
import fcntl
import sys
import time

handle = open(sys.argv[1], "w")
fcntl.flock(handle, fcntl.LOCK_EX)
time.sleep(2)
PYEOF
holder=$!
sleep 0.5
set +e
printf 'Three.\n' | "$RUNNER" send "$agent" - > /dev/null 2>&1
send_rc=$?
stop_started=$(date +%s)
"$RUNNER" stop "$agent" > /dev/null
stop_rc=$?
stop_waited=$(($(date +%s) - stop_started))
set -e
wait "$holder"
state="$("$RUNNER" status "$agent" | json_field state)"
if [ "$send_rc" -ne 0 ] && [ "$stop_rc" -eq 0 ] && [ "$stop_waited" -ge 1 ] && [ "$state" = "stopped" ]; then
  pass "writers wait for a held record lock while send refuses at once"
else
  fail "held lock: send rc $send_rc, stop rc $stop_rc after ${stop_waited}s, state $state"
fi

# A stop that arrives while a send holds the lock (here: still reading its task) must wait and
# then kill the turn that send launches, not mark the agent stopped around a live worker.
agent="$(start_agent --label stop-race-case)"
set +e
(
  sleep 1
  printf 'Late.\n'
) | FAKE_CODEX_MODE=hang "$RUNNER" send "$agent" - > /dev/null 2>&1 &
sender=$!
sleep 0.3
"$RUNNER" stop "$agent" > /dev/null
stop_rc=$?
wait "$sender"
set -e
sleep 0.5
survivors=0
for pidfile in "$CODEX_RUNNER_HOME/turns/$agent"-t*.pid; do
  if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2> /dev/null; then
    survivors=$((survivors + 1))
  fi
done
state="$("$RUNNER" status "$agent" | json_field state)"
if [ "$stop_rc" -eq 0 ] && [ "$survivors" -eq 0 ] && [ "$state" = "stopped" ]; then
  pass "stop during a send kills the turn that send launched"
else
  fail "stop during send: stop rc $stop_rc, $survivors live worker(s), state $state"
fi

# A worker that writes its envelope and turn.completed and exits between observe's log read
# and its liveness check must still report done, not gone. A separate home keeps this record
# out of the list count below.
if CODEX_RUNNER_HOME="$TMP/exit-race-home" python3 - "$RUNNER" << 'PYEOF'
import importlib.machinery
import importlib.util
import json
import subprocess
import sys
import time

# Loading the runner as a module would otherwise leave a __pycache__ beside it.
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("codex_runner", sys.argv[1])
spec = importlib.util.spec_from_loader("codex_runner", loader)
runner = importlib.util.module_from_spec(spec)
loader.exec_module(runner)

agent = "exit-race"
turn = f"{agent}-t01"
runner.save_agent({"name": agent, "thread_id": "thread-x", "turns": [turn], "state": "active"})
meta = {"turn": turn, "agent": agent, "started_at": time.time(), "aborted": False}
runner.write_json(runner.turn_path(turn, ".json"), meta)
log = runner.turn_path(turn, ".jsonl")
log.write_text(json.dumps({"type": "thread.started", "thread_id": "thread-x"}) + "\n")

# A reaped child's pid stands in for a worker that has already exited.
finished = subprocess.Popen(["true"])
finished.wait()
runner.turn_path(turn, ".pid").write_text(f"{finished.pid}\n")

real_scan = runner.scan_turn
envelope = {"status": "done", "summary": "late finish", "question": ""}
message = {"type": "agent_message", "text": "ENVELOPE " + json.dumps(envelope)}
late_events = [
    {"type": "item.completed", "item": message},
    {"type": "turn.completed"},
]


def scan_then_finish(name):
    result = real_scan(name)
    with open(log, "a", encoding="utf-8") as handle:
        for event in late_events:
            handle.write(json.dumps(event) + "\n")
    return result


runner.scan_turn = scan_then_finish
code, payload = runner.observe(turn, float("inf"), float("inf"))
if code != runner.EXIT_DONE:
    print(f"observe returned {code}: {payload}", file=sys.stderr)
    sys.exit(1)
PYEOF
then
  pass "turn completed just before the worker exited reports done"
else
  fail "turn completed just before the worker exited was not reported done"
fi

agents="$("$RUNNER" list | json_field '#')"
started="$(wc -l < "$STARTED" | tr -d ' ')"
if [ "$agents" -eq "$started" ]; then
  pass "list shows every agent"
else
  fail "list returned $agents agents, $started were started"
fi

if [ "$failures" -ne 0 ]; then
  echo "codex-runner tests: $failures failure(s)" >&2
  exit 1
fi
echo "codex-runner tests ok"
