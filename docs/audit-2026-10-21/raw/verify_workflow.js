export const meta = {
  name: 'movera-verify-findings',
  description: 'Verify one chunk of Movera audit findings: static tracer, independent reproducer, tie-break',
  phases: [
    { title: 'Trace', detail: 'static tracer per batch' },
    { title: 'Reproduce', detail: 'independent reproducer on what survived' },
    { title: 'Tie-break', detail: 'deciding verdict where the checkers disagree' },
  ],
}

const { app, appName, repoDir, otherRepoDir, docs } = args
const batches = args.batches.map(b => ({ ...b, path: `${args.batchDir}/${b.path}` }))
const SEVERITIES = ['critical', 'high', 'medium', 'low']
const VERDICTS_SCHEMA = {
  type: 'object',
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
          reason: { type: 'string', description: 'the decisive argument, with file:line' },
          severity: { type: 'string', enum: SEVERITIES, description: 'your own severity call' },
          repro: { type: 'string', description: 'how you checked: traced callers / ran a test (name it and quote the result)' },
          corrected_title: { type: 'string', description: 'if real but misdescribed, the accurate one-line title' },
        },
        required: ['id', 'verdict', 'reason', 'severity', 'repro'],
      },
    },
  },
  required: ['verdicts'],
}
const TIE_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'refuted'] },
    reason: { type: 'string' },
    severity: { type: 'string', enum: SEVERITIES },
    repro: { type: 'string' },
    corrected_title: { type: 'string' },
  },
  required: ['verdict', 'reason', 'severity', 'repro'],
}

const docsText = docs.map(d => `  - ${repoDir}/${d}`).join('\n')
const TOOLING = `Tooling: Flutter 3.47.6 is installed at /opt/flutter and dependencies are resolved. To reproduce, write a throwaway test as ${repoDir}/test/_audit_<unique-label>_test.dart, run it from ${repoDir} with \`PATH=/opt/flutter/bin:$PATH flutter test test/_audit_<unique-label>_test.dart\`, quote the result, then delete the file. You may run one existing test file the same way. Never run the whole suite, never run \`flutter pub get\`, never change tracked files, never run git commands that change state.`
const SEVERITY_RULE = `Severity: critical = crash/data loss/money wrong/security hole on a main path; high = main path wrong behaviour; medium = edge path wrong behaviour or leak; low = minor but real.`

function verifyPrompt(path, ids, lens) {
  const method = lens === 'tracer'
    ? `Your method is static tracing: open each cited file at the cited lines, then every caller and callee that matters, every place the same state is written, every guard (mounted checks, null checks, try/catch, early returns, keys, idempotency), the contract files under contracts/ if a wire format is involved, and the documents below. Decide from what the code actually does, not from what the finding says.`
    : `Your method is reproduction: find the shortest way to make each failure happen and make it happen. Prefer a real run (a throwaway test exercising the exact path, or the existing test covering that code). If a run is not possible, work the exact values by hand (actual inputs, Dart/Flutter runtime semantics, Duration/DateTime arithmetic, rounding, bounds) and show the computation. Do not rely on any earlier verdict; you have none.`
  return `You are a skeptical senior Flutter engineer verifying audit findings in the Movera ${appName} app, repository root ${repoDir}. Your job is to REFUTE each finding if it can be refuted. A finding survives only if a realistic runtime path from a real caller or real input reaches the failure and no guard stops it.
${method}
Read the findings from the JSON file ${path}. Verify ONLY these ids: ${ids.join(', ')}.
Verdicts: "confirmed" = you traced or reproduced the failure and found no guard; "refuted" = give the decisive reason with file:line (a guard, unreachable state, intentional per a document, misread code, harmless effect); "uncertain" = say exactly what would settle it. Default to "refuted" when the scenario is speculative or unreachable. Mocks are intentional and documented; "it's a mock" is not a bug, but the app showing success it did not achieve is. ${SEVERITY_RULE} If real but misdescribed, give corrected_title.
Documents that record intentional decisions (read first):
${docsText}
Counterpart app for cross-reference only: ${otherRepoDir}
${TOOLING}
Return one verdict per id.`
}

function tiePrompt(path, id, vs) {
  return `You are the deciding reviewer in a bug audit of the Movera ${appName} app, repository root ${repoDir}. Two checkers disagreed or could not decide about finding ${id}. Read it from the JSON file ${path} (the entry with "id": "${id}"). Read the code yourself, from the cited lines through callers and guards, and decide. Where a run would settle it, run it.
Documents that record intentional decisions:
${docsText}
Counterpart app for cross-reference only: ${otherRepoDir}
${TOOLING}
${SEVERITY_RULE}
Checker verdicts so far:
${vs.map(v => `* [${v.lens}] ${v.verdict}: ${v.reason}\n  repro: ${v.repro}`).join('\n')}
Decide confirmed or refuted, with the decisive reason and file:line.`
}

const verdicts = {}
const pathOf = {}
for (const b of batches) for (const id of b.ids) { pathOf[id] = b.path; verdicts[id] = [] }
function record(lens, r, allowed) {
  if (!r) return
  for (const v of r.verdicts) if (allowed.includes(v.id)) verdicts[v.id].push({ lens, ...v })
}

phase('Trace')
await parallel(batches.map((b, i) => () =>
  agent(verifyPrompt(b.path, b.ids, 'tracer'), { label: `trace:${app}:${b.path.split('/').pop()}`, phase: 'Trace', schema: VERDICTS_SCHEMA })
    .then(r => record('tracer', r, b.ids))))

phase('Reproduce')
const second = batches.map(b => ({
  path: b.path,
  ids: b.ids.filter(id => {
    const vs = verdicts[id]
    return !vs.length || vs.some(v => v.verdict !== 'refuted') || b.multi.includes(id)
  }),
})).filter(b => b.ids.length)
log(`${app}: reproducer re-checks ${second.reduce((n, b) => n + b.ids.length, 0)} of ${Object.keys(verdicts).length}`)
await parallel(second.map(b => () =>
  agent(verifyPrompt(b.path, b.ids, 'reproducer'), { label: `repro:${app}:${b.path.split('/').pop()}`, phase: 'Reproduce', schema: VERDICTS_SCHEMA })
    .then(r => record('reproducer', r, b.ids))))

phase('Tie-break')
const status = {}
const needTie = []
for (const id of Object.keys(verdicts)) {
  const vs = verdicts[id]
  const c = vs.filter(v => v.verdict === 'confirmed').length
  const r = vs.filter(v => v.verdict === 'refuted').length
  if (c >= 1 && r === 0 && vs.every(v => v.verdict === 'confirmed')) status[id] = 'confirmed'
  else if (r >= 1 && c === 0 && vs.every(v => v.verdict === 'refuted')) status[id] = 'refuted'
  else needTie.push(id)
}
log(`${app}: ${needTie.length} to tie-break`)
await parallel(needTie.map(id => () =>
  agent(tiePrompt(pathOf[id], id, verdicts[id]), { label: `tie:${id}`, phase: 'Tie-break', schema: TIE_SCHEMA, effort: 'xhigh' })
    .then(t => {
      if (!t) return
      verdicts[id].push({ lens: 'tiebreak', ...t })
      status[id] = t.verdict
    })))
for (const id of needTie) if (!status[id]) status[id] = 'unresolved'

const counts = {}
for (const s of Object.values(status)) counts[s] = (counts[s] || 0) + 1
log(`${app}: ${JSON.stringify(counts)}`)
return { app, status, verdicts, counts }
