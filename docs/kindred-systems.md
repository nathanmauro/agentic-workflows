# Kindred Systems

This manual distills one practice. Other people have distilled theirs, and when an independently built public system lands on the same patterns from a different direction, that convergence is evidence the patterns are real—not one person's habit. This page links those systems, maps the convergences honestly, and records what this manual has adopted from them.

## Skills For Real Engineers — Matt Pocock

[`mattpocock/skills`](https://github.com/mattpocock/skills) is a set of small, composable, model-agnostic agent skills condensed from the software-engineering classics (Brooks, Ousterhout, Fowler, Beck, Feathers), published with docs at [AI Hero](https://www.aihero.dev/). It is explicitly positioned against process-owning frameworks: the skills hold reusable discipline while the human keeps control of the process. Its best-known skill is [`grill-me`](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md)—"a relentless interview to sharpen a plan or design."

### Where the systems converge

The two systems were built independently and keep arriving at the same discipline:

| Shared idea | In Skills For Real Engineers | In this manual |
|---|---|---|
| The harness is the product | "Software engineering fundamentals matter more than ever… condensed into repeatable practices" | [Agentic operating system](concepts/agentic-operating-system.md) |
| One bounded slice per agent | [Tracer-bullet tickets](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md) "sized to fit in a single fresh context window"; never more than one decision per session | [Fleet execution](concepts/fleet-execution.md): one owner, one slice, one acceptance bar |
| The frontier | "Work the **frontier**: any ticket whose blockers are all done"—[wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md)'s "edge of the known" | The frontier handoffs that feed a [project trajectory](concepts/project-trajectory.md)'s futures—the same word, arrived at separately |
| Evidence over confidence | [Diagnosing bugs](https://github.com/mattpocock/skills/blob/main/skills/engineering/diagnosing-bugs/SKILL.md): "Build the right feedback loop, and the bug is 90% fixed"; triage verifies the claim before discussing it | Principle 3: a green command, inspected diff, or verified flow beats a persuasive summary |
| Manufactured disagreement before commitment | [Design-it-twice](https://github.com/mattpocock/skills/blob/main/skills/engineering/codebase-design/DESIGN-IT-TWICE.md): 3+ parallel sub-agents forced to radically different designs, then an opinionated synthesis | [Council review](concepts/council-review.md): independent views, adversarial cross-review, neutral synthesis |
| Remember the roads not taken | ADRs gated to load-bearing decisions; a `.out-of-scope/` knowledge base "so rejections aren't re-litigated" | Decisions captured with alternatives; rejected paths render as dead stubs on the [trajectory](concepts/project-trajectory.md), never as open futures |
| Compact, reference-first handoffs | [Handoff](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md): compact the conversation, redact secrets, reference existing artifacts instead of restating them | [Handoffs and continuity](concepts/handoffs-and-continuity.md): state, not transcripts; no secrets |
| The unknown is drawn honestly | Wayfinder's fog of war: "don't chart what you can't yet see" | [Projections](concepts/project-trajectory.md): plausible futures drawn as ghosts with confidence, expiring rather than lingering |

The fog-of-war and projection ideas are complements rather than duplicates: fog marks what cannot be stated precisely yet, while a projection names a future that can be stated—with a confidence attached. A trajectory needs both: ghosts for the futures you can name, fog for the ones you cannot.

### Different altitude, same seam

The systems own different layers. Skills For Real Engineers disciplines the **inside of a session**: how to interview the human, place a test seam, build a debugging feedback loop, review a diff. This manual disciplines the **space between sessions**: living specs, fleet rounds, mutation gates, closeouts, durable memory. They meet at the handoff—his skills end sessions the way this manual expects sessions to end. Run together, they compose rather than compete.

### Adopted here

Three of his moves were strong enough to fold into this manual:

1. **Grill before you spec.** The manual's core loop starts at intent, and the fastest way to corrupt a spec is to extract intent without interrogating it. A grilling session—the agent walks the design tree and asks every question whose prerequisites are settled, each with a recommended answer attached, fetching facts itself rather than asking the human for them—is the strongest known opening move for the [living spec](concepts/living-specs.md). The termination condition is the point: the interview ends when nothing is left silently assumed.
2. **Suggested disciplines travel with the handoff.** A handoff that records state but not *approach* makes the next session rediscover how to work. [`templates/HANDOFF.md`](../templates/HANDOFF.md) now carries a section naming the skills, patterns, or workflows the next session should load.
3. **Reference, don't duplicate.** A handoff points at specs, decisions, diffs, and commits by path or link; restating them creates copies that go stale and bloat the record.

## Adding to this page

A kindred system earns a place here by being public, independently built, and convergent on at least one of this manual's principles—with the convergence stated specifically, not as mutual admiration. Differences get recorded with the same care as agreements.
