#!/usr/bin/env node
// Harness for the feature-delivery workflow.
//
// T1 runs the workflow script with a stub `agent` that returns scripted
// results and validates each against the schema the script passed, then
// asserts on the returned status, the labels spawned, the options and the
// prompt texts. The real Workflow runtime spawns frontier agents and cannot be
// told what a critic finds, so no scenario could fail on demand there.
//
// T3 checks the documents against the script's single sources. The tables and
// lists the documents carry are generated from the script's `describe` output
// (`--write` rewrites them); each check passes on the repository and is shown,
// on every run, to fail on a temporary copy carrying one deliberate mismatch.
//
// Usage: node .claude/workflows/feature-delivery.harness.mjs
//        [--script <path>] [--only <prefix>] [--write]

import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(HERE, '..', '..')
const argValue = name => {
  const i = process.argv.indexOf(name)
  return i > 0 ? process.argv[i + 1] : null
}
const SCRIPT_PATH = argValue('--script') ? path.resolve(argValue('--script')) : path.join(HERE, 'feature-delivery.js')
const ONLY = argValue('--only')
const WRITE = process.argv.includes('--write')

const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor

function loadWorkflow(file) {
  const text = fs.readFileSync(file, 'utf8')
  if (!/^export const meta\s*=/m.test(text)) {
    throw new Error(`${file} has no "export const meta" to rewrite`)
  }
  const body = text.replace(/^export const meta\s*=/m, 'const meta =')
  return new AsyncFunction('args', 'agent', 'parallel', 'phase', 'log', body)
}

// ---- schema validation ---------------------------------------------------

// The subset of JSON Schema the workflow's schemas use.
function validate(schema, value, at = '$') {
  const errors = []
  if (!schema) {
    return errors
  }
  switch (schema.type) {
    case 'object': {
      if (value === null || typeof value !== 'object' || Array.isArray(value)) {
        return [`${at}: expected an object`]
      }
      for (const key of schema.required ?? []) {
        if (!(key in value)) {
          errors.push(`${at}: missing ${key}`)
        }
      }
      for (const key of Object.keys(value)) {
        if (schema.properties && key in schema.properties) {
          errors.push(...validate(schema.properties[key], value[key], `${at}.${key}`))
        } else if (schema.additionalProperties === false) {
          errors.push(`${at}: unexpected property ${key}`)
        }
      }
      return errors
    }
    case 'array':
      if (!Array.isArray(value)) {
        return [`${at}: expected an array`]
      }
      value.forEach((item, i) => errors.push(...validate(schema.items, item, `${at}[${i}]`)))
      return errors
    case 'string':
      if (typeof value !== 'string') {
        return [`${at}: expected a string`]
      }
      if (schema.enum && !schema.enum.includes(value)) {
        errors.push(`${at}: ${JSON.stringify(value)} not in ${schema.enum.join('|')}`)
      }
      if (schema.pattern && !new RegExp(schema.pattern).test(value)) {
        errors.push(`${at}: ${JSON.stringify(value)} does not match ${schema.pattern}`)
      }
      return errors
    case 'boolean':
      return typeof value === 'boolean' ? errors : [`${at}: expected a boolean`]
    case 'integer':
      return Number.isInteger(value) ? errors : [`${at}: expected an integer`]
    default:
      return [`${at}: unsupported schema type ${schema.type}`]
  }
}

// ---- the stub run ----------------------------------------------------------

const PROFILE_REL = 'doc/agents/delivery-profile.json'
const PROFILE = JSON.parse(fs.readFileSync(path.join(ROOT, PROFILE_REL), 'utf8'))
// The T1 scenarios test the script's logic, so they run on a fixture profile of
// their own, a project no scenario depends on. T1t shows the script accepts
// the project's real profile.
const FIXTURE = {
  version: 1,
  artifactsDir: 'work/runs',
  codePaths: ['src', 'tests', 'docs'],
  isolation: 'checkout',
  conventionDocs: ['docs/testing.md'],
  modules: {
    core: { paths: ['^src/core/'], guidance: ['docs/core.md'], vocabulary: 'Core vocabulary.' },
    io: { paths: ['^src/io/'], guidance: ['docs/io.md'], vocabulary: 'IO vocabulary.' },
  },
  gates: [
    { name: 'build', command: 'make build', pass: '0 errors', when: 'always', scope: 'step' },
    { name: 'io-tests', command: 'make io', pass: '0 failed', when: { paths: ['^src/io/'] }, scope: 'step' },
    { name: 'docs', command: 'make docs', pass: '0 warnings', when: { paths: ['^docs/'] }, scope: 'final' },
    { name: 'full', command: 'make all', pass: '0 failed', when: 'always', scope: 'final' },
  ],
  lenses: {
    runtime: { addendum: 'Correctness addendum.' },
    evidence: { reads: ['moduleGuidance', 'docs/perf.md'] },
  },
  ranking: ['user-visible-behaviour', 'architecture-fit'],
  hotPaths: ['per request'],
  planRules: ['Every fixture value names its unit.'],
  planChecks: [{ name: 'cites', stamp: 'check {plan} --stamp', verify: 'check {plan}', rebase: 'check {plan} --rebase', note: 'Accept with --accept.' }],
  defectClasses: ['stale-summary', 'unverified-claim'],
  roles: { planner: { effort: 'xhigh' }, extractor: { model: 'small', effort: 'low' } },
  budget: { rounds: 3, implementationRevisions: 1, fixLoops: 1 },
}
const SLUG = 'harness-run'
const DATE = '2026-10-09'
const DIR = FIXTURE.artifactsDir
const PLAN = `${DIR}/${DATE}-${SLUG}-plan.md`
const AUDIT = `${DIR}/${DATE}-${SLUG}-audit.md`
const ACCEPTANCE = `${DIR}/${DATE}-${SLUG}-acceptance.md`
const CRITERIA = ['Exporting an empty list writes only the header row, verified by tests/core/widget_test.ts']
const REQUEST = 'Make an export of an empty list write its header row.'
const SWEEP = ['runtime', 'evidence', 'surface']
const ROUND1 = SWEEP.map(k => `critic:${k}:r1`)
const CLEAN_RUN = ['plan:draft', ...ROUND1, 'steps', 'build', 'accept']

function baseArgs(over = {}) {
  return {
    slug: SLUG,
    date: DATE,
    requirements: {
      summary: 'A harness feature.',
      user_visible_behavior: [],
      acceptance_criteria: CRITERIA,
      modules_touched: ['src/core/widget.ts'],
      constraints: [],
      non_goals: [],
      open_questions: [],
    },
    profile: FIXTURE,
    request: REQUEST,
    baseRef: 'abc1234',
    ...over,
  }
}
const withProfile = over => baseArgs({ profile: { ...FIXTURE, ...over } })

const BASE_ITEM = { id: 'b1', location: 'd1', severity: 'blocking', title: 'Builder finding', why: 'w', suggested_direction: 's' }

let findingSerial = 0
function finding(over = {}) {
  findingSerial += 1
  return {
    id: `f-${findingSerial}`,
    location: 'd1',
    severity: 'minor',
    title: 'A finding',
    why: 'Evidence.',
    suggested_direction: 'A direction.',
    decision: 'none',
    kind: 'implementation',
    defect_class: 'other',
    ...over,
  }
}
const failingOn = (decision, over = {}) => finding({ severity: 'major', kind: 'surface', decision, ...over })
function critic(key, findings = []) {
  return { findings }
}

// The text between two markers of a prompt.
function between(prompt, start, end) {
  const i = prompt.indexOf(start)
  if (i < 0) {
    return ''
  }
  const rest = prompt.slice(i + start.length)
  const j = end ? rest.indexOf(end) : -1
  return j < 0 ? rest : rest.slice(0, j)
}
const idsIn = text => [...text.matchAll(/"id": "([^"]+)"/g)].map(m => m[1])
const numbers = text => text.split('\n').map(l => l.match(/^(\d+)\. /)).filter(Boolean).map(m => Number(m[1]))

function extraction(prompt, ctx) {
  const decisions = ctx.decisions
  const criteria = numbers(between(prompt, 'Acceptance criteria, verbatim:', 'Carried implementation findings'))
  const carried = idsIn(between(prompt, 'Carried implementation findings, to place:', 'Read the plan'))
  return {
    decisions,
    repros: ['test_repro'],
    steps: [
      { n: 1, title: 'Core', anchor: 'landing-order', decisions: decisions.slice(0, 1), files: ['src/core/widget.ts'], signal: 'test_core', group: '' },
      { n: 2, title: 'IO', anchor: 'landing-order', decisions: decisions.slice(1), files: ['src/io/reader.ts'], signal: 'test_io', group: '' },
    ],
    pins: decisions.map(d => ({ decision: d, codeSite: 'src/core/widget.ts', test: `test_${d}` })),
    criteria: criteria.map(number => ({ number, steps: [1] })),
    carried: carried.map(id => ({ id, step: 1, obsolete: '' })),
    gaps: [],
  }
}

function buildResult(ctx, over = {}) {
  const steps = ctx.steps ?? { repros: [], steps: [], pins: [] }
  const profile = ctx.profile
  const stepGates = profile.gates.filter(g => g.scope === 'step').map(g => ({ name: g.name, passed: true }))
  return {
    precondition: '',
    branch: SLUG,
    approval_recorded: true,
    plan_checks: (profile.planChecks ?? []).map(c => ({ name: c.name, passed: true, note: '' })),
    repros: steps.repros.map(test => ({ test, failed_on_base: true })),
    carried: (steps.carried ?? []).map(c => ({ id: c.id, addressed: true, evidence: c.step === -1 ? c.obsolete : 'test_carried' })),
    steps: steps.steps.map(s => ({ n: s.n, status: 'built', signal_passed: true, gates: stepGates, changed_files: s.files, commit: `c${s.n}` })),
    mutations: steps.pins.map(p => ({ decision: p.decision, test: p.test, test_failed: true, sha_before: 'aa', sha_after: 'aa' })),
    final_gates: profile.gates.filter(g => g.scope === 'final').map(g => ({ name: g.name, passed: true })),
    changed_files: [...new Set(steps.steps.flatMap(s => s.files))],
    complete: true,
    last_step: steps.steps.length,
    blocking_findings: [],
    discoveries: [],
    ...over,
  }
}

function review(prompt, status = 'met', findings = []) {
  const criteria = numbers(between(prompt, 'Acceptance criteria, verbatim:', 'Base commit:'))
  return { criteria: criteria.map(number => ({ number, status, evidence: 'tests/core/widget_test.ts passed' })), findings }
}

function defaultFor(label, prompt, ctx) {
  if (label === 'plan:draft') {
    return { aborted: '', decisions: ['d1', 'd2'], premises: [], scope_questions: [] }
  }
  if (label.startsWith('plan:revise-')) {
    const n = label.split('-').pop()
    const received = idsIn(between(prompt, 'Findings received', 'Address each failing finding'))
    return { snapshot: `${PLAN}.r${n}`, changed_decisions: [], decisions: ['d1', 'd2'], outcomes: received.map(id => ({ id, outcome: 'fixed', note: 'S d1' })), premises: [], scope_questions: [] }
  }
  if (label.startsWith('critic:')) {
    return critic(label.split(':')[1])
  }
  if (label.startsWith('probe:')) {
    return { precondition: '', branch: `${SLUG}-probe`, premises: idsIn(between(prompt, 'Premises to settle', '1. Run')).map(id => ({ id, outcome: 'held', observed: 'It held.' })) }
  }
  if (/^steps(-\d+)?$/.test(label)) {
    return extraction(prompt, ctx)
  }
  if (/^build(-\d+)?$/.test(label)) {
    return buildResult(ctx)
  }
  if (/^fix/.test(label)) {
    return { precondition: '', fixed: idsIn(prompt), needs_plan_change: [], gates: ctx.profile.gates.map(g => ({ name: g.name, passed: true })), changed_files: ['src/core/widget.ts'] }
  }
  if (/^accept(-\d+)?$/.test(label)) {
    return review(prompt)
  }
  throw new Error(`no default for label ${label}`)
}

const MAX_CALLS = 200

async function run({ args, respond } = {}) {
  const workflow = loadWorkflow(SCRIPT_PATH)
  const theArgs = args ?? baseArgs()
  const calls = []
  const logs = []
  const schemaErrors = []
  const perLabel = new Map()
  // A resumed build continues against the steps its run record holds.
  const kept = theArgs.resume?.steps
  const ctx = {
    steps: kept ? { repros: kept.repros, steps: kept.list, pins: kept.pins, carried: kept.carried } : null,
    decisions: theArgs.resume?.decisions ?? [],
    profile: theArgs.profile ?? FIXTURE,
  }
  const agent = async (prompt, opts) => {
    // A loop the script never leaves would otherwise exhaust the harness's
    // memory; the cap makes it a failing scenario instead.
    if (calls.length >= MAX_CALLS) {
      throw new Error(`runaway: more than ${MAX_CALLS} agent calls`)
    }
    const label = opts.label
    const n = (perLabel.get(label) ?? 0) + 1
    perLabel.set(label, n)
    calls.push({ label, prompt, opts })
    let value = respond ? respond(label, n, prompt, ctx) : undefined
    if (value === undefined) {
      value = defaultFor(label, prompt, ctx)
    }
    if (value === null) {
      return null
    }
    value = JSON.parse(JSON.stringify(value))
    if (opts.schema) {
      const errors = validate(opts.schema, value)
      if (errors.length > 0) {
        schemaErrors.push({ label, errors })
        return null
      }
    }
    if (/^steps(-\d+)?$/.test(label)) {
      ctx.steps = value
    }
    if (label === 'plan:draft' || label.startsWith('plan:revise-')) {
      ctx.decisions = value.decisions
    }
    return value
  }
  const parallel = thunks => Promise.all(thunks.map(t => t().catch(() => null)))
  let result = null
  let error = null
  try {
    result = await workflow(theArgs, agent, parallel, () => {}, m => logs.push(m))
  } catch (e) {
    error = e
  }
  const labels = calls.map(c => c.label)
  const prompt = label => calls.filter(c => c.label === label).map(c => c.prompt).join('\n----\n')
  const opts = label => calls.find(c => c.label === label)?.opts ?? {}
  return { result, error, calls, labels, logs, schemaErrors, prompt, opts }
}

// ---- reporting -------------------------------------------------------------

const results = []
function record(id, name, problems) {
  results.push({ id, name, problems })
}
function checker() {
  const problems = []
  const expect = (cond, message) => {
    if (!cond) {
      problems.push(message)
    }
  }
  return { problems, expect }
}
const ids = list => list.map(f => f.id).sort().join(',')
const titles = list => list.map(f => f.title).sort().join(',')
const round = (labels, r) => labels.filter(l => l.startsWith('critic:') && l.endsWith(`:r${r}`)).map(l => l.split(':')[1]).sort().join(' ')
const respondWith = map => (label, n, prompt, ctx) => {
  const v = map[label]
  return typeof v === 'function' ? v(n, prompt, ctx) : v
}

// ---- T1 scenarios ----------------------------------------------------------

let cleanRunLabels = null

const T1 = [
  ['T1a', 'a clean run spawns the draft, every lens once, the extractor, the builder and the reviewer', async ({ expect }) => {
    const r = await run()
    cleanRunLabels = r.labels
    expect(!r.error, `threw: ${r.error?.message}`)
    expect(r.result?.status === 'accepted' && r.result?.phase === 'done', `status ${r.result?.status}, phase ${r.result?.phase}`)
    expect(r.labels.join(' ') === CLEAN_RUN.join(' '), `labels ${r.labels.join(' ')}`)
    expect(r.schemaErrors.length === 0, `schema errors ${JSON.stringify(r.schemaErrors)}`)
    expect(r.opts('plan:draft').agentType === 'delivery-planner' && r.opts('plan:draft').effort === 'xhigh' && !('model' in r.opts('plan:draft')), 'the planner does not run with its profile role')
    expect(r.opts('steps').model === 'small' && r.opts('steps').effort === 'low', 'the extractor does not run with its profile role')
    expect(!('effort' in r.opts('critic:evidence:r1')) && r.opts('critic:evidence:r1').agentType === 'delivery-critic', 'a critic without a profile role got an effort')
    expect(r.result?.state?.metrics?.agents?.critic === SWEEP.length && r.result?.state?.metrics?.launches === 1, `metrics ${JSON.stringify(r.result?.state?.metrics)}`)
    expect(!['plan:draft', 'steps', 'build', 'accept', 'critic:runtime:r1'].some(l => 'isolation' in r.opts(l)), 'a checkout run isolated an agent')
  }],

  ['T1b', 'only design-level findings at blocking or major fail a round, and the re-round runs the failing lenses and consistency', async ({ expect }) => {
    const notFailing = await run({
      respond: respondWith({
        'critic:evidence:r1': critic('evidence', [finding({ severity: 'blocking', kind: 'implementation' }), finding({ severity: 'minor', kind: 'rank', decision: 'd2' })]),
      }),
    })
    expect(!notFailing.labels.some(l => l.startsWith('plan:revise')), 'a non-failing finding spawned a revision')
    expect(notFailing.result?.status === 'accepted', `status ${notFailing.result?.status}`)

    for (const kind of ['rank', 'surface', 'consistency']) {
      const failing = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1', { kind })]) }) })
      expect(failing.labels.includes('plan:revise-1'), `a major ${kind} finding spawned no revision`)
      expect(round(failing.labels, 2) === 'consistency runtime', `${kind}: round 2 ran ${round(failing.labels, 2)}`)
      expect(failing.result?.status === 'accepted', `${kind}: status ${failing.result?.status}`)
    }
  }],

  ['T1c', 'a re-run lens is told what changed and its earlier findings; consistency gets the snapshot and every outcome', async ({ expect }) => {
    const r = await run({
      respond: respondWith({
        'critic:runtime:r1': critic('runtime', [failingOn('d3', { title: 'Ordering A' }), finding({ title: 'Ordering B' })]),
        'plan:revise-1': (n, p) => ({
          snapshot: `${PLAN}.r1`, changed_decisions: ['d3'], decisions: ['d1', 'd2', 'd3'], premises: [], scope_questions: [],
          outcomes: receivedIn(p).filter(f => f.title === 'Ordering A').map(f => ({ id: f.id, outcome: 'fixed', note: 'S d3' })),
        }),
      }),
    })
    const c = r.prompt('critic:consistency:r2')
    expect(c.includes(`Snapshot: ${PLAN}.r1`) && c.includes(`git diff --no-index ${PLAN}.r1 ${PLAN}`), 'the consistency prompt lacks the snapshot diff')
    expect(/reports it changed: d3\./.test(c), 'the consistency prompt lacks the changed decisions')
    expect(/Ordering A -> fixed: S d3/.test(c) && /Ordering B -> no outcome recorded/.test(c), 'the consistency prompt lacks an outcome, or hides a missing one')
    const again = r.prompt('critic:runtime:r2')
    expect(/Revision 1 changed: d3\./.test(again) && again.includes('Ordering A') && again.includes('Ordering B'), 'the re-run lens is not told what changed and its earlier findings')
    expect(!again.includes('Snapshot:'), 'a non-consistency lens received the consistency context')
    expect(!/Revision \d+ changed/.test(r.prompt('critic:runtime:r1')), 'a first-round lens was told of a revision')
  }],

  ['T1d', 'R1 re-ranks a decision whose ranking keeps failing, or that the last revision changed', async ({ expect }) => {
    const rank = (d, over = {}) => finding({ severity: 'major', kind: 'rank', decision: d, ...over })
    const twice = await run({
      respond: respondWith({
        'critic:evidence:r1': critic('evidence', [rank('d2')]),
        'critic:evidence:r2': critic('evidence', [rank('d2')]),
      }),
    })
    expect(!/Re-rank these decisions/.test(twice.prompt('plan:revise-1')), 'R1 fired on a first failure')
    expect(/Re-rank these decisions, do not patch them: d2\./.test(twice.prompt('plan:revise-2')), 'first clause: no re-rank of d2 after two failing rounds')

    const changed = await run({
      respond: respondWith({
        'critic:evidence:r1': critic('evidence', [rank('d1')]),
        'plan:revise-1': { snapshot: `${PLAN}.r1`, changed_decisions: ['d1', 'd4'], decisions: ['d1', 'd4', 'd5'], outcomes: [], premises: [], scope_questions: [] },
        'critic:evidence:r2': critic('evidence', [rank('d4'), rank('d5'), failingOn('d1')]),
      }),
    })
    const line = (changed.prompt('plan:revise-2').match(/do not patch them: ([^.]*)\./) ?? [])[1] ?? ''
    expect(line.split(', ').includes('d4'), `second clause: d4 not re-ranked ("${line}")`)
    expect(!line.split(', ').includes('d5') && !line.split(', ').includes('d1'), `control: d5 or a surface finding on d1 was re-ranked ("${line}")`)

    const dead = await run({
      respond: respondWith({
        'critic:evidence:r1': critic('evidence', [rank('d1')]),
        'plan:revise-1': { snapshot: `${PLAN}.r1`, changed_decisions: ['d1'], decisions: ['d1', 'd2'], outcomes: [], premises: [], scope_questions: [] },
        'critic:evidence:r2': critic('evidence', [rank('d1', { title: 'Owed finding' })]),
        'plan:revise-2': null,
      }),
    })
    const st = dead.result?.state ?? {}
    expect(dead.result?.status === 'failed' && st.phase === 'revise', `a dead revision: status ${dead.result?.status}, phase ${st.phase}`)
    expect(dead.labels.filter(l => l === 'plan:revise-2').length === 1, 'the dead revision was dispatched again')
    expect(st.pendingRerank?.includes('d1') && (st.received ?? []).some(f => f.title === 'Owed finding'), 'the dead revision dropped its obligations or findings')
    const resumed = await run({ args: baseArgs({ resume: st }) })
    expect(resumed.labels[0] === 'plan:revise-2' && /do not patch them: d1\./.test(resumed.prompt('plan:revise-2')) && resumed.prompt('plan:revise-2').includes('Owed finding'),
      `the resumed revision: ${resumed.labels[0]}`)
  }],

  ['T1e', 'a failing scope finding or a scope question ends the run; the next revision is told they were settled', async ({ expect }) => {
    const r = await run({
      respond: respondWith({
        'critic:evidence:r1': critic('evidence', [finding({ title: 'Scope one', severity: 'major', kind: 'scope' }), finding({ title: 'Scope two', kind: 'scope' }), finding({ title: 'Other one' })]),
      }),
    })
    expect(r.result?.status === 'needs-scope' && r.result?.phase === 'revise', `status ${r.result?.status}, phase ${r.result?.phase}`)
    expect(titles(r.result?.scopeFindings ?? []) === 'Scope one,Scope two', `scopeFindings ${titles(r.result?.scopeFindings ?? [])}`)
    expect(titles(r.result?.state?.received ?? []) === 'Other one,Scope one,Scope two', 'the findings owed to the revision are wrong')
    expect(JSON.stringify(r.result?.state?.pendingLenses) === '["evidence"]', `pendingLenses ${JSON.stringify(r.result?.state?.pendingLenses)}`)
    const resumed = await run({ args: baseArgs({ resume: r.result.state }) })
    expect(resumed.labels[0] === 'plan:revise-1' && resumed.prompt('plan:revise-1').includes('Scope one'), 'the resumed revision did not receive the scope findings')
    expect(round(resumed.labels, 2) === 'consistency evidence', `the round after it ran ${round(resumed.labels, 2)}`)

    const asked = await run({
      respond: respondWith({ 'plan:draft': { aborted: '', decisions: ['d1'], premises: [], scope_questions: [{ question: 'Keep the old format?', options: ['yes', 'no'], recommendation: 'no' }] } }),
    })
    expect(asked.result?.status === 'needs-scope' && asked.labels.join() === 'plan:draft', `a draft scope question: ${asked.result?.status}, ${asked.labels.join(' ')}`)
    const settled = await run({ args: baseArgs({ resume: asked.result.state }) })
    expect(/settled these scope questions[^]*Keep the old format\?/.test(settled.prompt('plan:revise-1')), 'the revision is not told the scope questions were settled')
    expect(round(settled.labels, 1) === [...SWEEP, 'consistency'].sort().join(' '), `round 1 after a settled draft ran ${round(settled.labels, 1)}`)
    expect(settled.result?.status === 'accepted', `status ${settled.result?.status}`)
  }],

  ['T1f', 'a lens that cannot review is dispatched once more, one that returns nothing is not, and the round is failed and runs again whole', async ({ expect }) => {
    const lost = await run({
      respond: respondWith({ 'critic:runtime:r1': null, 'critic:evidence:r1': critic('evidence', [finding({ title: 'Kept finding' })]) }),
    })
    const st = lost.result?.state ?? {}
    expect(lost.labels.filter(l => l === 'critic:runtime:r1').length === 1, 'a lens that returned nothing was dispatched again')
    expect(lost.result?.status === 'failed' && st.phase === 'critique', `status ${lost.result?.status}, phase ${st.phase}`)
    expect((lost.result?.lensesMissing ?? []).join() === 'runtime', `lensesMissing ${lost.result?.lensesMissing}`)
    expect(st.round === 0 && (st.pendingLenses ?? []).length === SWEEP.length, `round ${st.round}, pendingLenses ${st.pendingLenses}`)
    expect(!(st.received ?? []).some(f => f.title === 'Kept finding') && !(st.carried ?? []).some(f => f.title === 'Kept finding'), 'the findings of a round that runs again were kept')
    const again = await run({ args: baseArgs({ resume: st }) })
    expect(round(again.labels, 1) === [...SWEEP].sort().join(' '), `the round ran again as ${round(again.labels, 1)}`)
    expect(again.result?.status === 'accepted', `status ${again.result?.status}`)

    const blind = await run({ respond: respondWith({ 'critic:surface:r1': critic('surface', [finding({ kind: 'coverage', severity: 'blocking' })]) }) })
    expect(blind.result?.status === 'failed' && (blind.result?.lensesMissing ?? []).join() === 'surface' && blind.labels.filter(l => l === 'critic:surface:r1').length === 2, `coverage twice: ${blind.result?.status}`)
  }],

  ['T1g', 'a spent round budget returns the diagnosis; resuming gets a fresh budget, or the owner approves', async ({ expect }) => {
    const rank = () => finding({ id: 'stuck', severity: 'major', kind: 'rank', decision: 'd2' })
    const always = label => /^critic:evidence:r[1-4]$/.test(label) ? critic('evidence', [rank()]) : undefined
    const r = await run({ respond: always })
    expect(r.result?.status === 'budget-spent' && r.result?.phase === 'revise' && r.result?.budget === 'rounds', `status ${r.result?.status}, budget ${r.result?.budget}`)
    expect(r.labels.filter(l => l.startsWith('plan:revise')).length === FIXTURE.budget.rounds, `revisions ${r.labels.filter(l => l.startsWith('plan:revise')).join(' ')}`)
    const d2 = (r.result?.diagnosis ?? []).find(d => d.decision === 'd2')
    expect(d2 && d2.rounds.join() === '1,2,3,4' && d2.reranked === true, `diagnosis ${JSON.stringify(r.result?.diagnosis)}`)
    const st = r.result?.state

    const fresh = await run({ args: baseArgs({ resume: st }) })
    expect(fresh.labels[0] === 'plan:revise-4' && fresh.labels.includes('critic:evidence:r5'), `the resumed run: ${fresh.labels.slice(0, 3).join(' ')}`)
    expect(fresh.result?.status === 'accepted', `with a fresh budget: ${fresh.result?.status}`)

    const unapproved = await run({ args: baseArgs({ resume: st, start: 'steps' }) })
    expect(unapproved.error && unapproved.calls.length === 0, 'a start past failing findings without the owner did not throw')
    const owner = await run({ args: baseArgs({ resume: st, start: 'steps', ownerApproval: 'The owner accepts d2 as ranked.' }) })
    expect(owner.labels[0] === 'steps' && owner.result?.status === 'accepted', `the owner's approval: ${owner.labels[0]}, ${owner.result?.status}`)
    expect(/Basis: the owner's approval: The owner accepts d2 as ranked\./.test(owner.prompt('build')) && /evidence-r4-1, evidence, rank, major: not revised, by the owner's approval/.test(owner.prompt('build')),
      'the Approval record does not carry the owner\'s basis and the finding it skips')
  }],

  ['T1h', 'premises are probed before the round in a checkout, beside it in a worktree, and a failed one is a rank finding', async ({ expect }) => {
    const premise = { id: 'p1', decision: 'd1', claim: 'The scheduler runs jobs in order.', experiment: 'Schedule two jobs and log their order.' }
    const drafted = { 'plan:draft': { aborted: '', decisions: ['d1', 'd2'], premises: [premise], scope_questions: [] } }
    const held = await run({ respond: respondWith(drafted) })
    expect(held.labels.join(' ') === ['plan:draft', 'probe:r1', ...ROUND1, 'steps', 'build', 'accept'].join(' '), `labels ${held.labels.join(' ')}`)
    expect(held.prompt('probe:r1').includes('The scheduler runs jobs in order.') && held.prompt('probe:r1').includes(`git switch -c ${SLUG}-probe abc1234`), 'the probe prompt lacks the premise or the base commit')
    expect(/Premises: p1 held\./.test(held.prompt('build')), 'the Approval record does not record the premise')

    const notHeld = await run({
      respond: respondWith({ ...drafted, 'probe:r1': { precondition: '', branch: `${SLUG}-probe`, premises: [{ id: 'p1', outcome: 'not-held', observed: 'They ran out of order.' }] } }),
    })
    expect(notHeld.prompt('plan:revise-1').includes('premise-p1') && notHeld.prompt('plan:revise-1').includes('They ran out of order.'), 'the failed premise did not reach the revision')
    expect(round(notHeld.labels, 2) === 'consistency', `the round after it ran ${round(notHeld.labels, 2)}`)
    expect(JSON.stringify(notHeld.result?.state?.rankFailRounds) === '{"d1":[1]}', `rankFailRounds ${JSON.stringify(notHeld.result?.state?.rankFailRounds)}`)

    const worktree = await run({ args: withProfile({ isolation: 'worktree' }), respond: respondWith(drafted) })
    expect(worktree.labels.indexOf('probe:r1') > worktree.labels.indexOf('critic:evidence:r1'), 'in a worktree the probe did not run beside the critics')
    expect(['probe:r1', 'build', 'accept'].every(l => worktree.opts(l).isolation === 'worktree') && !('isolation' in worktree.opts('critic:evidence:r1')) && !('isolation' in worktree.opts('plan:draft')),
      'the worktree isolation is not exactly the probe, the builder and the reviewer')
    expect(worktree.prompt('build').includes('You run in a git worktree of your own'), 'the builder is not told where the run files are')

    const dirty = await run({ respond: respondWith({ ...drafted, 'probe:r1': { precondition: 'src/core/a.ts is modified', branch: '', premises: [] } }) })
    expect(dirty.result?.status === 'failed' && dirty.result?.phase === 'critique' && !dirty.labels.some(l => l.startsWith('critic:')), `a dirty probe: ${dirty.result?.status}, ${dirty.labels.join(' ')}`)

    const added = await run({
      respond: respondWith({
        'critic:runtime:r1': critic('runtime', [failingOn('d1')]),
        'plan:revise-1': { snapshot: `${PLAN}.r1`, changed_decisions: ['d1'], decisions: ['d1', 'd2'], outcomes: [], premises: [{ ...premise, id: 'p2' }], scope_questions: [] },
      }),
    })
    expect(added.labels.includes('probe:r2'), 'a premise a revision added was not probed')
  }],

  ['T1i', 'the extraction is checked by the script; gaps go to an in-run revision', async ({ expect }) => {
    const gapped = (n, p, ctx) => ({ ...extraction(p, ctx), gaps: [{ title: 'Step 2 names no signal', location: 'landing-order', why: 'No test.' }] })
    const gap = await run({ respond: respondWith({ steps: gapped, 'steps-2': gapped }) })
    const after = gap.labels.slice(gap.labels.indexOf('steps'))
    expect(after.join(' ') === 'steps steps-2 plan:revise-1 critic:consistency:r2 critic:surface:r2 steps-3 build accept', `after the gap: ${after.join(' ')}`)
    expect(/revision 1 \(steps\)/.test(gap.prompt('plan:revise-1')) && gap.prompt('plan:revise-1').includes('Step 2 names no signal'), 'the revision did not receive the gap')
    expect(gap.result?.status === 'accepted' && gap.result?.state?.metrics?.implementationRevisions === 1, `status ${gap.result?.status}`)

    const sloppy = await run({
      respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), steps: extraction(p, ctx).steps.map(s => ({ ...s, n: s.n * 2 - 1 })) }) }),
    })
    expect(sloppy.labels.includes('steps-2') && !sloppy.labels.includes('plan:revise-1'), 'a malformed extraction was not dispatched once more before a revision')
    expect(/previous result had these problems[^]*not numbered 1 to 2/.test(sloppy.prompt('steps-2')), 'the second extraction is not told the problem')

    const twice = await run({
      respond: (label, n, p, ctx) => /^steps/.test(label) && label !== 'steps-3' ? { ...extraction(p, ctx), pins: [] } : undefined,
    })
    expect(/steps-r0-problem-1/.test(twice.prompt('plan:revise-1')) && /d1 needs exactly one pin/.test(twice.prompt('plan:revise-1')), 'a problem that survives two extractions did not reach a revision')

    const unmapped = await run({ respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), criteria: [] }), 'steps-2': (n, p, ctx) => ({ ...extraction(p, ctx), criteria: [] }) }) })
    expect(unmapped.prompt('plan:revise-1').includes('is not mapped to a step that exists'), 'an unmapped criterion was not caught')
  }],

  ['T1y', 'the next extraction is told the planner\'s outcome for each gap the last one reported', async ({ expect }) => {
    const gap = { title: 'Step 2 names no signal', location: 'landing-order', why: 'No test is named.' }
    const reject = (n, p) => ({
      ...defaultFor('plan:revise-1', p, {}),
      outcomes: idsIn(between(p, 'Findings received', 'Address each failing finding')).map(id => ({ id, outcome: 'rejected', note: 'Landing Order step 2 names test_io.' })),
    })
    const withGap = (n, p, ctx) => ({ ...extraction(p, ctx), gaps: [gap] })
    const gapped = { steps: withGap, 'steps-2': withGap }
    const r = await run({ respond: respondWith({ ...gapped, 'plan:revise-1': reject }) })
    const second = r.prompt('steps-3')
    expect(second.includes('Step 2 names no signal') && /-> rejected: Landing Order step 2 names test_io\./.test(second), 'the extraction after the revision is not told the planner rejected the gap')
    expect(/Report a gap again only when the plan still lacks it/.test(second), 'the extraction after the revision is not told when to report a gap again')
    expect(!/-> rejected/.test(r.prompt('steps') + r.prompt('steps-2')), 'an extraction before the revision was told of its outcome')
    expect(r.result?.status === 'accepted' && (r.result?.state?.stepGaps ?? []).length === 0, `a clean extraction did not clear the gaps: ${r.result?.status}`)
    expect(new Set(r.labels.filter(l => l.startsWith('plan:revise')).map(l => r.prompt(l).match(/"id": "(steps-[^"]+)"/)?.[1])).size === 1, 'a gap id is not unique')

    const scoped = await run({
      respond: respondWith({ ...gapped, 'plan:revise-1': (n, p) => ({ ...reject(n, p), scope_questions: [{ question: 'Keep the old format?', options: ['yes', 'no'], recommendation: 'no' }] }) }),
    })
    const st = scoped.result?.state ?? {}
    expect(scoped.result?.status === 'needs-scope' && (st.stepGaps ?? []).some(g => g.outcome?.outcome === 'rejected'), 'a gap and its outcome do not survive a stop')
    const resumed = await run({ args: baseArgs({ resume: st }) })
    expect(/-> rejected: Landing Order step 2 names test_io\./.test(resumed.prompt('steps')), 'the resumed extraction is not told the planner\'s outcome')
  }],

  ['T1j', 'a blocking build finding revises the plan in the run, and the builder reworks the steps it changed', async ({ expect }) => {
    const firstBuild = (n, p, ctx) => buildResult(ctx, { complete: false, last_step: 1, steps: [{ n: 1, status: 'built', signal_passed: true, gates: [{ name: 'build', passed: true }], changed_files: ['src/core/widget.ts'], commit: 'c1' }], blocking_findings: [BASE_ITEM] })
    const r = await run({
      respond: respondWith({
        build: firstBuild,
        'plan:revise-1': { snapshot: `${PLAN}.r1`, changed_decisions: ['d1'], decisions: ['d1', 'd2'], outcomes: [{ id: 'b1', outcome: 'fixed', note: 'S d1' }], premises: [], scope_questions: [] },
      }),
    })
    const after = r.labels.slice(r.labels.indexOf('build'))
    expect(after.join(' ') === 'build plan:revise-1 critic:consistency:r2 critic:surface:r2 critic:runtime:r2 critic:evidence:r2 steps-2 build-2 accept', `after the blocking finding: ${after.join(' ')}`)
    expect(/committed steps through 1 on harness-run/.test(r.prompt('plan:revise-1')), 'the revision is not told what the builder committed')
    expect(/a decision each carries changed \(d1\)[^\n]*\n- Core \(c1\), carrying d1/.test(r.prompt('build-2')), 'the builder is not told what to rework')
    expect(r.result?.status === 'accepted' && r.result?.state?.build?.rework === null, `status ${r.result?.status}, rework ${JSON.stringify(r.result?.state?.build?.rework)}`)

    const again = await run({ respond: respondWith({ build: firstBuild, 'build-2': (n, p, ctx) => buildResult(ctx, { complete: false, blocking_findings: [{ ...BASE_ITEM, id: 'b2' }] }) }) })
    const st = again.result?.state ?? {}
    expect(again.result?.status === 'budget-spent' && again.result?.budget === 'implementationRevisions' && st.phase === 'revise', `a second blocking finding: ${again.result?.status}`)
    expect((st.received ?? []).some(f => f.lens === 'build') && JSON.stringify(st.pendingLenses) === '["surface"]', `the owed finding or the re-round is lost: ${JSON.stringify(st.pendingLenses)}`)
    const resumed = await run({ args: baseArgs({ resume: st }) })
    expect(resumed.labels[0] === 'plan:revise-2' && round(resumed.labels, 3) === 'consistency surface', `the resumed run: ${resumed.labels.slice(0, 3).join(' ')}`)
  }],

  ['T1k', 'the build report is checked against the steps, the gates, the pins and the repros', async ({ expect }) => {
    const breaking = over => (n, p, ctx) => {
      const base = buildResult(ctx)
      return typeof over === 'function' ? over(base) : { ...base, ...over }
    }
    const cases = [
      ['a step gate its files trigger', b => ({ ...b, steps: b.steps.map(s => s.n === 2 ? { ...s, gates: [{ name: 'build', passed: true }] } : s) }), /step 2 changed files that trigger io-tests/],
      ['a failed step gate', b => ({ ...b, steps: b.steps.map(s => ({ ...s, gates: s.gates.map(g => ({ ...g, passed: false })) })) }), /step 1 failed build/],
      ['a final gate', b => ({ ...b, final_gates: [] }), /final gate full/],
      ['a final gate its files trigger', b => ({ ...b, changed_files: [...b.changed_files, 'docs/guide.md'], final_gates: b.final_gates.filter(g => g.name !== 'docs') }), /final gate docs/],
      ['a mutation', b => ({ ...b, mutations: b.mutations.slice(1) }), /d1 has no mutation/],
      ['a restore', b => ({ ...b, mutations: b.mutations.map(m => ({ ...m, sha_after: 'bb' })) }), /not restored/],
      ['a repro', b => ({ ...b, repros: b.repros.map(x => ({ ...x, failed_on_base: false })) }), /repro test_repro/],
      ['the Approval record', b => ({ ...b, approval_recorded: false }), /Approval record/],
      ['a step', b => ({ ...b, steps: b.steps.slice(0, 1) }), /step 2 is not reported/],
      ['a stop that settles nothing', b => ({ ...b, complete: false, steps: [], mutations: [] }), /stopped before the final gates/],
    ]
    for (const [what, over, pattern] of cases) {
      const once = await run({ respond: respondWith({ build: breaking(over) }) })
      expect(pattern.test(once.prompt('build-2')) && once.result?.status === 'accepted', `${what}: build-2 was not told, or the run ended ${once.result?.status}`)
    }
    const twice = await run({ respond: (label, n, p, ctx) => /^build/.test(label) ? breaking(cases[0][1])(n, p, ctx) : undefined })
    expect(twice.result?.status === 'failed' && twice.result?.phase === 'build' && /io-tests/.test(twice.result?.reason ?? ''), `twice: ${twice.result?.status}, ${twice.result?.reason}`)
  }],

  ['T1l', 'a failed precondition ends the run at the build, and the resumed run continues it', async ({ expect }) => {
    const r = await run({ respond: respondWith({ build: (n, p, ctx) => buildResult(ctx, { precondition: 'src/core/a.ts is modified', complete: false, approval_recorded: false, steps: [], repros: [], mutations: [] }) }) })
    const st = r.result?.state ?? {}
    expect(r.result?.status === 'failed' && st.phase === 'build' && /src\/core\/a\.ts is modified/.test(r.result?.reason ?? ''), `status ${r.result?.status}, phase ${st.phase}`)
    const resumed = await run({ args: baseArgs({ resume: st }) })
    expect(resumed.labels.join(' ') === 'build accept' && resumed.result?.status === 'accepted', `the resumed run: ${resumed.labels.join(' ')}`)
    expect(/Append this Approval record/.test(resumed.prompt('build')), 'an unrecorded approval was reported as recorded')
    const recorded = await run({ args: baseArgs({ resume: { ...st, approval: { ...st.approval, recorded: true } } }) })
    expect(recorded.prompt('build').includes(`The Approval record is already in ${AUDIT}`), 'a recorded approval is appended again')
  }],

  ['T1m', 'an agent that returns nothing, skipped or dead, ends the run at its phase without a second dispatch, and the resumed run continues there', async ({ expect }) => {
    for (const [label, phase] of [['plan:draft', 'draft'], ['steps', 'steps'], ['build', 'build'], ['accept', 'accept']]) {
      const dead = await run({ respond: respondWith({ [label]: null }) })
      const count = dead.labels.filter(l => l === label).length
      expect(dead.result?.status === 'failed' && dead.result?.phase === phase && count === 1 && /skipped or died/.test(dead.result?.reason ?? ''),
        `${label}: ${dead.result?.status} at ${dead.result?.phase}, dispatched ${count} time(s), reason ${dead.result?.reason}`)
    }
    const buildDead = await run({ respond: respondWith({ build: null }) })
    const resumedBuild = await run({ args: baseArgs({ resume: buildDead.result?.state }) })
    expect(resumedBuild.labels.join(' ') === 'build accept' && resumedBuild.result?.status === 'accepted', `a resumed build: ${resumedBuild.labels.join(' ')}`)
    expect(/a commit whose message says its step is unfinished holds partial work/.test(resumedBuild.prompt('build')), 'the builder is not told how to recognise the partial work of a builder that died')
    const revised = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    const rp = revised.prompt('plan:revise-1')
    expect(rp.includes(`copy the plan to ${PLAN}.r1 and report`) && rp.includes(`If ${PLAN}.r1 already exists, a dispatch of this revision that did not finish made it`),
      'a revision is not told its own snapshot, or how to finish one a dead dispatch began')
    const reviewDead = await run({ respond: respondWith({ accept: null }) })
    const resumed = await run({ args: baseArgs({ resume: reviewDead.result?.state }) })
    expect(resumed.labels.join(' ') === 'accept' && resumed.result?.status === 'accepted', `a resumed review: ${resumed.labels.join(' ')}`)
    const refused = await run({ respond: respondWith({ 'plan:draft': { aborted: 'the plan exists', decisions: [], premises: [], scope_questions: [] } }) })
    expect(refused.result?.status === 'failed' && refused.labels.length === 1, `a refused draft: ${refused.result?.status}`)
  }],

  ['T1n', 'the review is blind; gaps go to a bounded fix loop', async ({ expect }) => {
    const r = await run({ respond: respondWith({ build: (n, p, ctx) => buildResult(ctx, { changed_files: ['src/core/widget.ts', 'src/io/reader.ts', `${DIR}/notes.md`] }) }) })
    const p = r.prompt('accept')
    expect(p.includes(REQUEST) && CRITERIA.every(c => p.includes(c)) && p.includes('abc1234') && p.includes(ACCEPTANCE), 'the review lacks the request, a criterion, the base or its document')
    expect(![PLAN, AUDIT, `${DIR}/notes.md`].some(x => p.includes(x)), 'the review names a run file other than its own document')
    expect(r.opts('accept').agentType === 'delivery-reviewer', 'wrong agent type')

    const partialOnce = await run({ respond: respondWith({ accept: (n, prompt) => review(prompt, 'partial') }) })
    expect(partialOnce.labels.slice(-3).join(' ') === 'accept fix accept-2' && partialOnce.result?.status === 'accepted', `one fix: ${partialOnce.labels.slice(-3).join(' ')}, ${partialOnce.result?.status}`)
    expect(partialOnce.prompt('fix').includes('criterion-1') && partialOnce.prompt('accept-2').includes('criterion-1'), 'the fix or the second review lacks the gap')
    expect(partialOnce.result?.state?.metrics?.fixLoops === 1, 'the fix loop is not counted')

    const stubborn = await run({ respond: (label, n, prompt) => /^accept/.test(label) ? review(prompt, 'met', [{ ...BASE_ITEM, id: 'rv-1' }]) : undefined })
    expect(stubborn.result?.status === 'acceptance-gaps' && stubborn.labels.filter(l => /^accept/.test(l)).length === 2, `gaps after the budget: ${stubborn.result?.status}`)

    const planChange = await run({ respond: respondWith({ accept: (n, prompt) => review(prompt, 'unmet'), fix: { precondition: '', fixed: [], needs_plan_change: [{ id: 'criterion-1', why: 'The format is decided by d1.' }], gates: [], changed_files: [] } }) })
    expect(planChange.result?.status === 'acceptance-gaps' && (planChange.result?.needsPlanChange ?? []).length === 1 && !planChange.labels.includes('accept-2'), `a plan change: ${planChange.result?.status}`)

    const ungated = await run({ respond: respondWith({ accept: (n, prompt) => review(prompt, 'partial'), fix: (n, prompt, ctx) => ({ ...defaultFor('fix', prompt, ctx), gates: [] }) }) })
    expect(ungated.labels.includes('fix-again') && /trigger build/.test(ungated.prompt('fix-again')), 'a fix that skipped its gates was accepted')

    const none = await run({ args: withProfile({ budget: { ...FIXTURE.budget, fixLoops: 0 } }), respond: respondWith({ accept: (n, prompt) => review(prompt, 'partial') }) })
    expect(none.result?.status === 'acceptance-gaps' && !none.labels.includes('fix'), `no fix budget: ${none.result?.status}`)
  }],

  ['T1o', 'arguments, the profile and the resume state are validated before the first agent', async ({ expect }) => {
    const throwsEarly = async (args, what) => {
      const r = await run({ args })
      expect(r.error && r.calls.length === 0, `${what}: ${r.error ? 'spawned an agent first' : 'did not throw'}`)
    }
    await throwsEarly({ ...baseArgs(), maxRounds: 3 }, 'an unknown argument')
    await throwsEarly(baseArgs({ profile: undefined }), 'a missing profile')
    await throwsEarly(withProfile({ methodFiles: [] }), 'an unknown profile key')
    const { gates, ...noGates } = FIXTURE
    await throwsEarly(baseArgs({ profile: noGates }), 'a profile without gates')
    await throwsEarly(withProfile({ gates: [{ ...FIXTURE.gates[0], when: 'a file changed' }] }), 'a gate whose when is prose')
    await throwsEarly(withProfile({ gates: [{ ...FIXTURE.gates[0], scope: 'sometimes' }] }), 'a gate with an unknown scope')
    await throwsEarly(withProfile({ gates: [{ ...FIXTURE.gates[1], when: { paths: ['(['] } }] }), 'a gate with an invalid pattern')
    await throwsEarly(withProfile({ lenses: { security: { reads: [] } } }), 'a project lens without a focus')
    await throwsEarly(withProfile({ lenses: { consistency: { enabled: false } } }), 'the consistency lens switched off')
    await throwsEarly(withProfile({ roles: { auditor: { effort: 'low' } } }), 'an unknown role')
    await throwsEarly(withProfile({ roles: { critic: { effort: 'extreme' } } }), 'an unknown effort')
    await throwsEarly(withProfile({ budget: { rounds: 0, implementationRevisions: 1, fixLoops: 1 } }), 'a round budget of zero')
    await throwsEarly(withProfile({ artifactsDir: 'work/runs/' }), 'an artifacts directory with a trailing slash')
    await throwsEarly(baseArgs({ budget: { rounds: '3' } }), 'a quoted budget')
    await throwsEarly(withProfile({ preflight: [{ name: 'tool-closed', command: '', pass: 'exits 0' }] }), 'a preflight check without a command')
    const req = baseArgs().requirements
    await throwsEarly(baseArgs({ requirements: { ...req, modules_touched: ['lib/other.ts'] } }), 'files no profile module matches')
    await throwsEarly(baseArgs({ requirements: { ...req, acceptance_criteria: [] } }), 'no acceptance criterion')
    await throwsEarly(baseArgs({ requirements: { ...req, extra: [] } }), 'an unknown requirement field')
    await throwsEarly(baseArgs({ start: 'build' }), 'a start without a run record')
    await throwsEarly(baseArgs({ priorFindings: [{ ...BASE_ITEM, why: '' }] }), 'an empty priorFindings field')
    const st = (await run({ respond: respondWith({ accept: null }) })).result?.state
    await throwsEarly(baseArgs({ resume: { ...st, workflow: 'feature-implementation' } }), 'a run record of another workflow')
    await throwsEarly(baseArgs({ resume: { ...st, version: 0 } }), 'a run record of another version')
    await throwsEarly(baseArgs({ resume: { ...st, baseRef: 'other' } }), 'a run record of another base commit')
    await throwsEarly(baseArgs({ resume: st, priorFindings: [BASE_ITEM] }), 'priorFindings at a phase past the revision')
    await throwsEarly(baseArgs({ resume: { ...st, approval: null }, start: 'build' }), 'a start past the critique with no approval')
    await throwsEarly(baseArgs({ resume: { ...st, steps: null }, start: 'build' }), 'a start at the build without steps')
    const { round: _, ...partial } = st
    await throwsEarly(baseArgs({ resume: partial }), 'a run record missing a field')
    const initial = { workflow: 'feature-delivery', version: 1, phase: 'draft', baseRef: 'abc1234' }
    const first = await run({ args: baseArgs({ resume: initial }) })
    expect(!first.error && first.labels.join(' ') === CLEAN_RUN.join(' '), `the initial record: ${first.error?.message ?? first.labels.join(' ')}`)
    await throwsEarly(baseArgs({ resume: { ...initial, phase: 'build' }, ownerApproval: 'Owner.' }), 'an initial record past the draft')
  }],

  ['T1p', 'every field of the run state survives a resume', async ({ expect }) => {
    const st = (await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [finding({ id: 'carry-1' })]), accept: null }) })).result?.state
    const again = await run({ args: baseArgs({ resume: st }), respond: respondWith({ accept: null }) })
    const back = again.result?.state ?? {}
    const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x)) ? Object.fromEntries(Object.entries(x).sort()) : x)
    const differ = Object.keys(st).filter(k => k !== 'metrics' && canon(back[k]) !== canon(st[k]))
    expect(differ.length === 0 && Object.keys(back).length === Object.keys(st).length, `fields changed by a resume: ${differ.join(', ')}`)
    expect(back.metrics?.launches === 2 && back.metrics?.statuses?.failed === 2 && back.metrics?.agents?.reviewer === 2, `metrics ${JSON.stringify(back.metrics)}`)
  }],

  ['T1q', 'a run reads the guidance of every module its files match', async ({ expect }) => {
    const both = await run({ args: baseArgs({ requirements: { ...baseArgs().requirements, modules_touched: ['src/core/widget.ts', 'src/io/reader.ts'] } }) })
    expect(/Also read: docs\/core\.md, docs\/io\.md\./.test(both.prompt('critic:runtime:r1')), `reads ${(both.prompt('critic:runtime:r1').match(/Also read: .*/) ?? [])[0]}`)
    expect(/Modules: core, io\. .*Core vocabulary\. IO vocabulary\./.test(both.prompt('plan:draft')), 'the draft lacks a module or its vocabulary')
    expect(both.result?.modules?.join() === 'core,io', `modules ${both.result?.modules}`)
    const { modules, ...bare } = FIXTURE
    const none = await run({ args: baseArgs({ profile: bare }) })
    expect(!none.error && none.prompt('plan:draft').includes('No module guidance applies'), `no modules: ${none.error?.message}`)
  }],

  ['T1r', 'the profile switches a core lens off and adds a project lens', async ({ expect }) => {
    const r = await run({ args: withProfile({ lenses: { ...FIXTURE.lenses, evidence: { enabled: false }, security: { focus: 'Security focus.', reads: ['docs/sec.md'] } } }) })
    expect(round(r.labels, 1) === [...SWEEP.filter(k => k !== 'evidence'), 'security'].sort().join(' '), `round 1 ran ${round(r.labels, 1)}`)
    expect(r.prompt('critic:security:r1').includes('Focus: Security focus.') && r.prompt('critic:security:r1').includes('Also read: docs/sec.md.'), 'the project lens lacks its focus or reads')
    expect(/Correctness addendum\.\n/.test(r.prompt('critic:runtime:r1')), 'the addendum is not appended to its lens focus')
    expect(/Also read: docs\/core\.md\./.test(r.prompt('critic:surface:r1')), 'a lens without reads does not default to the module guidance')
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)
  }],

  ['T1s', 'each lens prompt carries exactly the blocks its flags name', async ({ expect }) => {
    const r = await run()
    const has = (label, text) => r.prompt(label).includes(text)
    expect(has('critic:evidence:r1', '### Acceptance Criteria') && !SWEEP.filter(k => k !== 'evidence').some(k => has(`critic:${k}:r1`, '### Acceptance Criteria')), 'the requirements block is not exactly the acceptance lens\'s')
    const rule = FIXTURE.planRules[0]
    expect(has('critic:surface:r1', rule) && has('plan:draft', rule) && !has('critic:runtime:r1', rule), 'the plan rules are not exactly the surface lens\'s and the planner\'s')
    expect(has('critic:evidence:r1', `check ${PLAN}\``) && !has('critic:surface:r1', `check ${PLAN}`), 'the plan check is not the evidence lens\'s')
    expect(has('plan:draft', `check ${PLAN} --stamp\``) && has('build', `check ${PLAN}\``), 'the draft does not stamp or the builder does not verify')
    expect(has('critic:surface:r1', 'Gates (method section 8.3)') && has('build', '- io-tests (step scope, when a changed file matches `^src/io/`)') && !has('critic:runtime:r1', 'Gates ('), 'the gates are not the surface lens\'s alone among the lenses, or the builder lacks them')
    expect(has('critic:runtime:r1', 'Ranking criteria, in order: user-visible-behaviour') && has('critic:evidence:r1', 'Ranking criteria') && !has('critic:surface:r1', 'Ranking criteria'), 'the ranking line is not exactly the ranking lenses\'')
    const revised = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    expect(revised.prompt('plan:revise-1').includes(`check ${PLAN} --rebase`), 'the revision does not rebase')
  }],

  ['T1t', 'the project profile validates and runs', async ({ expect }) => {
    const [key, mod] = Object.entries(PROFILE.modules ?? {})[0] ?? []
    const sample = mod ? mod.paths[0].replace(/^\^/, '').replace(/\(\?![^)]*\)/g, '').replace(/\\(.)/g, '$1') + 'x' : 'x'
    expect(!mod || new RegExp(mod.paths[0]).test(sample), `could not build a path for module ${key}`)
    const req = { ...baseArgs().requirements, modules_touched: [sample] }
    const r = await run({ args: baseArgs({ profile: PROFILE, requirements: req }) })
    expect(!r.error && r.labels[0] === 'plan:draft' && r.result?.status === 'accepted', `the project profile: ${r.error?.message ?? r.result?.status}`)
    expect(r.schemaErrors.length === 0, `schema errors ${JSON.stringify(r.schemaErrors)}`)
  }],

  ['T1u', 'every agent told to switch branches is told by its file to switch back', async ({ expect }) => {
    const r = await run({ respond: respondWith({ 'plan:draft': { aborted: '', decisions: ['d1'], premises: [{ id: 'p1', decision: 'd1', claim: 'c', experiment: 'e' }], scope_questions: [] }, accept: (n, prompt) => review(prompt, n === 1 ? 'partial' : 'met') }) })
    const told = r.calls.filter(c => /git switch|checked out/.test(c.prompt))
    expect(told.length >= 4, `only ${told.length} switching calls`)
    for (const c of told) {
      const file = fs.readFileSync(path.join(ROOT, '.claude/agents', `${c.opts.agentType}.md`), 'utf8').replace(/\s+/g, ' ')
      expect(/switch back to the branch you started on/i.test(file), `${c.opts.agentType} (${c.label}) switches branches without switching back`)
    }
  }],

  ['T1v', 'the owner\'s findings open a run at the revision', async ({ expect }) => {
    const prior = { id: 'owner-1', location: 'testing-plan', severity: 'blocking', title: 'A gap', why: 'Why.', suggested_direction: 'Direction.' }
    const r = await run({ args: baseArgs({ priorFindings: [prior] }) })
    expect(r.labels[0] === 'plan:revise-1' && r.prompt('plan:revise-1').includes('owner-1') && /revision 1 \(owner\)/.test(r.prompt('plan:revise-1')), `the run opened with ${r.labels[0]}`)
    expect(round(r.labels, 1) === [...SWEEP, 'consistency'].sort().join(' '), `round 1 ran ${round(r.labels, 1)}`)
  }],

  ['T1w', 'the Approval record carries the basis, the lenses, the premises and the clean rounds\' findings', async ({ expect }) => {
    const r = await run({ respond: respondWith({ 'critic:surface:r1': critic('surface', [finding({ id: 'nit-1', severity: 'nit', kind: 'consistency' }), finding({ id: 'impl-1' })]) }) })
    const b = r.prompt('build')
    expect(/## Approval\n\nRound 1\. Basis: converged/.test(b), 'the Approval record lacks its round or basis')
    expect(SWEEP.every(k => b.includes(k)) && b.includes('Premises: none.'), 'the Approval record lacks the lenses or the premises')
    expect(/surface-r1-1, surface, consistency, nit: left open/.test(b) && /surface-r1-2, surface, implementation, minor: carried/.test(b), 'the Approval record lacks a clean round\'s finding')
  }],

  ['T1x', 'critics are told the carried findings and the owner decisions, and not to restate them', async ({ expect }) => {
    const decision = 'D1. The owner fixed the export format.'
    const r = await run({
      args: baseArgs({ requirements: { ...baseArgs().requirements, decisions: [decision] } }),
      respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1', { id: 'gate-1' }), finding({ id: 'carry-1', title: 'No test pins the header row' })]) }),
    })
    const carriedLine = /- runtime-r1-2 \(runtime, round 1, d1\): No test pins the header row/
    for (const label of ['critic:runtime:r2', 'critic:consistency:r2']) {
      expect(carriedLine.test(r.prompt(label)) && /only when the plan now contradicts it/.test(r.prompt(label)), `${label} was not told the carried finding`)
    }
    expect(!/- runtime-r1-1 \(/.test(r.prompt('critic:runtime:r2').split('Already settled')[1] ?? ''), 'a failing finding was listed as carried')
    expect(r.prompt('critic:runtime:r1').includes(`- ${decision}`) && r.prompt('critic:evidence:r1').split(decision).length === 2, 'the owner decisions reach a lens twice or not at all')
    expect(r.prompt('steps').includes('"runtime-r1-2"'), 'the extractor is not given the carried finding to place')
    expect(!/Already settled/.test((await run()).prompt('critic:runtime:r1')), 'a critic was given an empty settled list')
  }],
]

// The findings a revision prompt hands the planner.
function receivedIn(prompt) {
  try {
    return JSON.parse(between(prompt, 'at every severity:\n', '\nAddress each failing finding'))
  } catch {
    return []
  }
}

// T2: the defects an audit found, each shown failing before its fix.
const T2 = [
  ['T2a', 'the builder is given each carried finding\'s text, and reports each one addressed', async ({ expect }) => {
    const carry = finding({ id: 'c1', title: 'Empty list header untested', why: 'No test reads the file back.', suggested_direction: 'Add a read-back test.' })
    const raised = { 'critic:runtime:r1': critic('runtime', [carry]) }
    const r = await run({ respond: respondWith(raised) })
    const b = r.prompt('build')
    expect(['Empty list header untested', 'No test reads the file back.', 'Add a read-back test.'].every(t => b.includes(t)), 'the builder is not given the carried finding\'s text')
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)
    const ignored = await run({ respond: respondWith({ ...raised, build: (n, p, ctx) => ({ ...buildResult(ctx), carried: [] }) }) })
    expect(/carried finding \S+ is not reported addressed/.test(ignored.prompt('build-2')), 'a carried finding the builder did not address was accepted')
  }],

  ['T2b', 'finding ids are unique per source, so outcomes and placements never merge', async ({ expect }) => {
    const r = await run({
      respond: respondWith({
        'critic:runtime:r1': critic('runtime', [failingOn('d1', { id: 'F1', title: 'Correctness defect' })]),
        'critic:evidence:r1': critic('evidence', [finding({ id: 'F1', title: 'Integration gap' })]),
        'plan:revise-1': (n, p) => ({
          ...defaultFor('plan:revise-1', p, {}),
          outcomes: receivedIn(p).map(f => ({ id: f.id, outcome: f.kind === 'implementation' ? 'carried' : 'fixed', note: f.title })),
        }),
      }),
    })
    const got = receivedIn(r.prompt('plan:revise-1')).map(f => f.id)
    expect(got.length === 2 && new Set(got).size === 2, `the revision received ids ${got.join(', ')}`)
    expect(/Correctness defect -> fixed: Correctness defect/.test(r.prompt('critic:consistency:r2')), 'the consistency lens is told another finding\'s outcome')
  }],

  ['T2c', 'a revision no round has checked is chained into the next one', async ({ expect }) => {
    const stopped = await run({
      respond: respondWith({
        'critic:runtime:r1': critic('runtime', [failingOn('d1', { id: 'cor-a', title: 'Ordering defect' })]),
        'plan:revise-1': (n, p) => ({
          snapshot: `${PLAN}.r1`, changed_decisions: ['d1'], decisions: ['d1', 'd2'], premises: [],
          outcomes: receivedIn(p).map(f => ({ id: f.id, outcome: 'fixed', note: 'S d1' })),
          scope_questions: [{ question: 'Keep the old format?', options: ['yes', 'no'], recommendation: 'no' }],
        }),
      }),
    })
    expect(stopped.result?.status === 'needs-scope', `status ${stopped.result?.status}`)
    const resumed = await run({
      args: baseArgs({ resume: stopped.result?.state }),
      respond: respondWith({ 'plan:revise-2': { snapshot: `${PLAN}.r2`, changed_decisions: ['d2'], decisions: ['d1', 'd2'], outcomes: [], premises: [], scope_questions: [] } }),
    })
    const c = resumed.prompt('critic:consistency:r2')
    expect(c.includes(`Snapshot: ${PLAN}.r1`), 'the consistency lens does not diff from the first unchecked snapshot')
    expect(/changed: d1, d2\./.test(c) && /Ordering defect -> fixed: S d1/.test(c), 'the consistency lens is not told the first revision\'s changes and outcomes')
    expect(/Revisions 1 to 2/.test(c), 'the consistency lens is not told it checks two revisions')

    const checked = await run({
      respond: respondWith({
        'critic:runtime:r1': critic('runtime', [failingOn('d1')]),
        'critic:runtime:r2': critic('runtime', [failingOn('d1')]),
      }),
    })
    const third = checked.prompt('critic:consistency:r3')
    expect(third.startsWith('Plan:') && /Revision 2 \(critique\)\. Snapshot: [^\n]*\.r2\./.test(third), 'a revision a round already checked was chained into the next')
  }],

  ['T2d', 'a kept step must be one verified earlier, and rework names steps by title and commit', async ({ expect }) => {
    const allKept = await run({ respond: respondWith({ build: (n, p, ctx) => { const b = buildResult(ctx); return { ...b, steps: b.steps.map(s => ({ ...s, status: 'kept', signal_passed: false, gates: [] })) } } }) })
    expect(allKept.labels.includes('build-2') && /step 1 is reported kept, but commit c1 was not verified/.test(allKept.prompt('build-2')), 'a step never verified was accepted as kept')

    const built = s => ({ n: s.n, status: 'built', signal_passed: true, gates: [{ name: 'build', passed: true }, { name: 'io-tests', passed: true }], changed_files: s.files, commit: `c${s.n}` })
    const firstBuild = (n, p, ctx) => ({ ...buildResult(ctx), complete: false, steps: ctx.steps.steps.map(built), blocking_findings: [BASE_ITEM] })
    const renumbered = (n, p, ctx) => {
      const e = extraction(p, ctx)
      return { ...e, steps: [e.steps[0], { n: 2, title: 'Cache', anchor: 'landing-order', decisions: [], files: ['src/core/cache.ts'], signal: 'test_cache', group: '' }, { ...e.steps[1], n: 3 }] }
    }
    const base = {
      build: firstBuild,
      'plan:revise-1': (n, p) => ({ ...defaultFor('plan:revise-1', p, {}), changed_decisions: ['d2'] }),
      'steps-2': renumbered,
    }
    const r = await run({ respond: respondWith(base) })
    const b2 = r.prompt('build-2')
    expect(/- Core \(c1\), carrying d1/.test(b2) && /- IO \(c2\), carrying d2/.test(b2), 'the builder is not told the verified and the reworked steps by title and commit')
    expect(!/Committed steps that carry them: 2/.test(b2), 'the builder is told to rework a step by a number the revision changed')
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)
    const stale = await run({ respond: respondWith({ ...base, 'build-2': (n, p, ctx) => { const b = buildResult(ctx); return { ...b, steps: b.steps.map(s => s.n === 3 ? { ...s, status: 'kept', commit: 'c2' } : s) } } }) })
    expect(/step 3 is reported kept, but commit c2 was not verified/.test(stale.prompt('build-3')), 'a reworked step was accepted as kept')
    const keptOk = await run({ respond: respondWith({ ...base, 'build-2': (n, p, ctx) => { const b = buildResult(ctx); return { ...b, steps: b.steps.map(s => s.n === 1 ? { ...s, status: 'kept', commit: 'c1', gates: [] } : s) } } }) })
    expect(!keptOk.labels.includes('build-3') && keptOk.result?.status === 'accepted', 'a verified step was not allowed to be kept')
  }],

  ['T2e', 'the extraction\'s decisions are checked against the run\'s', async ({ expect }) => {
    const r = await run({ respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), decisions: ['d1', 'd2', 'd3'] }) }) })
    expect(/the plan's Decisions section anchors d1, d2, d3, but the run recorded d1, d2/.test(r.prompt('steps-2')), 'a decision the run did not record went unnoticed')
  }],

  ['T2f', 'the approval names only the lenses that reported', async ({ expect }) => {
    const clean = await run()
    const basis = (clean.prompt('build').match(/Basis: [^\n]*/) ?? [''])[0]
    expect(!basis.includes('consistency') && SWEEP.every(k => basis.includes(k)), `a clean run's basis: ${basis}`)
    const revised = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    expect(/Basis: [^\n]*consistency/.test(revised.prompt('build')), 'a revised run\'s basis omits the consistency lens')
  }],

  ['T2g', 'a gap and a problem in one extraction get the retry; what survives it goes to the revision together', async ({ expect }) => {
    const gap = { title: 'GAPX', location: 'landing-order', why: 'w' }
    const first = await run({ respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), pins: [], gaps: [gap] }) }) })
    expect(first.labels[first.labels.indexOf('steps') + 1] === 'steps-2', 'an extraction with a problem went to a revision without its retry')
    const both = await run({ respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), pins: [] }), 'steps-2': (n, p, ctx) => ({ ...extraction(p, ctx), pins: [], gaps: [gap] }) }) })
    const p = both.prompt('plan:revise-1')
    expect(p.includes('GAPX') && /d1 needs exactly one pin/.test(p), 'a problem that survived the retry was dropped beside a gap')
  }],

  ['T2h', 'a probe finding from a round that fails for coverage keeps its re-rank history; no prompt calls it kindless', async ({ expect }) => {
    const premise = { id: 'p1', decision: 'd1', claim: 'Jobs run in order.', experiment: 'Log two jobs.' }
    const r = await run({
      respond: respondWith({
        'plan:draft': { aborted: '', decisions: ['d1', 'd2'], premises: [premise], scope_questions: [] },
        'probe:r1': { precondition: '', branch: `${SLUG}-probe`, premises: [{ id: 'p1', outcome: 'not-held', observed: 'Out of order.' }] },
        'critic:runtime:r1': null,
      }),
    })
    expect(r.result?.status === 'failed' && JSON.stringify(r.result?.state?.rankFailRounds) === '{"d1":[1]}', `rankFailRounds ${JSON.stringify(r.result?.state?.rankFailRounds)}`)
    const revised = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    expect(!/without a kind \(from the probe/.test(revised.prompt('plan:revise-1')), 'the revision prompt calls a probe finding kindless')
  }],

  ['T2i', 'a worktree agent is told how to reach the main checkout', async ({ expect }) => {
    const r = await run({ args: withProfile({ isolation: 'worktree' }) })
    for (const label of ['build', 'accept']) {
      expect(r.prompt(label).includes('git rev-parse --path-format=absolute --git-common-dir'), `${label} is pointed at the method instead of told the command`)
    }
  }],

  ['T2j', 'a carried finding the extractor calls obsolete is confirmed by the builder', async ({ expect }) => {
    const raised = { 'critic:runtime:r1': critic('runtime', [finding({ title: 'Moot finding' })]) }
    const obsolete = (n, p, ctx) => {
      const e = extraction(p, ctx)
      return { ...e, carried: e.carried.map(c => ({ ...c, step: -1, obsolete: 'd1 removed the path.' })) }
    }
    const r = await run({ respond: respondWith({ ...raised, steps: obsolete }) })
    expect(/marked obsolete: confirm its reason against the plan and the code/.test(r.prompt('build')), 'the builder is not told to confirm an obsolete reason')
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)
    const waived = await run({ respond: respondWith({ ...raised, steps: obsolete, build: (n, p, ctx) => ({ ...buildResult(ctx), carried: [] }) }) })
    expect(/carried finding \S+ is not reported addressed/.test(waived.prompt('build-2')), 'an obsolete finding was waived without the builder')
  }],

  ['T2k', 'a critic reports findings only, and a serious defect outside its lens is a finding', async ({ expect }) => {
    const r = await run({ respond: respondWith({ 'critic:runtime:r1': { findings: [] } }) })
    expect(r.schemaErrors.length === 0 && r.result?.status === 'accepted', `a findings-only report: ${JSON.stringify(r.schemaErrors)}`)
    const file = read(ROOT, '.claude/agents/delivery-critic.md').replace(/\s+/g, ' ')
    expect(!/summary only/.test(file) && /outside your lens is still a finding/.test(file), 'the critic file still sends a defect outside the lens to an unread summary')
  }],

  ['T2l', 'a re-run lens is given the diff of the revision', async ({ expect }) => {
    const r = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    expect(r.prompt('critic:runtime:r2').includes(`git diff --no-index ${PLAN}.r1 ${PLAN}`), 'the re-run lens is not given the diff')
  }],

  ['T2m', 'each step carries the gates its files trigger, and the build the final gates', async ({ expect }) => {
    const r = await run()
    const b = r.prompt('build')
    let listed = []
    try {
      listed = JSON.parse(between(b, 'every citation it holds.\n', '\nEach step\'s gates'))
    } catch {
      listed = []
    }
    expect(JSON.stringify(listed.map(s => s.gates)) === '[["build"],["build","io-tests"]]', `step gates ${JSON.stringify(listed.map(s => s.gates))}`)
    expect(/Final gates the declared files trigger: full\./.test(b), 'the builder is not told the final gates')
  }],

  ['T2n', 'a lens that could not review is retried with its stated cause, and the cause reaches the result', async ({ expect }) => {
    const cov = finding({ kind: 'coverage', severity: 'blocking', title: 'The plan file is missing' })
    const r = await run({ respond: respondWith({ 'critic:surface:r1': critic('surface', [cov]) }) })
    const second = r.calls.filter(c => c.label === 'critic:surface:r1')[1]?.prompt ?? ''
    expect(/reported it could not review: The plan file is missing/.test(second), 'the retry is not told the stated cause')
    expect(/The plan file is missing/.test(r.result?.reason ?? ''), `the failure does not carry the cause: ${r.result?.reason}`)
    expect(/coverage only when you could not review the plan at all, never for missing tests/.test(r.prompt('critic:runtime:r1')), 'the kinds line does not define coverage')
  }],

  ['T2o', 'the consistency lens is told which lenses did not re-run', async ({ expect }) => {
    const r = await run({ respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }) })
    const c = r.prompt('critic:consistency:r2')
    expect(/did not re-run this round[^]*- surface: The public surface/.test(c), 'the consistency lens is not told the lenses that did not re-run')
    expect(!/did not re-run this round[^]*- runtime:/.test(c), 'a lens that re-ran is listed as not re-run')
  }],

  ['T2p', 'a critic reads only its reading list; the reviewer judges against the conventions', async ({ expect }) => {
    const r = await run({ args: withProfile({ lenses: { ...FIXTURE.lenses, evidence: { reads: [] } } }) })
    expect(!r.prompt('critic:evidence:r1').includes('docs/core.md'), 'a critic is pointed at module rules its reading list leaves out')
    expect(r.prompt('plan:draft').includes('docs/core.md') && r.prompt('build').includes('docs/core.md'), 'the planner or the builder lost the module rules')
    expect(/House conventions to judge the code against: docs\/testing\.md\./.test(r.prompt('accept')), 'the reviewer is told to read the conventions before writing code')
  }],

  ['T2q', 'the extractor is not sent to the method document', async ({ expect }) => {
    const r = await run()
    expect(!/method section/.test(r.prompt('steps')), 'the extraction prompt sends the extractor to the method document')
    expect(!/method section/.test(read(ROOT, '.claude/agents/delivery-extractor.md')), 'the extractor file sends it to the method document')
  }],

  ['T2r', 'every plan check is reported, every gap is fixed or sent to the plan, and no prose report is required', async ({ expect }) => {
    const unchecked = await run({ respond: respondWith({ build: (n, p, ctx) => ({ ...buildResult(ctx), plan_checks: [] }) }) })
    expect(/plan check cites was not reported/.test(unchecked.prompt('build-2')), 'a plan check the builder did not report was accepted')
    const skipped = await run({ respond: respondWith({ accept: (n, prompt) => review(prompt, 'partial'), fix: (n, p, ctx) => ({ ...defaultFor('fix', p, ctx), fixed: [] }) }) })
    expect(/gap criterion-1 is neither fixed nor sent to the plan/.test(skipped.prompt('fix-again')), 'a gap the fixer skipped was accepted')
    const lean = await run({ respond: respondWith({ build: (n, p, ctx) => { const { report, ...b } = buildResult(ctx); return { ...b, repros: b.repros.map(({ commit, ...x }) => x) } } }) })
    expect(lean.schemaErrors.length === 0 && lean.result?.status === 'accepted', `a report without prose: ${JSON.stringify(lean.schemaErrors)}`)
  }],

  ['T2s', 'the reviewer judges against the owner\'s behaviour, constraints and non-goals, and is given nothing the plan settles', async ({ expect }) => {
    const owner = { user_visible_behavior: ['The header row names every column.'], constraints: ['The file format stays readable by version 1.'], non_goals: ['Exporting a nested list.'], open_questions: ['Which separator?'], decisions: ['A stream writer, measured faster.'] }
    const r = await run({ args: baseArgs({ requirements: { ...baseArgs().requirements, ...owner } }) })
    const p = r.prompt('accept')
    expect([...owner.user_visible_behavior, ...owner.constraints, ...owner.non_goals].every(x => p.includes(`- ${x}`)), 'the review lacks the owner\'s behaviour, constraints or non-goals')
    expect(![...owner.open_questions, ...owner.decisions].some(x => p.includes(x)), 'the review is given an open question or an owner decision, which the plan settles')
    expect(/case a non-goal excludes is not missing/.test(read(ROOT, agentFile('delivery-reviewer')).replace(/\s+/g, ' ')), 'the reviewer file does not say a case a non-goal excludes is not missing')
  }],

  ['T2t', 'the planner is given what the critics review the plan against: the gates, the documents they read and the lenses\' project text', async ({ expect }) => {
    const r = await run({
      args: withProfile({ lenses: { ...FIXTURE.lenses, security: { focus: 'Security focus.', reads: ['docs/sec.md'] } } }),
      respond: respondWith({ 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }),
    })
    for (const label of ['plan:draft', 'plan:revise-1']) {
      const p = r.prompt(label)
      expect(p.includes('- io-tests (step scope, when a changed file matches `^src/io/`)'), `${label} lacks the gates`)
      expect(['docs/testing.md', 'docs/perf.md', 'docs/sec.md'].every(d => p.includes(d)), `${label} lacks a house convention or a document a lens reads`)
      expect(p.includes('- runtime: Correctness addendum.') && p.includes('- security: Security focus.'), `${label} lacks a lens addendum or a project lens's focus`)
    }
  }],

  ['T2u', 'a builder that hands over after settling a step or a pin is continued without spending the retry; one that settles nothing spends it', async ({ expect }) => {
    const builds = r => r.labels.filter(l => /^build/.test(l)).join(' ')
    const stepsOnly = (k, p, ctx) => ({ ...buildResult(ctx), complete: false, mutations: [], final_gates: [] })
    const pinsToo = (k, p, ctx) => ({ ...buildResult(ctx), complete: false, final_gates: [] })
    const r = await run({ respond: respondWith({ build: stepsOnly, 'build-2': pinsToo }) })
    expect(builds(r) === 'build build-2 build-3' && r.result?.status === 'accepted', `a step handover, then a pin handover: ${builds(r)}, ${r.result?.status}`)
    expect(!/stopped before the final gates/.test(r.prompt('build-2') + r.prompt('build-3')), 'a handover was sent back as a breach')
    expect(r.result?.state?.metrics?.handovers === 2, `handovers ${r.result?.state?.metrics?.handovers}`)
    const firstStep = (k, p, ctx) => { const b = buildResult(ctx); return { ...b, complete: false, last_step: 1, steps: b.steps.slice(0, 1), mutations: [], final_gates: [] } }
    const stuck = await run({ respond: (label, k, p, ctx) => /^build/.test(label) ? firstStep(k, p, ctx) : undefined })
    expect(builds(stuck) === 'build build-2 build-3' && stuck.result?.status === 'failed' && stuck.result?.phase === 'build', `a handover, then two that settle nothing: ${builds(stuck)}, ${stuck.result?.status}`)
    expect(!/stopped before the final gates/.test(stuck.prompt('build-2')) && /stopped before the final gates/.test(stuck.prompt('build-3')), 'a report that settles nothing did not spend the retry')
    expect(stuck.result?.state?.metrics?.handovers === 1, `handovers ${stuck.result?.state?.metrics?.handovers}`)
    expect(/When your context is compacted/.test(read(ROOT, agentFile('delivery-builder')).replace(/\s+/g, ' ')), 'the builder file, which compaction keeps, does not say when to hand over')
  }],

  ['T2v', 'criteria are named by number: no quote is matched, and a list that misnumbers them is refused rather than sent to a fix', async ({ expect }) => {
    const two = [CRITERIA[0], 'Exporting a list of one writes two rows, verified by tests/core/widget_test.ts']
    const args = baseArgs({ requirements: { ...baseArgs().requirements, acceptance_criteria: two } })
    const r = await run({ args })
    expect(r.result?.status === 'accepted' && !r.labels.includes('fix'), `numbered judgements: ${r.result?.status}, ${JSON.stringify(r.schemaErrors)}`)
    expect(['steps', 'accept'].every(l => r.prompt(l).includes(`1. ${two[0]}\n2. ${two[1]}`)), 'a prompt does not number the criteria')
    expect(two.every((c, i) => r.result?.acceptance?.criteria?.[i]?.criterion === c), 'the result does not quote each criterion from the requirements')
    const judge = numbers => ({ criteria: numbers.map(number => ({ number, status: 'met', evidence: 'e' })), findings: [] })
    const fromZero = await run({ args, respond: (label, n) => label === 'accept' && n === 1 ? judge([0, 1]) : undefined })
    const retry = fromZero.calls.filter(c => c.label === 'accept')[1]?.prompt ?? ''
    expect(fromZero.result?.status === 'accepted' && !fromZero.labels.includes('fix') && /criteria 0 do not exist[^\n]*criterion 2 is judged 0 times/.test(retry), 'a review numbered from 0 was not refused and retried with its problems')
    const twice = await run({ args, respond: label => label === 'accept' ? judge([1, 1]) : undefined })
    expect(twice.result?.status === 'failed' && /criterion 1 is judged 2 times[^]*criterion 2 is judged 0 times/.test(twice.result?.reason ?? ''), `a review that misnumbers twice: ${twice.result?.status}, ${twice.result?.reason}`)
    const dup = await run({ args, respond: (label, n, p, ctx) => label === 'steps' ? { ...extraction(p, ctx), criteria: [{ number: 2, steps: [1] }, { number: 2, steps: [1] }] } : undefined })
    expect(/criterion 1 \([^)]*\) is not mapped to a step that exists[^]*criterion 2 \([^)]*\) is mapped 2 times/.test(dup.prompt('steps-2')) && dup.result?.status === 'accepted', 'a misnumbered extraction was not retried with its problems')
  }],

  ['T2w', 'a critic grades by the method\'s definitions alone, never by what a failing finding costs the run', async ({ expect }) => {
    const file = read(ROOT, agentFile('delivery-critic')).replace(/\s+/g, ' ')
    expect(/`severity`: by method section 6\.3's definitions alone/.test(file), 'the critic file does not grade by method section 6.3 alone')
    expect(!/\bcosts?\b[^.]*\b(revision|round)\b|deliberately/i.test(file), 'the critic file tells a critic what a failing finding costs')
  }],

  ['T2x', 'a gap alone earns the one retry, told the gap; a gap the retry withdraws costs no revision, and every gap quotes the plan', async ({ expect }) => {
    const gap = { title: 'Step 2 names no signal', location: 'landing-order', why: 'Landing Order step 2 reads "IO reader"; it names no test.' }
    const r = await run({ respond: respondWith({ steps: (n, p, ctx) => ({ ...extraction(p, ctx), gaps: [gap] }) }) })
    expect(r.labels[r.labels.indexOf('steps') + 1] === 'steps-2' && !r.labels.includes('plan:revise-1'), `a gap alone went to a revision without its retry: ${r.labels.slice(r.labels.indexOf('steps')).join(' ')}`)
    expect(/previous extraction reported these gaps[^]*report it again when the plan still does not state it[^]*- landing-order: Step 2 names no signal/.test(r.prompt('steps-2')), 'the retry is not told the gap')
    expect(r.result?.status === 'accepted' && r.result?.state?.metrics?.implementationRevisions === 0, `a withdrawn gap: ${r.result?.status}, ${r.result?.state?.metrics?.implementationRevisions}`)
    expect(/why \(what the plan says there, quoted, and what it lacks\)/.test(r.prompt('steps')), 'the extraction does not ask each gap to quote the plan')
  }],

  ['T2y', 'a gate command\'s {base} is the base commit in every prompt that lists the gates', async ({ expect }) => {
    const gates = FIXTURE.gates.map(g => g.name === 'docs' ? { ...g, command: 'make docs BASE={base}' } : g)
    const r = await run({ args: withProfile({ gates }), respond: respondWith({ accept: (n, prompt) => review(prompt, 'partial') }) })
    for (const label of ['plan:draft', 'critic:surface:r1', 'build', 'fix']) {
      expect(r.prompt(label).includes('`make docs BASE=abc1234`'), `${label} is not given the gate command with the base commit`)
    }
    expect(!r.calls.some(c => c.prompt.includes('{base}')), 'a prompt still holds {base}')
  }],

  ['T2z', 'a premise the probe could not run stays open and fails the run; one its experiment leaves undecided goes to the plan', async ({ expect }) => {
    const p1 = { id: 'p1', decision: 'd1', claim: 'Jobs run in order.', experiment: 'Log two jobs.' }
    const p2 = { id: 'p2', decision: 'd2', claim: 'The cache survives a reload.', experiment: 'Reload and read the cache.' }
    const drafted = { 'plan:draft': { aborted: '', decisions: ['d1', 'd2'], premises: [p1, p2], scope_questions: [] } }
    const blocked = await run({ respond: respondWith({ ...drafted, 'probe:r1': { precondition: '', branch: `${SLUG}-probe`, premises: [{ id: 'p1', outcome: 'not-held', observed: 'Out of order.' }, { id: 'p2', outcome: 'not-run', observed: 'The gate reported it could not run.' }] } }) })
    const st = blocked.result?.state
    expect(blocked.schemaErrors.length === 0, `the probe's honest outcomes were refused: ${JSON.stringify(blocked.schemaErrors)}`)
    expect(blocked.result?.status === 'failed' && blocked.result?.phase === 'critique' && /p2 \(The gate reported it could not run\.\)/.test(blocked.result?.reason ?? '') && !blocked.labels.some(l => l.startsWith('critic:')),
      `a premise that could not run: ${blocked.result?.status}, ${blocked.result?.reason}`)
    expect(st?.premises?.map(p => `${p.id} ${p.status}`).join() === 'p1 not-held,p2 open', `premises ${JSON.stringify(st?.premises?.map(p => p.status))}`)
    expect((st?.received ?? []).some(f => f.id === 'premise-p1') && JSON.stringify(st?.rankFailRounds) === '{"d1":[1]}', 'the settled premise\'s finding was lost with the failed probe')
    const resumed = await run({ args: baseArgs({ resume: st }) })
    expect(/"id": "p2"/.test(resumed.prompt('probe:r1')) && !/"id": "p1"/.test(resumed.prompt('probe:r1')) && resumed.prompt('plan:revise-1').includes('premise-p1'),
      'the resumed round did not probe only the open premise, or lost the settled one\'s finding')

    const undecided = await run({ respond: respondWith({ ...drafted, 'probe:r1': { precondition: '', branch: `${SLUG}-probe`, premises: [{ id: 'p1', outcome: 'held', observed: 'In order.' }, { id: 'p2', outcome: 'undecided', observed: 'Within noise.' }] } }) })
    const sent = receivedIn(undecided.prompt('plan:revise-1')).find(f => f.id === 'premise-p2')
    expect(sent?.kind === 'consistency' && sent?.severity === 'major' && sent?.why === 'Within noise.', `the undecided premise reached the revision as ${JSON.stringify(sent)}`)
    expect(JSON.stringify(undecided.result?.state?.rankFailRounds) === '{}' && undecided.result?.state?.premises?.find(p => p.id === 'p2')?.status === 'undecided', 'an undecided premise was recorded as a rank failure, or left open')
  }],

  ['T2za', 'the profile\'s preflight checks validate, the start skill runs them before every launch, and no workflow file may name their program', async ({ expect }) => {
    const preflight = [{ name: 'tool-closed', command: 'tools/check_tool.py --closed', pass: 'exits 0' }]
    const r = await run({ args: withProfile({ preflight }) })
    expect(!r.error && r.result?.status === 'accepted', `a profile with a preflight: ${r.error?.message ?? r.result?.status}`)
    const skill = read(ROOT, START_SKILL).replace(/\s+/g, ' ')
    expect(/each command of the profile's `preflight` passes/.test(skill) && /undoes a `preflight` check/.test(skill), 'the start skill does not run the preflight before launch, or does not tell the user to keep it')
    expect(profileTerms({ ...PROFILE, preflight }).some(t => t.term === 'tools/check_tool.py'), 'the project-fact check does not read the preflight commands')
  }],

  ['T2zb', 'a kept step must be the one an earlier dispatch verified under that commit, not any verified commit', async ({ expect }) => {
    const firstStep = (k, p, ctx) => { const b = buildResult(ctx); return { ...b, complete: false, last_step: 1, steps: b.steps.slice(0, 1), mutations: [], final_gates: [] } }
    const keep = (n, commit, over = {}) => (k, p, ctx) => { const b = buildResult(ctx); return { ...b, steps: b.steps.map(s => s.n === n ? { ...s, status: 'kept', commit, ...over } : s) } }
    const borrowed = await run({ respond: respondWith({ build: firstStep, 'build-2': keep(2, 'c1') }) })
    expect(/step 2 is reported kept, but commit c1 was not verified as this step/.test(borrowed.prompt('build-3')), `a step was kept on another step's verified commit: ${borrowed.labels.filter(l => /^build/.test(l)).join(' ')}`)
    expect(borrowed.result?.status === 'accepted', `status ${borrowed.result?.status}`)
    const own = await run({ respond: respondWith({ build: firstStep, 'build-2': keep(1, 'c1', { gates: [] }) }) })
    expect(!own.labels.includes('build-3') && own.result?.status === 'accepted', 'a step kept on its own verified commit was refused')
  }],

  ['T2zc', 'a builder dispatched again is told the repros, mutations and carried findings already settled; a reworked step\'s carried finding is owed again', async ({ expect }) => {
    const raised = { 'critic:runtime:r1': critic('runtime', [finding({ title: 'Empty list header untested', why: 'No test reads the file back.' })]) }
    const stepsOnly = (k, p, ctx) => ({ ...buildResult(ctx), complete: false, mutations: [], final_gates: [] })
    const pinsToo = (k, p, ctx) => ({ ...buildResult(ctx), complete: false, final_gates: [] })
    const r = await run({ respond: respondWith({ ...raised, build: stepsOnly, 'build-2': pinsToo }) })
    const [b2, b3] = [r.prompt('build-2'), r.prompt('build-3')]
    expect(!/Commit them first/.test(b2) && /which you do not run again: test_repro\./.test(b2), 'a builder after a handover is sent to run step 0 again')
    expect(!b2.includes('No test reads the file back.') && /which you do not address again: runtime-r1-1\./.test(b2), 'a builder after a handover is sent to address a carried finding again')
    expect(/Pins, one mutation each/.test(b2) && !/Pins, one mutation each/.test(b3) && /which you do not mutate again: d1 \(test_d1\), d2 \(test_d2\)\./.test(b3),
      'a builder after a handover is sent to mutate a pin again, or not sent to mutate one still owed')
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)

    const firstBuild = (k, p, ctx) => buildResult(ctx, { complete: false, last_step: 1, steps: [{ n: 1, status: 'built', signal_passed: true, gates: [{ name: 'build', passed: true }], changed_files: ['src/core/widget.ts'], commit: 'c1' }], mutations: [], final_gates: [], blocking_findings: [BASE_ITEM] })
    const reworked = await run({
      respond: respondWith({
        ...raised,
        build: firstBuild,
        'plan:revise-1': (k, p) => ({ ...defaultFor('plan:revise-1', p, {}), changed_decisions: ['d1'] }),
        'build-2': (k, p, ctx) => ({ ...buildResult(ctx), carried: [] }),
      }),
    })
    expect(reworked.prompt('build-2').includes('No test reads the file back.'), 'a carried finding placed in a reworked step is not owed again')
    expect(/carried finding runtime-r1-1 is not reported addressed/.test(reworked.prompt('build-3')), 'a reworked step\'s carried finding was accepted without being addressed again')
  }],

  ['T2zd', 'every path a gate or a module matches lies under the code paths, which the probe and the builder keep clean', async ({ expect }) => {
    const refused = async (args, what) => {
      const r = await run({ args })
      expect(r.error && r.calls.length === 0 && /codePaths/.test(r.error.message), `${what}: ${r.error ? r.error.message : 'did not throw'}`)
    }
    const md = { name: 'md', command: 'make md', pass: '0 warnings', when: { paths: ['\\.md$'] }, scope: 'final' }
    await refused(withProfile({ codePaths: ['src', 'tests'] }), 'a gate watching docs/ outside the code paths')
    await refused(withProfile({ codePaths: ['src/core', 'tests', 'docs'] }), 'a module and a gate under src/io/ outside the code paths')
    await refused(withProfile({ gates: [...FIXTURE.gates, md] }), 'an unanchored gate path, which only the whole tree covers')
    const whole = await run({ args: withProfile({ codePaths: ['.'], gates: [...FIXTURE.gates, md] }) })
    expect(!whole.error && whole.result?.status === 'accepted', `the whole tree as the code path: ${whole.error?.message ?? whole.result?.status}`)
    const slashed = await run({ args: withProfile({ codePaths: ['src/', 'tests', 'docs/'] }) })
    expect(!slashed.error && /git status --porcelain -- src\/ tests docs\//.test(slashed.prompt('build')), `code paths with a trailing slash: ${slashed.error?.message}`)
  }],

  ['T2ze', 'a profile may hold the settings a plan check reads from it, under citations, which the workflow accepts unread', async ({ expect }) => {
    const r = await run({ args: withProfile({ citations: { sdkRoot: '', extensions: ['dart', 'md'] } }) })
    expect(!r.error && r.result?.status === 'accepted', `a profile with citations: ${r.error?.message ?? r.result?.status}`)
    const bad = await run({ args: withProfile({ citations: 'dart md' }) })
    expect(bad.error && bad.calls.length === 0 && /\.citations must be an object/.test(bad.error.message), `a citations value that is not an object: ${bad.error ? bad.error.message : 'did not throw'}`)
  }],

  ['T2zf', 'a revision that changes a decision re-runs the lenses that grade a decision\'s rank, told what changed; one that changes none does not', async ({ expect }) => {
    const failing = { 'critic:runtime:r1': critic('runtime', [failingOn('d1')]) }
    const round2 = r => r.labels.filter(l => l.endsWith(':r2')).sort().join(' ')
    const changed = await run({ respond: respondWith({ ...failing, 'plan:revise-1': (n, p) => ({ ...defaultFor('plan:revise-1', p, {}), changed_decisions: ['d1'] }) }) })
    expect(round2(changed) === 'critic:consistency:r2 critic:evidence:r2 critic:runtime:r2', `after a changed decision, round 2 ran: ${round2(changed)}`)
    expect(/Revision 1 changed: d1\. See every edit/.test(changed.prompt('critic:runtime:r2')), 'the re-run runtime lens is not told the changed decision')
    const unchanged = await run({ respond: respondWith(failing) })
    expect(round2(unchanged) === 'critic:consistency:r2 critic:runtime:r2', `after no changed decision, round 2 ran: ${round2(unchanged)}`)
  }],

  ['T2zg', 'the builder, the fixer and the reviewer are told the hot paths and the runtime lens\'s addendum as the runtime rules', async ({ expect }) => {
    const rules = 'No allocation in a request.'
    const lenses = { ...FIXTURE.lenses, runtime: { ...FIXTURE.lenses.runtime, addendum: rules } }
    const respond = respondWith({ accept: (n, prompt) => review(prompt, n === 1 ? 'partial' : 'met') })
    const r = await run({ args: withProfile({ lenses }), respond })
    for (const label of ['build', 'fix', 'accept', 'accept-2']) {
      expect(r.prompt(label).includes(`Hot paths: per request. The project's runtime rules: ${rules}`), `${label} is not told the hot paths and the runtime rules`)
    }
    expect(/On a hot path, add none of the costs these rules name unless the plan's decision/.test(r.prompt('build')), 'the builder is not told to add none of the costs')
    expect(/On a hot path, a fix adds none of the costs these rules name/.test(r.prompt('fix')), 'the fixer is not told to add none of the costs')
    const none = await run({ args: withProfile({ lenses: { ...FIXTURE.lenses, runtime: {} } }), respond })
    expect(['build', 'fix', 'accept'].every(l => !/runtime rules|On a hot path/.test(none.prompt(l))), 'a profile with no runtime addendum was told rules')
  }],
]

// ---- T3 document checks ----------------------------------------------------

// Line endings differ between the documents, so every read is normalised to LF.
const read = (root, rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n')
const sameSet = (a, b) => [...new Set(a)].sort().join(',') === [...new Set(b)].sort().join(',')
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

const METHOD_DOC = 'doc/agents/delivery-method.md'
const START_SKILL = '.claude/skills/delivery-start/SKILL.md'
const STATUS_SKILL = '.claude/skills/delivery-status/SKILL.md'
const SCRIPT_REL = '.claude/workflows/feature-delivery.js'
const AGENTS_DIR = '.claude/agents'
const agentFile = name => `${AGENTS_DIR}/${name}.md`
// The project-neutral files of the workflow: everything but the profile and
// this harness.
const workflowFiles = d => [SCRIPT_REL, METHOD_DOC, START_SKILL, STATUS_SKILL, ...Object.values(d.roles).map(agentFile)]

// The blocks the documents carry, generated from the script's single sources.
function generated(d) {
  const statusRow = k => `| \`${k}\` | ${d.statusInfo[k].meaning} | ${k === 'failed' ? 'the phase its state names' : d.statusInfo[k].next.map(p => `\`${p}\``).join(' or ')} |`
  return {
    [METHOD_DOC]: {
      statuses: ['| Status | Meaning | The next run starts at |', '|---|---|---|', ...d.statuses.map(statusRow)].join('\n'),
      lenses: ['| Lens | Sweeps |', '|---|---|', ...d.lenses.map(l => `| \`${l.key}\` | ${l.summary} |`)].join('\n'),
      kinds: d.kinds.map(k => `- \`${k}\`: ${d.kindInfo[k]}`).join('\n'),
      'premise-outcomes': Object.entries(d.premiseOutcomes).map(([k, v]) => `- \`${k}\`: ${v}`).join('\n'),
      profile: Object.entries(d.profileKeys).map(([k, v]) => `- \`${k}\` (${v.required ? 'required' : 'optional'}): ${v.about}`).join('\n'),
      cost: `A clean run is ${d.cleanRun.length} agents: the draft, the ${d.lenses.filter(l => !l.afterRevisionOnly).length} lenses of round 1, the extractor, the builder and the reviewer.`,
      'initial-record': ['```json', JSON.stringify({ workflow: d.workflow, version: d.stateVersion, phase: 'draft', baseRef: '<the base commit>' }), '```'].join('\n'),
    },
    [START_SKILL]: {
      outcomes: ['| `status` | Meaning | Next step |', '|---|---|---|', ...d.statuses.map(k => `| \`${k}\` | ${d.statusInfo[k].meaning} | ${d.statusInfo[k].action} |`)].join('\n'),
    },
  }
}

// A block runs from its marker to the first end marker after it; its body is
// the lines between them.
const BLOCK = /<!-- generated: ([a-z-]+) -->\n([\s\S]*?)<!-- end generated -->/g
function blocks(text) {
  return [...text.matchAll(BLOCK)].map(m => ({ name: m[1], body: m[2].replace(/\n$/, '') }))
}

function writeBlocks(d) {
  for (const [rel, expected] of Object.entries(generated(d))) {
    const text = read(ROOT, rel)
    let out = text
    for (const [name, body] of Object.entries(expected)) {
      const re = new RegExp(`<!-- generated: ${escapeRe(name)} -->\\n[\\s\\S]*?<!-- end generated -->`)
      if (!re.test(out)) {
        throw new Error(`${rel} has no generated block ${name}`)
      }
      out = out.replace(re, () => `<!-- generated: ${name} -->\n${body}\n<!-- end generated -->`)
    }
    if (out !== text) {
      fs.writeFileSync(path.join(ROOT, rel), out)
      console.log(`wrote ${rel}`)
    }
  }
}

function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/)
  const fields = {}
  for (const line of (m ? m[1] : '').split('\n')) {
    const kv = line.match(/^([a-z-]+):\s*(.*)$/)
    if (kv) {
      fields[kv[1]] = kv[2].trim()
    }
  }
  return fields
}

function jsonBlocks(text) {
  return [...text.matchAll(/```json\n([\s\S]*?)```/g)].map(m => {
    try {
      return JSON.parse(m[1])
    } catch {
      return { __unparsed: m[1].slice(0, 60) }
    }
  })
}

// The heading numbers of the method document, and every numbered section a
// workflow file points at: "method section N" anywhere, and "section N" inside
// the method document itself.
function headingNumbers(text) {
  return new Set([...text.matchAll(/^#{2,3} (\d+(?:\.\d+)?)\.? /gm)].map(m => m[1]))
}
function sectionReferences(text, self) {
  const refs = []
  const flat = text.replace(/\s+/g, ' ')
  const pattern = self
    ? /\b[Ss]ections? (\d+(?:\.\d+)?)((?:(?:, | and | to )\d+(?:\.\d+)?)*)/g
    : /\bmethod sections? (\d+(?:\.\d+)?)((?:(?:, | and | to )\d+(?:\.\d+)?)*)/g
  for (const m of flat.matchAll(pattern)) {
    for (const n of [m[1], ...[...m[2].matchAll(/\d+(?:\.\d+)?/g)].map(x => x[0])]) {
      refs.push({ n, at: flat.slice(Math.max(0, m.index - 50), m.index + 30) })
    }
  }
  return refs
}

// Every term the profile holds that a project-neutral file must not name. A
// command that runs one of this workflow's own files names no project fact, and
// neither does a code path that holds them.
const HARNESS_REL = '.claude/workflows/feature-delivery.harness.mjs'
const OWN_PATHS = [SCRIPT_REL, HARNESS_REL, METHOD_DOC, START_SKILL, STATUS_SKILL, PROFILE_REL, AGENTS_DIR]
const holdsOwn = p => OWN_PATHS.some(f => f === p || f.startsWith(`${p}/`))
function profileTerms(profile) {
  const programs = [...profile.gates.map(g => g.command), ...(profile.preflight ?? []).map(c => c.command), ...(profile.planChecks ?? []).flatMap(c => [c.verify, c.stamp, c.rebase].filter(Boolean))]
    .flatMap(c => c.split(/\s+/).filter(w => /[/.]/.test(w) && !w.startsWith('-') && !w.includes('{')).slice(0, 1))
    .filter(p => p !== HARNESS_REL)
  const prose = [
    ...Object.values(profile.modules ?? {}).map(m => m.vocabulary),
    ...Object.values(profile.lenses ?? {}).map(l => l.addendum ?? ''),
    ...(profile.planRules ?? []),
    ...(profile.planChecks ?? []).map(c => c.note ?? ''),
  ].join(' ')
  const identifiers = [...new Set(prose.match(/@?\b[A-Za-z_]*[a-z][A-Z][A-Za-z0-9_]*\b/g) ?? [])]
  return [
    ...Object.keys(profile.modules ?? {}).map(k => ({ term: k, word: true })),
    ...Object.values(profile.modules ?? {}).flatMap(m => m.guidance.map(g => ({ term: g }))),
    ...profile.codePaths.filter(p => !holdsOwn(p)).map(p => ({ term: `${p}/` })),
    { term: `${profile.artifactsDir}/` },
    ...(profile.conventionDocs ?? []).map(d => ({ term: d })),
    ...programs.map(p => ({ term: p })),
    ...(profile.hotPaths ?? []).flatMap(h => [{ term: h }, { term: h.replace(/ /g, '-') }]),
    ...profile.ranking.map(r => ({ term: r })),
    ...identifiers.map(i => ({ term: i, word: true })),
  ]
}

// A count written in the same sentence as the `wc -l` or `grep -c` that
// produced it, before or after the command.
function countsBesideCommands(root, files) {
  const command = '`[^`]*\\b(?:wc -l|grep -c)\\b[^`]*`'
  const patterns = [
    new RegExp(`\\b\\d[\\d,]*\\b[^.;]{0,160}?${command}`, 'g'),
    new RegExp(`${command}[^.;]{0,160}?\\b\\d[\\d,]*\\b`, 'g'),
  ]
  const problems = []
  for (const rel of files) {
    const text = read(root, rel).replace(/\s+/g, ' ')
    for (const re of patterns) {
      for (const m of text.matchAll(re)) {
        problems.push(`${rel}: "${m[0].slice(0, 80)}"`)
      }
    }
  }
  return problems
}

// The repository guidance every agent loads or is routed to, beside this
// workflow's own files: AGENTS.md, CLAUDE.md and the rules.
const RULES_DIR = '.claude/rules'
const GUIDANCE = ['AGENTS.md', 'CLAUDE.md', RULES_DIR]
const guidanceFiles = root => ['AGENTS.md', 'CLAUDE.md', ...fs.readdirSync(path.join(root, RULES_DIR)).filter(f => f.endsWith('.md')).map(f => `${RULES_DIR}/${f}`)]

// A rule's `paths:` list, or null for a rule that loads at launch.
function rulePaths(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/)
  if (!m || !/^paths:/m.test(m[1])) {
    return null
  }
  return [...m[1].matchAll(/^\s+- "([^"]+)"$/gm)].map(x => x[1])
}

// The method sections a guidance file points at: "method section N", or the
// method document's path followed by "section N".
function methodReferences(text) {
  const flat = text.replace(/\s+/g, ' ')
  const refs = sectionReferences(text, false)
  for (const m of flat.matchAll(/delivery-method\.md`? sections? (\d+(?:\.\d+)?)((?:(?:, | and | to )\d+(?:\.\d+)?)*)/g)) {
    for (const n of [m[1], ...[...m[2].matchAll(/\d+(?:\.\d+)?/g)].map(x => x[0])]) {
      refs.push({ n, at: flat.slice(Math.max(0, m.index - 50), m.index + 30) })
    }
  }
  return refs
}

const T3 = [
  ['T3a', 'every generated block matches what the script describes', d => [METHOD_DOC, START_SKILL],
    (root, d) => {
      const problems = []
      for (const [rel, expected] of Object.entries(generated(d))) {
        const found = blocks(read(root, rel))
        for (const [name, body] of Object.entries(expected)) {
          const hits = found.filter(b => b.name === name)
          if (hits.length !== 1) {
            problems.push(`${rel} holds ${hits.length} generated ${name} blocks, expected 1`)
          } else if (hits[0].body !== body) {
            problems.push(`${rel}: the generated ${name} block is stale; run the harness with --write`)
          }
        }
        for (const b of found.filter(b => !(b.name in expected))) {
          problems.push(`${rel} holds an unknown generated block ${b.name}`)
        }
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, METHOD_DOC), read(root, METHOD_DOC).replace('| `needs-scope` |', '| `needs-scoping` |'))],

  ['T3b', 'each role has its agent file, which sets no model, effort or memory', d => Object.values(d.roles).map(agentFile),
    (root, d) => {
      const problems = []
      for (const [role, name] of Object.entries(d.roles)) {
        const rel = agentFile(name)
        if (!fs.existsSync(path.join(root, rel))) {
          problems.push(`role ${role} has no agent file ${rel}`)
          continue
        }
        const fm = frontmatter(read(root, rel))
        if (fm.name !== name || !fm.description || !fm.tools) {
          problems.push(`${rel} needs name ${name}, a description and tools`)
        }
        for (const key of ['model', 'effort', 'memory']) {
          if (key in fm) {
            problems.push(`${rel} sets ${key}; the profile's roles set model and effort per call, and no workflow agent keeps memory`)
          }
        }
      }
      return problems
    },
    (root, d) => {
      const rel = agentFile(d.roles.extractor)
      fs.writeFileSync(path.join(root, rel), read(root, rel).replace('\ntools:', '\nmodel: sonnet\ntools:'))
    }],

  ['T3c', 'the start skill\'s args template names exactly what the script reads', d => [START_SKILL],
    (root, d) => {
      const all = jsonBlocks(read(root, START_SKILL))
      const args = all.find(b => b && typeof b === 'object' && 'requirements' in b)
      if (!args) {
        return ['the start skill has no args template']
      }
      const problems = []
      const unknown = Object.keys(args).filter(k => !d.argNames.includes(k))
      if (unknown.length > 0) {
        problems.push(`the args template names ${unknown.join(', ')}, which the script does not read`)
      }
      const absent = d.requiredArgs.filter(k => !(k in args))
      if (absent.length > 0) {
        problems.push(`the args template omits ${absent.join(', ')}, which the script requires`)
      }
      if (!sameSet(Object.keys(args.requirements ?? {}), d.requirementFields)) {
        problems.push(`requirements template ${Object.keys(args.requirements ?? {}).join(',')} vs script ${d.requirementFields.join(',')}`)
      }
      const prior = all.find(b => b && typeof b === 'object' && 'priorFindings' in b)
      if (!sameSet(Object.keys(prior?.priorFindings?.[0] ?? {}), d.baseFindingFields)) {
        problems.push(`priorFindings template ${Object.keys(prior?.priorFindings?.[0] ?? {}).join(',')} vs script ${d.baseFindingFields.join(',')}`)
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, START_SKILL), read(root, START_SKILL).replace('"open_questions"', '"open_issues"'))],

  ['T3d', 'every method section a workflow file points at exists', d => workflowFiles(d),
    (root, d) => {
      const numbers = headingNumbers(read(root, METHOD_DOC))
      const problems = []
      for (const rel of workflowFiles(d)) {
        for (const { n, at } of sectionReferences(read(root, rel), rel === METHOD_DOC)) {
          if (!numbers.has(n)) {
            problems.push(`${rel} points at method section ${n}: "${at}"`)
          }
        }
      }
      return problems
    },
    root => fs.appendFileSync(path.join(root, STATUS_SKILL), '\nSee method section 19.\n')],

  ['T3e', 'the workflow files name no project fact the profile holds', d => [...workflowFiles(d), PROFILE_REL],
    (root, d) => {
      const terms = profileTerms(JSON.parse(read(root, PROFILE_REL)))
      const problems = []
      for (const rel of workflowFiles(d)) {
        const text = read(root, rel)
        for (const { term, word } of terms) {
          const named = word ? new RegExp(`(^|[^A-Za-z0-9_])${escapeRe(term)}([^A-Za-z0-9_]|$)`, 'i').test(text) : text.toLowerCase().includes(term.toLowerCase())
          if (named) {
            problems.push(`${rel} names ${term}`)
          }
        }
      }
      return problems
    },
    root => {
      const profile = JSON.parse(read(root, PROFILE_REL))
      fs.appendFileSync(path.join(root, STATUS_SKILL), `\nSee ${profile.codePaths[0]}/ for an example.\n`)
    }],

  ['T3f', 'the workflow files state no count beside the command that produces it', d => workflowFiles(d),
    (root, d) => countsBesideCommands(root, workflowFiles(d)),
    root => fs.appendFileSync(path.join(root, METHOD_DOC), '\n- The suite holds 12 files (`ls test | wc -l`).\n')],

  ['T3g', 'the method document names every plan section the agents read by name', d => [METHOD_DOC, ...Object.values(d.roles).map(agentFile)],
    (root, d) => {
      const method = read(root, METHOD_DOC)
      const sections = [...method.slice(method.indexOf('### 2.1')).split('\n### ')[0].matchAll(/^\| \d+ \| `([^`]+)` \|/gm)].map(m => m[1])
      if (sections.length === 0) {
        return ['the method document has no plan section table in section 2.1']
      }
      const problems = []
      for (const name of Object.values(d.roles)) {
        for (const m of read(root, agentFile(name)).replace(/\s+/g, ' ').matchAll(/the plan's ([A-Z][A-Za-z &]+?)(?= section|,| and|\.)/g)) {
          if (!sections.includes(m[1].trim())) {
            problems.push(`${agentFile(name)} names the plan's ${m[1].trim()}, which section 2.1 does not define`)
          }
        }
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, METHOD_DOC), read(root, METHOD_DOC).replace('| `Landing Order` |', '| `Landing Steps` |'))],

  ['T3h', 'path-scoped rules import nothing, and each profile module lists exactly the rules under its paths', d => [RULES_DIR, PROFILE_REL],
    root => {
      const modules = JSON.parse(read(root, PROFILE_REL)).modules ?? {}
      const owned = new Map(Object.keys(modules).map(k => [k, []]))
      const problems = []
      for (const f of fs.readdirSync(path.join(root, RULES_DIR)).filter(f => f.endsWith('.md'))) {
        const rel = `${RULES_DIR}/${f}`
        const text = read(root, rel)
        const paths = rulePaths(text)
        if (paths === null) {
          continue
        }
        if (/(^|\s)@[A-Za-z0-9_.\/~-]+/m.test(text.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, ''))) {
          problems.push(`${rel} has paths: and an @ import, which loads at launch anyway`)
        }
        for (const [key, m] of Object.entries(modules)) {
          if (paths.some(p => m.paths.some(pattern => new RegExp(pattern).test(p)))) {
            owned.get(key).push(rel)
          }
        }
        if (paths.every(p => !p.includes('*'))) {
          const names = new Set(paths.map(p => p.split('/').pop()))
          for (const named of new Set([...text.matchAll(/`([A-Za-z0-9_]+\.dart)`/g)].map(x => x[1]))) {
            if (!names.has(named) && !/_test\.dart$/.test(named)) {
              problems.push(`${rel} names ${named}, which its paths do not load it for`)
            }
          }
        }
      }
      for (const [key, m] of Object.entries(modules)) {
        if (!sameSet(owned.get(key), m.guidance)) {
          problems.push(`modules.${key}.guidance ${m.guidance.join(',')} vs the rules under its paths ${owned.get(key).join(',')}`)
        }
      }
      return problems
    },
    root => {
      const rule = Object.values(JSON.parse(read(root, PROFILE_REL)).modules)[0].guidance[0]
      fs.appendFileSync(path.join(root, rule), '\nSee @../../AGENTS.md for the rules.\n')
    }],

  ['T3i', 'the repository guidance states no count beside the command that produces it', d => GUIDANCE,
    root => countsBesideCommands(root, guidanceFiles(root)),
    root => fs.appendFileSync(path.join(root, RULES_DIR, 'testing.md'), '\n- The suite holds 12 files (`ls test | wc -l`).\n')],

  ['T3j', 'every method section the repository guidance points at exists', d => [METHOD_DOC, ...GUIDANCE],
    root => {
      const numbers = headingNumbers(read(root, METHOD_DOC))
      const problems = []
      for (const rel of guidanceFiles(root)) {
        for (const { n, at } of methodReferences(read(root, rel))) {
          if (!numbers.has(n)) {
            problems.push(`${rel} points at method section ${n}: "${at}"`)
          }
        }
      }
      return problems
    },
    root => fs.appendFileSync(path.join(root, 'AGENTS.md'), '\nSee `doc/agents/delivery-method.md` section 19.\n')],
]

function copyInto(tmp, rel) {
  const src = path.join(ROOT, rel)
  const dst = path.join(tmp, rel)
  fs.mkdirSync(path.dirname(dst), { recursive: true })
  fs.cpSync(src, dst, { recursive: true })
}

// ---- main ------------------------------------------------------------------

async function main() {
  const describe = await loadWorkflow(SCRIPT_PATH)({ describe: true }, null, null, () => {}, () => {})
  if (WRITE) {
    writeBlocks(describe)
    return
  }
  const selected = ([id]) => !ONLY || id.startsWith(ONLY)
  for (const [id, name, body] of [...T1, ...T2].filter(selected)) {
    const c = checker()
    try {
      await body(c)
    } catch (e) {
      c.problems.push(`threw: ${e.stack ?? e}`)
    }
    record(id, name, c.problems)
  }
  if (cleanRunLabels && cleanRunLabels.length !== describe.cleanRun.length) {
    record('T1a', 'the clean run spawns as many agents as the script describes', [`spawned ${cleanRunLabels.length}, described ${describe.cleanRun.length}`])
  }

  for (const [id, name, files, check, mutate] of T3.filter(selected)) {
    const safely = root => {
      try {
        return check(root, describe)
      } catch (e) {
        return [`threw: ${e.message}`]
      }
    }
    const problems = safely(ROOT).map(p => `on the repository: ${p}`)
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fd-harness-'))
    try {
      for (const rel of new Set([...files(describe), ...workflowFiles(describe), PROFILE_REL])) {
        if (fs.existsSync(path.join(ROOT, rel))) {
          copyInto(tmp, rel)
        }
      }
      mutate(tmp, describe)
      if (safely(tmp).length === 0) {
        problems.push('did not fail on a copy with one deliberate mismatch')
      }
    } catch (e) {
      problems.push(`the falsification copy could not be built: ${e.message}`)
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true })
    }
    record(id, name, problems)
  }

  let failed = 0
  for (const { id, name, problems } of results) {
    console.log(`${problems.length === 0 ? 'pass' : 'FAIL'}  ${id}  ${name}`)
    for (const p of problems) {
      console.log(`        ${p}`)
    }
    failed += problems.length === 0 ? 0 : 1
  }
  console.log(`${results.length - failed} passed, ${failed} failed`)
  process.exitCode = failed === 0 ? 0 : 1
}

await main()
