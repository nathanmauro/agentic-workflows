# Authorization Provenance

## The Problem

A human says "start Claude in the project and ask it X." The coordinating agent launches a second
agent and hands it the task. Two things go wrong from here. The second agent, seeing no human in
the conversation, asks for permission again, and the human answers the same question twice. Or the
second agent, trusting the coordinator's summary ("the user approved this"), sends records the
human never mentioned to a provider the human never named. Both failures come from the same gap:
the authorization did not travel with the work.

## The Pattern

Treat authorization as evidence that is carried, not a state that is asserted. When one agent
delegates to another, the handoff includes the human's exact words, where they were said, the
destination, the authorized action or payload, and the limits. The receiving agent keeps that
record visible through the final reviewed tool call, including any sandbox escalation it has to
justify.

```text
Human instruction: <exact relevant quote>
Source: <chat or turn reference; include the approval question and answer if one was used>
Destination: <provider or system>, <project>
Authorized action/payload: <task or question, and any specifically approved records>
Limits: <purpose, relevant-only boundaries, exclusions, remaining holds>
```

Three rules make it work:

1. **Quote, do not paraphrase.** "The user approved this" is a claim. The user's sentence is
   evidence. An agent-written task is not new consent.
2. **Reuse matching scope; ask only for a missing one.** Approval for a destination, purpose, and
   data scope covers that triple until the human changes it. A later approval satisfies only the
   hold it names; every other exclusion stays.
3. **Respect a denial.** If a platform or tool review refuses, distinguish missing evidence from
   expanded access. Retry only with materially relevant evidence or a narrower scope, through the
   same reviewed mechanism. A repeated unchanged denial ends the attempt. Never switch transports,
   infer approval from elapsed time, or fix a denial with blanket permissions.

## How To Apply It

Add the record to every skill that launches or messages another agent, and to every fleet or
workflow prompt that passes human-approved work down a level. Fill it from observed instructions,
never from inference. Keep the supplied task distinct from any extra records or research the
coordinator proposes to attach; local read access to a file is not permission to share it with
another provider.

Check delivery before retrying after a timeout; the message may already have arrived. Do not paste
private records into the record merely to demonstrate authorization.

## Failure Modes

A coordinator that summarizes consent instead of quoting it will eventually broaden it. A
receiving agent that re-asks every question trains the human to say yes without reading. A
retry that changes transport after a denial is an evasion, whatever the intent. An authorization
record copied forward after the human changed their mind is worse than none, because it looks
complete.

## Related

- [`templates/portable-policy.md`](../../templates/portable-policy.md), "Authorization across handoffs"
- [`skills/claude-remote`](../../skills/claude-remote/SKILL.md), which carries this record
- [Claude from Codex](../workflows/claude-from-codex.md)
- [Handoffs and continuity](handoffs-and-continuity.md)
