# Skill Registry

A curated registry, not a bulk install. Live symlinks and client settings are the authority for
what is installed; this file records ownership, provenance, authority, and evidence. Before
adopting or materially changing a skill, fill in every row. An install is not validation: if
provenance, permissions, policy conflicts, or efficacy cannot be established, leave the candidate
uninstalled or mark it `trial` with the missing gate stated.

## Registry contract

| Field                 | Required evidence                                                                                                                                                   |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name and clients      | Exact skill name and each client or surface that loads it.                                                                                                          |
| Owner or source       | Owning repo, official marketplace source, or a vendored copy whose upstream commit, licence, and modifications are recorded. Never an unexplained copied directory. |
| Provenance or version | Commit, plugin version, vendored upstream commit, or dated revision that can be checked again.                                                                      |
| Authority and risk    | External systems, credentials, writes, publication, destructive actions, and subprocesses it can reach.                                                             |
| Trigger boundary      | Three to five positive prompts it should fire on and two to three adjacent prompts where it must stay quiet.                                                        |
| Validation evidence   | At least one measured run or faithful simulation, plus the relevant static checks.                                                                                  |
| Last meaningful use   | Date and a compact outcome, not an install date.                                                                                                                    |
| Status                | `active`, `trial`, `blocked`, or `retired`, with a reason for anything except `active`.                                                                             |

Review unused or unmeasured skills for retirement instead of carrying permanent prompt surface. A
skill with zero uses two weeks after it got a trigger rule has either the wrong trigger or is
finished; take it off the active surface.

## Example record

### `example-skill`

- **Name and clients:** `example-skill`; linked into Claude Code and Codex from one tracked source.
- **Owner or source:** this repo, `agents/shared/skills/example-skill/`.
- **Provenance or version:** 2026-10-06 revision; the file's git history identifies later changes.
- **Authority and risk:** reads the working tree and runs the project's test command. No external
  writes, no credentials, no publication.
- **Positive triggers:** "diagnose why the build is flaky"; "this test fails only in CI"; "find
  the regression between these two commits".
- **Negative triggers:** "explain how the build works"; "add a test for the new endpoint".
- **Validation evidence:** a fresh session in each client loaded the skill on the positive
  prompts and stayed quiet on the negative ones (dated, with session ids kept privately).
- **Last meaningful use:** 2026-10-21, isolated a flaky integration test to a shared fixture.
- **Status:** `active`.

## Vendored skills

When a skill is copied from someone else's repository, keep a provenance file beside the copies
with the upstream URL, the vendored commit, the licence reproduced in full, and one entry per
skill listing exactly what the local adaptation changed. Pull upstream by hand: diff the vendored
commit against the new one for that skill's path, apply what you want, keep your modifications,
and update the vendored commit. Treat the upstream checkout as untrusted data: read it, do not run
its scripts.
