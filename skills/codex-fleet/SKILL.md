---
name: codex-fleet
description: >
  Use when the user wants to advance several local code projects at once over multiple
  rounds, one Codex session per project, leaving each project's work on stacked feature
  branches. Default is PLAN mode: Claude proposes each project's next vertical slice and
  the human owner approves, redirects, or skips it through Claude Code's native option
  prompts on the terminal or a phone, with mid-flight clarifying questions surfaced the
  same way. DO is unattended execution; FULL_AUTO is DO plus an explicit, fail-closed
  merge grant. Triggers: "codex fleet", "run codex across my projects", "fire up a codex
  session per project and do what's next", "plan mode fleet", "loop this N times across
  my repos". Each project carries a living spec, a stakes tier, and a slim fleet-wide
  kanban board.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Set your models through the client or env knobs, and replace paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex Fleet: multi-project agentic SDLC (PLAN, DO, FULL_AUTO)

Claude is the **conductor and safety boundary**; one **Codex** session per project is the
engine. The work unit is a **vertical slice** (one story) per project per round. Three modes
share one machine:

- **PLAN** (default). Claude proposes each project's next slice from its living spec. The
  human owner **approves, redirects, or skips** it before any code runs, through Claude
  Code's **native option prompt** (`AskUserQuestion`): the usual tappable surface on a
  terminal or phone, with a freeform **Other** choice to redirect or talk it through. Codex
  asks **clarifying questions mid-flight** through the same prompt when the spec does not
  decide something, like a developer who does not guess.
- **DO**. The unattended run: recon picks the slice and Codex executes it immediately. Same
  living spec, clarification channel, PR gate, and board; it skips only the approval gate.
- **FULL_AUTO**. DO plus an explicit merge grant. The human-owned merge rule is suspended in
  this mode only, and only through [`fleet-merge.sh`](fleet-merge.sh). RECON and RUNNING
  behave exactly as in DO. In REVIEW the helper gates each slice that has an open PR from
  the current round and squash-merges only a green one. A red, timed-out, queued, or
  gated slice stays in review for a normal human acknowledgement.

Every slice lands on its own `fleet/round-N-<slug>` branch. With a remote PR it stacks
only on a still-open previous PR; a local-only slice stacks on the previous local-only
branch while that branch exists. For non-danger-flagged repos with a remote, `gh`, and an
explicit push grant, a **draft PR** is opened per slice.
In PLAN and DO the human owner reviews along the way and merges; the fleet never merges.
Danger-flagged and public repos stay strictly local in every mode.

Public workflow guide: [`docs/workflows/codex-fleet.md`](../../docs/workflows/codex-fleet.md).
Pattern rationale: [`docs/concepts/fleet-execution.md`](../../docs/concepts/fleet-execution.md).
Starter inputs and sanitized examples:
[`templates/fleet-projects.json`](../../templates/fleet-projects.json) and
[`examples/fleet-round/`](../../examples/fleet-round/).

## When to use

- "Look at my projects, figure out what's next on each, and let me steer it." (PLAN)
- "Fire up a Codex session per project and run the next slice." / "codex fleet"
- "Put this on a loop, keep going N rounds, and ping me when you need a decision."

**When NOT to use:**

- A single project or task. Use `codex-workflow-hybrid`, which drives one Codex worker over
  the supervised channel ([`scripts/codex-runner`](../../scripts/codex-runner)).
- The same project in two live fleets. tmux sessions are run-scoped, but branches and
  working trees are per project.
- Anything that must merge automatically outside FULL_AUTO's fail-closed gates. PLAN and DO
  never merge.

## Relationship to supervised delegation

The shared contract for handing work to a second agent is supervised delegation
(`docs/concepts/supervised-delegation.md`): separate send and watch, the worker's own
transcript as the data plane, a one-line result envelope, and bounded attention. The
reference adapter is [`scripts/codex-runner`](../../scripts/codex-runner) with the verbs
`start`, `send`, `watch`, and `stop` and the shared exit-code table (0 done, 10 question,
11 failed, 2 timeout, 3 blocked or gone, 4 aborted, 12 attention, 1 error).

The fleet applies the same rules to many long-lived interactive sessions at once, with
file-based equivalents instead of the runner's envelope:

| Contract rule                     | Fleet equivalent                                                                            |
| --------------------------------- | ------------------------------------------------------------------------------------------- |
| Send and wait are separate        | `launch.sh` returns immediately; each `/loop` tick observes and reschedules                 |
| Result is structured, not scraped | `<name>.question.json`, `<name>-round-N-artifacts.json`, the spec mirror, and `results.tsv` |
| A question is not a completion    | An open question file holds the round; it is never treated as `blocked`                     |
| Attention is bounded and explicit | The ACTIVE rule plus an artifact probe; silence is never proof of idleness                  |
| The human stays sole author       | Codex commits as the owner only, behind the scope, deviation, and push gates                |

## Inputs (interactive via start-fleet.sh)

```bash
cd <agentic-workflows-repo>
./skills/codex-fleet/start-fleet.sh
```

It prompts for: which projects (numbers, ranges, names, or paths; numbered discovery needs
`CODEX_FLEET_PROJECT_ROOT`), a per-project **hint** (per-repo dangers, copied verbatim into
every goal prompt), a per-project **tier** (`production` default or `prototype`), the
**mode** (`PLAN` default, `DO`, or `FULL_AUTO`), and the **round count**. It then runs
pre-flight health checks and asks for an explicit per-project push and draft-PR grant.
**`push_allowed`** is true only when that grant is given, an `origin` remote exists, `gh` is
on PATH, and the danger hint does not forbid pushing. It seeds a **living-spec mirror** per
project, writes `projects.json` and `state.env` into the run directory, and emits that run's
`loop-instruction.txt`. Paste its full contents into Claude's `/loop` (dynamic, no
interval).

## Run directory (one directory per fleet run)

Each `start-fleet.sh` invocation atomically creates a unique run directory with
`mktemp -d`, for example `~/.codex-goals/runs/YYYY/MM/DD-HHMMSS.XXXXXX/`. It holds that run's
entire state: `loop-instruction.txt` (the archived instructions), `state.env`,
`projects.json`, spec mirrors, goal prompts, questions, artifacts, session names,
`board.json`, and `results.tsv`. Old runs are never overwritten, so you can always read
exactly what a past fleet was told to do.

- **`current` is published last.** `~/.codex-goals/current` is a symlink to the most
  recently _completed_ setup. It is repointed only after the run is fully seeded, so a
  cancelled or failed setup leaves the previous `current` intact. A `current` path that
  exists but is not a symlink fails closed before any directory is allocated.
- **Fresh state every time.** An inherited `CODEX_GOALS_DIR` is ignored at start, so
  starting a fleet from inside another fleet cannot reset or reuse a live run.
- **Legacy guard.** If a legacy flat-layout `~/.codex-goals/state.env` is not at
  `PHASE=DONE`, start asks before repointing `current`, because that run's unpinned helper
  calls would follow the new symlink.

**Resolution order** in every helper and the launcher: explicit `CODEX_GOALS_DIR`, then
`~/.codex-goals/current` (a dangling link is skipped), then the legacy flat
`~/.codex-goals`.

**Concurrent fleets.** The generated loop instruction pins its own `RUN_DIR` and passes it
on every helper call as `CODEX_GOALS_DIR`, into each Codex tmux session (`launch.sh`
resolves the physical path with `pwd -P` and exports it), and into the recon Workflow as
`goalsDir` (recon refuses to run without it rather than guess). tmux session names hash
both the run directory and the original project name, and each name is recorded in
`<run-dir>/<name>.session`, so concurrent fleets never share state or kill each other's
sessions. For manual commands against a non-current run, for example `fleet-review.sh` on
an older fleet, prefix `CODEX_GOALS_DIR=<run-dir>`.

## State machine

`<run-dir>/state.env` holds `ROUND`, `TOTAL_ROUNDS`, `MODE` (`PLAN`, `DO`, or `FULL_AUTO`),
`FLEET_SKILL_DIR`, and `PHASE` (`RECON`, `APPROVAL`, `RUNNING`, `REVIEW`, `DONE`; `APPROVAL`
runs only in PLAN). Per-project `status` (`planned`, `doing`, `review`, `done`, `blocked`,
`skipped`) lives in the spec mirror and drives the board.

The round handoff is two-step and retry-safe. The loop first runs `fleet-spec.sh advance`
for every project, then [`fleet-state.sh`](fleet-state.sh) `<round> <next-round>` locks the
run, verifies that every mirror is at the next round with `status="planned"`, and changes
`ROUND` and `PHASE` together. A partial advance, or a merge still `pending` or `submitting`,
fails closed and holds REVIEW.

## The living spec (the contract with the AI)

Two files, with fleet-side writes serialized:

- **In-repo `docs/fleet/spec.md`**: markdown body plus YAML frontmatter, versioned with the
  project and PR-reviewed. Written by **Codex** via [`fleet-spec.sh`](fleet-spec.sh)
  `render` and committed _with_ the slice. Human-edited body blocks survive re-render.
- **Fleet-side `<run-dir>/<name>.spec.json`**: live machine state, written by the
  **orchestrator (Claude)**, plus Codex's own slice `branch_lineage` via
  [`fleet-open-pr.sh`](fleet-open-pr.sh). `fleet-spec.sh set` and `advance` use an atomic
  lock and rename, so concurrent conductor and helper updates never overwrite each other.
  Never committed; the board derives from it.

Round N reads the spec as primary context, so decisions and guardrails carry forward instead
of being re-derived from a cold recon.

## Clarification channel (the developer who does not guess)

If Codex hits a fork the spec does not decide (scope, architecture, user-facing behavior,
safety), it writes `<run-dir>/<name>.question.json` and **stops** instead of guessing. The
loop surfaces the question as a native `AskUserQuestion` prompt (Codex's own options plus a
freeform **Other** answer) and **holds the round**. It never advances while a question is
unanswered; a pending question is a transient pause, not terminal `blocked`. Once the human
owner replies, `launch.sh` relaunches the slice with a continuation block ("you asked Q, the
human owner answered A, continue"). The `open`, `notified`, `answered` state machine is
unchanged; on a headless host it falls back to the configured notification channel plus a
typed reply.

## Draft PR per slice (push-grant and danger gated)

At the commit gate Codex runs [`fleet-open-pr.sh`](fleet-open-pr.sh)
`<name> <round> <branch>`, which **fails closed**. It goes LOCAL-ONLY when
`push_allowed != true`, `gh` is missing, there is no `origin`, or the danger hint matches
`PUBLIC|never push|do not push` (case-insensitive; write one of those exact phrases, such
as "do not push", to block pushing). It also refuses a non-fleet branch, a round the mirror has
not authorized, a branch that is not checked out or whose tip is not `HEAD`, and a call
from outside the selected project worktree. Push authority is re-read immediately before
the push. Otherwise it pushes and opens a **draft** PR (human owner sole author, no
attribution in the body). It stacks on the previous slice only while that PR is still open
and its remote head exists; a merged, closed, or deleted base falls back to the default
branch. A local-only slice stacks on the previous local-only branch when it is still a
local ancestor, and prints a hand-off that pushes the branch (and that unpushed base) before
`gh pr create`; with no `origin`, the hand-off says to add a remote first.

## Auto-merge per slice (FULL_AUTO only)

In REVIEW with `MODE=FULL_AUTO`, the loop runs [`fleet-merge.sh`](fleet-merge.sh)
`<name> <round>` on every slice with an open PR from this round. Each gate that fails is a
`NOOP:` that leaves the slice untouched in review:

1. **Stale lineage.** The newest `branch_lineage` entry must belong to the requested round;
   otherwise the helper prints "no PR for round N" before any other gate runs.
2. **Run state.** `MODE=FULL_AUTO`, `PHASE=REVIEW`, and global `ROUND` equal to the
   requested round.
3. **Slice state.** Mirror `status` and lineage `status` are `review`, mirror
   `current_round` matches, `push_allowed` is true, no danger hint, and a real PR (not
   `local-only`) with a recorded head SHA.
4. **Identity.** The project path is a Git worktree, its `origin` maps to the same
   repository as the PR URL, and the PR head branch, base, and head commit match the
   recorded lineage. The base must be the mirror's `default_branch`: a slice stacked on a
   still-open fleet branch would squash into that branch, so it stays in review for a
   human. `gh` must be on PATH.

A draft is marked ready only after identity passes, and checks are polled after that so
ready-triggered CI is observed. Polling uses `gh pr checks` without `--watch` and needs no
`timeout` binary. Red checks leave the slice in review immediately; checks still pending at
the deadline leave it in review with a "checks timeout after Ns" note. A repository that
reports no configured checks after the registration grace merges with that fact recorded
in the ledger.

After CI, every gate is re-read and the lineage must be identical to the one whose checks
were observed. The helper writes a `submitting` state ahead of the external call, re-reads
the gates once more, then runs `gh pr merge --squash --match-head-commit <sha>`. It does not
request branch deletion, so merge queues keep working. Only a remote `MERGED` with
`mergedAt` is terminal: the ledger row is written first, then the mirror flips to `done`. A
queue or auto-merge enrollment that has not merged by the confirmation deadline becomes
`pending`; later REVIEW ticks only confirm and never submit twice. A merge GitHub refuses
outright (its error names a required review, branch protection or rules, a conflict, a moved
head, or permissions) is recorded as `merge_state="rejected"` with the refusal in the note,
so it no longer holds REVIEW and waits for a human like any other gated slice; later ticks
do not re-submit it but still record a manual merge. Any other `gh pr merge` failure
(network, timeout, rate limit, 5xx) keeps `submitting` and exits nonzero so the next tick
retries, or becomes `pending` when GitHub shows auto-merge already enabled.

| Knob                                   | Default | Meaning                                        |
| -------------------------------------- | ------- | ---------------------------------------------- |
| `FLEET_MERGE_CHECKS_TIMEOUT`           | 1800    | Seconds to wait for pending checks             |
| `FLEET_MERGE_POLL_INTERVAL`            | 30      | Seconds between check polls                    |
| `FLEET_MERGE_CHECK_REGISTRATION_GRACE` | 60      | Seconds a just-readied PR may report no checks |
| `FLEET_MERGE_CONFIRM_TIMEOUT`          | 300     | Seconds to wait for GitHub to report `MERGED`  |
| `FLEET_MERGE_CONFIRM_INTERVAL`         | 15      | Seconds between confirmation polls             |

PLAN and DO never call `fleet-merge.sh`, and the helper refuses them itself.

## Model, effort, and service tier

Skills are model-generic. [`launch.sh`](launch.sh) exposes three env knobs and pins no
model:

- `CODEX_MODEL` has no default; when unset, the Codex client default model applies.
- `CODEX_EFFORT` defaults to the highest reasoning effort tier, because unattended fleet
  rounds depend on it. Set it empty to defer to the client default.
- `CODEX_TIER` has no default, so the client default (standard) service tier applies.

The tier rule: attended delegation (a human watching one worker, as in
`codex-workflow-hybrid`) uses the fast service tier at high reasoning effort; unattended
fleet rounds use the standard tier at the highest effort, since speed is wasted on a run
nobody is watching. The launch line prints the effective values, with `client-default` for
any knob left unset.

## Tiers and the board

`tier` is `prototype` or `production` per project. It is advisory context: recon and the
approval prompt read it to calibrate how heavy a slice and its eval bar should be, and the
human can flip it at approval. No helper gates on it. Push and draft PRs are gated only by
`push_allowed`, the explicit push grant, and the danger hint; the mode is fleet-wide.

[`fleet-board.sh`](fleet-board.sh) `build|show|text` renders a **fleet-wide grid** (projects
by `Planned`, `Doing`, `Review`, `Done`, `Blocked`), regenerated each loop tick as a pure
read-only view with zero agent bookkeeping. Terminal uses `show`; the configured
notification channel uses `text`.

In PLAN and DO the one human-driven transition is **REVIEW to DONE**:
`CODEX_GOALS_DIR=<run-dir> fleet-review.sh <project> <round>`. Pin the run directory; an
unpinned acknowledgement resolves `current`, which is the newest fleet. A delayed
acknowledgement updates only its own lineage entry and cannot be repeated. Unreviewed work
accumulates **visibly**, never silently. In FULL_AUTO a merged slice moves to done by
itself; any other slice needs the same `fleet-review.sh` acknowledgement, which records
workflow acceptance and does not claim the PR merged.

**ACTIVE detection (hard-won):** a session is still working if its pane shows `Working (`
or `Waiting for background terminal` or an approval or trust prompt. Absence of "done"
text is NOT idle. When unsure whether a session is stuck or progressing, probe the real
artifact (curl the dev server, check `git log`) instead of staring at the pane.

## Guardrails (embedded verbatim in every Codex goal prompt)

- **Identity:** commit as the human owner only. NO `Co-Authored-By` naming Claude, Codex,
  or a model, and NO "Generated with" lines. This global rule overrides any default.
- **Branch:** a new `fleet/round-N-<slug>`. With remote PRs, stack only on a still-open
  remote PR; after a merge, close, or deletion, fetch and branch from the remote default
  branch. A local-only slice stacks on the previous local-only branch while it exists; with
  no remote, branch from the local default branch.
- **Push/PR:** push and open a **draft** PR for non-danger-flagged repos with a remote,
  only when the human explicitly granted push for that project and run.
  Danger-flagged, public, and no-remote repos stay local-only in every mode. PLAN and DO
  never merge; FULL_AUTO merges only through the fail-closed helper.
- **Scope:** stage explicitly, NEVER `git add -A`, `.`, or `--update`. Exclude `.claude/`,
  `.firecrawl/`, `.idea/`, and any pre-existing dirty files.
- **Verify before commit:** run the repo's test or verify command; commit only green.
- **Fail closed:** on a flagged danger or failed verify, set `blocked` with a ledger note
  and do NO mid-run git surgery.
- **Autonomy:** the launcher uses `-a never` with an explicit `workspace-write` sandbox: the
  project, its git dir (to branch and commit), the run dir, and network for push and `gh`.
  It does not inherit sandbox settings from the user's Codex config. This skill
  is a **manual trust boundary**: starting the run is the execution grant, and selecting
  FULL_AUTO is the separate merge grant.
- **Per-repo dangers** travel in the project `hint` and the spec (for example,
  example-public-repo: origin is PUBLIC; a protected experiment branch and its sibling
  worktree may contain sensitive data and are NEVER touched or pushed).

## Watch for the deviation pattern

A Codex session may fold pre-existing dirty files into its commit (observed: example-service
folded `preexisting-ui-file.tsx` and `theme.css`). The commit gate diffs
`git status --porcelain` against `<run-dir>/<name>.pre.status`; a folded pre-existing or
danger file flips the project to `blocked` with a deviation note. Do NOT do git surgery
mid-run; isolated commits are recoverable.

## Files (bundled next to this skill)

| File                                     | Role                                                                                                                                                                                                                 |
| ---------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`start-fleet.sh`](start-fleet.sh)       | Entry point: interactive projects, hints, **tier**, **mode**, rounds; health checks and `push_allowed`; allocates the run dir, seeds spec mirrors and state, writes `loop-instruction.txt`, publishes `current` last |
| [`init-fleet.sh`](init-fleet.sh)         | Seeds `state.env` (including `MODE`) and the 6-column `results.tsv` ledger                                                                                                                                           |
| [`recon-workflow.js`](recon-workflow.js) | Recon and vet Workflow: reads the living spec, proposes the next **vertical slice**, and emits the goal prompt with the spec-render, clarification, and PR-gate git workflow; requires `goalsDir`                    |
| [`loop-prompt.md`](loop-prompt.md)       | The `/loop` driver: the `MODE`/`PHASE` machine (APPROVAL, clarification poll and round hold, commit gate, REVIEW, board)                                                                                             |
| [`fleet-prompt.sh`](fleet-prompt.sh)     | Builds the native `AskUserQuestion` payloads, `approval <round>` and `clarify`, within the tool's shape limits                                                                                                       |
| [`launch.sh`](launch.sh)                 | Run- and name-hashed tmux plus `codex -a never` launcher with env model knobs and continuation relaunch                                                                                                              |
| [`fleet-spec.sh`](fleet-spec.sh)         | Locked living-spec data layer: `init`, `get`, `set`, retry-safe `advance`, and `render` into in-repo `docs/fleet/spec.md`                                                                                            |
| [`fleet-open-pr.sh`](fleet-open-pr.sh)   | Fail-closed push gate: stacked draft PR per slice or LOCAL-ONLY fallback; records `branch_lineage`                                                                                                                   |
| [`fleet-merge.sh`](fleet-merge.sh)       | FULL_AUTO only: stale-lineage, mode, phase, round, repository, and PR-head gates; ready-triggered bounded CI; post-CI revalidation; write-ahead, head-bound, confirmed squash merge                                  |
| [`fleet-results.sh`](fleet-results.sh)   | Locked, idempotent `results.tsv` upserts shared by the conductor, merge, and review paths                                                                                                                            |
| [`fleet-state.sh`](fleet-state.sh)       | Locked, atomic fleet-wide REVIEW to next-round RECON transition after every mirror advances                                                                                                                          |
| [`fleet-board.sh`](fleet-board.sh)       | Slim fleet-wide board: `build` (derive `board.json`), `show` (ASCII grid), `text` (one line per project)                                                                                                             |
| [`fleet-review.sh`](fleet-review.sh)     | REVIEW to DONE acknowledgement: updates the mirror and `results.tsv`, refreshes the board                                                                                                                            |
| [`tests/`](tests/)                       | Fixture tests, listed below                                                                                                                                                                                          |

Tests (run each with `bash tests/<file>`; every case prints a `PASS:` line):

| Test                                           | Covers                                                                                       |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [`test-board.sh`](tests/test-board.sh)         | Board columns, `show` grid, `text` lines                                                     |
| [`test-merge.sh`](tests/test-merge.sh)         | Every merge gate, stale-round lineage, CI polling and timeout, write-ahead and queued merges |
| [`test-prompt.sh`](tests/test-prompt.sh)       | `AskUserQuestion` payload shape for approval and clarification                               |
| [`test-push-gate.sh`](tests/test-push-gate.sh) | Push denial paths, stacking and base fallback, worktree and branch checks                    |
| [`test-results.sh`](tests/test-results.sh)     | Concurrent ledger upserts, duplicate repair, field injection                                 |
| [`test-review.sh`](tests/test-review.sh)       | Current-round and delayed acknowledgements                                                   |
| [`test-run-dir.sh`](tests/test-run-dir.sh)     | Resolution order and run-scoped tmux session names                                           |
| [`test-spec.sh`](tests/test-spec.sh)           | Mirror init, set, render, advance, and lock serialization                                    |
| [`test-start.sh`](tests/test-start.sh)         | Unique run dirs, late `current` publish, path canonicalization                               |
| [`test-state.sh`](tests/test-state.sh)         | Atomic round transition, idempotence, partial-advance and pending-merge holds                |

## Common mistakes

- Reusing a stale recon (resuming the Workflow) instead of re-running it fresh each round,
  so it re-picks a done slice. Re-run it; let it re-read the spec and git.
- Treating a silent pane as idle and committing nothing. Use the ACTIVE rule and probe.
- Treating a clarification pause as terminal `blocked`, which advances the round and kills
  a paused session. A pending question **holds the round**.
- `git add -A`, or committing on idle without the scope and deviation check, which folds in
  dirty files.
- Pushing a danger-flagged or public repo by hand. `fleet-open-pr.sh` fails closed; never
  bypass it.
- Calling `fleet-merge.sh` outside `MODE=FULL_AUTO`, or merging around its gates. The
  helper checks the mode itself; blocked slices stay in review.
- Running a manual helper without `CODEX_GOALS_DIR` while two fleets are live. It resolves
  `current`, the newest fleet, and can acknowledge or mutate the wrong run.
- Putting one project in two live fleets. Run directories are isolated; working trees and
  branches are not.
- Pinning a model in the prompt or the launcher. Set `CODEX_MODEL` in the environment, or
  leave it unset for the client default.
- Falling back to the typed `1 approve` / `1 skip` grammar when `AskUserQuestion` can reach
  the human owner. That grammar is for headless hosts only. Pass the `questions` built by
  `fleet-prompt.sh` to `AskUserQuestion` verbatim, batched at most 4 per call.
