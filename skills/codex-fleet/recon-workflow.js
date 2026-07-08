// codex-fleet recon workflow (fleet mode).
// Pass as Workflow `args`: {projects: [{name, path, hint}, ...], round: N }
// Re-run FRESH each round (no resumeFromRunId).
// Produces goalPrompts that tell Codex to:
//   - use fleet/round-N-... branch
//   - perform builds + optionally leave reviewable app instances
//   - record artifacts json for later cleanup (handled by the loop orchestrator in next RECON)
// Write each .goalPrompt to ~/.codex-goals/<name>.md.
// In PLAN mode the APPROVAL phase overrides recon's acceptanceCriteria with the human owner's approved version before launch.
export const meta = {
  name: 'codex-fleet-recon',
  description: 'Read specs/plans per project and draft + adversarially vet a codex goal prompt for the next task on each',
  phases: [
    { title: 'Recon', detail: 'one thorough reader per project' },
    { title: 'Vet', detail: 'adversarially sanity-check each goal is correct, well-scoped, safe' },
  ],
}

let PROJECTS = []
let ROUND = 1
let FLEET_SKILL_DIR = ''

// args may arrive as a JSON-encoded string depending on the harness; normalize to a value.
let ARGS = args
if (typeof ARGS === 'string') {
  try { ARGS = JSON.parse(ARGS) } catch (_e) { /* leave as raw string */ }
}

if (Array.isArray(ARGS)) {
  PROJECTS = ARGS
} else if (ARGS && typeof ARGS === 'object') {
  PROJECTS = Array.isArray(ARGS.projects) ? ARGS.projects : []
  ROUND = ARGS.round || 1
  FLEET_SKILL_DIR = ARGS.fleetSkillDir || ARGS.fleet_skill_dir || ''
}

if (!FLEET_SKILL_DIR && typeof process !== 'undefined' && process.env) {
  FLEET_SKILL_DIR = process.env.FLEET_SKILL_DIR || ''
}
FLEET_SKILL_DIR = FLEET_SKILL_DIR || '${FLEET_SKILL_DIR:-<agentic-workflows-repo>/skills/codex-fleet}'

if (!PROJECTS.length) {
  log('codex-fleet-recon: no projects passed via args (expected {projects: [...], round: N} or array).')
  return []
}

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['project', 'path', 'tier', 'pushAllowed', 'sliceSummary', 'stateSummary', 'specSources', 'nextTask', 'goalPrompt', 'complexity', 'currentBranch'],
  properties: {
    project: { type: 'string' },
    path: { type: 'string' },
    tier: { type: 'string', enum: ['prototype', 'production'] },
    pushAllowed: { type: 'boolean' },
    sliceSummary: { type: 'string', description: 'One-line vertical slice: the single coherent story, e.g. server + client + test.' },
    currentBranch: { type: 'string', description: 'git branch currently checked out, and whether working tree is dirty' },
    stateSummary: { type: 'string', description: '3-5 sentences: what the project is, what is already built/done, where it stands' },
    specSources: { type: 'array', items: { type: 'string' }, description: 'concrete files (paths) that define the roadmap/next steps, e.g. plans/*, ROADMAP, TODO, backlog, README sections, open issues' },
    nextTask: {
      type: 'object',
      additionalProperties: false,
      required: ['title', 'why', 'acceptanceCriteria', 'keyFiles', 'risks'],
      properties: {
        title: { type: 'string' },
        why: { type: 'string', description: 'why THIS is the next task per the specs/plans (cite the source)' },
        acceptanceCriteria: { type: 'array', items: { type: 'string' } },
        keyFiles: { type: 'array', items: { type: 'string' } },
        risks: { type: 'string', description: 'what could go wrong if an autonomous agent does this; any blockers' },
      },
    },
    complexity: { type: 'string', enum: ['small', 'medium', 'large'] },
    goalPrompt: { type: 'string', description: 'The complete, ready-to-fire prompt to hand a fresh Codex session (FLEET ROUND). Self-contained: names files, task + acceptance, verify cmd, per-repo dangers verbatim, fleet/round-N branch instruction, artifact recording instructions, and the full git workflow.' },
  },
}

const GIT_WORKFLOW = (projectName) => `Git workflow for the autonomous Codex session (FLEET MODE, ROUND ${ROUND}):
(1) Never commit as anyone but the human owner — do NOT add any Co-Authored-By trailer naming Claude/Codex/a model, do NOT add "Generated with" lines.
(2) Before editing, run \`git status\` and remember which files were ALREADY dirty — those are the human owner's in-flight work and are off-limits.
(3) Create and checkout a NEW **fleet iteration specific branch** named exactly \`fleet/round-${ROUND}-<kebab-case-slice-title>\` (e.g. fleet/round-2-add-user-auth). Stack off the previous fleet round's branch for this project if it exists.
(4) "If you hit a genuine fork the spec does not decide (scope, architecture, user-facing behavior, or a safety question), do NOT guess. Write ~/.codex-goals/<name>.question.json ({status:'open', round, question, context, options}) and STOP without committing partial guesses (commit only finished, verified work to the branch; otherwise leave the tree clean)." For this project, write that JSON to \`~/.codex-goals/${projectName}.question.json\`.
(5) Implement the task, then run the project's test/verify command and confirm it passes (commit only green).
(6) After the green verify, run \`bash "${FLEET_SKILL_DIR}/fleet-spec.sh" render ${projectName}\` and stage \`docs/fleet/spec.md\` with the slice. Stage ONLY files you created or modified: run \`git diff --name-only\` / \`git status\` first and \`git add\` those exact paths. NEVER use \`git add -A\`, \`git add .\`, or \`git add --update\`. Do NOT stage .claude/.firecrawl/.idea or any file that was already dirty before you started. Commit to the fleet branch only. Do NOT merge to main.
(7) **Artifacts for review (leave behind when useful)**:
   - If the project supports builds (npm run build, make build, etc.), run the build and leave the output (dist/, build/, .next/, etc.) as a reviewable version.
   - If it is a runnable app/server (web frontend, backend, TUI that can be demoed), after successful verify you MAY start a background instance for review (e.g. npm run dev & or the equivalent) on a non-conflicting port. Record the pid, port, and localhost URL.
   - Before the final fleet-open-pr.sh helper call, write a JSON file at \`~/.codex-goals/${projectName}-round-${ROUND}-artifacts.json\` containing at minimum: {"round": ${ROUND}, "branch": "<the exact branch you created>", "pids": [pid1, ...], "ports": [3001, ...], "review_url": "http://localhost:XXXX", "build_artifact_dir": "dist/", "notes": "short description of what is left for review"}.
   Only record things that are genuinely useful for the human owner to review the changes on this fleet branch. Do not leave long-running things that will collide if not cleaned.
(8) At the very end, after the commit and artifact recording, run \`bash "${FLEET_SKILL_DIR}/fleet-open-pr.sh" ${projectName} ${ROUND} <the exact branch you created>\`. Do NOT push or open PRs by hand; the helper owns push-vs-local-only and draft PR decisions.
(9) End with a 3-5 line summary of what changed, the branch name, and the verify command + result.`

phase('Recon')
const recon = await pipeline(
  PROJECTS,
  (p) => agent(
    `You are scoping the NEXT task for a project so a fresh autonomous Codex coding session can execute it. Project: ${p.name} at ${p.path}.

Context hint: ${p.hint || '(none)'}

Do this:
1. cd into the project. Run: git -C ${p.path} status -sb and git -C ${p.path} log --oneline -15 to see branch + recent work.
2. Run: cat ~/.codex-goals/${p.name}.spec.json. Read tier, push_allowed, and danger from that mirror and echo them back as tier, pushAllowed, and the verbatim danger in the goalPrompt.
3. Read docs/fleet/spec.md if it exists and treat it as PRIMARY context: Intent, Acceptance bar, Decided, Deferred, and prior Rounds. Respect Decided/Deferred. Fall back to PLAN.md/ROADMAP/README/git history only to fill gaps.
4. Find the supporting roadmap/next-step sources. Look hard for: plans/ or docs/plans/ or docs/superpowers/plans/, ROADMAP.md, TODO.md, BACKLOG, NEXT.md, README "next steps"/"roadmap" sections, CHANGELOG (to see what just shipped), open items in docs, and any *.md spec files. Also check for a tests/ dir and how tests run.
5. From the living spec, supporting specs/plans, and recent git history (what was just finished implies what's next), determine the SINGLE highest-value, well-scoped next VERTICAL SLICE that one autonomous agent can complete in a focused session. It must be one coherent story, for example server change + client change + test, not a vague task or disconnected chores.
6. Identify the exact files to read first and the files likely to change.
7. Determine the test/verify command for this repo.
8. Write a complete, self-contained goalPrompt to hand a fresh Codex session (it will start cold with no other context). The goalPrompt MUST:
   - name the plan/spec files to read first
   - state the task and acceptance criteria
   - give the test/verify command
   - copy any per-repo danger from the context hint VERBATIM
   - copy the mirror danger field VERBATIM when present
   - mention this is FLEET round ${ROUND}
   - embed this exact git workflow verbatim (with the correct project name substituted):

${GIT_WORKFLOW(p.name)}

Return a structured object with tier from the mirror (prototype|production), pushAllowed from mirror push_allowed, and sliceSummary as the vertical slice in one line. Be rigorous — read the actual files, do not guess. If the project has no clear plan, say so in stateSummary and propose the most defensible next slice from README + git history. Return the structured object.`,
    { label: `recon:${p.name}`, phase: 'Recon', schema: SCHEMA, effort: 'high' }
  ),
  // Vet stage: adversarial sanity check of the drafted goal
  (r, p) => {
    if (!r) return null
    return agent(
      `Adversarially vet this proposed next-task + Codex goal prompt for project "${p.name}" (${p.path}). Be a skeptic.

PROPOSED:
${JSON.stringify(r, null, 2)}

Check, by inspecting the repo yourself (cd ${p.path}):
- Is this genuinely the next task per the specs/plans, or did the recon agent miss a more obvious / explicitly-prioritized item? Verify the specSources actually say this.
- Did it treat docs/fleet/spec.md as primary context when present, including Intent, Acceptance bar, Decided/Deferred, and prior Rounds?
- Is sliceSummary a real vertical slice / single story rather than a bag of unrelated tasks?
- Is the task already done / partially done in recent commits or a branch?
- Is it well-scoped for ONE autonomous session (not too big, not blocked on a decision the human owner must make)?
- Is the test/verify command real (does it exist in package.json / Makefile / tests dir)?
- Do tier and pushAllowed exactly echo ~/.codex-goals/${p.name}.spec.json?
- Any safety issue per the project hint (e.g. a PUBLIC origin, a protected experimental branch, secrets)? If a per-repo danger from the hint is NOT already stated in the goalPrompt, INSERT it verbatim before returning — a cold Codex session sees only the goalPrompt.
- Is the goalPrompt self-contained and unambiguous for a cold-start agent?

Return the SAME schema object, corrected: fix anything wrong, tighten the goalPrompt, and append a one-line "[VET]" note at the END of stateSummary describing your verdict (confirmed / changed-task / scoped-down / flagged) and any residual risk. Keep the git workflow block in goalPrompt intact.`,
      { label: `vet:${p.name}`, phase: 'Vet', schema: SCHEMA, effort: 'high' }
    )
  }
)

return recon.filter(Boolean)
