// codex-workflow-hybrid template.
// Claude orchestrates; Codex implements over a supervised channel; Claude verifies;
// the SAME Codex worker fixes. Customize REPO, AGENT, AUTHORIZATION, the *_TASK strings, and
// the verify prompts, then pass inline to the Workflow tool. The main loop runs `start` and the
// branch (pre-flight), then `stop` and the commit (post-flight), OUTSIDE this script.

export const meta = {
  name: 'codex-hybrid',
  description: 'Codex implements + Claude adversarially verifies a scoped build',
  phases: [
    { title: 'Implement', detail: 'Codex writes the code over the supervised channel' },
    { title: 'Verify', detail: 'Claude lenses: functional + editorial' },
    { title: 'Fix', detail: 'The same Codex worker fixes any real issues' },
  ],
};

const RUNNER = 'codex-runner'; // any CLI implementing docs/concepts/supervised-delegation.md

const REPO = '/ABSOLUTE/PATH/TO/REPO'; // <-- set me
const AGENT = 'REPLACE-ME'; // <-- the "name" printed by `codex-runner start` in pre-flight

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
  },
};

// The relay saves the exact turn: the same worker may receive a later task after this one.
function codexAgentPrompt(taskTitle, taskBody) {
  const sendCommand = RUNNER + ' send ' + AGENT + " - <<'CODEX_TASK'";
  const watchCommand = RUNNER + ' watch <TURN> --timeout 60';

  return [
    'Relay ' + taskTitle + ' to Codex worker ' + AGENT + ' via ' + RUNNER + '. Do exactly this:',
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
  ].join('\n');
}

// ---- Define the work (edit these) ----
const IMPLEMENT_TASK = [
  'You are implementing <FEATURE> in <PROJECT>. Working dir is the repo root.',
  '',
  '<Describe exactly what to build, with concrete acceptance criteria.>',
  '<Name the command that proves it worked.>',
  '',
  'HARD CONSTRAINTS:',
  '- Only edit files under <ALLOWED_PATHS>. Do NOT touch <FORBIDDEN_LAYERS>.',
  '- Do NOT run git add / git commit / git push. Leave changes unstaged.',
  '- No new runtime dependencies, no CDN. Match the existing code style.',
  'Output a concise summary: each file changed and 1-2 lines on what you did.',
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
          real: {
            type: 'boolean',
            description: 'true ONLY for genuine breakage / missing required feature / overclaim',
          },
          detail: { type: 'string' },
        },
      },
    },
  },
};

const FUNCTIONAL_VERIFY = [
  'Verify the change in ' + REPO + '. Steps:',
  '1. git diff --stat: flag any file OUTSIDE the allowed paths as a REAL issue.',
  '2. Syntax/lint the changed files (e.g. node --check). Errors = real issue.',
  '3. Confirm each required feature is actually present in the code (cite line numbers).',
  '4. Build/test (the project build or test command). Failure = real issue.',
  'Return structured issues. real=true ONLY for genuine breakage or a missing required feature.',
].join('\n');

const EDITORIAL_VERIFY = [
  'Review the diff in ' + REPO + ' (git diff) for honesty + correctness.',
  '1. HONESTY: does anything overclaim beyond what was actually built? Flag as real.',
  '2. CORRECTNESS/AESTHETIC: genuine violations of the stated constraints = real;',
  '   style nits = real:false.',
  'Read the changed files. Return structured issues.',
].join('\n');

function fixTask(issues) {
  const list = issues.map((i, n) => n + 1 + '. ' + i.title + ': ' + i.detail).join('\n');

  return [
    'Fix these REAL issues found in the change (repo root cwd):',
    list,
    '',
    'CONSTRAINTS: stay within the allowed paths, do NOT git commit, no new deps.',
    'Summarize each file changed.',
  ].join('\n');
}

// A question needs an answer, and a relay that returns on timeout leaves a live turn behind;
// both go to the human owner, who resumes the same turn instead of starting another writer.
const OWNER_STATUSES = ['attention', 'timeout', 'question'];

function needsHumanOwner(result) {
  return Boolean(result) && OWNER_STATUSES.includes(result.status);
}

function isValidVerdict(verdict) {
  return Boolean(verdict) && Array.isArray(verdict.issues);
}

// ---- Execute ----
phase('Implement');
log('Delegating implementation to Codex via ' + RUNNER + ' (' + AGENT + ')...');
const impl = await agent(codexAgentPrompt('Implement', IMPLEMENT_TASK), {
  label: 'codex:impl',
  phase: 'Implement',
  schema: CODEX_SCHEMA,
});

if (!impl || impl.status !== 'done') {
  // Owner statuses return to the conductor for notification and inspection; the worker keeps
  // running.
  return {
    stoppedAt: 'Implement',
    notifyHumanOwner: needsHumanOwner(impl),
    impl,
  };
}

phase('Verify');
log('Codex finished turn ' + impl.turn + '; reviewers are running: functional + editorial.');
const verdicts = await parallel([
  () =>
    agent(FUNCTIONAL_VERIFY, {
      label: 'verify:functional',
      phase: 'Verify',
      schema: VERIFY_SCHEMA,
    }),
  () =>
    agent(EDITORIAL_VERIFY, {
      label: 'verify:editorial',
      phase: 'Verify',
      schema: VERIFY_SCHEMA,
    }),
]);

if (verdicts.length !== 2 || !verdicts.every(isValidVerdict)) {
  return {
    stoppedAt: 'Verify',
    impl,
    status: 'error',
    summary: 'A required reviewer did not return a valid verdict.',
  };
}

const realIssues = verdicts.flatMap((v) => v.issues.filter((i) => i.real));

let fix = null;

if (realIssues.length) {
  phase('Fix');
  log(realIssues.length + ' real issue(s); sending the fix to the same Codex worker...');
  fix = await agent(codexAgentPrompt('Fix', fixTask(realIssues)), {
    label: 'codex:fix',
    phase: 'Fix',
    schema: CODEX_SCHEMA,
  });
} else {
  log('No real issues found.');
}

return {
  impl,
  verify: verdicts,
  realIssuesFound: realIssues.length,
  realIssues: realIssues.map((i) => i.title),
  fixApplied: Boolean(fix && fix.status === 'done'),
  notifyHumanOwner: needsHumanOwner(fix),
  fix,
};
