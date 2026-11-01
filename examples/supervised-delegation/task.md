# Task as sent

The text below is the task the conductor sent to the worker over the channel, condensed and
sanitized: private paths became `<private-control-plane>` or were dropped, the owner's name,
private implementation names, and vendor model IDs were generalized, and some clauses were
shortened. The protocol preamble (envelope contract, never wait
for input, never run git write commands) is prepended by the adapter and is not repeated here.

```text
You are working in the git worktree at the current directory (branch codex/skills-port) of a
PUBLIC portfolio repo: a sanitized export of a private agent control plane. The private sources
are read-only references at <private-control-plane>. HEAD already contains a July port of the
fleet skill. Your job is a reconciliation and sanitization pass on skills/ only.

HARD CONSTRAINTS
- Edit ONLY files under skills/ and scripts/audit-public.sh. Do NOT touch README.md, docs/,
  templates/, examples/, LICENSE.
- Never run git add / git commit / git push / git stash / git checkout. Leave changes unstaged.
- No new runtime dependencies. Keep each script's existing language and style; lines wrap at 100.
- Sanitization rules (the audit script enforces most of these; `bash scripts/audit-public.sh`
  must end with `audit ok`):
  * never write absolute home paths or the owner's private checkout paths
  * never write private implementation names anywhere under skills/
  * the owner's name becomes "the human owner"; private repo names become example names
  * a durable memory system is called "a durable memory adapter"; a notification channel is
    "the configured notification channel"
  * Herdr is a public tool and MAY be named. Any private wrapper around it must be replaced by
    the native `herdr` subcommand that does the same thing; only name flags that exist.
  * Model policy: skills stay model-generic. Remove every hard-coded model ID from prose and
    from script defaults. Scripts keep env-overridable knobs with NO default model and a
    one-line comment saying the client default applies.

TASKS
1. Fleet reconcile. Diff the private skill against skills/codex-fleet. Port, sanitized, every
   behavior the private skill has that the public one lacks or states differently. Where the
   public copy is MORE rigorous, keep it and make SKILL.md describe what the public scripts
   actually do. Make the helper table and the tests list match the files on disk exactly.
2. claude-remote. Port the current private skill over the public one, sanitized: Herdr-managed
   pane with Remote Control as the default; keep the "Preserve the authorization" section and
   its record block; native herdr commands only; the tmux script stays as the documented
   fallback. Make --model optional with no default; prove --dry-run still works.
3. council and lean. Remove model pins. In council, keep the "Public v0 Status" note and match
   the private skill's invocation wording.
4. Audit script. Make sure every script and test under skills/ is syntax-checked and run.
5. Verify: the audit ends with `audit ok`; `bash -n` every .sh; `node --check` every .js; run
   each test. Then grep skills/ for model names and justify every remaining hit.

OUTPUT: a terse summary: files changed with one line each, the audit's last line, the grep hit
list with your judgment per hit, and any private string you were unsure how to sanitize (leave
it in place and flag it rather than guessing). End with the protocol ENVELOPE line.
```
