# Claude From Codex

## When To Use It

Use this workflow when a Codex-led session needs Claude for bounded review, planning, debugging, or
a second opinion. It fits hard design choices, unfamiliar code paths, and any change where an
independent critique from a different model is worth more than another implementation pass. It is
the mirror of [Codex from Claude](codex-from-claude.md): either engine can lead a session, and the
model that did not write the code reviews it.

## Inputs

- A bounded Claude prompt: the question, the repo path, constraints, the relevant files, and the
  expected output shape.
- A terminal multiplexer that can host and observe agent terminals. The default is Herdr
  ([herdr.dev](https://herdr.dev)): `herdr-app` places one space per checkout with agents as tabs,
  and `hc` (`herdr-core`) runs and inspects the underlying terminal. Claude Code Remote Control is
  enabled on the new session so the human owner can join it from mobile. Detached tmux is the
  portable fallback, through the bundled [`start-claude-remote`][tmux-helper] script.
- An authorization record that carries the human owner's exact words, their source, the
  destination, the authorized payload, and the limits
  (see [Authorization provenance](../concepts/authorization-provenance.md)).
- Any project instructions, living spec, handoff, or context pack the review needs.

## Steps

1. Codex frames the request as review, planning, debugging, or a second opinion. It does not hand
   over open-ended ownership of the work.
2. Codex fills the authorization record from what the human owner actually said. "Start Claude and
   ask it X" authorizes both the launch and delivery of X; it does not authorize attaching other
   records that Codex can read locally. An agent-written task is not new consent.
3. Codex places the session. It checks `herdr-app ls`, adds a tab to the Herdr space that already
   holds this checkout (`herdr-app do tab.new`), or creates a space named after the repo
   (`herdr-app do space.new`) when none exists. If Claude will write while another writer is active
   on the same checkout, Codex creates a linked git worktree first and points `--folder` at it.
4. Codex starts Claude in that terminal with Remote Control on, using the configured Claude model
   and effort unless the human owner named another. When no Herdr window is open, `hc run --bg`
   starts a hidden `herdr-core` terminal that can be opened later with `herdr-app do terminal.open`.
   It honors an explicit request for tmux, no Remote Control, or a specific model.
5. Codex verifies the launch via `hc get` and `hc read` and reports what it observed: the terminal
   address (`tNN`), the space and tab, and the Remote Control URL only if Claude actually exposed
   one. A launched process and a reachable Remote Control session are different claims; if a check
   fails, Codex names that check.
6. Codex passes `--task` on launch or sends a prompt via `hc send` only when the human owner
   supplied a task, then inspects `hc read` before claiming the prompt ran.
7. Claude returns findings, a plan, or a recommendation.
8. Codex checks the response against local repo evidence and decides what to implement, adapt, or
   ignore. Nothing is accepted because it sounds right.
9. Codex records any accepted decision in the living spec, the handoff, or the durable memory
   adapter, with the rejected alternatives.

## Outputs

- Claude's bounded review, plan, or second-opinion result.
- A launch report that separates "process started" from "Remote Control verified".
- Codex's decision on what changes, if any, to make, and the evidence behind it.
- Updated project state when the result affects future work.

## Verification

Verify before accepting. Any change Codex makes on the strength of Claude's review is proven with a
concrete command in the target repo. A remote opinion is useful input; it is not local proof. If
Claude found a defect, reproduce it before fixing it.

## Safety Gates

- Keep the request bounded to review, planning, debugging, or a second opinion unless the human
  owner explicitly expands scope.
- Treat a working pane host as a prerequisite to check, not an assumption. If Herdr cannot provide
  a pane, report the blocker; do not silently switch to tmux or invent pane IDs.
- Carry the authorization record through the final reviewed tool call. On a denial, retry only with
  materially relevant evidence or a narrower scope through the same mechanism; never switch
  transport around it.
- After a timeout, check whether the prompt was delivered before resending it.
- Preserve unrelated dirty files.
- Do not publish private data, and do not paste private records into the prompt to prove
  authorization.
- Record a handoff when work remains.

## Related

- [`skills/claude-remote`](../../skills/claude-remote/SKILL.md)
- [Authorization provenance](../concepts/authorization-provenance.md)
- [Council review](../concepts/council-review.md), when one second opinion is not enough
- [Codex-led session](codex-led-session.md)
- [Codex from Claude](codex-from-claude.md)

[tmux-helper]: ../../skills/claude-remote/scripts/start-claude-remote
