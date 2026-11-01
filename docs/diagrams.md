# Workflow Diagrams

These Mermaid diagrams show the operating patterns in this repository at a glance. They describe
reusable workflow shapes for two engines, Claude Code and Codex, under one policy. They are
intentionally public-safe: no private machine wiring, accounts, or project inventories.

## Agentic Operating System

```mermaid
flowchart TB
  Human["Human owner"] --> Intent["Intent and constraints"]
  Intent --> Instructions["Project instructions"]
  subgraph Engines["Coding agents"]
    Claude["Claude Code"] <-->|"delegate with an authorization record"| Codex["Codex"]
  end
  Policy["Shared portable policy"] --> Engines
  Instructions --> Engines
  Specs["Living specs"] --> Engines
  Tools["Scoped tools"] --> Engines
  Gates["Review and mutation gates"] --> Engines
  Engines --> Diff["Branch or working diff"]
  Diff --> Verify["Verification evidence"]
  Verify --> Decision{"Accept result?"}
  Decision -->|revise| Intent
  Decision -->|yes| Handoff["Handoff or durable memory"]
  Handoff --> Specs
  Handoff --> Next["Next session resumes with context"]
```

The model is only one part of the system. Instructions, specs, tools, gates, verification, and
handoffs turn isolated agent runs into an inspectable engineering workflow. One shared policy
reaches both engines, and authorization travels with delegated work as a quoted record; see
[One Policy, Two Engines](#one-policy-two-engines) and
[Claude And Codex Delegation](#claude-and-codex-delegation).

## Fleet Round

```mermaid
flowchart LR
  Registry["Project registry"] --> Conductor["Conductor"]
  Round["Round objective"] --> Conductor
  Conductor -->|RECON| StateCheck["Check repo state, propose slices"]
  StateCheck --> Approve{"PLAN only: human approves, redirects, or skips"}
  Approve -->|RUNNING| AgentA["Project agent A"]
  Approve -->|RUNNING| AgentB["Project agent B"]
  Approve -->|RUNNING| AgentC["Project agent C"]
  AgentA --> SliceA["Scoped slice"]
  AgentB --> SliceB["Scoped slice"]
  AgentC --> SliceC["Scoped slice"]
  SliceA --> Evidence["Verification evidence"]
  SliceB --> Evidence
  SliceC --> Evidence
  Evidence -->|REVIEW| Merge{"FULL_AUTO only: fleet-merge.sh gates, CI, re-check"}
  Merge -->|green| Merged["Squash-merged"]
  Merge -->|"red, timed out, queued, gated, or PLAN and DO"| Review["Review acknowledgement"]
  Merged --> Summary["Conductor summary"]
  Review --> Summary
  Summary --> NextRound["Next round or stop"]
```

A fleet round keeps one conductor responsible for scope and review while each project agent works
inside one repository on one narrow slice. Claude Code conducts and is the safety boundary; each
project agent is a Codex session. PLAN, the default, waits for the human to approve each slice; DO
skips only that gate; FULL_AUTO also merges, but only through the fail-closed merge helper, and any
slice it cannot merge stays in review for a human. See
[Fleet execution](concepts/fleet-execution.md) and [Codex fleet](workflows/codex-fleet.md).

## Closeout And Handoff

```mermaid
flowchart TD
  StopPoint["Stop point reached"] --> Branch["Inspect branch and dirty state"]
  Branch --> Diff["Review relevant diff"]
  Diff --> Verify["Run verification"]
  Verify --> Effects["Record live effects"]
  Effects --> Gaps["Record skipped work and risks"]
  Gaps --> Resume["Write next useful action"]
  Resume --> Store{"Durable memory available?"}
  Store -->|yes| Memory["Store compact handoff"]
  Store -->|no| File["Write handoff file"]
  Memory --> Next["Next agent resumes responsibly"]
  File --> Next
  Next --> Baton["Resume report: who, state, last, open, next"]
```

Closeout is not a transcript dump. It is a compact state record that tells the next session
where the work lives, what changed, what was proved, and what to do next. The read side is a
fixed-format resume report, so a Codex session can pick up a Claude Code handoff and the reverse.

## Project Trajectory And Possible Futures

```mermaid
flowchart LR
  DeepPast["Earlier work (collapsed)"] --> BurstA["Burst of activity"]
  BurstA --> BurstB["Burst of activity"]
  BurstB --> Head(("Head: latest handoff"))
  BurstB -.-> Stub["Rejected alternative (stub)"]
  Head --> NextAction["Next action from handoff"]
  Head --> OpenLoop["Open loop"]
  Head --> BlockedTask["Blocked task"]
  Head -.-> Ghost1["Projection: possible future"]
  Head -.-> Ghost2["Projection: possible future"]
```

The trajectory is a view over the same durable captures. Solid futures derive from recorded
facts: next actions, open loops, task state. Dashed ghosts are projections, possible futures an
agent wrote down at closeout, each with a confidence and superseded by the next projection set.
Rejected alternatives stay behind the head as dead stubs. See
[Project trajectory](concepts/project-trajectory.md).

## Council Review

```mermaid
sequenceDiagram
  participant Owner as Human or conductor
  participant Pack as Shared context pack
  participant R1 as Reviewer 1
  participant R2 as Reviewer 2
  participant R3 as Reviewer 3
  participant Synth as Neutral synthesis
  participant Record as Spec or handoff

  Owner->>Pack: Define decision, evidence, constraints, expected output
  Pack->>R1: Independent review
  Pack->>R2: Independent review
  Pack->>R3: Independent review
  R1->>Synth: Findings and risks
  R2->>Synth: Findings and risks
  R3->>Synth: Findings and risks
  Synth->>Synth: Separate consensus, disagreement, and experiments
  Synth->>Owner: Recommendation or decision options
  Owner->>Record: Record accepted decision
```

Council review is useful when independent disagreement can improve a decision. It ends with a
recorded decision, experiment, or explicit deferral.

## Claude And Codex Delegation

```mermaid
flowchart LR
  Human["Human owner"] --> Conductor["Conductor: Claude Code or Codex"]
  Conductor --> Auth["Authorization record: quote, source, destination, payload, limits"]
  Auth --> Request["Bounded request"]
  Request --> Delegate["Delegate: the other engine"]
  Delegate --> Result["Diff or result, no commits"]
  Result --> Verify["Verification by the model that did not write it"]
  Verify --> Decision{"Accept the result?"}
  Decision -->|fix| Delegate
  Decision -->|reject| Record["Spec, handoff, or durable memory"]
  Decision -->|yes| Commit["Conductor owns git: re-verify and commit"]
  Commit --> Record
```

Either engine can lead. Usually Claude Code conducts and Codex implements well-specified work, but
a Codex-led session delegates to Claude Code the same way. Delegation does not transfer ownership
of truth or authority: the request carries the human's quoted approval and nothing more, the model
that did not write the change verifies it, fixes go back to the same delegate, and only the
conductor touches git. See [Authorization provenance](concepts/authorization-provenance.md),
[Codex from Claude](workflows/codex-from-claude.md), and
[Claude from Codex](workflows/claude-from-codex.md).

## Supervised Delegation

```mermaid
sequenceDiagram
  participant Conductor as Conductor
  participant Channel as Worker channel
  participant Worker as Worker in workspace-write sandbox
  participant Verifier as Verifier, the other model
  participant Human as Human owner

  Conductor->>Channel: start in the repo checkout
  Channel-->>Conductor: worker name
  Conductor->>Channel: send task with envelope rule and authorization record
  Channel-->>Conductor: turn record, returned immediately
  Channel->>Worker: deliver turn
  Worker->>Worker: edit the working tree, .git stays read-only
  Worker-->>Channel: final message closes with one ENVELOPE line
  loop while exit 2 (every other exit leaves the loop)
    Conductor->>Channel: watch the saved turn with a timeout
    alt exit 2, timeout
      Channel-->>Conductor: not observed yet, watch the same turn again
    else exit 12, attention
      Channel-->>Conductor: quiet too long, over budget, or no valid envelope
      Conductor->>Human: notify and inspect, no automatic restart
    else exit 10, question
      Channel-->>Conductor: envelope status question
      Conductor->>Human: surface the worker question
    else exit 11, 3, 4, or 1
      Channel-->>Conductor: failed, blocked or gone, aborted, or observation error
      Conductor->>Human: report the observed reason
    else exit 0, done
      Channel-->>Conductor: envelope status done
    end
  end
  opt exit 0, done (no other exit reaches verification or commit)
    Conductor->>Verifier: verify the diff against the task
    Verifier-->>Conductor: findings
    opt findings need a fix
      Conductor->>Channel: send a fix turn to the same worker
      Conductor->>Channel: watch the new turn
    end
    Conductor->>Conductor: re-run verification and commit
  end
  Conductor->>Channel: stop
```

Send and wait are separate calls, so waiting is restartable from the turn record alone. A timeout
means "not observed yet", never "resend", and attention means a person should look, not that the
worker should be killed. The worker cannot write `.git`, so the conductor reviews, re-verifies,
and commits. The full contract and exit-code table are in
[Supervised delegation](concepts/supervised-delegation.md); a public reference adapter lives at
[`scripts/codex-runner`](../scripts/codex-runner).

## One Policy, Two Engines

```mermaid
flowchart LR
  Policy["Portable policy source"] --> ClaudeGuide["Claude Code global guide: imports the source"]
  Policy --> Render["Render with sha256"]
  Render --> CodexGuide["Codex global guide: hash-marked managed block"]
  Skills["One skill source per skill"] -->|symlink| ClaudeSkills["Claude Code skill path"]
  Skills -->|symlink| CodexSkills["Codex skill path plus openai.yaml"]
  CodexGuide --> Check{"Check: import present once, block hash matches source?"}
  ClaudeGuide --> Check
  Policy --> Check
  Check -->|no| Fail["Check fails on drift or hand edit"]
  Check -->|yes| Pass["Both engines run one rulebook"]
```

The rules that matter most, such as who commits, what needs a gate, and how authorization travels,
are written once and reach both engines from the same source. Skills are linked, never copied, so
an improvement made in one client is live in the other. A check command fails when a rendered
block no longer matches its source. See
[One policy, two engines](concepts/one-policy-two-engines.md),
[`templates/portable-policy.md`](../templates/portable-policy.md), and
[`templates/skill-registry.md`](../templates/skill-registry.md).

## Execution-Path Triage

```mermaid
flowchart TD
  Task["Non-trivial task"] --> Stage{"Stage: which discipline fits?"}
  Stage --> Engine{"Engine: which path runs it?"}
  Engine --> Ranked["Two or three ranked options, leaner path wins ties"]
  Ranked --> PrintOnly["Always offered: print the command, do not run it"]
  Ranked --> Pick{"Human owner picks"}
  PrintOnly --> Pick
  Pick -->|print only| Printed["Command shown, nothing dispatched"]
  Pick -->|chosen path| Dispatch["Dispatch"]
  Dispatch --> Answer["Just answer or research"]
  Dispatch --> Plan["Plan first"]
  Dispatch --> Direct["Direct build in the main loop"]
  Dispatch --> Delegated["Delegated build: one engine implements, the other verifies"]
  Dispatch --> Review["Review"]
```

Triage runs in the main loop, with no classifier subagent, before any heavy workflow starts. It
asks which stage discipline fits (interview, prototype, spec, diagnose, test-first, module design,
domain modeling, or conflict resolution), then which engine runs it (just-answer, research, plan
first, direct build, delegated build, or review), and the human owner picks from ranked options.
The gate exists because one default-to-heavy run burned about 11.75M tokens across 317 agents and
produced no diff. The working mode is chosen separately: prototype for end-to-end slices verified
through use, or sdlc for plan and review checkpoints.

## Public And Private Boundary

```mermaid
flowchart TB
  Private["Private control plane"] --> Curate["Curate reusable pattern"]
  Curate --> Audit["Public release audit, also run in CI"]
  Audit --> Public["Public workflow kit"]

  Public --> Docs["Concept docs"]
  Public --> Templates["Templates"]
  Public --> Examples["Sanitized examples"]
  Public --> Skills["Runnable portable skills"]

  Private --> Machine["Machine-specific automation"]
  Private --> Accounts["Account routing and credentials"]
  Private --> Personal["Personal operating context"]
  Private --> Logs["Raw sessions and logs"]

  Audit -. keeps out .-> Machine
  Audit -. keeps out .-> Accounts
  Audit -. keeps out .-> Personal
  Audit -. keeps out .-> Logs
```

The public artifact is the pattern, not the private implementation. A release audit keeps private
wiring, credentials, personal context, and raw logs out of the published kit.
