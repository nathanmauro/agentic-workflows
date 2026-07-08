---
name: codex-workflow-hybrid
description: >
  Run a multi-step build by having Claude orchestrate a background Workflow while
  Codex (gpt-5.5) does the heavy implementation and Claude adversarially verifies.
  Claude stays lean on tokens; Codex carries the generation. Use when the user wants
  to "use codex", "defer to codex", "save claude tokens", "use codex for the heavy
  lifting", or run a phase/feature through a Codex-delegated workflow. Triggers:
  "codex workflow", "delegate to codex", "lean on claude tokens", "hybrid codex".
  This is the BALANCED variant (Claude verifies). For maximum leanness where Codex
  also verifies, use codex-workflow-lean instead.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Replace model names, paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex-delegated workflow (hybrid: Claude orchestrates + verifies, Codex implements)

The pattern proven in the Black Box `phase-2-polish` session. Claude is the conductor
and the safety boundary; Codex (gpt-5.5, xhigh) is the engine. Heavy generation runs
as **Codex** tokens; Claude only pays orchestration + an adversarial verify pass.

## Why this shape

- **Codex writes the code.** Each implementation step is a *thin* Claude workflow agent
  whose entire job is to shell out to `codex exec` and relay a terse summary. Codex runs
  with `--dangerously-bypass-approvals-and-sandbox`, so it edits files directly.
- **Claude verifies.** Verification is the one place Claude earns its tokens: a different
  model checking Codex's work catches what self-review misses (cross-model adversarial check).
- **Claude owns git.** The main loop makes every commit so the user stays sole author
  (no AI attribution, ever — see the global git rule). Codex is forbidden to commit.
- **Everything on a branch.** Fully reversible; the outer Claude session is the boundary.

## The exact Codex invocation (memorize this)

```bash
codex exec \
  -c model='"gpt-5.5"' \
  -c model_reasoning_effort='"xhigh"' \
  -c service_tier='"priority"' \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --color never \
  -- "$(cat /tmp/<task>.md)"
```

Always write the task prompt to a temp file first and pass it via `"$(cat ...)"` — it
sidesteps shell-quoting hell for long, multi-line prompts. Give the wrapping agent a
Bash timeout of `600000` ms (xhigh runs can take minutes).

## Run it — three movements

### 1. Pre-flight (Claude main loop, cheap — do NOT delegate this)

1. **Lock the scope.** Reconcile any drift, define exactly what this phase delivers and
   what it explicitly defers. Show the user the shape; let them redirect.
2. **Persist the plan off-session** so it survives a `/clear`:
   - a repo doc (`ROADMAP.md` / `PLAN.md`), committed; and
   - if the project has a memory bus (e.g. Black Box `captureDecision`/`captureHandoff`),
     dogfood the plan into it.
3. **Branch** from the default branch (`git checkout -b <feature>`), commit the plan.

### 2. Execute (the Workflow tool — Codex does the work)

Customize `templates/workflow.js` (bundled next to this file) for the task and pass it
inline to the Workflow tool. Its pipeline:

- **Implement** — one (or a few) thin Claude agents, each running `codex exec` on a
  scoped task. One coherent Codex call per cohesive unit beats many parallel calls that
  fight over the same files. Run sequentially when tasks share files.
- **Verify** — parallel **Claude** lenses with a structured schema:
  - *functional*: scope (no stray files), syntax, feature-presence, build/tests green;
  - *editorial*: honesty/no-overclaim, correctness, aesthetic constraints.
- **Fix** — a conditional `codex exec` pass, only for issues the verify lenses marked
  `real: true`.

### 3. Post-flight (Claude main loop)

1. If it's a running app/server, **rebuild + restart and confirm the new assets are
   actually served** (a packaged jar/binary serves stale files until rebuilt). Curl a
   known new marker; watch for keep-alive daemons (PPID 1) that respawn on kill.
2. **Review the diff scope** and **commit** — user sole author, no AI co-author/trailer.
3. Report the diff, the verdicts, and what was deliberately left to the user.

## Hard guardrails (put these in every Codex prompt)

- Edit ONLY the named paths. Never touch out-of-scope layers (e.g. data/API/build files).
- Never run `git add` / `git commit` / `git push`. Leave changes unstaged.
- No new runtime deps, no CDN — stay consistent with the existing stack.
- Output a terse summary of files changed; do not paste reasoning traces.

## Token economics

Heavy generation = Codex tokens. Claude pays: orchestration (small) + the verify reads
(moderate — the lenses read diffs and run builds). If even the verify budget matters,
switch to **codex-workflow-lean** (Codex verifies too; you lose the cross-model check).

## On failure

If `codex exec` errors (auth lapse, rate limit, model gone), surface it verbatim and
suggest `codex login status` / `codex doctor`. The verify phase catches incomplete or
out-of-scope Codex work before anything is committed.
