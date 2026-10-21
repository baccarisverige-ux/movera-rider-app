export const meta = {
  name: 'movera-app-audit',
  description: 'Deep bug audit of one Movera Flutter app: area + lens finders, dedup, two adversarial verifiers per batch, tie-break, gap round',
  phases: [
    { title: 'Find', detail: 'area finders and bug-class lens finders' },
    { title: 'Dedup', detail: 'merge duplicate findings' },
    { title: 'Verify', detail: 'two independent skeptics per batch of findings' },
    { title: 'Tie-break', detail: 'third verdict where the skeptics disagree' },
    { title: 'Gaps', detail: 'completeness critic, targeted re-find, verify' },
  ],
}

// ---------- args ----------
const app = args.app           // 'driver' | 'rider'
const appName = args.appName
const repoDir = args.repoDir
const otherRepoDir = args.otherRepoDir
const docs = args.docs         // repo-relative doc paths finders must read first
const areas = args.areas       // [{key, label, scope, focus}]
const lenses = args.lenses     // [{key, label, focus, greps}]
const skipGlobs = args.skipGlobs

// ---------- schemas ----------
const SEVERITIES = ['critical', 'high', 'medium', 'low']
const FINDING = {
  type: 'object',
  properties: {
    file: { type: 'string', description: 'repo-relative path, e.g. lib/core/ride/x.dart' },
    line: { type: 'integer' },
    title: { type: 'string', description: 'one line, the defect itself' },
    category: { type: 'string', description: 'kebab-case class: crash, state-corruption, race, leak, data-loss, wrong-math, wrong-time, parsing, l10n, security, privacy, web-platform, contract-mismatch, ui-truth, test-integrity, ci, a11y, other' },
    severity: { type: 'string', enum: SEVERITIES },
    confidence: { type: 'number', description: '0..1' },
    description: { type: 'string', description: 'what is wrong and why, with the code path from a real caller' },
    failure_scenario: { type: 'string', description: 'concrete inputs/state -> wrong output/crash, as a user or operator would see it' },
    evidence: { type: 'string', description: 'quoted code lines with file:line' },
    suggested_fix: { type: 'string' },
  },
  required: ['file', 'line', 'title', 'category', 'severity', 'confidence', 'description', 'failure_scenario', 'evidence'],
}
const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    findings: { type: 'array', items: FINDING },
    files_read: { type: 'array', items: { type: 'string' }, description: 'every file you read fully' },
    coverage_notes: { type: 'string', description: 'what in scope you could not cover or only skimmed, and why' },
  },
  required: ['findings', 'files_read', 'coverage_notes'],
}
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
          evidence: { type: 'string' },
          severity: { type: 'string', enum: SEVERITIES, description: 'your own severity call' },
          repro: { type: 'string', description: 'how you checked: traced callers / ran a test (name it and quote the result) / docs' },
          corrected_title: { type: 'string', description: 'if the finding is real but misdescribed, the accurate one-line title' },
        },
        required: ['id', 'verdict', 'reason', 'severity', 'repro'],
      },
    },
  },
  required: ['verdicts'],
}
const MERGE_SCHEMA = {
  type: 'object',
  properties: {
    groups: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          ids: { type: 'array', items: { type: 'string' }, description: 'two or more ids that are the same defect' },
          keep: { type: 'string', description: 'the id whose write-up is best' },
          why: { type: 'string' },
        },
        required: ['ids', 'keep', 'why'],
      },
    },
  },
  required: ['groups'],
}
const TIEBREAK_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'refuted'] },
    reason: { type: 'string' },
    severity: { type: 'string', enum: SEVERITIES },
    repro: { type: 'string' },
  },
  required: ['verdict', 'reason', 'severity', 'repro'],
}
const GAPS_SCHEMA = {
  type: 'object',
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          label: { type: 'string' },
          scope: { type: 'string', description: 'files/dirs to read' },
          focus: { type: 'string', description: 'what to look for and why it is likely under-covered' },
        },
        required: ['label', 'scope', 'focus'],
      },
    },
    notes: { type: 'string' },
  },
  required: ['gaps', 'notes'],
}

// ---------- shared prompt text ----------
const FLUTTER_HINT = args.readOnly ? `
Tooling: this run is READ-ONLY to save CPU for other checkers. Do not run flutter, dart or any build/test command. Verify by reading code and working exact values by hand; say so in repro.` : `
Tooling: a Flutter 3.47.6 SDK is being installed at /opt/flutter (ready when the file /opt/flutter/.audit-ready exists; check with ls). When it is ready you may reproduce a finding with a throwaway test: write it as ${repoDir}/test/_audit_<your-label>_test.dart (unique name, nothing else in test/), run it from ${repoDir} with \`PATH=/opt/flutter/bin:$PATH flutter test test/_audit_<your-label>_test.dart\`, quote the result, then delete the file. You may also run an existing single test file the same way. Never run the whole suite, never run \`flutter pub get\`, \`git checkout\`, \`git stash\` or any command that changes tracked files, and never edit app code. If the SDK is not ready, verify by reading only and say so.`

const GROUND_RULES = `
Ground rules for a professional audit:
- Report only real defects: a crash, wrong behaviour the user or operator would see, data loss or corruption, a state machine that can go wrong, a race, a leak that grows or fires after dispose, wrong math/time/money, mis-parsed data, a security or privacy hole, a broken translation, a UI that claims an action succeeded when it did not, a test that cannot fail or asserts the wrong thing, a CI step that cannot do its job.
- Not defects: style, naming, architecture taste, "this is a mock" (mocks are intentional and documented), TODOs, missing features, speculation with no reachable path.
- Every finding must be traced from a real caller or a real input to the failure. Quote the code. If a guard exists elsewhere, the finding is wrong: look for the guard before reporting.
- Read the documents listed below first; they record intentional decisions. Something those documents say is intended is not a bug, but a place where the code does NOT do what the document says it does IS a bug: report those.
- Read every file in your scope completely (use Read with offset/limit for long files). Do not sample. Big generated files (lib/l10n/app_localizations*.dart) are out of scope unless a finding leads you there.
- Do not modify any file in the repository. Do not run git commands that change state.
- Severity: critical = crash/data loss/money wrong/security hole on a main path; high = main path wrong behaviour; medium = edge path wrong behaviour or leak; low = minor but real.
- Confidence is your honest probability that a skeptical senior engineer with the code open would agree it is a bug.
- Be exhaustive inside your scope. Prefer well-evidenced findings, but a missed real bug is a failure of this audit.`

const docsText = docs.map(d => `  - ${repoDir}/${d}`).join('\n')

function areaPrompt(a) {
  return `You are one finder in a deep bug audit of the Movera ${appName} app (Flutter), repository root ${repoDir}.
Your scope (read all of it):
${a.scope}
Focus for this scope: ${a.focus}
${GROUND_RULES}
Documents to read first:
${docsText}
Counterpart app for cross-reference only (read-only, not in scope): ${otherRepoDir}
Skip: ${skipGlobs}
${FLUTTER_HINT}
Return every defect you can trace, with repo-relative file paths and exact line numbers from the file as it is now.`
}

function lensPrompt(l) {
  return `You are one finder in a deep bug audit of the Movera ${appName} app (Flutter), repository root ${repoDir}.
You hunt ONE class of defect across the whole app (lib/**, web/*.js, web/index.html; tests only where they prove or hide a bug): ${l.label}.
What to look for: ${l.focus}
How: start with grep over lib/ for the patterns listed (and your own), then read each hit's surrounding code and callers fully. Useful greps: ${l.greps}
${GROUND_RULES}
Documents to read first:
${docsText}
Counterpart app for cross-reference only (read-only, not in scope): ${otherRepoDir}
Skip: ${skipGlobs}
${FLUTTER_HINT}
Return every defect you can trace, with repo-relative file paths and exact line numbers from the file as it is now.`
}

function describe(f) {
  return `--- id: ${f.id}
file: ${f.file}:${f.line}
title: ${f.title}
severity (claimed): ${f.severity}   confidence (claimed): ${f.confidence}   reported independently by ${f.reported_by.length} finder(s): ${f.reported_by.join(', ')}
description: ${f.description}
failure scenario: ${f.failure_scenario}
evidence: ${f.evidence}
suggested fix: ${f.suggested_fix || '(none)'}`
}

function verifierPrompt(batch, lens) {
  const lensText = lens === 'tracer'
    ? `Your method is static tracing: open each cited file at the cited lines, then every caller and callee that matters, every place the same state is written, every guard (mounted checks, null checks, try/catch, early returns, keys, idempotency), the contract files under contracts/ if a wire format is involved, and the documents below. Decide from what the code actually does, not from what the finding says it does.`
    : `Your method is reproduction: for each finding, find the shortest way to make it happen and make it happen. Prefer a real run: if the Flutter SDK is ready, write a throwaway test that exercises the exact path and run it; or run the existing test that covers that code and read what it proves. If a run is not possible, work the exact values by hand (actual inputs, Dart/Flutter runtime semantics such as setState after dispose throwing only in debug, Duration/DateTime arithmetic, double rounding, list bounds) and show the computation.`
  return `You are a skeptical senior Flutter engineer verifying findings from an audit of the Movera ${appName} app, repository root ${repoDir}. Your job is to REFUTE each finding below if it can be refuted. A finding survives only if a realistic runtime path from a real caller or real input reaches the failure and no guard stops it.
${lensText}
Verdicts: "confirmed" = you traced or reproduced the failure path and found no guard; "refuted" = give the decisive reason with file:line (a guard, dead code, unreachable state, intentional per a document, the finder misread the code, the effect is harmless); "uncertain" = say exactly what would settle it. Default to "refuted" when the scenario is speculative or not reachable from any real caller. Set your own severity for confirmed findings using: critical = crash/data loss/money wrong/security hole on a main path; high = main path wrong behaviour; medium = edge path wrong behaviour or leak; low = minor but real. If the finding is real but the title misstates it, give corrected_title.
Documents that record intentional decisions (read first):
${docsText}
Counterpart app for cross-reference only: ${otherRepoDir}
${FLUTTER_HINT}
Findings to verify (${batch.length}):
${batch.map(describe).join('\n')}
Return one verdict per id.`
}

function tiebreakPrompt(f, verdicts) {
  return `You are the deciding reviewer in a bug audit of the Movera ${appName} app, repository root ${repoDir}. Two verifiers disagreed (or could not decide) about one finding. Read the code yourself, from the cited lines through callers and guards, and decide. Where a run would settle it and the Flutter SDK is ready, run it.
Documents that record intentional decisions:
${docsText}
Counterpart app for cross-reference only: ${otherRepoDir}
${FLUTTER_HINT}
The finding:
${describe(f)}
Verifier verdicts so far:
${verdicts.map(v => `* [${v.lens}] ${v.verdict}: ${v.reason}\n  evidence: ${v.evidence || '(none)'}\n  repro: ${v.repro}`).join('\n')}
Decide confirmed or refuted, with the decisive reason and file:line.`
}

// ---------- helpers ----------
function key(f) { return `${f.file}:${f.line}` }
function nearby(a, b) { return a.file === b.file && Math.abs(a.line - b.line) <= 8 }
function dedupe(list, keptSoFar) {
  const kept = []
  for (const f of list) {
    const prior = keptSoFar.find(k => nearby(k, f)) || kept.find(k => nearby(k, f))
    if (prior) {
      if (!prior.reported_by.includes(f.reported_by[0])) prior.reported_by.push(f.reported_by[0])
      if (f.confidence > prior.confidence) {
        // keep the better write-up, keep the merged reporter list
        const reporters = prior.reported_by
        Object.assign(prior, f, { id: prior.id, reported_by: reporters })
      }
      continue
    }
    kept.push(f)
  }
  return kept
}
function batches(list, size) {
  const byFile = {}
  for (const f of list) (byFile[f.file] = byFile[f.file] || []).push(f)
  const out = []
  for (const file of Object.keys(byFile).sort()) {
    const fs = byFile[file].sort((a, b) => a.line - b.line)
    for (let i = 0; i < fs.length; i += size) out.push(fs.slice(i, i + size))
  }
  // small batches from different files can share one verifier (keeps the file count low)
  const merged = []
  for (const b of out) {
    const last = merged[merged.length - 1]
    if (last && last.length + b.length <= size) last.push(...b)
    else merged.push([...b])
  }
  return merged
}

let nextId = 1
function assignIds(findings, reporter) {
  return findings.filter(Boolean).map(f => ({
    ...f,
    line: Number.isInteger(f.line) ? f.line : 0,
    confidence: typeof f.confidence === 'number' ? f.confidence : 0.5,
    id: `${app}-${nextId++}`,
    reported_by: [reporter],
  }))
}

async function verifyAll(findings, phaseFind, phaseTie) {
  const byId = {}
  for (const f of findings) byId[f.id] = f
  const verdicts = {}  // id -> [{lens, ...}]
  async function runLens(list, lens) {
    const groups = batches(list, 5)
    log(`${app}: ${lens} pass over ${list.length} findings in ${groups.length} batches`)
    await parallel(groups.map((b, i) => async () => {
      const r = await agent(verifierPrompt(b, lens), { label: `verify:${lens}:${i + 1}/${groups.length}`, phase: phaseFind, schema: VERDICTS_SCHEMA })
      if (!r) return null
      for (const v of r.verdicts) {
        if (!byId[v.id]) continue
        ;(verdicts[v.id] = verdicts[v.id] || []).push({ lens, ...v })
      }
      return true
    }))
  }
  // Pass 1: every finding gets a static tracer. Pass 2: an independent reproducer
  // re-checks everything the tracer confirmed or could not decide, plus anything the
  // tracer refuted that two or more finders reported independently.
  await runLens(findings, 'tracer')
  const second = findings.filter(f => {
    const vs = verdicts[f.id] || []
    if (!vs.length) return true
    return vs.some(v => v.verdict !== 'refuted') || f.reported_by.length >= 2
  })
  await runLens(second, 'reproducer')

  const confirmed = [], refuted = [], needTie = []
  for (const f of findings) {
    const vs = verdicts[f.id] || []
    const c = vs.filter(v => v.verdict === 'confirmed').length
    const r = vs.filter(v => v.verdict === 'refuted').length
    f.verdicts = vs
    if (c >= 1 && r === 0) confirmed.push(f)
    else if (r >= 1 && c === 0 && vs.length >= 1 && r === vs.length) refuted.push(f)
    else needTie.push(f)   // disagreement, all-uncertain, or a verifier died
  }
  log(`${app}: ${confirmed.length} confirmed, ${refuted.length} refuted, ${needTie.length} to tie-break`)

  const tied = await parallel(needTie.map(f => () =>
    agent(tiebreakPrompt(f, f.verdicts), { label: `tie:${f.id}`, phase: phaseTie, schema: TIEBREAK_SCHEMA, effort: 'xhigh' })
      .then(t => ({ f, t }))))
  const decided = tied.filter(x => x && x.t)
  for (const x of decided) {
    x.f.verdicts.push({ lens: 'tiebreak', ...x.t })
    if (x.t.verdict === 'confirmed') confirmed.push(x.f)
    else refuted.push(x.f)
  }
  const unresolved = needTie.filter(f => !decided.some(x => x.f === f))

  for (const f of confirmed) {
    const sv = f.verdicts.filter(v => v.verdict === 'confirmed' && v.severity).map(v => v.severity)
    // final severity: the most common verifier call, ties broken toward the milder one
    const count = {}
    for (const s of sv) count[s] = (count[s] || 0) + 1
    f.final_severity = SEVERITIES.slice().reverse().sort((a, b) => (count[b] || 0) - (count[a] || 0))[0] || f.severity
    const ct = f.verdicts.find(v => v.corrected_title)
    if (ct) f.corrected_title = ct.corrected_title
  }
  return { confirmed, refuted, unresolved }
}

// ---------- Phase 1: find ----------
phase('Find')
const finders = [
  ...areas.map(a => ({ label: `area:${a.key}`, prompt: areaPrompt(a) })),
  ...lenses.map(l => ({ label: `lens:${l.key}`, prompt: lensPrompt(l) })),
]
log(`${app}: ${finders.length} finders (${areas.length} areas, ${lenses.length} lenses)`)
const raw = await parallel(finders.map(f => () =>
  agent(f.prompt, { label: f.label, phase: 'Find', schema: FINDINGS_SCHEMA }).then(r => ({ label: f.label, r }))))

const coverage = []
let all = []
for (const x of raw.filter(Boolean)) {
  if (!x.r) { coverage.push({ finder: x.label, note: 'finder returned nothing' }); continue }
  coverage.push({ finder: x.label, files_read: (x.r.files_read || []).length, notes: x.r.coverage_notes })
  all.push(...assignIds(x.r.findings || [], x.label))
}
const deadFinders = finders.length - raw.filter(Boolean).length
if (deadFinders) log(`${app}: ${deadFinders} finder(s) died; their scope is uncovered`)
log(`${app}: ${all.length} raw findings`)

// ---------- Phase 2: dedup ----------
phase('Dedup')
all.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line)
let deduped = dedupe(all, [])
log(`${app}: ${deduped.length} after line-window dedup`)
if (deduped.length > 1) {
  const listing = deduped.map(f => `${f.id} | ${f.file}:${f.line} | ${f.title}`).join('\n')
  const m = await agent(`Below are bug findings from several independent finders over the Movera ${appName} app (${repoDir}). Group the ones that are the SAME defect (same root cause; a fix for one fixes the others), even if they cite different lines. Different symptoms of different root causes in the same file are NOT the same defect. Only group when you are sure; when in doubt, read the cited code. Return only groups of two or more.\n${listing}`,
    { label: 'dedup:merge', phase: 'Dedup', schema: MERGE_SCHEMA })
  if (m) {
    const drop = new Set()
    for (const g of m.groups) {
      const members = g.ids.map(id => deduped.find(f => f.id === id)).filter(Boolean)
      if (members.length < 2) continue
      const keep = members.find(f => f.id === g.keep) || members[0]
      for (const f of members) if (f !== keep) {
        for (const r of f.reported_by) if (!keep.reported_by.includes(r)) keep.reported_by.push(r)
        keep.merged_from = (keep.merged_from || []).concat([`${f.file}:${f.line} ${f.title}`])
        drop.add(f.id)
      }
    }
    deduped = deduped.filter(f => !drop.has(f.id))
    log(`${app}: ${deduped.length} after merge (${drop.size} merged)`)
  }
}

// ---------- Phase 3/4: verify + tie-break ----------
phase('Verify')
const round1 = await verifyAll(deduped, 'Verify', 'Tie-break')

// ---------- Phase 5: gaps ----------
phase('Gaps')
const seen = deduped.slice()
const scopeText = areas.map(a => `[${a.key}] ${a.scope}`).join('\n')
const critic = args.noGaps ? null : await agent(`You are the completeness critic for a bug audit of the Movera ${appName} app (${repoDir}). The finders' scopes were:\n${scopeText}\nLens finders also swept the whole app for: ${lenses.map(l => l.label).join('; ')}.\nFinder coverage notes:\n${coverage.map(c => `- ${c.finder}: read ${c.files_read ?? '?'} files. ${c.notes || ''}`).join('\n')}\nConfirmed so far (${round1.confirmed.length}):\n${round1.confirmed.map(f => `- ${f.file}:${f.line} ${f.corrected_title || f.title} [${f.final_severity}]`).join('\n') || '(none)'}\nRefuted (${round1.refuted.length}):\n${round1.refuted.map(f => `- ${f.file}:${f.line} ${f.title}`).join('\n') || '(none)'}\nYour job: say what is most likely still missed. Look at the repository yourself: list lib/ and web/, compare against the scopes and the notes, spot files and flows no finder could have read closely (large files, files the notes say were skimmed, flows that cross several areas such as crash-restore, cancel paths, payment capture, scheduled rides, background/foreground lifecycle, locale switching, first-run permissions), and defect classes under-represented above relative to what this kind of app usually gets wrong. Return at most 3 targeted gap scopes, each small enough for one careful reader (under ~4000 lines), most valuable first.`,
  { label: 'gaps:critic', phase: 'Gaps', schema: GAPS_SCHEMA })

let round2 = { confirmed: [], refuted: [], unresolved: [] }
let gapFindingsCount = 0
if (critic && critic.gaps.length) {
  const gaps = critic.gaps.slice(0, 3)
  log(`${app}: ${gaps.length} gap scopes: ${gaps.map(g => g.label).join('; ')}`)
  const rawGap = await parallel(gaps.map(g => () =>
    agent(areaPrompt({ key: `gap:${g.label}`, scope: g.scope, focus: g.focus + '\nFindings already known (do not re-report; look for what is NOT on this list):\n' + seen.map(f => `- ${f.file}:${f.line} ${f.title}`).join('\n') }),
      { label: `gap:${g.label}`, phase: 'Gaps', schema: FINDINGS_SCHEMA }).then(r => ({ label: `gap:${g.label}`, r }))))
  let gapAll = []
  for (const x of rawGap.filter(Boolean)) {
    if (!x.r) continue
    coverage.push({ finder: x.label, files_read: (x.r.files_read || []).length, notes: x.r.coverage_notes })
    gapAll.push(...assignIds(x.r.findings || [], x.label))
  }
  gapAll.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line)
  const fresh = dedupe(gapAll, seen)
  gapFindingsCount = fresh.length
  log(`${app}: gap round found ${gapAll.length} raw, ${fresh.length} new`)
  if (fresh.length) round2 = await verifyAll(fresh, 'Gaps', 'Gaps')
}

// ---------- result ----------
const strip = f => ({
  id: f.id, file: f.file, line: f.line, title: f.corrected_title || f.title, original_title: f.title,
  category: f.category, severity: f.final_severity || f.severity, claimed_severity: f.severity, confidence: f.confidence,
  reported_by: f.reported_by, merged_from: f.merged_from || [],
  description: f.description, failure_scenario: f.failure_scenario, evidence: f.evidence, suggested_fix: f.suggested_fix || '',
  verdicts: (f.verdicts || []).map(v => ({ lens: v.lens, verdict: v.verdict, severity: v.severity, reason: v.reason, repro: v.repro, evidence: v.evidence || '' })),
})
const order = s => SEVERITIES.indexOf(s)
const confirmed = round1.confirmed.concat(round2.confirmed).map(strip).sort((a, b) => order(a.severity) - order(b.severity) || a.file.localeCompare(b.file))
const refuted = round1.refuted.concat(round2.refuted).map(strip)
const unresolved = round1.unresolved.concat(round2.unresolved).map(strip)
log(`${app}: done. ${confirmed.length} confirmed, ${refuted.length} refuted, ${unresolved.length} unresolved`)
return {
  app, repoDir,
  counts: { finders: finders.length, dead_finders: deadFinders, raw: all.length, deduped: deduped.length, gap_new: gapFindingsCount, confirmed: confirmed.length, refuted: refuted.length, unresolved: unresolved.length },
  confirmed, refuted, unresolved,
  coverage, critic_notes: critic ? critic.notes : '',
}
