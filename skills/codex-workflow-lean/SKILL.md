---
name: codex-workflow-lean
description: >
  The leanest Codex-delegated build: Claude is used ONLY for the Workflow orchestration
  engine (deterministic fan-out, pipelines, structured output) and to own git. EVERY
  agent — implementation AND verification — shells out to Codex (gpt-5.5). Use when the
  user wants maximum Claude-token savings: "codex for everything", "leanest", "claude
  only for the workflow", "minimize claude tokens". Triggers: "codex only", "leanest
  codex workflow", "claude just for the workflow engine". Tradeoff vs codex-workflow-hybrid:
  Codex grades its own work (no cross-model check), so reserve for lower-risk or
  well-specified tasks, or add a human review gate after.
---

> Public adaptation note: This skill is a sanitized public version of a private local workflow. Replace model names, paths, notification channels, and memory adapters with the equivalents in your own agent harness.

# Codex-only workflow (Claude = the workflow engine + git; Codex does everything else)

Maximum leanness on Claude tokens. Claude contributes exactly two things it alone can do:
the **Workflow tool** (deterministic background orchestration, pipelines, structured
output, the agent budget) and **git authorship** (user stays sole author). Everything
with real token weight — implementation AND verification — is a `codex exec` call wrapped
in a thin Claude agent that only relays.

## When to prefer this over the hybrid

- The user explicitly wants the leanest possible Claude footprint.
- The task is well-specified or lower-risk, OR a human will eyeball the result before merge.

If correctness is high-stakes, prefer **codex-workflow-hybrid** — its Claude verify lens
is a *different model* checking Codex, which catches what self-review can't. Here, Codex
reviews its own diff: cheaper, but blind to its own blind spots. Mitigate by (a) using a
*fresh* Codex review pass with an explicitly adversarial prompt ("try to find what's
wrong; default to flagging"), and/or (b) a human review gate before commit.

## The exact Codex invocation

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

Write each prompt to a temp file; pass via `"$(cat ...)"`. Bash timeout `600000` ms.

## Run it

### Pre-flight (Claude main loop — same as hybrid)
Lock scope → persist the plan (repo doc + memory bus) → branch → commit the plan.

### Execute (Workflow tool — every agent wraps Codex)
Customize `templates/workflow.js` (bundled here). Its pipeline:
- **Implement** — thin Claude agent runs `codex exec` to write the code.
- **Review** — thin Claude agent runs a SECOND, adversarial `codex exec` that inspects
  `git diff` and emits a JSON verdict; the agent's `schema` validates/relays it. No Claude
  reasoning is spent reviewing — Codex does it, Claude just shapes the output.
- **Fix** — conditional `codex exec` for `real: true` issues only.

### Post-flight (Claude main loop)
Rebuild/restart + confirm served (if an app) → review scope → commit (user sole author) → report.

## Hard guardrails (in every Codex prompt)

- Edit ONLY named paths; never touch out-of-scope layers.
- Never `git add` / `commit` / `push` — Claude main loop owns git and authorship.
- No new runtime deps, no CDN.
- Implementation prompt: terse summary of files changed. Review prompt: emit ONLY JSON
  matching the verdict schema.

## Token economics

Claude pays only: orchestration overhead + per-agent relay + JSON validation. All
generation and all review are Codex tokens. This is as lean as it gets while still using
Claude's Workflow engine. The cost is the lost cross-model verification — buy it back with
an adversarial Codex review prompt or a human gate.
