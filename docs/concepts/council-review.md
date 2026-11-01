# Council Review

## The Problem

Hard technical decisions can suffer from single-model blind spots. One model may anchor on the first plausible solution, miss operational risk, or overfit to the wording of the prompt.

## The Pattern

Use one shared context pack, ask for independent opinions, run anonymized adversarial review, and then produce a neutral synthesis. The process is useful only when the voices can disagree before the final decision is written.

## How To Apply It

Prepare a context pack with the decision, constraints, relevant evidence, and the exact output expected. Send the same pack to each reviewer independently. Strip identities before cross-review so each reviewer critiques arguments rather than status or style.

After the reviews, write a neutral synthesis that separates consensus, disagreements, risks, and the final decision. Record the final decision in the project spec, handoff, or durable memory adapter so it can guide later work.

Invocation is adapter-specific: use an installed council skill or call the runner directly, and do not advertise a command that the current client does not provide. Present divergent positions through the client's question UI when available, or a numbered ballot in ordinary chat. Keep the moderator neutral and persist the independent opinions, cross-reviews, and synthesis as inspectable artifacts.

## Failure Modes

A biased prompt can make every reviewer repeat the same assumption. A moderator must not invent a missing voice, pretend that an unrun review happened, or become an extra voting voice. Review without action becomes theater; every council should end with a decision, a follow-up experiment, or a clear reason to defer.

## Related Templates

Related material:

- [`skills/council/SKILL.md`](../../skills/council/SKILL.md)
- [`templates/HANDOFF.md`](../../templates/HANDOFF.md)
