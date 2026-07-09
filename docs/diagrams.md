# Workflow Diagrams

These Mermaid diagrams show the operating patterns in this repository at a glance. They are intentionally public-safe: the diagrams describe reusable workflow shapes, not private machine wiring, accounts, or project inventories.

## Agentic Operating System

```mermaid
flowchart TB
  Human["Human owner"] --> Intent["Intent and constraints"]
  Intent --> Instructions["Project instructions"]
  Instructions --> Model["Coding agent"]
  Specs["Living specs"] --> Model
  Tools["Scoped tools"] --> Model
  Gates["Review and mutation gates"] --> Model
  Model --> Diff["Branch or working diff"]
  Diff --> Verify["Verification evidence"]
  Verify --> Decision{"Accept result?"}
  Decision -->|revise| Intent
  Decision -->|yes| Handoff["Handoff or durable memory"]
  Handoff --> Specs
  Handoff --> Next["Next session resumes with context"]
```

The model is only one part of the system. Instructions, specs, tools, gates, verification, and handoffs turn isolated agent runs into an inspectable engineering workflow.

## Fleet Round

```mermaid
flowchart LR
  Registry["Project registry"] --> Conductor["Conductor"]
  Round["Round objective"] --> Conductor
  Conductor --> StateCheck["Check repo state"]
  StateCheck --> AgentA["Project agent A"]
  StateCheck --> AgentB["Project agent B"]
  StateCheck --> AgentC["Project agent C"]
  AgentA --> SliceA["Scoped slice"]
  AgentB --> SliceB["Scoped slice"]
  AgentC --> SliceC["Scoped slice"]
  SliceA --> Evidence["Verification evidence"]
  SliceB --> Evidence
  SliceC --> Evidence
  Evidence --> Review["Review acknowledgement"]
  Review --> Summary["Conductor summary"]
  Summary --> NextRound["Next round or stop"]
```

A fleet round keeps one conductor responsible for scope and review while each project agent works inside one repository on one narrow slice.

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
```

Closeout is not a transcript dump. It is a compact state record that tells the next session where the work lives, what changed, what was proved, and what to do next.

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

Council review is useful when independent disagreement can improve a decision. It ends with a recorded decision, experiment, or explicit deferral.

## Claude And Codex Delegation

```mermaid
flowchart LR
  Coordinator["Coordinator agent"] --> Prompt["Bounded request"]
  Prompt --> Delegate["Delegate agent"]
  Delegate --> Result["Review, plan, fix, or verification result"]
  Result --> EvidenceCheck["Coordinator checks local evidence"]
  EvidenceCheck --> Decision{"Use the result?"}
  Decision -->|no| Reject["Discard or revise"]
  Decision -->|yes| Apply["Apply accepted change"]
  Apply --> Verify["Run target repo verification"]
  Verify --> Record["Update spec, handoff, or memory"]
  Reject --> Record
```

Delegation does not transfer ownership of truth. The coordinating agent still checks the local repo, accepts or rejects the result, and records decisions that future sessions need.

## Public And Private Boundary

```mermaid
flowchart TB
  Private["Private control plane"] --> Curate["Curate reusable pattern"]
  Curate --> Audit["Public release audit"]
  Audit --> Public["Public workflow kit"]

  Public --> Docs["Concept docs"]
  Public --> Templates["Templates"]
  Public --> Examples["Sanitized examples"]
  Public --> Skills["Portable skill drafts"]

  Private --> Machine["Machine-specific automation"]
  Private --> Accounts["Account routing and credentials"]
  Private --> Personal["Personal operating context"]
  Private --> Logs["Raw sessions and logs"]

  Machine -. not published .-> Audit
  Accounts -. not published .-> Audit
  Personal -. not published .-> Audit
  Logs -. not published .-> Audit
```

The public artifact is the pattern, not the private implementation. A release audit keeps private wiring, credentials, personal context, and raw logs out of the published kit.
