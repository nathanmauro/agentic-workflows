---
name: council
description: >
  Convene the tri-agent council from Codex: fan one question out to fresh Claude, Codex
  (gpt-5.5), and Gemini CLI calls, run an adversarial cross-review round, then moderate
  a neutral synthesis and a numbered pick. Use when the user says "$council", "convene the
  council", "ask all three models", "council this", or wants cross-model adversarial
  answers to a design or architecture question.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Replace model names, paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Council

## Public v0 Status

This skill documents the council workflow and expected artifacts. A runner implementation is not included in v0. To use this publicly, wire the same protocol to your own runner: one context pack, independent model opinions, anonymized cross-review, neutral synthesis, and a final human pick.

## Overview

Same engine as Claude's `/council`. A `council-runner` adapter sends an identical
context pack to three frontier models as fresh one-shot CLI calls (round 1: opinions), then shows
each voice the other two's answers anonymized as Advisor A/B (round 2: adversarial
review), and leaves artifacts in a run dir. The in-session Codex agent is the **neutral
moderator**, not a voice — the council's Codex opinion comes from a fresh `codex exec`,
never from this session.

Cost: ~6 deep-reasoning frontier calls; a full run takes 10–20 minutes. `--quick` skips
the review round.

## Workflow

1. **Question.** If the user gave no question, ask one sentence and stop. Pull `--quick`
   and `--skip <agent>` (repeatable: claude|codex|gemini) out of the request and pass
   them through verbatim.

2. **Pack.** Write a context pack to a temp file (`mktemp -t council-pack`), sections:
   `## Question` (verbatim), `## Context` (decisions already made, constraints, relevant
   absolute paths — 150–600 words), `## What a good answer looks like`. The pack must be
   self-contained (no session references), identical for all voices, and free of secrets.

3. **Run detached and poll** (a full run outlives most shell timeouts):

```bash
LOG="$(mktemp -t council-run).log"
COUNCIL_RUNNER="${COUNCIL_RUNNER:-council-runner}"
nohup "$COUNCIL_RUNNER" run \
  --caller codex --pack "$PACK" > "$LOG" 2>&1 &
echo "PID=$! LOG=$LOG"
```

   `council-runner` is an adapter command the user must provide in public v0.
   Poll every 30–60 seconds with `tail -5 "$LOG"` until the final `RUN_DIR=<path>` line
   appears (`grep -E '^RUN_DIR=' "$LOG"`). If the process exits without it, report the
   log tail verbatim and stop.

4. **Read artifacts** from `RUN_DIR`: `manifest.json` first (which voices completed,
   failed, or were skipped — never invent a missing voice's opinion), then
   `opinions/{claude,codex,gemini}.md`, then `reviews/*.md` (absent on `--quick`).
   Fewer than two opinions: report and stop. Exactly two: proceed, flag the gap.

5. **Moderate.** Present in this order, positions always before any recommendation:
   **Agreement map** → **Genuine disagreements** (only action-changing ones) →
   **Objections that survived review** → **Strongest point per voice** (one line each)
   → **Moderator's read** (labeled as synthesis, not a council position).

6. **The pick.** End the final message with an explicit numbered ballot — only when
   positions genuinely diverge:

```text
Pick a position:
  1. <position A> — backed by <voices>; strongest surviving argument: <one line>
  2. <position B> — backed by <voices>; strongest surviving argument: <one line>
Reply 1, 2, ... — or describe a different direction.
```

   If all surviving voices converge, skip the ballot and state the consensus plus any
   surviving caveats.

7. **Capture.** When the user picks (or accepts a consensus that settles a real
   decision), capture via the user's durable memory adapter: decision, rationale,
   rejected alternatives with their backing voices, and the run dir. If the adapter is
   unavailable, note that in one line — do not block.

## Failure modes

- One CLI fails → `manifest.json` records it; continue with the surviving voices and say
  so. Auth checks: `codex login status`, `gemini`, `claude --version`.
- Engine missing → report that public v0 needs a `council-runner` adapter command on
  `PATH` or in `COUNCIL_RUNNER`, then stop.
