// codex-workflow-hybrid — template.
// Claude orchestrates; Codex (gpt-5.5) implements; Claude verifies; Codex fixes.
// Customize REPO, the *_TASK strings, and the verify prompts, then pass inline to the
// Workflow tool. Claude main loop handles plan/branch/commit OUTSIDE this script.

export const meta = {
  name: 'codex-hybrid',
  description: 'Codex implements + Claude adversarially verifies a scoped build',
  phases: [
    { title: 'Implement', detail: 'Codex (gpt-5.5) writes the code' },
    { title: 'Verify', detail: 'Claude lenses: functional + editorial' },
    { title: 'Fix', detail: 'Codex fixes any real issues' },
  ],
}

const REPO = '/ABSOLUTE/PATH/TO/REPO' // <-- set me

const CODEX_FLAGS =
  "-c model='\"gpt-5.5\"' -c model_reasoning_effort='\"xhigh\"' -c service_tier='\"priority\"' --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --color never"

// Wraps a Codex task in a thin Claude agent: write prompt -> run codex -> relay terse summary.
function codexAgentPrompt(taskTitle, taskFile, taskBody) {
  return [
    'Delegate this task to Codex CLI (gpt-5.5) and report back tersely. Do exactly this:',
    '1. Use the Write tool to write the TASK block below VERBATIM to ' + taskFile + '.',
    '2. Run this via Bash with timeout 600000 ms, cwd ' + REPO + ' :',
    '   cd ' + REPO + ' && codex exec ' + CODEX_FLAGS + ' -- "$(cat ' + taskFile + ')"',
    '3. When Codex finishes, run: cd ' + REPO + ' && git status --short && git diff --stat',
    '4. Return ONLY a terse report: files changed (from git), one line each, plus success/error.',
    '   Do NOT paste Codex reasoning. Do NOT git add/commit/push. Do NOT edit files yourself.',
    '',
    'TASK (' + taskTitle + '):',
    '------',
    taskBody,
    '------',
  ].join('\n')
}

// ---- Define the work (edit these) ----
const IMPLEMENT_TASK = [
  'You are implementing <FEATURE> in <PROJECT>. Working dir is the repo root.',
  '',
  '<Describe exactly what to build, with concrete acceptance criteria.>',
  '',
  'HARD CONSTRAINTS:',
  '- Only edit files under <ALLOWED_PATHS>. Do NOT touch <FORBIDDEN_LAYERS>.',
  '- Do NOT run git add / git commit / git push. Leave changes unstaged.',
  '- No new runtime dependencies, no CDN. Match the existing code style.',
  'Output a concise summary: each file changed and 1-2 lines on what you did.',
].join('\n')

const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['summary', 'issues'],
  properties: {
    summary: { type: 'string' },
    issues: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['title', 'real', 'detail'],
        properties: {
          title: { type: 'string' },
          real: { type: 'boolean', description: 'true ONLY for genuine breakage / missing required feature / overclaim' },
          detail: { type: 'string' },
        },
      },
    },
  },
}

const FUNCTIONAL_VERIFY = [
  'Verify the change in ' + REPO + '. Steps:',
  '1. git diff --stat — flag any file OUTSIDE the allowed paths as a REAL issue.',
  '2. Syntax/lint the changed files (e.g. node --check). Errors = real issue.',
  '3. Confirm each required feature is actually present in the code (cite line numbers).',
  '4. Build/test (e.g. mvn -q -DskipTests package, or the project build). Failure = real issue.',
  'Return structured issues. real=true ONLY for genuine breakage or a missing required feature.',
].join('\n')

const EDITORIAL_VERIFY = [
  'Review the diff in ' + REPO + ' (git diff) for honesty + correctness.',
  '1. HONESTY: does anything overclaim beyond what was actually built? Flag as real.',
  '2. CORRECTNESS/AESTHETIC: genuine violations of the stated constraints = real; style nits = real:false.',
  'Read the changed files. Return structured issues.',
].join('\n')

function fixTask(issues) {
  const list = issues.map((i, n) => (n + 1) + '. ' + i.title + ' — ' + i.detail).join('\n')
  return [
    'Fix these REAL issues found in the change (repo root cwd):',
    list,
    '',
    'CONSTRAINTS: stay within the allowed paths, do NOT git commit, no new deps.',
    'Summarize each file changed.',
  ].join('\n')
}

// ---- Execute ----
phase('Implement')
log('Delegating implementation to Codex gpt-5.5...')
const impl = await agent(codexAgentPrompt('Implement', '/tmp/cwf-impl.md', IMPLEMENT_TASK), { label: 'codex:impl', phase: 'Implement' })

phase('Verify')
log('Adversarial verify: functional + editorial (Claude lenses)...')
const verdicts = await parallel([
  () => agent(FUNCTIONAL_VERIFY, { label: 'verify:functional', phase: 'Verify', schema: VERIFY_SCHEMA }),
  () => agent(EDITORIAL_VERIFY, { label: 'verify:editorial', phase: 'Verify', schema: VERIFY_SCHEMA }),
])
const clean = verdicts.filter(Boolean)
const realIssues = clean.flatMap(v => (v.issues || []).filter(i => i.real))

let fix = null
if (realIssues.length) {
  phase('Fix')
  log(realIssues.length + ' real issue(s) — delegating fixes to Codex...')
  fix = await agent(codexAgentPrompt('Fix', '/tmp/cwf-fix.md', fixTask(realIssues)), { label: 'codex:fix', phase: 'Fix' })
} else {
  log('No real issues found.')
}

return { impl, verify: clean, realIssuesFound: realIssues.length, realIssues: realIssues.map(i => i.title), fixApplied: Boolean(fix), fix }
