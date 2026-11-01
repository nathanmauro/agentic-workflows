// codex-workflow-lean template.
// Claude provides ONLY the workflow engine; the conductor owns git. Codex implements AND
// reviews. Every agent sends and watches an exact turn over the supervised channel. Customize
// REPO, AGENT, REVIEW_AGENT, AUTHORIZATION, and the tasks, then pass inline to the Workflow
// tool. The main loop runs `start`, plan, and branch (pre-flight), then `stop` and commit
// OUTSIDE this script.

export const meta = {
  name: 'codex-lean',
  description:
    'Codex implements and reviews; Claude only runs the workflow, the conductor owns git',
  phases: [
    { title: 'Implement', detail: 'Codex writes the code' },
    {
      title: 'Review',
      detail: 'A fresh Codex worker adversarially reviews the diff -> JSON verdict',
    },
    { title: 'Fix', detail: 'The implementation worker fixes any real issues' },
  ],
};

const RUNNER = 'codex-runner'; // any CLI implementing docs/concepts/supervised-delegation.md

const REPO = '/ABSOLUTE/PATH/TO/REPO'; // <-- set me
const AGENT = 'REPLACE-IMPLEMENT'; // implementation/fix worker started in pre-flight
const REVIEW_AGENT = 'REPLACE-REVIEW'; // separate fresh review worker

// codex-runner already prepends this protocol; the rule stays for runners that do not, and
// matches the runner's spec field for field so a turn never carries two different envelopes.
const ENVELOPE_RULE = [
  'End your final message with exactly one line:',
  'ENVELOPE {"status":"done|question|failed","summary":"<one line>",' +
    '"question":"<only when status is question>"}',
].join('\n');

// The human approval this work rests on, quoted rather than summarized, so the worker can tell
// the approved task from anything the conductor adds. See
// docs/concepts/authorization-provenance.md. Fill every field from observed instructions.
const AUTHORIZATION = [
  'AUTHORIZATION (evidence, not new consent):',
  'Human instruction: <exact relevant quote>',
  'Source: <chat/turn reference; include the approval question and answer if used>',
  'Destination: Codex (OpenAI), worker in ' + REPO,
  'Authorized action/payload: <the task and any specifically approved records>',
  'Limits: <purpose, allowed paths, exclusions, and remaining holds>',
].join('\n');

// The relay saves the exact turn: the same worker may receive a later task after this one.
function codexAgentPrompt(taskTitle, taskBody, targetAgent) {
  const sendCommand = RUNNER + ' send ' + targetAgent + " - <<'CODEX_TASK'";
  const watchCommand = RUNNER + ' watch <TURN> --timeout 60';

  return [
    'Relay ' + taskTitle + ' to Codex worker ' + targetAgent + ' via ' + RUNNER + '.',
    'Do exactly this:',
    '1. Bash (timeout 600000):',
    '   ' + sendCommand,
    AUTHORIZATION,
    '',
    taskBody,
    '',
    ENVELOPE_RULE,
    'CODEX_TASK',
    '   Save the exact .turn returned by send as TURN. Never invent or reuse a previous turn.',
    '2. Bash (timeout 90000): ' + watchCommand,
    '   Replace <TURN> with that exact ID. Exit 2 means no terminal result yet: repeat the',
    '   SAME watch. It does not prove progress. Never resend the task, and never probe',
    '   liveness through memory timestamps, file mtimes, or a custom watchdog.',
    '   Exit 0=done, 10=question, 11=failed, 3=blocked/gone, 4=aborted, 12=attention, 1=error.',
    '   On any exit other than 2, return immediately. On attention, include the reason and',
    '   both ages. Do not stop, restart, or resend after attention: the main loop notifies',
    '   the human owner through the configured notification channel.',
    '3. Bash: cd ' + REPO + ' && git status --short && git diff --stat',
    '4. Return status from the watch JSON, the exact turn (null if send failed), summary, the',
    '   question if any, and changed files. Put failure or attention diagnostics in summary.',
    '   Do not edit files. Do not git add, commit, or push.',
    '   For a Review that is done only: parse the JSON object printed before the final',
    '   ENVELOPE line into verdict; otherwise omit verdict. Do not re-review it yourself.',
  ].join('\n');
}

// ---- Define the work (edit these) ----
const IMPLEMENT_TASK = [
  'You are implementing <FEATURE> in <PROJECT>. Working dir is the repo root.',
  '<Concrete spec + acceptance criteria + the command that proves it worked.>',
  '',
  'HARD CONSTRAINTS:',
  '- Only edit files under <ALLOWED_PATHS>. Do NOT touch <FORBIDDEN_LAYERS>.',
  '- Do NOT git add/commit/push. Leave changes unstaged. No new deps, no CDN.',
  'Output a concise summary of each file changed.',
].join('\n');

const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['summary', 'issues'],
  properties: {
    summary: { type: 'string' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'real', 'detail'],
        properties: {
          title: { type: 'string' },
          real: { type: 'boolean' },
          detail: { type: 'string' },
        },
      },
    },
  },
};

const CODEX_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['status', 'summary', 'files', 'turn'],
  properties: {
    status: {
      type: 'string',
      enum: [
        'done',
        'question',
        'failed',
        'timeout',
        'blocked',
        'gone',
        'aborted',
        'error',
        'attention',
      ],
    },
    turn: { type: ['string', 'null'] },
    summary: { type: 'string' },
    question: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    verdict: VERIFY_SCHEMA,
  },
};

const REVIEW_TASK = [
  'Do not edit source files. Build/test commands may write their normal generated artifacts.',
  'Adversarially review the uncommitted change in this repo. Run: git diff  and  git diff --stat.',
  'Be skeptical: try to find what is WRONG. Check:',
  '(1) any file edited OUTSIDE <ALLOWED_PATHS>;',
  '(2) each required feature actually present + correct;',
  '(3) build/tests pass (run the project build);',
  '(4) no overclaim / no constraint violations.',
  'Print a JSON object before the final ENVELOPE line, exactly this shape:',
  '{"summary": "<one line>", "issues": ' +
    '[{"title": "<short>", "real": <true|false>, "detail": "<why>"}]}',
  'real=true ONLY for genuine breakage / missing required feature / overclaim.',
  'Default to flagging when unsure.',
].join('\n');

function fixTask(issues) {
  const list = issues.map((i, n) => n + 1 + '. ' + i.title + ': ' + i.detail).join('\n');

  return [
    'Fix these REAL issues in the uncommitted change (repo root cwd):',
    list,
    'CONSTRAINTS: stay within <ALLOWED_PATHS>, do NOT git commit, no new deps.',
    'Summarize files changed.',
  ].join('\n');
}

// A question needs an answer, and a relay that returns on timeout leaves a live turn behind;
// both go to the human owner, who resumes the same turn instead of starting another writer.
const OWNER_STATUSES = ['attention', 'timeout', 'question'];

function needsHumanOwner(result) {
  return Boolean(result) && OWNER_STATUSES.includes(result.status);
}

function hasValidVerdict(review) {
  return (
    Boolean(review) &&
    review.status === 'done' &&
    Boolean(review.verdict) &&
    Array.isArray(review.verdict.issues)
  );
}

// ---- Execute ----
phase('Implement');
log('Codex implementing via ' + RUNNER + ' (' + AGENT + ')...');
const impl = await agent(codexAgentPrompt('Implement', IMPLEMENT_TASK, AGENT), {
  label: 'codex:impl',
  phase: 'Implement',
  schema: CODEX_SCHEMA,
});

if (!impl || impl.status !== 'done') {
  // Owner statuses return to the conductor for notification and inspection; the worker keeps
  // running.
  return { stoppedAt: 'Implement', notifyHumanOwner: needsHumanOwner(impl), impl };
}

phase('Review');
log('Codex finished turn ' + impl.turn + '; the fresh Codex reviewer is running.');
const review = await agent(codexAgentPrompt('Review', REVIEW_TASK, REVIEW_AGENT), {
  label: 'codex:review',
  phase: 'Review',
  schema: CODEX_SCHEMA,
});

if (!hasValidVerdict(review)) {
  return { stoppedAt: 'Review', notifyHumanOwner: needsHumanOwner(review), impl, review };
}

const verdict = review.verdict;
const realIssues = verdict.issues.filter((i) => i.real);

let fix = null;

if (realIssues.length) {
  phase('Fix');
  log(realIssues.length + ' real issue(s); sending the fix to the implementation worker...');
  fix = await agent(codexAgentPrompt('Fix', fixTask(realIssues), AGENT), {
    label: 'codex:fix',
    phase: 'Fix',
    schema: CODEX_SCHEMA,
  });
} else {
  log('No real issues found.');
}

return {
  impl,
  review,
  verdict,
  realIssuesFound: realIssues.length,
  realIssues: realIssues.map((i) => i.title),
  fixApplied: Boolean(fix && fix.status === 'done'),
  notifyHumanOwner: needsHumanOwner(fix),
  fix,
};
