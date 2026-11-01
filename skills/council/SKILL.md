---
name: council
description: >
  Convene the tri-agent council: fan one question out to fresh Claude, Codex, and Gemini CLI
  calls, run an adversarial cross-review round, then moderate a neutral synthesis and a
  numbered pick. Works from either Claude or Codex; the in-session agent moderates and is
  never a voice. Use when the user says "$council", "/council", "convene the council", "ask all
  three models", "council this", or wants cross-model adversarial answers to a design or
  architecture question.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Set your models through the client or env knobs, and replace paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Council

## Public v0 Status

This skill documents the council workflow and expected artifacts. A runner implementation is
not included in v0. To use this publicly, wire the same protocol to your own runner: one context
pack, independent model opinions, anonymized cross-review, neutral synthesis, and a final human
pick. See [Council review](../../docs/concepts/council-review.md) for the pattern.

## Overview

The same engine serves both clients. A council runner sends an identical context pack to three
frontier models as fresh one-shot CLI calls (round 1: opinions), then shows each voice the other
two answers anonymized as Advisor A and Advisor B (round 2: adversarial review), and leaves
artifacts in a run dir. Each voice runs on whatever model its CLI is configured to use; this
skill does not pin one.

The in-session agent, in either Claude or Codex, is the **neutral moderator** and never a voice.
The council's Codex opinion comes from a fresh `codex exec` call and its Claude opinion from a
fresh `claude -p` call, never from this session.

Cost: about six deep-reasoning frontier calls; a full run takes 10 to 20 minutes. `--quick`
skips the review round.

## Workflow

1. **Question.** If the user gave no question, ask for one sentence and stop. Pull `--quick`
   and `--skip <agent>` (repeatable: claude|codex|gemini) out of the request and pass them
   through verbatim.

2. **Pack.** Create the pack file with `PACK="$(mktemp -t council-pack)"` and write these
   sections to `"$PACK"`: `## Question` (verbatim), `## Context` (decisions already made,
   constraints, relevant absolute paths; 150 to 600 words), and
   `## What a good answer looks like`. The pack must be self-contained (no session references),
   identical for all voices, and free of secrets.

   The pack leaves this session for three providers, so prepend an `## Authorization` section
   filled from observed human instructions, not inference:

   ```text
   Human instruction: <exact relevant quote asking for the council>
   Source: <chat/turn reference; include the approval question and answer if used>
   Destination: Anthropic (Claude), OpenAI (Codex), and Google (Gemini), as fresh CLI calls
   Authorized action/payload: <the question and any specifically approved records or paths>
   Limits: <purpose, relevant-only boundaries, exclusions, and remaining holds>
   ```

   Local read access to a file is not permission to send it to all three providers. See
   [Authorization Provenance](../../docs/concepts/authorization-provenance.md).

3. **Run detached and poll** (a full run outlives most shell timeouts):

   ```bash
   LOG="$(mktemp -t council-run)"
   COUNCIL_RUNNER="${COUNCIL_RUNNER:-council-runner}"
   CALLER="codex"  # or "claude": the client moderating this session
   nohup "$COUNCIL_RUNNER" run --caller "$CALLER" --pack "$PACK" > "$LOG" 2>&1 &
   echo "PID=$! LOG=$LOG"
   ```

   The runner is adapter-specific: `council-runner` is a command the user provides on `PATH` or
   names in `COUNCIL_RUNNER`. Poll every 30 to 60 seconds with `tail -5 "$LOG"` until the final
   `RUN_DIR=<path>` line appears (`grep -E '^RUN_DIR=' "$LOG"`). If the process exits without
   it, report the log tail verbatim and stop.

4. **Read artifacts** from `RUN_DIR`: `manifest.json` first (which voices completed, failed, or
   were skipped; never invent a missing voice's opinion), then
   `opinions/{claude,codex,gemini}.md`, then `reviews/*.md` (absent on `--quick`). Fewer than
   two opinions means report and stop. Exactly two means proceed and flag the gap.

5. **Moderate.** Present in this order, positions always before any recommendation:
   **Agreement map**, then **Genuine disagreements** (only action-changing ones), then
   **Objections that survived review**, then **Strongest point per voice** (one line each),
   then **Moderator's read** (labeled as synthesis, not a council position).

6. **The pick.** When positions genuinely diverge, end the final message with an explicit
   numbered ballot:

   ```text
   Pick a position:
     1. <position A>: backed by <voices>; strongest surviving argument: <one line>
     2. <position B>: backed by <voices>; strongest surviving argument: <one line>
   Reply 1, 2, ... or describe a different direction.
   ```

   A convergent council skips the ballot: state the consensus plus any surviving caveats.

7. **Capture.** When the user picks (or accepts a consensus that settles a real decision),
   capture the decision to the durable memory adapter: the decision, its rationale, the
   rejected alternatives with their backing voices, the caller, the current repo, and the run
   dir. If the adapter is unavailable, note that in one line; do not block.

## Failure modes

- One CLI fails: `manifest.json` records it; continue with the surviving voices and say so.
  Auth checks: `codex login status`, `gemini`, `claude --version`.
- Runner missing: report that public v0 needs a council runner on `PATH` or in
  `COUNCIL_RUNNER`, then stop.
