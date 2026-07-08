---
name: codex-fleet
description: >
  Use when the user wants to advance several local code projects at once over
  multiple rounds, one Codex session per project, leaving each project's work on
  stacked feature branches. Default is PLAN mode — Claude proposes each project's
  next vertical slice and the human owner approves/redirects/skips through Claude Code's native
  option prompts on the terminal or their phone — with mid-flight clarifying questions
  surfaced the same way; DO mode is the unattended auto-run. Triggers: "run codex across my projects", "fire up a codex
  session per project and do what's next", "plan mode fleet", "loop this N times
  across my repos", "codex fleet". Each project carries a living spec, a stakes
  tier, and a slim fleet-wide kanban board.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Replace model names, paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex Fleet — agentic-SDLC multi-project execution (PLAN ⇄ DO)

Claude is the **conductor and safety boundary**; one **Codex** session per project is
the engine. The work unit is a **vertical slice** (one story) per project per round.
Two modes share one machine:

- **PLAN** (default) — Claude proposes each project's next slice from its living spec;
  the human owner **approves / redirects / skips** before any code runs via Claude Code's **native
  option prompt** (`AskUserQuestion`) — the usual tappable surface on terminal or phone,
  with a freeform **Other** choice to redirect or talk it through. The agent asks
  **clarifying questions mid-flight** through the same native prompt when the spec doesn't
  decide something — like a developer who doesn't guess.
- **DO** — the legacy unattended auto-run: recon picks the slice and Codex executes
  immediately. Same living spec, clarification channel, PR gate, and board; it only
  skips the approval gate.

Every slice lands on a stacked `fleet/round-N-<slug>` branch. For tier-allowed,
non-danger-flagged repos a **draft PR** is opened per slice (stacked); the human owner reviews
along the way and **merges the top branch** to integrate. Danger-flagged/public repos
stay strictly local. Nothing is ever merged by the fleet.

Public workflow guide: `docs/workflows/codex-fleet.md`. Pattern rationale:
`docs/concepts/fleet-execution.md`. Starter inputs and sanitized examples:
`templates/fleet-projects.json` and `examples/fleet-round/`.

## When to use
- "Look at my projects, figure out what's next on each, and let me steer it." (PLAN)
- "Fire up a Codex session per project and run the next slice." / "codex fleet"
- "Put this on a loop — keep going N rounds and ping me when you need a decision."

**When NOT to use:** a single project/task (use `codex-workflow-hybrid`); anything that
must be merged automatically (the fleet never merges).

## Inputs (interactive via start-fleet.sh)

```
cd <agentic-workflows-repo>
./skills/codex-fleet/start-fleet.sh
```

It prompts for: which projects (numbers/ranges/names/paths), a per-project **hint**
(per-repo dangers, copied verbatim into every goal prompt), a per-project **tier**
(`production` default | `prototype`), the **mode** (`PLAN` default | `DO`), and the
**round count**. It then runs pre-flight health checks, computes **`push_allowed`** per
project (true only if an `origin` remote exists, `gh` is on PATH, and the danger hint
doesn't forbid pushing), seeds a **living-spec mirror** per project, writes
`~/.codex-goals/projects.json` + `state.env`, and emits
`~/.codex-goals/loop-instruction.txt` — paste its full contents into Claude's `/loop`
(dynamic, no interval).

## State machine

`~/.codex-goals/state.env`: `ROUND`, `TOTAL_ROUNDS`, `MODE` (`PLAN`|`DO`), `PHASE`
(`RECON → APPROVAL → RUNNING → REVIEW → DONE`; `APPROVAL` only runs in PLAN). Per-project
`status` (`planned·doing·review·done·blocked·skipped`) lives in the spec mirror and
drives the board.

## The living spec (the contract with the AI)

Two files, **two writers, no contention**:
- **In-repo `docs/fleet/spec.md`** — markdown body + YAML frontmatter, versioned with
  the project, PR-reviewed. Written by **Codex** via `fleet-spec.sh render` and
  committed *with* the slice.
- **Fleet-side `~/.codex-goals/<name>.spec.json`** — live machine state, written by the
  **orchestrator (Claude)** (plus Codex's own slice `branch_lineage` via the
  `fleet-open-pr.sh` helper). Never committed; the board derives from it.

Round N reads the spec as primary context, so decisions/guardrails carry forward
instead of being re-derived from a cold recon.

## Clarification channel (the developer who doesn't guess)

If Codex hits a fork the spec doesn't decide (scope, architecture, user-facing
behavior, safety), it writes `~/.codex-goals/<name>.question.json` and **stops** instead
of guessing. The loop surfaces the question as a native `AskUserQuestion` prompt — Codex's
own options plus a freeform **Other** answer — and **holds the round** (never advances
while a question is unanswered — a transient pause, not terminal `blocked`), then resumes
the slice with `"you asked Q, the human owner answered A, continue"` once the human owner replies. The
`open → notified → answered` state machine is unchanged; on a headless host it falls back
to a `PushNotification` + typed reply.

## Draft PR per slice (tier/danger gated)

At the commit gate Codex runs `fleet-open-pr.sh <name> <round> <branch>`, which **fails
closed**: it goes LOCAL-ONLY when `push_allowed != true`, `gh` is missing, there's no
`origin`, or the danger hint matches `PUBLIC|never push|do not push`; otherwise it
pushes and opens a **draft** PR stacked on the previous slice's branch (human owner sole
author, no attribution in the body). A danger-flagged repo never pushes, regardless of
tier. Local-only slices print a ready-to-run `gh pr create` you can fire by hand.

## Tiers + the board

`tier ∈ {prototype, production}` per project calibrates how many gates apply (production
= full eval bar + draft PR + REVIEW ack; prototype = lighter, may pin to auto-DO).

`fleet-board.sh build|show|text` renders a **fleet-wide grid** (projects × `Planned ·
Doing · Review · Done · Blocked`), regenerated each loop tick as a pure read-only view —
zero agent bookkeeping. Terminal = `show`; mobile push = `text`. The one human-driven
transition is **REVIEW → DONE**: `fleet-review.sh <project> <round>` acks a reviewed
branch; unreviewed work accumulates **visibly**, never silently.

**ACTIVE-detection (hard-won):** a session is still working if its pane shows
`Working (` OR `Waiting for background terminal` OR an approval/trust prompt. Absence of
"done" text is NOT idle. When unsure stuck-vs-progressing, probe the real artifact (curl
the dev server, check `git log`), don't just stare at the pane.

## Guardrails — embedded verbatim in every Codex goal prompt
- **Identity:** commit as the human owner only. NO `Co-Authored-By` naming Claude/Codex/a model,
  NO "Generated with" lines. (Global rule; overrides any default.)
- **Branch:** new `fleet/round-N-<slug>` stacked on the prior round's branch; commit to
  that branch only.
- **Push/PR (relaxed by decision):** push + **draft** PR for tier-allowed,
  non-danger-flagged repos with a remote; **the human owner owns every merge**. Danger-flagged /
  public / no-remote repos stay strictly **local-only**. The fleet never merges.
- **Scope:** stage explicitly — NEVER `git add -A`/`.`/`--update`. Exclude `.claude/`,
  `.firecrawl/`, `.idea/`, and any pre-existing dirty files.
- **Verify before commit:** run the repo's test/verify; commit only green.
- **Fail closed:** on a flagged danger or failed verify → `blocked`, ledger note, NO
  mid-run git surgery.
- **Autonomy:** the launcher uses `-a never`; full local autonomy on a branch. This
  skill is a **manual trust boundary** — the human owner invokes it explicitly, which IS the
  authorization.
- **Per-repo dangers** travel in the project `hint` and the spec (e.g.
  example-public-repo: origin is PUBLIC; protected experiment branch/worktree may
  contain sensitive data — NEVER touched or pushed).

## Watch for the deviation pattern

A Codex session may fold pre-existing dirty files into its commit (observed: example-service
folded `preexisting-ui-file.tsx` + `theme.css`). The commit gate diffs `git status --porcelain`
against `~/.codex-goals/<name>.pre.status`; a folded pre-existing/danger file flips the
project to `blocked` with a deviation note. Do NOT do git surgery mid-run — isolated
commits are recoverable.

## Files (bundled next to this skill)

| File | Role |
|------|------|
| `start-fleet.sh` | Entry point — interactive projects/hints/**tier**/**mode**/rounds, health checks + `push_allowed`, seeds spec mirrors + state, writes `loop-instruction.txt` |
| `init-fleet.sh` | Seed `state.env` (incl. `MODE`) + the 6-column `results.tsv` ledger |
| `recon-workflow.js` | Recon+Vet Workflow — reads the living spec, proposes the next **vertical slice**, emits the goal prompt with the spec-render + clarification + PR-gate git workflow |
| `loop-prompt.md` | The `/loop` driver — `MODE/PHASE` machine (APPROVAL, clarification poll + round-hold, commit gate, REVIEW + board) |
| `fleet-prompt.sh` | Builds the native `AskUserQuestion` payloads — `approval <round>` and `clarify` — so the human owner steers with option prompts + freeform, not typed grammar (fixture-tested for the tool's shape limits) |
| `launch.sh` | tmux + `codex -a never` launcher (with continuation-relaunch for the clarification channel) |
| `fleet-spec.sh` | Living-spec data layer — `init`/`get`/`set` the JSON mirror + `render` it into in-repo `docs/fleet/spec.md` |
| `fleet-open-pr.sh` | Fail-closed push gate — draft PR per slice (stacked) or LOCAL-ONLY fallback; records `branch_lineage` |
| `fleet-board.sh` | Slim fleet-wide board — `build` (derive `board.json`) / `show` (ASCII grid) / `text` (mobile) |
| `fleet-review.sh` | `REVIEW → DONE` ack — updates the mirror + `results.tsv` status, refreshes the board |
| `tests/` | Fixture tests for the helper layer (`test-spec.sh`, `test-board.sh`, `test-push-gate.sh`) |

## Common mistakes
- Reusing a stale recon (resuming the Workflow) instead of re-running it fresh each round
  → it re-picks a done slice. Re-run; let it re-read the spec + git.
- Treating a silent pane as idle → committing nothing. Use the ACTIVE rule + probe.
- Treating a clarification pause as terminal `blocked` → advancing the round and killing
  a paused session. A pending question **holds the round**.
- `git add -A` / committing on idle without the scope + deviation check → folds in dirty
  files.
- Pushing a danger-flagged/public repo → `fleet-open-pr.sh` fails closed; never bypass it
  by pushing by hand.
- Falling back to the typed `1 approve` / `1 skip` grammar when `AskUserQuestion` can reach
  the human owner → that grammar is for headless hosts only. The native option prompt (built by
  `fleet-prompt.sh`) is the primary surface for approval AND clarification; pass its
  `questions` to `AskUserQuestion` verbatim, batched ≤4.
