// codex-workflow-lean — template.
// Claude provides ONLY the workflow engine + git. Codex implements AND reviews.
// Every agent is a thin wrapper around `codex exec`. Customize REPO + tasks, pass inline
// to the Workflow tool. Claude main loop does plan/branch/commit OUTSIDE this script.

export const meta = {
  name: 'codex-lean',
  description: 'Codex implements and reviews; Claude only runs the workflow + owns git',
  phases: [
    { title: 'Implement', detail: 'Codex (gpt-5.5) writes the code' },
    { title: 'Review', detail: 'Codex adversarially reviews its own diff -> JSON verdict' },
    { title: 'Fix', detail: 'Codex fixes any real issues' },
  ],
}

const REPO = '/ABSOLUTE/PATH/TO/REPO' // <-- set me

const CODEX_FLAGS =
  "-c model='\"gpt-5.5\"' -c model_reasoning_effort='\"xhigh\"' -c service_tier='\"priority\"' --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --color never"

// Thin Claude wrapper: write prompt -> run codex -> relay terse text summary.
function codexImplPrompt(taskTitle, taskFile, taskBody) {
  return [
    'Delegate to Codex CLI (gpt-5.5) and report tersely. Do exactly this:',
    '1. Write the TASK block below VERBATIM to ' + taskFile + ' (Write tool).',
    '2. Bash (timeout 600000, cwd ' + REPO + '): cd ' + REPO + ' && codex exec ' + CODEX_FLAGS + ' -- "$(cat ' + taskFile + ')"',
    '3. Then: cd ' + REPO + ' && git status --short && git diff --stat',
    '4. Return ONLY files changed + one line each + success/error. No reasoning traces. No git commit. No self-edits.',
    '',
    'TASK (' + taskTitle + '):',
    '------', taskBody, '------',
  ].join('\n')
}

// Thin Claude wrapper for REVIEW: Codex inspects the diff and prints JSON; agent validates via schema.
function codexReviewPrompt(taskFile, reviewBody) {
  return [
    'Run an adversarial code review via Codex and return its verdict as structured output.',
    '1. Write the REVIEW INSTRUCTIONS below VERBATIM to ' + taskFile + ' (Write tool).',
    '2. Bash (timeout 600000, cwd ' + REPO + '): cd ' + REPO + ' && codex exec ' + CODEX_FLAGS + ' -- "$(cat ' + taskFile + ')"',
    '3. Codex will print a JSON object. Return EXACTLY that JSON as your structured output',
    '   (match the required schema; do not add commentary, do not re-review yourself).',
    '',
    'REVIEW INSTRUCTIONS:',
    '------', reviewBody, '------',
  ].join('\n')
}

// ---- Define the work (edit these) ----
const IMPLEMENT_TASK = [
  'You are implementing <FEATURE> in <PROJECT>. Working dir is the repo root.',
  '<Concrete spec + acceptance criteria.>',
  '',
  'HARD CONSTRAINTS:',
  '- Only edit files under <ALLOWED_PATHS>. Do NOT touch <FORBIDDEN_LAYERS>.',
  '- Do NOT git add/commit/push. Leave changes unstaged. No new deps, no CDN.',
  'Output a concise summary of each file changed.',
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
          real: { type: 'boolean' },
          detail: { type: 'string' },
        },
      },
    },
  },
}

const REVIEW_TASK = [
  'Adversarially review the uncommitted change in this repo. Run: git diff  and  git diff --stat.',
  'Be skeptical — try to find what is WRONG. Check: (1) any file edited OUTSIDE <ALLOWED_PATHS>;',
  '(2) each required feature actually present + correct; (3) build/tests pass (run the project build);',
  '(4) no overclaim / no constraint violations.',
  'Then print ONLY a JSON object, no prose, exactly this shape:',
  '{"summary": "<one line>", "issues": [{"title": "<short>", "real": <true|false>, "detail": "<why>"}]}',
  'real=true ONLY for genuine breakage / missing required feature / overclaim. Default to flagging when unsure.',
].join('\n')

function fixTask(issues) {
  const list = issues.map((i, n) => (n + 1) + '. ' + i.title + ' — ' + i.detail).join('\n')
  return [
    'Fix these REAL issues in the uncommitted change (repo root cwd):',
    list,
    'CONSTRAINTS: stay within <ALLOWED_PATHS>, do NOT git commit, no new deps. Summarize files changed.',
  ].join('\n')
}

// ---- Execute ----
phase('Implement')
log('Codex implementing...')
const impl = await agent(codexImplPrompt('Implement', '/tmp/clean-impl.md', IMPLEMENT_TASK), { label: 'codex:impl', phase: 'Implement' })

phase('Review')
log('Codex adversarial self-review (fresh pass)...')
const verdict = await agent(codexReviewPrompt('/tmp/clean-review.md', REVIEW_TASK), { label: 'codex:review', phase: 'Review', schema: VERIFY_SCHEMA })
const realIssues = (verdict && verdict.issues ? verdict.issues : []).filter(i => i.real)

let fix = null
if (realIssues.length) {
  phase('Fix')
  log(realIssues.length + ' real issue(s) — Codex fixing...')
  fix = await agent(codexImplPrompt('Fix', '/tmp/clean-fix.md', fixTask(realIssues)), { label: 'codex:fix', phase: 'Fix' })
} else {
  log('No real issues found.')
}

return { impl, verdict, realIssuesFound: realIssues.length, realIssues: realIssues.map(i => i.title), fixApplied: Boolean(fix), fix }
