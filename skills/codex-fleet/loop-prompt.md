# codex-fleet loop prompt template (Claude orchestrator via /loop)

This drives a multi-round Codex fleet with Claude as orchestrator using native `/loop`, `ScheduleWakeup`, Workflow, `AskUserQuestion`, terminal output, and `PushNotification`.

**Nathan steers through native prompts.** Every decision Nathan makes — approving a slice, redirecting it, answering a mid-flight clarifying question — is surfaced with the **`AskUserQuestion`** tool: the standard Claude Code option prompt he sees on mobile / CLU, with tappable options plus a freeform **Other** choice to type or talk it through. The old typed command grammar (`1 approve`, `1 skip`, …) survives ONLY as a non-interactive fallback (headless/cron hosts) and must never be the primary surface. The `fleet-prompt.sh` helper builds the exact `AskUserQuestion` payloads so they always satisfy the tool's shape.

Preferred launch: run `start-fleet.sh` from the cockpit directory. It seeds `~/.codex-goals/state.env`, `projects.json`, spec mirrors, and the ready-to-paste loop instruction.

The loop never edits a project working tree except the commit-gate fallback commit described in `PHASE == RUNNING`. All other orchestration state writes stay under `~/.codex-goals/`. `MODE=DO` skips only `APPROVAL`; it keeps living specs, clarification polling, board refresh, draft-PR/local-only handling through `fleet-open-pr.sh`, and REVIEW tracking.

---

## Every Tick

At the top of every tick:

1. Read `~/.codex-goals/state.env` and load `ROUND`, `TOTAL_ROUNDS`, `MODE`, and `PHASE`.
2. Load projects from `~/.codex-goals/projects.json`.
3. Run `bash ~/.claude/skills/codex-fleet/fleet-board.sh build`.
4. Keep the project danger hint verbatim. Every Codex goal prompt must include the per-repo danger from `projects.json` and the mirror danger from `~/.codex-goals/<name>.spec.json`.

State values:

- `MODE`: `PLAN` or `DO`
- `PHASE`: `RECON`, `APPROVAL`, `RUNNING`, `REVIEW`, or `DONE`
- mirror status: `planned`, `doing`, `review`, `done`, `blocked`, or `skipped`

## PHASE == RECON

Before recon for this round:

- Keep the existing artifact cleanup. For every project, read `~/.codex-goals/<name>-round-$((ROUND - 1))-artifacts.json` if it exists, kill recorded pids, free recorded ports, then move the artifact record to `.cleaned` or remove it.
- Keep the light health check on each project: `git status -sb`, path accessibility, and obvious missing-repo notes. Log issues but continue unless a project is inaccessible, then mark that project `blocked`.

Run Workflow fresh every round:

```json
{
  "scriptPath": "~/.claude/skills/codex-fleet/recon-workflow.js",
  "args": { "projects": "<contents of projects.json>", "round": "$ROUND" }
}
```

Do not use `resumeFromRunId`. Save the returned objects to `~/.codex-goals/recon-round-$ROUND.json` so APPROVAL/RUNNING can read the same proposals on later ticks.

If `MODE=PLAN`:

- Set `PHASE=APPROVAL` in `state.env`.
- `ScheduleWakeup(delaySeconds: 60)` as the last action.

If `MODE=DO`:

- For each returned project, write `.goalPrompt` to `~/.codex-goals/<name>.md`.
- Run `bash ~/.claude/skills/codex-fleet/fleet-spec.sh set <name> '.status="doing"'`.
- Capture pre-existing dirty state with `git -C <path> status --porcelain > ~/.codex-goals/<name>.pre.status`.
- Launch with `bash ~/.claude/skills/codex-fleet/launch.sh <name> <path> ~/.codex-goals/<name>.md`.
- Set `PHASE=RUNNING` in `state.env`.
- `ScheduleWakeup(delaySeconds: 1500)` as the last action.

## PHASE == APPROVAL

`APPROVAL` exists only for `MODE=PLAN`. If `MODE=DO` reaches this phase, set `PHASE=RUNNING` only after launching any already-approved work; otherwise return to `RECON`.

Nathan approves through the **native `AskUserQuestion` prompt** — the same option surface he sees on mobile / CLU. He never types command grammar in the normal path.

1. Build the prompt payload deterministically:

   ```
   bash ~/.claude/skills/codex-fleet/fleet-prompt.sh approval $ROUND
   ```

   It reads `~/.codex-goals/recon-round-$ROUND.json` + each project mirror and emits `{ "batches": [ [question, ...], ... ] }`. One question per project still `planned`, each already shaped for `AskUserQuestion.questions[]`: the text carries title, why (`specSources`), `sliceSummary`, `tier`, the frozen `verify_cmd`, and acceptance; the options are `Approve (Recommended)` · `Skip` · `Approve as <other-tier>`; the freeform **Other** choice is the redirect/discuss channel.
2. For each batch, call the **`AskUserQuestion`** tool with that batch's array passed **verbatim** as `questions` — do not paraphrase, reorder, or drop options. `AskUserQuestion` blocks until Nathan answers; that block IS the approval gate, so no `ScheduleWakeup` poll is needed in the interactive path. (Batches exist only because the tool caps `questions` at 4 — if the helper emits more than one batch, call the tool once per batch.)
3. Map each answer back to its project (by the header/question you built) and decide:
   - **`Approve (Recommended)`** → approve the proposal as-is.
   - **`Skip`** → run `bash ~/.claude/skills/codex-fleet/fleet-spec.sh set <name> '.status="skipped"'`; do not launch that project this round.
   - **`Approve as <other-tier>`** → `bash ~/.claude/skills/codex-fleet/fleet-spec.sh set <name> '.tier="<other-tier>"'`, then approve.
   - **Freeform (Other / any typed text)** → read the intent:
     - A **directive** ("do X instead", "scope it to Y") is a **redirect**: write `approved_story` from Nathan's text. His redirect overrides recon's `acceptanceCriteria`; derive a compact acceptance list from the redirect and the frozen `verify_cmd` rather than carrying forward rejected criteria.
     - A **question / discussion** ("why this?", "what about Z?") → answer it in the turn, then **re-call `AskUserQuestion` for that project** (rebuild just its question, optionally appending your answer) until Nathan lands on a concrete decision. This is the "talk about it" path.

For every approved or redirected project:

1. Write `approved_story` with shape `{title, why, acceptanceCriteria, keyFiles}`.
2. Set `.status="doing"`.
3. Regenerate `~/.codex-goals/<name>.md` from the approved story, not from unapproved recon acceptance. Keep the full guardrail and git workflow text from recon's `goalPrompt`, but replace the task title, why, and acceptance criteria with Nathan's approved story.
4. Capture pre-existing dirty state with `git -C <path> status --porcelain > ~/.codex-goals/<name>.pre.status`.
5. Launch with `bash ~/.claude/skills/codex-fleet/launch.sh <name> <path> ~/.codex-goals/<name>.md`.

When every project is approved, redirected, or skipped, set `PHASE=RUNNING` and `ScheduleWakeup(delaySeconds: 1500)`.

**Fallback — non-interactive host only.** If this loop runs where `AskUserQuestion` cannot reach a human (a headless/cron host with no interactive client), fall back to the legacy text gate: print one numbered proposal per project to the terminal, send a compact `PushNotification`, and accept typed replies — `1 approve` · `1 redirect <text>` · `1 skip` · optional `tier=prototype`/`tier=production` on any line · `all approve` — blocking with `ScheduleWakeup(delaySeconds: 270)` until a reply arrives. This grammar is a fallback only; never use it when the native prompt can reach Nathan.

## PHASE == RUNNING

For each non-skipped/non-blocked project, poll `tmux capture-pane -t codex-<name> -p`.

ACTIVE detection is unchanged:

- A session is ACTIVE if its pane shows `Working (` OR `Waiting for background terminal` OR an approval/directory-trust prompt.
- If a directory-trust or approval/trust prompt shows, send Enter with `tmux send-keys -t codex-<name> Enter`.
- Absence of "done" text is not idle. When unsure stuck-vs-progressing on a long task, probe the real artifact: curl the dev server, inspect the build output, check `git log`, or read the actual file the task should be changing.

Before any idle/commit check, poll the clarification channel. For every project whose `~/.codex-goals/<name>.question.json` exists with `.status=="open"`:

1. Read it. Set the mirror blocked with the question — this drives the board, and a pending question is a transient pause, not a terminal state:
   `bash ~/.claude/skills/codex-fleet/fleet-spec.sh set <name> ".status=\"blocked\" | .pending_question=$(jq -c . ~/.codex-goals/<name>.question.json)"`
2. Mark the question file `status="notified"` using an atomic temp-file rewrite. Marking `notified` BEFORE prompting keeps it crash-safe: if the tick dies mid-prompt, the next tick re-surfaces it.

Then ask Nathan natively — the same surface as APPROVAL:

3. Build the payload: `bash ~/.claude/skills/codex-fleet/fleet-prompt.sh clarify`. It gathers every project with an `open` or `notified` (not-yet-`answered`) question and emits `{ "batches": [...] }`, each question carrying Codex's own `question` + `context` and its proposed `options`, plus the freeform **Other** choice for an answer in Nathan's own words.
4. For each batch, call **`AskUserQuestion`** with the batch's array verbatim as `questions`. The tool blocks until Nathan answers, and that block holds the round — no Codex session can be cleaned while it is parked. The native prompt already reaches mobile / CLU, so no `PushNotification` is needed for the question itself in the interactive path.

Answer + resume path, per answered project:

- Write the chosen option label (or the freeform text) to `~/.codex-goals/<name>.answer.txt`.
- Mark the question file `status="answered"`.
- Rebuild `~/.codex-goals/<name>.md` from the original goalPrompt plus:

```markdown
--- CONTINUATION ---
Earlier you asked: <Q>
Nathan answered: <A>
Continue the slice from where you left off; do not restart.
```

- Relaunch with `bash ~/.claude/skills/codex-fleet/launch.sh <name> <path> ~/.codex-goals/<name>.md`.
- Set the mirror status back to `doing`.

**Fallback — non-interactive host only.** Where `AskUserQuestion` cannot reach a human, fall back to the legacy channel: `PushNotification` the project / round / question / context / options, then accept a typed answer on a later tick, polling with `ScheduleWakeup(delaySeconds: 270)`. The open → notified → answered state machine is identical either way.

If any session is ACTIVE after the clarification poll, OR any project still has an outstanding clarification question (`~/.codex-goals/<name>.question.json` status `open` or `notified`, not yet `answered`), the round is not complete: call `ScheduleWakeup(delaySeconds: 270)` as the last action and stop the tick. A question pause **holds the whole round** — never advance past `RUNNING` while a question is unanswered, so the next `RECON` artifact cleanup can never kill a paused Codex session.

For each idle project:

1. Read `git -C <path> status -sb`, current branch, and `git -C <path> status --porcelain`.
2. If uncommitted work remains, run the mirror `verify_cmd`. If verify is green, perform the fallback commit:
   - Stage ONLY changed files for this slice by exact path.
   - Never use `git add -A`, `git add .`, or `git add --update`.
   - Do not stage `.claude/`, `.firecrawl/`, `.idea/`, or any file that appears in `~/.codex-goals/<name>.pre.status`.
   - Commit as Nathan only; no `Co-Authored-By`, no "Generated with", no push, no PR, no merge.
3. If verify fails, set mirror `status="blocked"` and record the failure note. Do not do git surgery.
4. Compare current status with `~/.codex-goals/<name>.pre.status`. If a pre-existing dirty file, `.claude`, `.firecrawl`, `.idea`, or a danger-flagged file was folded into the slice, set `status="blocked"` and record a deviation note. Do not rewrite history or attempt repair.
5. Read the latest `branch_lineage` and PR/local-only entry from the mirror. The slice should already have run `fleet-open-pr.sh`; do not push or open PRs by hand. If the committed slice has no lineage entry, mark it `blocked` with a note that `fleet-open-pr.sh` did not record review state.
6. If the tree is clean and lineage exists for this round, set mirror `status="review"` and record a trajectory note comparing intended `keyFiles` to actual changed files.

When every project for the round has reached a round-terminal state — `review`, `done`, `skipped`, or **terminally** `blocked` (failed verify, or a folded danger/deviation) — set `PHASE=REVIEW` and continue to the REVIEW/advance logic. A project `blocked` on an **open or notified clarification question is NOT round-terminal** (its `pending_question` is unanswered); per the clarification hold above it keeps the round in `RUNNING` until Nathan answers and the slice resumes.

## PHASE == REVIEW

Append exactly one `results.tsv` row per project for this round, guarded so a project-round is not duplicated. The row has six columns:

```tsv
round	project	branch	commit	note	status
```

Use the mirror's latest `branch_lineage` for `branch`, `commit`, PR/local-only note, and `status`; use `skipped` or `blocked` when there is no lineage.

Then:

1. Run `bash ~/.claude/skills/codex-fleet/fleet-board.sh build`.
2. Print `bash ~/.claude/skills/codex-fleet/fleet-board.sh show`.
3. Send `PushNotification` containing `bash ~/.claude/skills/codex-fleet/fleet-board.sh text` plus: `review with fleet-review <project> <round>`.

`REVIEW -> DONE` acks happen out-of-band through `fleet-review.sh`; the loop does not block the whole fleet waiting for acks.

If `ROUND < TOTAL_ROUNDS`:

- Increment `ROUND`.
- Set `PHASE=RECON`.
- `ScheduleWakeup(delaySeconds: 60)` as the last action.

If `ROUND == TOTAL_ROUNDS`:

- Set `PHASE=DONE`.
- Print the final board and `~/.codex-goals/results.tsv`.
- Send a final `PushNotification` with the board text and summary.
- Stop. Do not reschedule.

## PHASE == DONE

The run is complete. Print the current board if useful, then stop without `ScheduleWakeup`.
