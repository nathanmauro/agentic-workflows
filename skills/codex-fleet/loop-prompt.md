# codex-fleet loop prompt template (Claude orchestrator via /loop)

This drives a multi-round Codex fleet with Claude as orchestrator using native `/loop`, `ScheduleWakeup`, Workflow, `AskUserQuestion`, terminal output, and `PushNotification`.

**The human owner steers through native prompts.** Every decision the human owner makes — approving a slice, redirecting it, answering a mid-flight clarifying question — is surfaced with the **`AskUserQuestion`** tool: the standard Claude Code option prompt they see on mobile / CLU, with tappable options plus a freeform **Other** choice to type or talk it through. The old typed command grammar (`1 approve`, `1 skip`, …) survives ONLY as a non-interactive fallback (headless/cron hosts) and must never be the primary surface. The [`fleet-prompt.sh`](fleet-prompt.sh) helper builds the exact `AskUserQuestion` payloads so they always satisfy the tool's shape.

Preferred launch: run [`start-fleet.sh`](start-fleet.sh) from the agentic-workflows repo. It creates a timestamped run directory, seeds `state.env` (including `FLEET_SKILL_DIR`), `projects.json`, spec mirrors, and an archived ready-to-paste loop instruction.

**Run directory (`$GOALS`).** Every run atomically owns a directory such as `~/.codex-goals/runs/YYYY/MM/DD-HHMMSS.XXXXXX`, carried in the generated instruction as `RUN_DIR`. Throughout this document, `$GOALS` means that concrete directory. Prefix every helper with `CODEX_GOALS_DIR="$GOALS"`; `launch.sh` pins and exports it into each run-scoped Codex tmux session, and recon receives it as `goalsDir`. `current` is published only after successful initialization. Unpinned manual helpers resolve it, then the legacy flat directory. Concurrent fleets remain isolated as long as each uses its own run dir and no project appears in two live fleets.

The loop never edits a project working tree except the commit-gate fallback commit described in `PHASE == RUNNING`. All other orchestration state writes stay under `$GOALS/`. `MODE=DO` skips only `APPROVAL`; it keeps living specs, clarification polling, board refresh, draft-PR/local-only handling, and REVIEW tracking. `MODE=FULL_AUTO` behaves like DO through RUNNING, then calls the fail-closed merge helper during REVIEW.

---

## Every Tick

At the top of every tick:

1. Read `$GOALS/state.env` and load `ROUND`, `TOTAL_ROUNDS`, `MODE`, `PHASE`, and `FLEET_SKILL_DIR`. If `FLEET_SKILL_DIR` is absent, use `${FLEET_SKILL_DIR:-skills/codex-fleet}` relative to the agentic-workflows repo.
2. Load projects from `$GOALS/projects.json`.
3. Run `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-board.sh" build`.
4. Keep the project danger hint verbatim. Every Codex goal prompt must include the per-repo danger from `projects.json` and the mirror danger from `$GOALS/<name>.spec.json`.

State values:

- `MODE`: `PLAN`, `DO`, or `FULL_AUTO`
- `PHASE`: `RECON`, `APPROVAL`, `RUNNING`, `REVIEW`, or `DONE`
- mirror status: `planned`, `doing`, `review`, `done`, `blocked`, or `skipped`

## PHASE == RECON

Before recon for this round:

- Keep the existing artifact cleanup. For every project, read `$GOALS/<name>-round-$((ROUND - 1))-artifacts.json` if it exists, kill recorded pids, free recorded ports, then move the artifact record to `.cleaned` or remove it.
- Keep the light health check on each project: `git status -sb`, path accessibility, and obvious missing-repo notes. Log issues but continue unless a project is inaccessible, then mark that project `blocked`.

Run Workflow fresh every round:

```json
{
  "scriptPath": "$FLEET_SKILL_DIR/recon-workflow.js",
  "args": {
    "projects": "<contents of projects.json>",
    "round": "$ROUND",
    "fleetSkillDir": "$FLEET_SKILL_DIR",
    "goalsDir": "$GOALS"
  }
}
```

Do not use `resumeFromRunId`. Save the returned objects to `$GOALS/recon-round-$ROUND.json` so APPROVAL/RUNNING can read the same proposals on later ticks.

If `MODE=PLAN`:

- Set `PHASE=APPROVAL` in `state.env`.
- `ScheduleWakeup(delaySeconds: 60)` as the last action.

If `MODE=DO` or `MODE=FULL_AUTO`:

- For each returned project, write `.goalPrompt` to `$GOALS/<name>.md`.
- Run `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-spec.sh" set <name> '.status="doing"'`.
- Capture pre-existing dirty state with `git -C <path> status --porcelain > $GOALS/<name>.pre.status`.
- Launch with `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/launch.sh" <name> <path> $GOALS/<name>.md`.
- Set `PHASE=RUNNING` in `state.env`.
- `ScheduleWakeup(delaySeconds: 1500)` as the last action.

## PHASE == APPROVAL

`APPROVAL` exists only for `MODE=PLAN`. If `MODE=DO` or `MODE=FULL_AUTO` reaches this phase, set `PHASE=RUNNING` only after launching any already-approved work; otherwise return to `RECON`.

The human owner approves through the **native `AskUserQuestion` prompt** — the same option surface they see on mobile / CLU. They never type command grammar in the normal path.

1. Build the prompt payload deterministically:

   ```
   CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-prompt.sh" approval $ROUND
   ```

   It reads `$GOALS/recon-round-$ROUND.json` + each project mirror and emits `{ "batches": [ [question, ...], ... ] }`. One question per project still `planned`, each already shaped for `AskUserQuestion.questions[]`: the text carries title, why (`specSources`), `sliceSummary`, `tier`, the frozen `verify_cmd`, and acceptance; the options are `Approve (Recommended)` · `Skip` · `Approve as <other-tier>`; the freeform **Other** choice is the redirect/discuss channel.

2. For each batch, call the **`AskUserQuestion`** tool with that batch's array passed **verbatim** as `questions` — do not paraphrase, reorder, or drop options. `AskUserQuestion` blocks until the human owner answers; that block IS the approval gate, so no `ScheduleWakeup` poll is needed in the interactive path. (Batches exist only because the tool caps `questions` at 4 — if the helper emits more than one batch, call the tool once per batch.)
3. Map each answer back to its project (by the header/question you built) and decide:
   - **`Approve (Recommended)`** → approve the proposal as-is.
   - **`Skip`** → run `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-spec.sh" set <name> '.status="skipped"'`; do not launch that project this round.
   - **`Approve as <other-tier>`** → `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-spec.sh" set <name> '.tier="<other-tier>"'`, then approve.
   - **Freeform (Other / any typed text)** → read the intent:
     - A **directive** ("do X instead", "scope it to Y") is a **redirect**: write `approved_story` from the human owner's text. Their redirect overrides recon's `acceptanceCriteria`; derive a compact acceptance list from the redirect and the frozen `verify_cmd` rather than carrying forward rejected criteria.
     - A **question / discussion** ("why this?", "what about Z?") → answer it in the turn, then **re-call `AskUserQuestion` for that project** (rebuild just its question, optionally appending your answer) until the human owner lands on a concrete decision. This is the "talk about it" path.

For every approved or redirected project:

1. Write `approved_story` with shape `{title, why, acceptanceCriteria, keyFiles}`.
2. Set `.status="doing"`.
3. Regenerate `$GOALS/<name>.md` from the approved story, not from unapproved recon acceptance. Keep the full guardrail and git workflow text from recon's `goalPrompt`, but replace the task title, why, and acceptance criteria with the human owner's approved story.
4. Capture pre-existing dirty state with `git -C <path> status --porcelain > $GOALS/<name>.pre.status`.
5. Launch with `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/launch.sh" <name> <path> $GOALS/<name>.md`.

When every project is approved, redirected, or skipped, set `PHASE=RUNNING` and `ScheduleWakeup(delaySeconds: 1500)`.

**Fallback — non-interactive host only.** If this loop runs where `AskUserQuestion` cannot reach a human (a headless/cron host with no interactive client), fall back to the legacy text gate: print one numbered proposal per project to the terminal, send a compact `PushNotification`, and accept typed replies — `1 approve` · `1 redirect <text>` · `1 skip` · optional `tier=prototype`/`tier=production` on any line · `all approve` — blocking with `ScheduleWakeup(delaySeconds: 270)` until a reply arrives. This grammar is a fallback only; never use it when the native prompt can reach the human owner.

## PHASE == RUNNING

For each non-skipped/non-blocked project, read its exact run-scoped tmux target from
`$GOALS/<name>.session`, then poll `tmux capture-pane -t "<session-from-file>" -p`.
If the session file is missing after launch, mark the project blocked rather than
guessing a global session name.

ACTIVE detection is unchanged:

- A session is ACTIVE if its pane shows `Working (` OR `Waiting for background terminal` OR an approval/directory-trust prompt.
- If a directory-trust or approval/trust prompt shows, send Enter to the exact
  session from `$GOALS/<name>.session`.
- Absence of "done" text is not idle. When unsure stuck-vs-progressing on a long task, probe the real artifact: curl the dev server, inspect the build output, check `git log`, or read the actual file the task should be changing.

Before any idle/commit check, poll the clarification channel. For every project whose `$GOALS/<name>.question.json` exists with `.status=="open"`:

1. Read it. Set the mirror blocked with the question — this drives the board, and a pending question is a transient pause, not a terminal state:
   `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-spec.sh" set <name> ".status=\"blocked\" | .pending_question=$(jq -c . $GOALS/<name>.question.json)"`
2. Mark the question file `status="notified"` using an atomic temp-file rewrite. Marking `notified` BEFORE prompting keeps it crash-safe: if the tick dies mid-prompt, the next tick re-surfaces it.

Then ask the human owner natively — the same surface as APPROVAL:

3. Build the payload: `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-prompt.sh" clarify`. It gathers every project with an `open` or `notified` (not-yet-`answered`) question and emits `{ "batches": [...] }`, each question carrying Codex's own `question` + `context` and its proposed `options`, plus the freeform **Other** choice for an answer in the human owner's own words.
4. For each batch, call **`AskUserQuestion`** with the batch's array verbatim as `questions`. The tool blocks until the human owner answers, and that block holds the round — no Codex session can be cleaned while it is parked. The native prompt already reaches mobile / CLU, so no `PushNotification` is needed for the question itself in the interactive path.

Answer + resume path, per answered project:

- Write the chosen option label (or the freeform text) to `$GOALS/<name>.answer.txt`.
- Mark the question file `status="answered"`.
- Rebuild `$GOALS/<name>.md` from the original goalPrompt plus:

```markdown
--- CONTINUATION ---
Earlier you asked: <Q>
The human owner answered: <A>
Continue the slice from where you left off; do not restart.
```

- Relaunch with `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/launch.sh" <name> <path> $GOALS/<name>.md`.
- Set the mirror status back to `doing`.

**Fallback — non-interactive host only.** Where `AskUserQuestion` cannot reach a human, fall back to the legacy channel: `PushNotification` the project / round / question / context / options, then accept a typed answer on a later tick, polling with `ScheduleWakeup(delaySeconds: 270)`. The open → notified → answered state machine is identical either way.

If any session is ACTIVE after the clarification poll, OR any project still has an outstanding clarification question (`$GOALS/<name>.question.json` status `open` or `notified`, not yet `answered`), the round is not complete: call `ScheduleWakeup(delaySeconds: 270)` as the last action and stop the tick. A question pause **holds the whole round** — never advance past `RUNNING` while a question is unanswered, so the next `RECON` artifact cleanup can never kill a paused Codex session.

For each idle project:

1. Read `git -C <path> status -sb`, current branch, and `git -C <path> status --porcelain`.
2. If uncommitted work remains, run the mirror `verify_cmd`. If verify is green, perform the fallback commit:
   - Stage ONLY changed files for this slice by exact path.
   - Never use `git add -A`, `git add .`, or `git add --update`.
   - Do not stage `.claude/`, `.firecrawl/`, `.idea/`, or any file that appears in `$GOALS/<name>.pre.status`.
   - Commit as the human owner only; no `Co-Authored-By`, no "Generated with", no push, no PR, no merge.
3. If verify fails, set mirror `status="blocked"` and record the failure note. Do not do git surgery.
4. Compare current status with `$GOALS/<name>.pre.status`. If a pre-existing dirty file, `.claude/`, `.firecrawl/`, `.idea/`, or a danger-flagged file was folded into the slice, set `status="blocked"` and record a deviation note. Do not rewrite history or attempt repair.
5. Read the latest `branch_lineage` and PR/local-only entry from the mirror. The slice should already have run [`fleet-open-pr.sh`](fleet-open-pr.sh); do not push or open PRs by hand. If the committed slice has no lineage entry, mark it `blocked` with a note that [`fleet-open-pr.sh`](fleet-open-pr.sh) did not record review state.
6. If the tree is clean and lineage exists for this round, set mirror `status="review"` and record a trajectory note comparing intended `keyFiles` to actual changed files.

When every project for the round has reached a round-terminal state — `review`, `done`, `skipped`, or **terminally** `blocked` (failed verify, or a folded danger/deviation) — set `PHASE=REVIEW` and continue to the REVIEW/advance logic. A project `blocked` on an **open or notified clarification question is NOT round-terminal** (its `pending_question` is unanswered); per the clarification hold above it keeps the round in `RUNNING` until the human owner answers and the slice resumes.

## PHASE == REVIEW

**`MODE=FULL_AUTO` only:** before the ledger bookkeeping below, call the merge helper for every current-round slice with a real PR:

```bash
CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-merge.sh" <name> <round>
```

The helper verifies `FULL_AUTO`, `PHASE=REVIEW`, the global and mirror round/status,
the selected repository, and the recorded PR head/base before doing anything external.
It marks a draft ready, allows ready-triggered checks to register, polls checks with a
bounded deadline, then re-runs every authority and identity gate before a head-bound
squash merge. A slice moves to `done` only after GitHub reports `MERGED`; a merge-queue
or auto-merge submission remains in `review` until a later retry confirms completion.
Any revoked, gated, changed-head, failed, or timed-out slice remains in `review` for a
human, and so does a slice stacked on another fleet branch rather than the mirror's
`default_branch`. `PLAN` and `DO` never call this helper.

After all FULL_AUTO helper calls, inspect the current-round lineage entries. If any
entry has `status="review"` and `merge_state` equal to `submitting` or `pending`, keep
`PHASE=REVIEW`, rebuild and print the board, call `ScheduleWakeup(delaySeconds: 60)` as
the last action, and stop this tick. **Do not advance the mirrors/global round and do
not enter DONE while a merge submission is unresolved.** `submitting` is written
before the external command, so a crash, a transient post-submit read, or a `gh pr merge`
failure the helper cannot classify as a refusal (network error, timeout, rate limit, 5xx)
stays `submitting` and is retry-safe; the helper exits nonzero in that last case. If such a
failure leaves auto-merge enabled on GitHub, the helper records `pending` instead. The
next REVIEW tick calls the helper again; `pending` retries only check for remote
`MERGED`, while `submitting` safely retries the head-bound submission. Only when GitHub's
error names a refusal (required review, branch protection or rules, conflict, moved head,
permissions) does the helper record `merge_state="rejected"` with the refusal in the note;
that is an ordinary review item and does not hold the round. A rejection sticks for the
rest of the round: later ticks never re-submit it, though they still record a merge a
human performed on GitHub. A human may
still close the item explicitly with the pinned `fleet-review.sh` command.

Upsert exactly one locked `results.tsv` row per project for this round:

```bash
CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-results.sh" upsert \
  <round> <project> <branch> <commit> <note> <status>
```

The helper serializes concurrent conductor, merge, and acknowledgement writers and
keeps exactly one row per project-round. The row has six columns:

```tsv
round	project	branch	commit	note	status
```

Use the mirror's latest `branch_lineage` for `branch`, `commit`, PR/local-only note, and `status`; use `skipped` or `blocked` when there is no lineage.

Then:

1. Run `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-board.sh" build`.
2. Print `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-board.sh" show`.
3. Send `PushNotification` containing `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-board.sh" text` plus the pinned acknowledgement command `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-review.sh" <project> <round>`.

`REVIEW -> DONE` acks happen out-of-band through [`fleet-review.sh`](fleet-review.sh);
the loop does not block the whole fleet waiting for ordinary acks. The one exception is
a persisted FULL_AUTO submitting/pending state, which holds REVIEW so the helper can
resolve it before the round moves. In FULL_AUTO, a manual ack closes the workflow
review item; it does not claim that an unmerged PR was merged.

If `ROUND < TOTAL_ROUNDS`:

- Compute `NEXT_ROUND=$((ROUND + 1))`. For every project in `$GOALS/projects.json`,
  run `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-spec.sh" advance
<name> "$NEXT_ROUND"`. This resets only the per-round proposal/question state,
  preserves `branch_lineage`, and is retry-safe while the target remains planned.
- After every per-project advance succeeds, atomically commit the global handoff:
  `CODEX_GOALS_DIR="$GOALS" bash "$FLEET_SKILL_DIR/fleet-state.sh" "$ROUND"
"$NEXT_ROUND"`. The helper locks run-scoped state, verifies that every project
  mirror is at the next round with `status="planned"`, then changes global
  `ROUND` and `PHASE` together. It is safe to retry after success and fails closed
  if only part of the fleet advanced.
- `ScheduleWakeup(delaySeconds: 60)` as the last action.

If `ROUND >= TOTAL_ROUNDS`:

- Set `PHASE=DONE`.
- Print the final board and `$GOALS/results.tsv`.
- Send a final `PushNotification` with the board text and summary.
- Stop. Do not reschedule.

## PHASE == DONE

The run is complete. Print the current board if useful, then stop without `ScheduleWakeup`.
