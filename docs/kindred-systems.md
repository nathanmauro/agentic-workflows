# Kindred Systems

This manual distills one practice. Other people have distilled theirs, and when an independently
built public system lands on the same patterns from a different direction, that convergence is
evidence the patterns are real, not one person's habit. This page links those systems, maps the
convergences honestly, and records what this manual has adopted from them.

## Skills For Real Engineers, by Matt Pocock

[`mattpocock/skills`](https://github.com/mattpocock/skills) is a set of small, composable,
model-agnostic agent skills condensed from the software-engineering classics (Brooks, Ousterhout,
Fowler, Beck, Feathers), published with docs at [AI Hero](https://www.aihero.dev/). It is
explicitly positioned against process-owning frameworks: the skills hold reusable discipline while
the human keeps control of the process. Its best-known skill is
[`grill-me`](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md),
"a relentless interview to sharpen a plan or design." The interview skill vendored into the
author's private control plane is its newer form, `grilling`.

### Where the systems converge

The two systems converged independently and are now installed side by side:

| Shared idea                                 | In Skills For Real Engineers                                                                                                                                                                                             | In this manual                                                                                                                                       |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| The harness is the product                  | "Software engineering fundamentals matter more than ever… condensed into repeatable practices"                                                                                                                           | [Agentic operating system](concepts/agentic-operating-system.md)                                                                                     |
| One bounded slice per agent                 | [Tracer-bullet tickets](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md) "sized to fit in a single fresh context window"; never more than one decision per session                 | [Fleet execution](concepts/fleet-execution.md): one owner, one slice, one acceptance bar                                                             |
| The frontier                                | "Work the **frontier**: any ticket whose blockers are all done", [wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md)'s "edge of the known"                                 | Handoffs at the edge of known work feed a [project trajectory](concepts/project-trajectory.md)'s futures: the same idea, arrived at separately       |
| Evidence over confidence                    | [Diagnosing bugs](https://github.com/mattpocock/skills/blob/main/skills/engineering/diagnosing-bugs/SKILL.md): "Build the right feedback loop, and the bug is 90% fixed"; triage verifies the claim before discussing it | Principle 3: a green command, inspected diff, or verified flow beats a persuasive summary                                                            |
| Manufactured disagreement before commitment | [Design-it-twice](https://github.com/mattpocock/skills/blob/main/skills/engineering/codebase-design/DESIGN-IT-TWICE.md): 3+ parallel sub-agents forced to radically different designs, then an opinionated synthesis     | [Council review](concepts/council-review.md): independent views, adversarial cross-review, neutral synthesis                                         |
| Remember the roads not taken                | ADRs gated to load-bearing decisions; a `.out-of-scope/` knowledge base "so rejections aren't re-litigated"                                                                                                              | Decisions captured with alternatives; rejected paths render as dead stubs on the [trajectory](concepts/project-trajectory.md), never as open futures |
| Compact, reference-first handoffs           | [Handoff](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md): compact the conversation, redact secrets, reference existing artifacts instead of restating them                         | [Handoffs and continuity](concepts/handoffs-and-continuity.md): state, not transcripts; no secrets                                                   |
| The unknown is drawn honestly               | Wayfinder's fog of war: "don't chart what you can't yet see"                                                                                                                                                             | [Projections](concepts/project-trajectory.md): plausible futures drawn as ghosts with confidence, expiring rather than lingering                     |

The fog-of-war and projection ideas are complements rather than duplicates: fog marks what cannot
be stated precisely yet, while a projection names a future that can be stated, with a confidence
attached. A trajectory needs both: ghosts for the futures you can name, fog for the ones you
cannot.

### Different altitude, same seam

The systems own different layers. Skills For Real Engineers disciplines the **inside of a
session**: how to interview the human, place a test seam, build a debugging feedback loop, review a
diff. This manual disciplines the **space between sessions**: living specs, fleet rounds, mutation
gates, closeouts, durable memory. They meet at the handoff: his skills end sessions the way this
manual expects sessions to end. Run together, they compose rather than compete, and since 2026-10
the pack is installed in the author's private control plane on trial, as the next section records.

### Adopted here (updated 2026-10)

#### Folded into the manual

Three of his moves were strong enough to fold into this manual's own patterns:

1. **Grill before you spec.** The manual's core loop starts at intent, and the fastest way to
   corrupt a spec is to extract intent without interrogating it. A grilling session (the agent
   walks the design tree and asks every question whose prerequisites are settled, each with a
   recommended answer attached, fetching facts itself rather than asking the human for them) is
   the strongest known opening move for the [living spec](concepts/living-specs.md). The
   termination condition is the point: the interview ends when nothing is left silently assumed.
2. **Suggested disciplines travel with the handoff.** A handoff that records state but not
   _approach_ makes the next session rediscover how to work.
   [`templates/HANDOFF.md`](../templates/HANDOFF.md) now carries a section naming the skills,
   patterns, or workflows the next session should load.
3. **Reference, don't duplicate.** A handoff points at specs, decisions, diffs, and commits by path
   or link; restating them creates copies that go stale and bloat the record.

#### Vendored and adapted

On 2026-10-06 eleven of his skills were vendored from `mattpocock/skills` at commit
[`6fd9479`](https://github.com/mattpocock/skills/tree/6fd947921b935b7e1e69293a200400f0fdd5c15f)
(MIT, licence kept in full beside the copies) and adapted to run under both Claude Code and Codex
from one tracked source, as described in
[One Policy, Two Engines](concepts/one-policy-two-engines.md). The import commit holds the upstream
files byte for byte, so every local change is a plain diff against it, and a per-skill ledger
records what changed. Upstream is pulled by hand: fetched outside the repo, read as untrusted data,
diffed one skill at a time, and merged manually. It is never auto-installed, and the earlier plugin
build was disabled so no skill loads twice. The eleven share one adoption record kept to the
[skill registry](../templates/skill-registry.md) contract. The vendored copies, their licence, and
the per-skill ledger live in the private control plane and are not published in this repo; the
table below records what changed.

| Skill                           | Upstream path                                      | What changed                                                                                                                                                                                                                                    |
| ------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `grilling`                      | `skills/productivity/grilling`                     | Each round goes through the client's native option prompt in Claude Code (recommended answer first) and upstream's numbered prose in Codex; facts are looked up inline when the harness cannot spawn sub-agents.                                |
| `grill-with-docs`               | `skills/engineering/grill-with-docs`               | Harness-neutral skill loading; closes by pointing to `to-spec` then `to-tickets` once nothing is left open.                                                                                                                                     |
| `wait-what`                     | `skills/productivity/wait-what`                    | Unmodified, byte for byte upstream.                                                                                                                                                                                                             |
| `domain-modeling`               | `skills/engineering/domain-modeling`               | Recalls prior decisions before a choice settles; every ADR is paired with a [Black Box](https://github.com/nathanmauro/black-box) decision record, with `supersedes` set on both sides when one replaces another.                               |
| `to-spec`                       | `skills/engineering/to-spec`                       | The tracker is Linear: the spec is one issue, updated rather than duplicated; without tracker access the skill stops and returns the draft.                                                                                                     |
| `to-tickets`                    | `skills/engineering/to-tickets`                    | Linear sub-issues with native blocking relations; each ticket gains Boundaries and Verification sections and a flag for work that needs the human owner, so the same ticket can feed a [delegated Codex build](workflows/codex-from-claude.md). |
| `diagnosing-bugs`               | `skills/engineering/diagnosing-bugs`               | The human-in-the-loop script is handed to the human owner to run in a real terminal when the agent shell is non-interactive; a missing test seam points to `improve-codebase-architecture`.                                                     |
| `tdd`                           | `skills/engineering/tdd`                           | Harness-neutral loading of `codebase-design`; the review stage uses Claude Code's built-in review and simplify passes, or a review pass before commit in Codex.                                                                                 |
| `codebase-design`               | `skills/engineering/codebase-design`               | A sequential fallback for design-it-twice when the harness cannot spawn the three parallel design sub-agents.                                                                                                                                   |
| `improve-codebase-architecture` | `skills/engineering/improve-codebase-architecture` | Harness-neutral loading; recalls prior decisions for the area and treats a recorded rejection like an ADR; a sequential fallback without sub-agents; a load-bearing rejection is captured as a Black Box decision of kind `rejection`.          |
| `prototype`                     | `skills/engineering/prototype`                     | Hands the git commands to the human owner when the sandbox blocks git; posts the branch pointer on the originating Linear issue only when one is named, never searched for; a verdict that shapes later work becomes a Black Box decision.      |

The rest of the upstream set (its router, `wayfinder`, `triage`, its own `handoff` and
`code-review`, and others) was not adopted: this manual's own skills and the clients' built-in
commands already cover what they do.

## Adding to this page

A kindred system earns a place here by being public, independently built, and convergent on at
least one of this manual's principles, with the convergence stated specifically, not as mutual
admiration. Differences get recorded with the same care as agreements.
