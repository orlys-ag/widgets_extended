#!/usr/bin/env node
// Harness for the feature-implementation workflow.
//
// T1 runs the workflow script with a stub `agent` that returns scripted
// results and validates each against the schema the script passed, then
// asserts on the returned status, the labels spawned and the prompt texts.
// The real Workflow runtime spawns frontier agents and cannot be told what a
// critic finds, so no scenario could fail on demand there.
//
// T3 checks the documents that restate the script's and the profile's single
// sources: each check passes on the repository and is shown, on every run, to
// fail on a temporary copy carrying one deliberate mismatch.
//
// Usage: node .claude/workflows/feature-implementation.harness.mjs
//        [--script <path>] [--only <prefix>]

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
const SCRIPT_PATH = argValue('--script') ? path.resolve(argValue('--script')) : path.join(HERE, 'feature-implementation.js')
const ONLY = argValue('--only')

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

const PROFILE = JSON.parse(fs.readFileSync(path.join(ROOT, 'doc/agents/method-profile.json'), 'utf8'))
// The T1 scenarios test the script's logic, so they run on a fixture profile of
// their own, a project no scenario depends on. The T3 checks read the
// project's real profile, and T1s shows the script accepts it.
const FIXTURE = {
  codePaths: ['src', 'tests'],
  conventionDocs: ['docs/testing.md'],
  methodFiles: ['METHOD.md'],
  gates: [
    { name: 'build', command: 'make build', pass: '0 errors', when: 'always' },
    { name: 'test', command: 'make test', pass: '0 failed', when: 'always' },
    { name: 'docs', command: 'make docs', pass: '0 warnings', when: 'docs/ exists' },
  ],
  modules: { core: { paths: ['^src/core/'], guidance: ['docs/core.md', 'docs/core-io.md'], vocabulary: 'Core vocabulary.', lensAddenda: { correctness: 'Core correctness hazard.' } } },
  lenses: {
    correctness: { reads: ['moduleGuidance'], addendum: 'Correctness addendum.' },
    performance: { reads: ['moduleGuidance', 'docs/testing.md'], addendum: '' },
    design: { reads: ['moduleGuidance', 'conventionDocs'], addendum: '' },
    interaction: { reads: ['moduleGuidance'], addendum: '' },
    timing: { reads: ['moduleGuidance'], addendum: '' },
    consistency: { reads: [], addendum: '' },
  },
  defectClasses: ['stale-summary', 'unenumerated-consumer', 'unverified-claim', 'plan-history'],
  ranking: ['user-visible-behaviour', 'architecture-fit'],
  hotPaths: ['per request'],
  citations: { sdkRoot: 'sdk', extensions: ['ts', 'md'] },
  planRules: ['Every fixture value names its unit.'],
}
const SLUG = 'harness-run'
const DATE = '2026-10-02'
const PLAN = `plans/${DATE}-${SLUG}-plan.md`
const CHECKLIST = `plans/${DATE}-${SLUG}-checklist.md`
const AUDIT = `plans/${DATE}-${SLUG}-audit.md`
const ACCEPTANCE = `plans/${DATE}-${SLUG}-acceptance.md`
const CRITERIA = ['Exporting an empty list writes only the header row, verified by tests/core/widget_test.ts']
const REQUEST = 'Make an export of an empty list write its header row.'

function baseArgs(over = {}) {
  return {
    slug: SLUG,
    date: DATE,
    module: 'core',
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

const BASE_ITEM = { id: 'b1', location: 'd1', severity: 'blocking', title: 't', why: 'w', suggested_direction: 's' }

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
// A critic's report. The lens names the reporting lens at the call site only:
// the script keys each report by the lens it dispatched.
function critic(lens, findings = []) {
  return { findings }
}

function defaultFor(label, nthRevision) {
  if (label === 'plan:draft') {
    return 'Drafted.'
  }
  if (label.startsWith('plan:revise')) {
    return { changed_decisions: [], snapshot: `${PLAN}.r${nthRevision}` }
  }
  if (label.startsWith('critic:') || label.startsWith('fresh:')) {
    return critic()
  }
  if (label === 'trial') {
    return {
      section: 'S', branch: `${SLUG}-trial`, repro_failed_before: true, repro_passes_after: true,
      gates: FIXTURE.gates.map(g => ({ name: g.name, applies: true, passed: true })), mutations: [],
      commit: 'def5678', notes: '', blocking_findings: [],
    }
  }
  if (label === 'plan:approve') {
    return { stamped: true }
  }
  if (label === 'checklist') {
    return {
      checklist_path: CHECKLIST,
      phase_counts: { phase1: 1, phase2: 1, phase3: 0, phase4: 3 },
      blocking_discoveries: [],
      nonblocking_discoveries: [],
    }
  }
  if (label === 'implement') {
    return {
      changed_files: ['src/core/widget.ts', 'tests/core/widget_test.ts', CHECKLIST], report: 'Done.',
      branch: `${SLUG}-trial`, commit: 'fed9876', complete: true, blocking_discoveries: [],
    }
  }
  if (label === 'accept') {
    return { criteria: CRITERIA.map(c => ({ criterion: c, status: 'met', evidence: 'tests/core/widget_test.ts passed' })), findings: [] }
  }
  throw new Error(`no default for label ${label}`)
}

async function run({ args, respond } = {}) {
  const workflow = loadWorkflow(SCRIPT_PATH)
  const calls = []
  const logs = []
  const schemaErrors = []
  const perLabel = new Map()
  let revisions = 0
  const agent = async (prompt, opts) => {
    const label = opts.label
    const n = (perLabel.get(label) ?? 0) + 1
    perLabel.set(label, n)
    if (label.startsWith('plan:revise')) {
      revisions += 1
    }
    calls.push({ label, prompt, opts })
    let value = respond ? respond(label, n, prompt) : undefined
    if (value === undefined) {
      value = defaultFor(label, revisions)
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
    return value
  }
  const parallel = thunks => Promise.all(thunks.map(t => t()))
  let result = null
  let error = null
  try {
    result = await workflow(args ?? baseArgs(), agent, parallel, () => {}, m => logs.push(m))
  } catch (e) {
    error = e
  }
  const labels = calls.map(c => c.label)
  const prompt = label => calls.filter(c => c.label === label).map(c => c.prompt).join('\n----\n')
  return { result, error, calls, labels, logs, schemaErrors, prompt }
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

// ---- T1 scenarios ----------------------------------------------------------

const CLEAN_RUN = ['plan:draft', 'critic:correctness:r1', 'critic:performance:r1', 'critic:design:r1', 'fresh:interaction:r1', 'trial', 'plan:approve', 'checklist', 'implement', 'accept']
let cleanRunCount = null

const T1 = [
  ['T1a', 'a clean run spawns the clean-run labels and returns accepted', async ({ expect }) => {
    const r = await run()
    cleanRunCount = r.labels.length
    expect(!r.error, `threw: ${r.error?.message}`)
    expect(r.result?.status === 'accepted', `status ${r.result?.status}`)
    expect(r.labels.join(' ') === CLEAN_RUN.join(' '), `labels ${r.labels.join(' ')}`)
    expect(r.schemaErrors.length === 0, `schema errors ${JSON.stringify(r.schemaErrors)}`)
  }],

  ['T1b', 'only design-level findings at blocking or major fail a round', async ({ expect }) => {
    const notFailing = await run({
      respond: label => label === 'critic:design:r1'
        ? critic('design', [finding({ severity: 'blocking', kind: 'implementation' })]) : undefined,
    })
    expect(!notFailing.labels.some(l => l.startsWith('plan:revise')), 'a blocking implementation finding spawned a revision')
    expect(notFailing.result?.status === 'accepted', `status ${notFailing.result?.status}`)

    const failing = await run({
      respond: label => {
        if (label === 'critic:correctness:r1') {
          return critic('correctness', [finding({ severity: 'major', kind: 'surface' })])
        }
        if (label === 'critic:performance:r1') {
          return critic('performance', [finding({ severity: 'minor', kind: 'rank', decision: 'd2' })])
        }
        return undefined
      },
    })
    expect(failing.labels.includes('plan:revise-r2'), 'a major surface finding spawned no revision')
    const round2 = failing.labels.filter(l => l.startsWith('critic:') && l.endsWith(':r2')).sort()
    expect(round2.join(' ') === 'critic:consistency:r2 critic:correctness:r2', `round 2 dispatched ${round2.join(' ')}`)
  }],

  ['T1c', 'R1 re-ranks a decision whose ranking keeps failing', async ({ expect }) => {
    const rank = (d, over = {}) => finding({ severity: 'major', kind: 'rank', decision: d, ...over })
    const first = await run({
      respond: (label) => {
        if (label === 'critic:design:r1' || label === 'critic:design:r2') {
          return critic('design', [rank('d2')])
        }
        if (label.startsWith('plan:revise')) {
          return { changed_decisions: [], snapshot: `${PLAN}.r1` }
        }
        return undefined
      },
    })
    expect(!/Re-rank these decisions/.test(first.prompt('plan:revise-r2')), 'R1 fired on a first failure')
    expect(/Re-rank these decisions, do not patch them: d2\./.test(first.prompt('plan:revise-r3')), 'first clause: no re-rank of d2 after two failing rounds')

    const second = await run({
      respond: (label) => {
        if (label === 'critic:design:r1') {
          return critic('design', [rank('d1')])
        }
        if (label === 'plan:revise-r2') {
          return { changed_decisions: ['d1', 'd4'], snapshot: `${PLAN}.r1` }
        }
        if (label === 'critic:design:r2') {
          return critic('design', [rank('d4'), rank('d5'), finding({ severity: 'major', kind: 'surface', decision: 'd1' })])
        }
        return undefined
      },
    })
    const line = (second.prompt('plan:revise-r3').match(/Re-rank these decisions, do not patch them: ([^.]*)\./) ?? [])[1] ?? ''
    expect(line.split(', ').includes('d4'), `second clause: d4 not re-ranked (line "${line}")`)
    expect(!line.split(', ').includes('d5'), 'control: d5, failing for the first time and unchanged, was re-ranked')
    expect(!line.split(', ').includes('d1'), 'control: a surface finding on a changed decision triggered R1')

    const afterNull = await run({
      respond: (label) => {
        if (label === 'critic:design:r1' || label === 'critic:design:r2') {
          return critic('design', [rank('d1')])
        }
        if (label === 'plan:revise-r2') {
          return { changed_decisions: ['d1', 'd7'], snapshot: `${PLAN}.r1` }
        }
        if (label === 'plan:revise-r3') {
          return null
        }
        if (label === 'critic:design:r3') {
          return critic('design', [rank('d7')])
        }
        return undefined
      },
    })
    expect(afterNull.labels.includes('plan:revise-r4'), 'the null-revision scenario did not reach a fourth revision')
    expect(!/do not patch them: [^.]*d7/.test(afterNull.prompt('plan:revise-r4')), 'R1 used the changed_decisions of a revision before the one that returned nothing')
    expect(/do not patch them: [^.]*d1/.test(afterNull.prompt('plan:revise-r4')), 'a re-rank owed by a revision that returned nothing was dropped')
  }],

  ['T1d', 'the consistency prompt carries the snapshot, the received findings and the obligations', async ({ expect }) => {
    const r = await run({
      respond: (label) => {
        if (label === 'critic:design:r1') {
          return critic('design', [finding({ id: 'design-a', severity: 'major', kind: 'surface' }), finding({ id: 'design-b' })])
        }
        if (label === 'plan:revise-r2') {
          return { changed_decisions: ['d3'], snapshot: `${PLAN}.r1` }
        }
        return undefined
      },
    })
    const p = r.prompt('critic:consistency:r2')
    expect(p.includes(`Revision snapshot: ${PLAN}.r1`), 'no snapshot path in the consistency prompt')
    expect(p.includes('design-a') && p.includes('design-b'), 'the received findings are missing from the consistency prompt')
    expect(/reports it changed: d3\./.test(p), 'changed_decisions missing from the consistency prompt')
    expect(/Obligations the revision was given/.test(p), 'obligations missing from the consistency prompt')
    expect(!r.prompt('critic:design:r2').includes('Revision snapshot'), 'a non-consistency lens received the consistency context')

    const nulled = await run({
      respond: (label) => {
        if (label === 'critic:design:r1') {
          return critic('design', [finding({ severity: 'major', kind: 'surface' })])
        }
        return label === 'plan:revise-r2' ? null : undefined
      },
    })
    expect(/No revision snapshot exists/.test(nulled.prompt('critic:consistency:r2')), 'after a null revision the prompt does not say there is no snapshot')
  }],

  ['T1e', 'a failing scope finding ends the run from a standard or a fresh round', async ({ expect }) => {
    const standard = await run({
      respond: label => label === 'critic:design:r1'
        ? critic('design', [finding({ id: 'scope-1', severity: 'major', kind: 'scope' }), finding({ id: 'other-1' })]) : undefined,
    })
    expect(standard.result?.status === 'needs-scope', `standard: status ${standard.result?.status}`)
    expect(ids(standard.result?.scopeFindings ?? []) === 'scope-1', 'standard: scopeFindings wrong')
    expect(ids(standard.result?.unrecordedFindings ?? []) === 'other-1,scope-1', 'standard: unrecordedFindings wrong')

    const fresh = await run({
      respond: label => label === 'fresh:interaction:r1'
        ? critic('interaction', [finding({ severity: 'blocking', kind: 'scope' })]) : undefined,
    })
    expect(fresh.result?.status === 'needs-scope', `fresh: status ${fresh.result?.status}`)

    const minor = await run({
      respond: label => label === 'critic:design:r1'
        ? critic('design', [finding({ severity: 'minor', kind: 'scope' })]) : undefined,
    })
    expect(minor.result?.status === 'accepted', `minor scope: status ${minor.result?.status}`)
  }],

  ['T1f', 'R3 obliges a check for a profile defect class found in two rounds', async ({ expect }) => {
    const r = await run({
      respond: (label) => {
        if (label === 'critic:correctness:r1' || label === 'critic:correctness:r2') {
          return critic('correctness', [finding({ severity: 'major', kind: 'surface' })])
        }
        if (label === 'critic:performance:r1') {
          return critic('performance', [finding({ defect_class: 'stale-summary' }), finding({ defect_class: 'unverified-claim' }), finding({ defect_class: 'other' })])
        }
        if (label === 'critic:consistency:r2') {
          return critic('consistency', [finding({ defect_class: 'stale-summary' }), finding({ defect_class: 'other' })])
        }
        return undefined
      },
    })
    const revise3 = r.prompt('plan:revise-r3')
    expect(/recurred in two rounds: stale-summary\./.test(revise3), 'no mechanize instruction for stale-summary')
    expect(!/recurred in two rounds: [^.]*(other|unverified-claim)/.test(revise3), 'control: other, or a class found once, was obliged')
    expect(/add a check for defect class stale-summary/.test(r.prompt('critic:consistency:r3')), 'the obligation is missing from the next consistency prompt')

    const noRevision = await run({
      respond: (label) => {
        if (label === 'critic:correctness:r1') {
          return critic('correctness', [finding({ severity: 'major', kind: 'surface' }), finding({ defect_class: 'unenumerated-consumer' })])
        }
        if (label === 'critic:consistency:r2') {
          return critic('consistency', [finding({ defect_class: 'unenumerated-consumer' })])
        }
        return undefined
      },
    })
    expect(noRevision.result?.status === 'accepted', `no-revision case: status ${noRevision.result?.status}`)
    expect(/no revision followed to add a check: unenumerated-consumer/.test(noRevision.prompt('checklist')), 'an obligation with no revision to take it did not reach the checklist')
  }],

  ['T1g', 'a lens that cannot review is re-dispatched once, then ends the run', async ({ expect }) => {
    const recovered = await run({
      respond: (label, n) => label === 'critic:correctness:r1' && n === 1 ? null
        : label === 'critic:correctness:r1' ? critic('correctness', [finding({ id: 'late-1', severity: 'major', kind: 'surface' })]) : undefined,
    })
    expect(recovered.labels.filter(l => l === 'critic:correctness:r1').length === 2, 'the null lens was not re-dispatched once')
    expect(recovered.prompt('plan:revise-r2').includes('late-1'), 'the recovered lens\'s finding did not enter the round')

    const lost = await run({
      respond: label => label === 'critic:correctness:r1' ? null
        : label === 'critic:design:r1' ? critic('design', [finding({ id: 'kept-1' })]) : undefined,
    })
    expect(lost.labels.filter(l => l === 'critic:correctness:r1').length === 2, 'expected exactly two attempts')
    expect(lost.result?.status === 'critique-aborted-insufficient-coverage', `status ${lost.result?.status}`)
    expect((lost.result?.lensesMissing ?? []).join() === 'correctness', `lensesMissing ${lost.result?.lensesMissing}`)
    expect(ids(lost.result?.unrecordedFindings ?? []) === '' && !(lost.result?.state?.carried ?? []).length,
      'the findings of a round that is dispatched again were kept')

    const blind = await run({
      respond: label => label === 'critic:design:r1' ? critic('design', [finding({ kind: 'coverage', severity: 'blocking' })]) : undefined,
    })
    expect(blind.result?.status === 'critique-aborted-insufficient-coverage', `coverage twice: status ${blind.result?.status}`)

    const discarded = await run({
      respond: label => {
        if (label === 'critic:design:r1') {
          return critic('design', [finding({ severity: 'major', kind: 'surface', defect_class: 'stale-summary' })])
        }
        if (label === 'critic:consistency:r2') {
          return critic('consistency', [finding({ defect_class: 'stale-summary' })])
        }
        return label === 'fresh:interaction:r2' ? null : undefined
      },
    })
    const st = discarded.result?.state ?? {}
    expect(discarded.result?.status === 'critique-aborted-insufficient-coverage', `fresh coverage: status ${discarded.result?.status}`)
    expect(JSON.stringify(st.classRounds) === '{"stale-summary":[1]}' && (st.pendingMechanize ?? []).length === 0,
      `a discarded round still counts toward R3: classRounds ${JSON.stringify(st.classRounds)}, pendingMechanize ${JSON.stringify(st.pendingMechanize)}`)
  }],

  ['T1h', 'every finding reaches the next architect step, and an implementation finding the checklist', async ({ expect }) => {
    const r = await run({
      respond: (label) => {
        if (label === 'critic:design:r1') {
          return critic('design', [finding({ id: 'f1', severity: 'major', kind: 'surface' })])
        }
        if (label === 'critic:performance:r1') {
          return critic('performance', [finding({ id: 'f2', kind: 'rank', decision: 'd1' })])
        }
        if (label === 'critic:correctness:r1') {
          return critic('correctness', [finding({ id: 'f3', severity: 'nit' })])
        }
        if (label === 'critic:design:r2') {
          return critic('design', [finding({ id: 'f4' })])
        }
        if (label === 'fresh:interaction:r2') {
          return critic('interaction', [finding({ id: 'f5', severity: 'nit', kind: 'surface' })])
        }
        return undefined
      },
    })
    const revise = r.prompt('plan:revise-r2')
    expect(['f1', 'f2', 'f3'].every(id => revise.includes(`"${id}"`)), 'the revision did not receive every finding of its round')
    const approve = r.prompt('plan:approve')
    expect(approve.includes('"f4"') && approve.includes('"f5"') && !approve.includes('"f1"'), 'the approval step did not receive exactly the clean rounds\' findings')
    const checklist = r.prompt('checklist')
    expect(['f3', 'f4'].every(id => checklist.includes(`"${id}"`)) && !checklist.includes('"f2"') && !checklist.includes('"f5"'), 'the checklist did not receive exactly the implementation findings')

    const spent = await run({
      args: baseArgs({ maxRounds: 1 }),
      respond: label => label === 'critic:design:r1'
        ? critic('design', [finding({ id: 'g1', severity: 'major', kind: 'surface' }), finding({ id: 'g2' })]) : undefined,
    })
    expect(spent.result?.status === 'blocked-after-revisions', `spent budget: status ${spent.result?.status}`)
    expect(ids(spent.result?.unrecordedFindings ?? []) === 'g1,g2', 'a spent budget did not return the last round\'s findings')
    for (const outcome of [r, spent]) {
      expect(!('nonBlockingFindings' in (outcome.result ?? {})), 'a result still carries nonBlockingFindings')
    }
  }],

  ['T1i', 'a spent budget returns the diagnosis; a priorFindings run reopens the plan', async ({ expect }) => {
    const r = await run({
      args: baseArgs({ maxRounds: 3 }),
      respond: label => /^critic:design:r[123]$/.test(label)
        ? critic('design', [finding({ severity: 'major', kind: 'rank', decision: 'd2' })]) : undefined,
    })
    expect(r.result?.status === 'blocked-after-revisions', `status ${r.result?.status}`)
    const d2 = (r.result?.diagnosis ?? []).find(d => d.decision === 'd2')
    expect(d2 && d2.rounds.join() === '1,2,3' && d2.reranked === true, `diagnosis ${JSON.stringify(r.result?.diagnosis)}`)

    const prior = { id: 'checklist-gap', location: 'testing-plan', severity: 'blocking', title: 'Gap', why: 'Why.', suggested_direction: 'Direction.' }
    const resumed = await run({ args: baseArgs({ priorFindings: [prior] }) })
    expect(!resumed.error, `a priorFindings run threw: ${resumed.error?.message}`)
    expect(/replace it with <!-- PLAN-STATUS: draft -->/.test(resumed.prompt('plan:revise-r1')), 'the priorFindings revision does not carry the reopen line')
    expect(resumed.prompt('plan:revise-r1').includes('checklist-gap'), 'the prior finding is missing from the revision prompt')
    expect(resumed.labels.includes('critic:consistency:r1'), 'no consistency lens followed the opening revision')
  }],

  ['T1j', 'a blind reviewer closes the run', async ({ expect }) => {
    const dead = await run({ respond: label => label === 'implement' ? null : undefined })
    expect(dead.result?.status === 'implementation-failed', `null implementer: status ${dead.result?.status}`)
    expect(!dead.labels.includes('accept'), 'the reviewer ran after a null implementer')
    const deadNoTrial = await run({ args: baseArgs({ trial: false }), respond: label => label === 'implement' ? null : undefined })
    expect(deadNoTrial.result?.state?.branch === `${SLUG}-impl`, `a dead implementer with no trial leaves branch ${deadNoTrial.result?.state?.branch}`)
    const continued = await run({ args: baseArgs({ trial: false, resume: deadNoTrial.result?.state }) })
    expect(continued.prompt('implement').includes(`work on branch ${SLUG}-impl: git switch ${SLUG}-impl when it exists`), 'the resumed implementer is not sent to the dead one\'s branch')

    const r = await run()
    const p = r.prompt('accept')
    expect(p.includes(REQUEST), 'the request is missing')
    expect(CRITERIA.every(c => p.includes(c)), 'a criterion is missing')
    expect(p.includes('abc1234'), 'baseRef is missing')
    expect(p.includes(ACCEPTANCE), 'the acceptance document path is missing')
    expect(p.includes('src/core/widget.ts') && p.includes('tests/core/widget_test.ts'), 'a changed file is missing')
    expect(![PLAN, CHECKLIST, AUDIT].some(x => p.includes(x)), 'the prompt names the plan, checklist or audit file')
    expect(r.calls.find(c => c.label === 'accept')?.opts.agentType === 'acceptance-reviewer', 'wrong agent type')

    const partial = await run({ respond: label => label === 'accept' ? { criteria: CRITERIA.map(c => ({ criterion: c, status: 'partial', evidence: 'e' })), findings: [] } : undefined })
    expect(partial.result?.status === 'acceptance-gaps', `partial: status ${partial.result?.status}`)
    const blocking = await run({
      respond: label => label === 'accept'
        ? { criteria: CRITERIA.map(c => ({ criterion: c, status: 'met', evidence: 'e' })), findings: [{ id: 'a1', location: 'x', severity: 'blocking', title: 't', why: 'w', suggested_direction: 's' }] } : undefined,
    })
    expect(blocking.result?.status === 'acceptance-gaps', `blocking finding: status ${blocking.result?.status}`)
    const nulled = await run({ respond: label => label === 'accept' ? null : undefined })
    expect(nulled.result?.status === 'acceptance-failed', `null reviewer: status ${nulled.result?.status}`)
    const kinded = await run({
      respond: label => label === 'accept'
        ? { criteria: [], findings: [{ id: 'a1', location: 'x', severity: 'minor', title: 't', why: 'w', suggested_direction: 's', kind: 'rank' }] } : undefined,
    })
    expect(kinded.schemaErrors.some(e => e.label === 'accept'), 'a reviewer finding carrying kind passed validation')

    const stoppedState = (await run({
      respond: label => label === 'implement' ? { ...defaultFor('implement'), complete: false, blocking_discoveries: [BASE_ITEM] } : undefined,
    })).result?.state
    const resolution = 'Pinned on the branch by a new test.'
    const settled = await run({ args: baseArgs({ resume: stoppedState, start: 'accept', resolved: [{ id: 'b1', resolution }] }) })
    expect(!settled.error && settled.labels.join(' ') === 'accept', `a stop the owner resolved by hand: ${settled.error?.message ?? settled.labels.join(' ')}`)
    expect((settled.result?.resolvedFindings ?? []).map(f => `${f.id}: ${f.resolution}`).join() === `b1: ${resolution}`, `resolvedFindings ${JSON.stringify(settled.result?.resolvedFindings)}`)
    expect(settled.result?.state?.revise?.length === 0, 'a resolved finding is still queued for the revision')
    const typo = await run({ args: baseArgs({ resume: stoppedState, resolved: [{ id: 'b2', resolution }] }) })
    expect(typo.error && typo.calls.length === 0, 'a resolved id that names no queued finding did not throw')
    const orphanResolved = await run({ args: baseArgs({ resolved: [{ id: 'b1', resolution }] }) })
    expect(orphanResolved.error && orphanResolved.calls.length === 0, 'resolved without a run record did not throw')
    const again = await run({ args: baseArgs({ resume: r.result?.state, start: 'accept' }) })
    expect(!again.error && again.labels.join(' ') === 'accept', `a done run's review run again: ${again.error?.message ?? again.labels.join(' ')}`)
    const reopened = await run({ args: baseArgs({ resume: r.result?.state }) })
    expect(reopened.error && reopened.calls.length === 0, 'a done run resumed without start accept did not throw')
  }],

  ['T1k', 'arguments are validated before the first agent', async ({ expect }) => {
    const throwsEarly = async (args, what) => {
      const r = await run({ args })
      expect(r.error && r.calls.length === 0, `${what}: ${r.error ? 'spawned an agent first' : 'did not throw'}`)
    }
    await throwsEarly(baseArgs({ profile: undefined }), 'missing profile')
    const { gates, ...noGates } = PROFILE
    await throwsEarly(baseArgs({ profile: noGates }), 'profile without gates')
    await throwsEarly(baseArgs({ profile: { ...PROFILE, lenses: { ...FIXTURE.lenses, mechanism: { reads: [], addendum: '' } } } }), 'profile with an unknown lens')
    await throwsEarly(baseArgs({ request: undefined }), 'missing request')
    await throwsEarly(baseArgs({ baseRef: ' ' }), 'blank baseRef')
    const req = baseArgs().requirements
    await throwsEarly(baseArgs({ requirements: { ...req, decisions: 'd1: use X' } }), 'non-array decisions')
    await throwsEarly(baseArgs({ requirements: { ...req, decisions: ['d1: use X', ''] } }), 'an empty decision')
    await throwsEarly(baseArgs({ profile: { ...FIXTURE, modules: { core: { ...FIXTURE.modules.core, lensAddenda: { mechanism: 'x' } } } } }), 'a module addendum for a lens that does not exist')

    await throwsEarly(baseArgs({ start: 'checklist' }), 'start without resume')
    const state = (await run({ respond: label => label === 'checklist' ? null : undefined })).result?.state
    await throwsEarly(baseArgs({ resume: { ...state, baseRef: 'other' } }), 'a resume state from another base commit')
    await throwsEarly(baseArgs({ resume: { ...state, version: 0 } }), 'a resume state of another version')
    await throwsEarly(baseArgs({ resume: state, priorFindings: [BASE_ITEM] }), 'priorFindings at a phase past the revision')
    await throwsEarly(baseArgs({ resume: { ...state, phase: 'trial', clearedFresh: null } }), 'a start past the critique with no cleared angle and no owner approval')
    await throwsEarly(baseArgs({ resume: { ...state, clearedFresh: 'correctness' } }), 'a cleared angle that is not a fresh lens')
    await throwsEarly(baseArgs({ resume: { ...state, pendingLenses: [] } }), 'an empty pending lens list')
    const queued = (await run({
      respond: label => label === 'trial' ? { ...defaultFor('trial'), blocking_findings: [BASE_ITEM] } : undefined,
    })).result?.state
    await throwsEarly(baseArgs({ resume: queued, start: 'trial', ownerApproval: 'Owner.' }), 'a start that skips findings queued for the revision')

    const withDecisions = await run({ args: baseArgs({ requirements: { ...req, decisions: ['Use the span index: measured 3x faster'] } }) })
    expect(withDecisions.prompt('plan:draft').includes('Use the span index'), 'decisions missing from the draft prompt')
    expect(withDecisions.prompt('critic:design:r1').includes('Use the span index'), 'decisions missing from the design prompt')
  }],

  ['T1l', 'reading lists and the requirements block follow the profile', async ({ expect }) => {
    const r = await run()
    expect(r.prompt('critic:design:r1').includes('### Acceptance Criteria'), 'the design prompt lacks the requirements block')
    expect(!r.prompt('critic:correctness:r1').includes('### Acceptance Criteria') && !r.prompt('critic:performance:r1').includes('### Acceptance Criteria'), 'another critic received the requirements block')
    const guidance = FIXTURE.modules.core.guidance
    for (const key of ['correctness', 'performance', 'design']) {
      const expected = [...new Set(FIXTURE.lenses[key].reads.flatMap(x => x === 'moduleGuidance' ? guidance : x === 'conventionDocs' ? FIXTURE.conventionDocs : [x]))]
      const line = (r.prompt(`critic:${key}:r1`).match(/Also read: (.*)\./) ?? [])[1]
      expect(line === expected.join(', '), `${key} reads "${line}", expected "${expected.join(', ')}"`)
    }
    const hazard = FIXTURE.modules.core.lensAddenda.correctness
    expect(r.prompt('critic:correctness:r1').includes(hazard), 'the module addendum is missing from its lens')
    expect(!r.prompt('critic:performance:r1').includes(hazard), 'a module addendum reached another lens')
  }],

  ['T1m', 'finding shapes derive from one base item', async ({ expect }) => {
    const { kind, ...noKind } = finding({ severity: 'major', kind: 'surface' })
    const r = await run({ respond: label => label === 'critic:design:r1' ? critic('design', [noKind]) : undefined })
    expect(r.schemaErrors.some(e => e.label === 'critic:design:r1' && e.errors.some(x => /missing kind/.test(x))), 'a critic finding without kind passed validation')

    const base = { id: 'b1', location: 'x', severity: 'blocking', title: 't', why: 'w', suggested_direction: 's' }
    const trial = await run({
      respond: label => label === 'trial'
        ? { ...defaultFor('trial'), repro_passes_after: false, blocking_findings: [base] } : undefined,
    })
    expect(!trial.schemaErrors.some(e => e.label === 'trial'), `a base-field trial finding failed validation: ${JSON.stringify(trial.schemaErrors)}`)
    expect(trial.result?.status === 'trial-failed', `trial status ${trial.result?.status}`)

    const bare = await run({ respond: label => label === 'critic:design:r1' ? { findings: [] } : undefined })
    expect(!bare.schemaErrors.some(e => e.label === 'critic:design:r1'), `a critic report of findings alone failed validation: ${JSON.stringify(bare.schemaErrors)}`)
    const extra = await run({ respond: label => label === 'critic:design:r1' ? { findings: [], summary: 'Out of lens.' } : undefined })
    expect(extra.schemaErrors.some(e => e.label === 'critic:design:r1' && e.errors.some(x => /unexpected property summary/.test(x))), 'a critic report carrying a summary nothing reads passed validation')
  }],

  ['T1o', 'a resumed run continues the rounds, the spent fresh angles and the carried findings', async ({ expect }) => {
    const first = await run({
      respond: label => {
        if (label === 'critic:correctness:r1') {
          return critic('correctness', [finding({ id: 'impl-1' })])
        }
        if (label === 'trial') {
          return { ...defaultFor('trial'), blocking_findings: [BASE_ITEM] }
        }
        return undefined
      },
    })
    expect(first.result?.status === 'trial-failed', `a trial with a blocking finding and passing gates: status ${first.result?.status}`)
    const st = first.result?.state ?? {}
    expect(st.phase === 'revise', `next phase ${st.phase}`)
    expect((st.freshSpent ?? []).join() === 'interaction', `freshSpent ${st.freshSpent}`)
    expect((st.carried ?? []).some(f => f.id === 'impl-1'), 'the implementation finding is not carried')
    expect(ids(st.revise ?? []) === 'b1', 'the trial finding is not queued for the revision')
    expect(st.branch === null && (st.previousBranches ?? []).includes(`${SLUG}-trial`), `a failed trial's branch is ${st.branch}, retired ${st.previousBranches}`)

    const second = await run({
      args: baseArgs({ resume: JSON.parse(JSON.stringify(st)) }),
      respond: label => label === 'trial' ? { ...defaultFor('trial'), branch: `${SLUG}-trial-2` } : undefined,
    })
    expect(second.labels[0] === 'plan:revise-r2', `the resumed run opened with ${second.labels[0]}`)
    const revise = second.prompt('plan:revise-r2')
    expect(revise.includes('"b1"'), 'the trial finding did not reach the revision')
    expect(revise.includes('### Acceptance Criteria'), 'the revision lacks the requirements')
    expect(second.labels.includes('critic:consistency:r2'), 'no consistency lens followed the opening revision')
    expect(second.labels.includes('fresh:timing:r2') && !second.labels.some(l => l.startsWith('fresh:interaction')), 'the spent fresh angle ran again')
    expect(second.prompt('checklist').includes('"impl-1"'), 'a carried implementation finding did not reach the checklist')
    expect(second.prompt('trial').includes(`git switch -c ${SLUG}-trial abc1234`), 'the trial does not branch from the base commit')
    expect(second.prompt('implement').includes(`work on branch ${SLUG}-trial-2`), 'the implementer is not on the new trial branch')
    expect(second.prompt('implement').includes(`plan were trialed or implemented on ${SLUG}-trial.`), 'the implementer is not told of the retired branch')
    expect(second.result?.status === 'accepted', `status ${second.result?.status}`)
    expect(second.result?.state?.phase === 'done', `final phase ${second.result?.state?.phase}`)
  }],

  ['T1p', 'a run starts at the phase its state or the owner names', async ({ expect }) => {
    const st = (await run({ respond: label => label === 'checklist' ? null : undefined })).result?.state ?? {}
    expect(st.phase === 'checklist', `a dead checklist agent leaves phase ${st.phase}`)
    const later = await run({ args: baseArgs({ resume: st }) })
    expect(later.labels.join(' ') === 'checklist implement accept', `labels ${later.labels.join(' ')}`)
    const byOwner = await run({ args: baseArgs({ resume: { ...st, phase: 'trial', clearedFresh: null }, ownerApproval: 'Accepted under the yield rule.' }) })
    expect(byOwner.labels[0] === 'trial', `the owner-approved run opened with ${byOwner.labels[0]}`)
    expect(byOwner.prompt('plan:approve').includes('Accepted under the yield rule.'), 'the owner approval is missing from the approval prompt')
    const coverage = (await run({ respond: label => label === 'critic:design:r1' ? null : undefined })).result?.state ?? {}
    expect(coverage.phase === 'critique' && coverage.roundsRun === 0, `a coverage failure leaves phase ${coverage.phase}, round ${coverage.roundsRun}`)
    const again = await run({ args: baseArgs({ resume: coverage }) })
    expect(again.labels.slice(0, 3).join(' ') === 'critic:correctness:r1 critic:performance:r1 critic:design:r1', `the re-dispatched round is ${again.labels.slice(0, 3).join(' ')}`)

    const basis = 'Accepted under the yield rule.'
    const ownerStopped = (await run({
      args: baseArgs({ resume: { ...st, phase: 'trial', clearedFresh: null }, ownerApproval: basis }),
      respond: label => label === 'implement' ? null : undefined,
    })).result?.state ?? {}
    expect(ownerStopped.ownerApproval === basis, `the run record keeps the owner's approval as ${JSON.stringify(ownerStopped.ownerApproval)}`)
    const ownerResumed = await run({ args: baseArgs({ resume: ownerStopped }) })
    expect(!ownerResumed.error && ownerResumed.labels.join(' ') === 'implement accept', `an owner-approved run resumed without restating it: ${ownerResumed.error?.message ?? ownerResumed.labels.join(' ')}`)
    const ownerTrialed = (await run({
      args: baseArgs({ resume: { ...st, phase: 'trial', clearedFresh: null }, ownerApproval: basis }),
      respond: label => label === 'trial' ? { ...defaultFor('trial'), blocking_findings: [BASE_ITEM] } : undefined,
    })).result?.state
    const ownerRevised = await run({ args: baseArgs({ resume: ownerTrialed }) })
    expect(ownerRevised.labels[0]?.startsWith('plan:revise') && ownerRevised.result?.state?.ownerApproval === null, `after a revision the owner's approval is ${JSON.stringify(ownerRevised.result?.state?.ownerApproval)}`)
  }],

  ['T1q', 'a stopped implementation is committed and not reviewed', async ({ expect }) => {
    const implementWith = over => label => label === 'implement' ? { ...defaultFor('implement'), ...over } : undefined
    const stopped = await run({ respond: implementWith({ complete: false, blocking_discoveries: [BASE_ITEM] }) })
    expect(stopped.result?.status === 'implementation-stopped', `status ${stopped.result?.status}`)
    expect(!stopped.labels.includes('accept'), 'the reviewer ran on a stopped implementation')
    expect(stopped.result?.state?.phase === 'revise' && ids(stopped.result?.state?.revise ?? []) === 'b1', 'the blocking discovery is not queued for the revision')
    const unfinished = await run({ respond: implementWith({ complete: false }) })
    expect(unfinished.result?.state?.phase === 'implement', `an unfinished implementation leaves phase ${unfinished.result?.state?.phase}`)
    expect(/Commit each item's files on that branch when its acceptance signal passes, before you tick it, and commit any remaining change before you stop for any reason/.test(stopped.prompt('implement')), 'the implementer is not told to commit each item and before every stop')
    const retired = await run({ respond: implementWith({ complete: false, blocking_discoveries: [BASE_ITEM], changed_files: ['src/core/retired_only.ts'] }) })
    const next = await run({ args: baseArgs({ resume: retired.result?.state }) })
    expect(next.labels.includes('accept') && !next.prompt('accept').includes('retired_only.ts'), 'a file only a retired branch changed reached the reviewer')
  }],

  ['T1r', 'the approval and the acceptance gates read what the agents report', async ({ expect }) => {
    const unstamped = await run({ respond: label => label === 'plan:approve' ? { stamped: false } : undefined })
    expect(unstamped.result?.status === 'approval-failed', `status ${unstamped.result?.status}`)
    expect(!unstamped.labels.includes('checklist'), 'the checklist ran on an unstamped plan')
    const two = ['First criterion.', 'Second criterion.']
    const omitted = await run({
      args: baseArgs({ requirements: { ...baseArgs().requirements, acceptance_criteria: two } }),
      respond: label => label === 'accept' ? { criteria: [{ criterion: two[0], status: 'met', evidence: 'e' }], findings: [] } : undefined,
    })
    expect(omitted.result?.status === 'acceptance-gaps', `a criterion the reviewer left out: status ${omitted.result?.status}`)
    const absolute = await run({
      respond: label => label === 'implement'
        ? { ...defaultFor('implement'), changed_files: ['src/core/widget.ts', 'C:\\repo\\plans\\x-checklist.md'] } : undefined,
    })
    expect(!absolute.prompt('accept').includes('x-checklist.md'), 'an absolute plans path reached the reviewer')
    expect(absolute.prompt('accept').includes(`git diff --name-only abc1234 ${SLUG}-trial`), 'the reviewer is not told to diff the branch')
  }],

  ['T1s', 'the project profile validates, plan rules reach their readers, and an unknown argument throws', async ({ expect }) => {
    const real = await run({ args: baseArgs({ profile: PROFILE, module: Object.keys(PROFILE.modules)[0] }) })
    expect(!real.error && real.labels[0] === 'plan:draft', `the project profile: ${real.error?.message ?? real.labels[0]}`)
    const r = await run({
      respond: label => label === 'critic:design:r1' ? critic('design', [finding({ severity: 'major', kind: 'surface' })]) : undefined,
    })
    const rule = FIXTURE.planRules[0]
    for (const label of ['plan:draft', 'plan:revise-r2', 'critic:design:r1']) {
      expect(r.prompt(label).includes(rule), `the plan rules are missing from ${label}`)
    }
    expect(!r.prompt('critic:correctness:r1').includes(rule), 'the plan rules reached a lens that does not check them')
    expect(r.prompt('implement').includes('House conventions, read before writing code or tests: docs/testing.md.'), 'the implementer is not given the convention documents')
    for (const label of ['plan:draft', 'plan:revise-r2']) {
      expect(r.prompt(label).includes(FIXTURE.conventionDocs[0]), `${label} does not name the convention documents`)
    }
    const unknown = await run({ args: { ...baseArgs(), maxround: 3 } })
    expect(unknown.error && unknown.calls.length === 0, 'an unknown argument did not throw before the first agent')
  }],

  ['T1t', 'a revision clears the fresh angle, so a later approval needs a new one or the owner', async ({ expect }) => {
    const first = await run({
      respond: label => label === 'trial' ? { ...defaultFor('trial'), blocking_findings: [BASE_ITEM] } : undefined,
    })
    expect(first.result?.state?.clearedFresh === 'interaction', `before the revision: ${first.result?.state?.clearedFresh}`)
    const second = await run({
      args: baseArgs({ resume: first.result?.state }),
      respond: label => label === 'fresh:timing:r2' ? critic('timing', [finding({ severity: 'major', kind: 'surface' })]) : undefined,
    })
    expect(second.result?.status === 'fresh-angles-exhausted', `status ${second.result?.status}`)
    expect(second.result?.state?.clearedFresh === null, `after the revision: ${second.result?.state?.clearedFresh}`)
    const third = await run({ args: baseArgs({ resume: second.result?.state }) })
    expect(third.error && third.calls.length === 0, 'a plan whose only fresh angle since its revision failed reached approval without the owner')
  }],

  ['T1u', 'a failed trial is retired; a run without a trial branches from the base commit', async ({ expect }) => {
    const failed = await run({
      respond: label => label === 'trial' ? { ...defaultFor('trial'), repro_failed_before: false } : undefined,
    })
    const st = failed.result?.state ?? {}
    expect(failed.result?.status === 'trial-failed' && st.phase === 'trial', `status ${failed.result?.status}, next ${st.phase}`)
    expect(st.branch === null && st.trialCommit === null && st.previousBranches.includes(`${SLUG}-trial`), `branch ${st.branch}, commit ${st.trialCommit}`)
    const noTrial = await run({ args: baseArgs({ resume: st, trial: false }) })
    expect(noTrial.labels.join(' ') === 'plan:approve checklist implement accept', `labels ${noTrial.labels.join(' ')}`)
    expect(noTrial.prompt('plan:approve').includes('No trial was run for this version of the plan.'), 'the approval was told a failed trial passed')
    expect(noTrial.prompt('implement').includes(`git switch -c ${SLUG}-impl abc1234`), 'the implementer does not branch from the base commit')
    expect(noTrial.prompt('implement').includes(`git status --porcelain -- ${FIXTURE.codePaths.join(' ')}`), 'the implementer does not check the tree first')
  }],

  ['T1w', 'a failing fresh angle sends the plan to a revision, and only a later clean angle approves it', async ({ expect }) => {
    const r = await run({
      respond: label => label === 'fresh:interaction:r1' ? critic('interaction', [finding({ severity: 'major', kind: 'surface' })]) : undefined,
    })
    expect(r.labels.indexOf('plan:revise-r2') > r.labels.indexOf('fresh:interaction:r1'), 'no revision followed the failing fresh angle')
    expect(r.labels.includes('critic:consistency:r2') && !r.labels.includes('critic:design:r2'), 'the round after a fresh revision is not the consistency lens alone')
    expect(r.prompt('plan:approve').includes('the fresh angle "timing" came back clean'), 'the approval does not credit the angle that cleared this version')
  }],

  ['T1x', 'every field of the run state survives a resume', async ({ expect }) => {
    const full = {
      version: 1, phase: 'approve', baseRef: 'abc1234', roundsRun: 3,
      freshSpent: ['interaction', 'timing'], clearedFresh: 'timing', ownerApproval: 'Owner basis.', pendingLenses: null,
      rankFailRounds: { d1: [1, 2] }, failRounds: { d1: [1, 2], none: [2] }, reranked: ['d1'],
      classRounds: { 'unverified-claim': [1, 3] }, mechanizeIssued: ['unverified-claim'], pendingMechanize: ['stale-summary'],
      pendingRerank: ['d2'], lastRevision: { round: 3, changed_decisions: ['d1'], snapshot: `${PLAN}.r2` },
      lastReceived: [finding({ id: 'lr-1' })], lastObligations: { rerank: ['d1'], mechanize: [] },
      received: [finding({ id: 'rc-1', round: 3 })], revise: [], carried: [finding({ id: 'ca-1', round: 1 })],
      branch: `${SLUG}-trial-3`, trialCommit: 'feed123', previousBranches: [`${SLUG}-trial`], changedFiles: ['src/core/a.ts'],
    }
    const r = await run({ args: baseArgs({ resume: full }), respond: label => label === 'plan:approve' ? { stamped: false } : undefined })
    const canon = v => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x)) ? Object.fromEntries(Object.entries(x).sort()) : x)
    expect(r.result?.status === 'approval-failed', `status ${r.result?.status}`)
    const back = r.result?.state ?? {}
    const differ = Object.keys(full).filter(k => canon(back[k]) !== canon(full[k]))
    expect(differ.length === 0 && Object.keys(back).length === Object.keys(full).length, `fields changed by a resume: ${differ.join(', ')}`)
  }],

  ['T1y', 'every agent told to switch branches is told by its file to switch back', async ({ expect }) => {
    const r = await run()
    for (const c of r.calls.filter(c => /git switch|checked out/.test(c.prompt))) {
      const file = fs.readFileSync(path.join(ROOT, '.claude/agents', `${c.opts.agentType}.md`), 'utf8')
      expect(/switch back to the branch you started on/i.test(file), `${c.opts.agentType} (${c.label}) switches branches without switching back`)
    }
  }],

  ['T1v', 'a killed run resumes from its run record, its fresh angle spent', async ({ expect }) => {
    const record = jsonBlocks(read(ROOT, CONTRACTS)).find(b => b && b.phase === 'draft' && 'version' in b)
    expect(record, 'the contracts document has no initial run record')
    const initial = { ...record, baseRef: 'abc1234' }
    const fresh = await run({ args: baseArgs({ resume: initial }) })
    expect(!fresh.error && fresh.labels.join(' ') === CLEAN_RUN.join(' '), `the initial record: ${fresh.error?.message ?? fresh.labels.join(' ')}`)

    const killed = await run({ args: baseArgs({ resume: initial, start: 'critique', killed: true }) })
    expect(!killed.error && killed.labels[0] === 'critic:correctness:r1', `the killed first run: ${killed.error?.message ?? killed.labels[0]}`)
    expect(killed.labels.includes('fresh:timing:r1') && !killed.labels.some(l => l.startsWith('fresh:interaction')), 'the fresh angle the killed run could have opened ran again')
    expect(killed.prompt('plan:approve').includes('the fresh angle "timing" came back clean'), 'the approval does not credit the first-pass angle')

    const late = (await run({ respond: label => label === 'checklist' ? null : undefined })).result?.state
    const lateRun = await run({ args: baseArgs({ resume: late, killed: true }) })
    expect((lateRun.result?.state?.freshSpent ?? []).join() === 'interaction', `a killed run past the critique spent ${lateRun.result?.state?.freshSpent}`)

    const orphan = await run({ args: baseArgs({ killed: true }) })
    expect(orphan.error && orphan.calls.length === 0, 'killed without a run record did not throw')
    const misphased = await run({ args: baseArgs({ resume: { ...initial, phase: 'trial' }, ownerApproval: 'Owner.' }) })
    expect(misphased.error && misphased.calls.length === 0, 'an initial record past the draft did not throw')
  }],

  ['T1z', 'consistency fails a round; the Phase 4 floor, a blocked checklist and a refused draft route as documented', async ({ expect }) => {
    const consistency = await run({
      respond: label => label === 'critic:design:r1' ? critic('design', [finding({ severity: 'major', kind: 'consistency' })]) : undefined,
    })
    expect(consistency.labels.includes('plan:revise-r2'), 'a major consistency finding did not fail the round')

    const floor = FIXTURE.gates.filter(g => g.when === 'always').length
    const thin = await run({
      respond: label => label === 'checklist' ? { ...defaultFor('checklist'), phase_counts: { phase1: 1, phase2: 1, phase3: 0, phase4: floor - 1 } } : undefined,
    })
    expect(thin.result?.status === 'checklist-malformed', `a Phase 4 below the floor: status ${thin.result?.status}`)

    const blocked = await run({
      respond: label => label === 'checklist'
        ? { ...defaultFor('checklist'), phase_counts: { phase1: 0, phase2: 0, phase3: 0, phase4: 0 }, blocking_discoveries: [{ title: 'Gap', plan_section: 'testing-plan', why: 'No signal.' }] } : undefined,
    })
    expect(blocked.result?.status === 'checklist-blocked' && blocked.result?.state?.phase === 'revise' && (blocked.result?.state?.revise ?? []).length === 1,
      `a blocking discovery with no items: status ${blocked.result?.status}, next ${blocked.result?.state?.phase}`)

    const refused = await run({ respond: label => label === 'plan:draft' ? 'ABORT: plan already exists' : undefined })
    expect(refused.result?.status === 'draft-aborted' && refused.labels.length === 1, `a refused draft: status ${refused.result?.status}`)
  }],

  ['T1n', 'the trial and the checklist carry the profile gates', async ({ expect }) => {
    const r = await run()
    const trialPrompt = r.prompt('trial')
    expect(FIXTURE.gates.every(g => trialPrompt.includes(`- ${g.name}: \`${g.command}\``)), 'a gate is missing from the trial prompt')
    expect(trialPrompt.includes(`git status --porcelain -- ${FIXTURE.codePaths.join(' ')}`), 'the trial prompt does not check the profile code paths')
    const checklistPrompt = r.prompt('checklist')
    expect(/Phase 4, in this order: one item per rule the Decisions subsections list, a mutation when the rule's code site/.test(checklistPrompt), 'the checklist prompt lacks the Phase 4 order')
    expect(/Trial Log" record [^\n]*with these fields of your result: section, branch, repro_failed_before, repro_passes_after, gates, mutations, commit, blocking_findings\./.test(trialPrompt), 'the trial is not told to log every field its pass decision reads')
    expect(/break the rule there/.test(trialPrompt), 'the trial is not told to mutate the rules it lands')
    expect(FIXTURE.gates.every(g => checklistPrompt.includes(`- ${g.name}:`)), 'a gate is missing from the checklist prompt')

    const gates = FIXTURE.gates.map(g => ({ name: g.name, applies: true, passed: true }))
    const trialWith = gateList => label => label === 'trial' ? { ...defaultFor('trial'), gates: gateList } : undefined
    const missingGate = await run({ respond: trialWith(gates.slice(1)) })
    expect(missingGate.result?.status === 'trial-failed', `a missing gate: status ${missingGate.result?.status}`)
    const failedGate = await run({ respond: trialWith(gates.map((g, i) => i === 0 ? { ...g, passed: false } : g)) })
    expect(failedGate.result?.status === 'trial-failed', `an applying gate failed: status ${failedGate.result?.status}`)
    const skippedGate = await run({ respond: trialWith(gates.map((g, i) => i === 0 ? { ...g, applies: false, passed: false } : g)) })
    expect(skippedGate.result?.status === 'accepted', `a gate that does not apply blocked the trial: status ${skippedGate.result?.status}`)

    const mutatedWith = mutations => label => label === 'trial' ? { ...defaultFor('trial'), mutations } : undefined
    const survived = await run({ respond: mutatedWith([{ decision: 'd2', rule: 'rule 1', test: 'T4', failed: false }, { decision: 'd1', rule: 'rule 1', test: 'T1', failed: true }]) })
    expect(survived.result?.status === 'trial-failed' && survived.result?.state?.phase === 'revise', `a rule whose test passed with it broken: status ${survived.result?.status}, next ${survived.result?.state?.phase}`)
    const queued = survived.result?.state?.revise ?? []
    expect(queued.length === 1 && queued[0].location === 'd2' && queued[0].severity === 'blocking' && queued[0].title.includes('T4'), `the surviving mutation reached the revision as ${JSON.stringify(queued)}`)
    const caught = await run({ respond: mutatedWith([{ decision: 'd1', rule: 'rule 1', test: 'T1', failed: true }]) })
    expect(caught.result?.status === 'accepted', `a mutation its test caught: status ${caught.result?.status}`)
  }],
]

// ---- T3 consumer checks ----------------------------------------------------

// Line endings differ between the documents, so every read is normalised to LF.
const read = (root, rel) => fs.readFileSync(path.join(root, rel), 'utf8').replace(/\r\n/g, '\n')
const sameSet = (a, b) => [...new Set(a)].sort().join(',') === [...new Set(b)].sort().join(',')

function jsonBlocks(text) {
  return [...text.matchAll(/```json\n([\s\S]*?)```/g)].map(m => {
    try {
      return JSON.parse(m[1])
    } catch {
      return { __unparsed: m[1].slice(0, 60) }
    }
  })
}

function frontmatter(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/)
  const fields = {}
  for (const line of (m ? m[1] : '').split('\n')) {
    const kv = line.match(/^([a-z]+):\s*(.*)$/)
    if (kv) {
      fields[kv[1]] = kv[2].trim()
    }
  }
  return fields
}

const CORE = 'plans/AUDIT-METHOD.md'
const CONTRACTS = 'doc/agents/feature-workflow-contracts.md'
const START = '.claude/skills/feature-start/SKILL.md'
const STATUS_SKILL = '.claude/skills/feature-status/SKILL.md'
const CHECKER = 'plans/check_citations.py'
const MEMORY_DIR = '.claude/agent-memory'
const AGENTS_DIR = '.claude/agents'
const RULES_DIR = '.claude/rules'
const PROFILE_PATH = 'doc/agents/method-profile.json'
const SCRIPT_REL = '.claude/workflows/feature-implementation.js'
// The documents agents and the method read as standing instructions.
const GUIDANCE_FILES = ['AGENTS.md', 'CLAUDE.md', CORE, CONTRACTS, RULES_DIR, AGENTS_DIR, '.claude/skills']
// The project-neutral layer: the core, the contracts, the agents, the skills
// and the workflow script.
const NEUTRAL_FILES = [CORE, CONTRACTS, AGENTS_DIR, '.claude/skills', SCRIPT_REL]
// The files that point into the core's or the contracts' numbered sections.
const REFERRING_FILES = ['AGENTS.md', CORE, CONTRACTS, RULES_DIR, AGENTS_DIR, '.claude/skills', SCRIPT_REL]
function guidanceFiles(root) {
  return expand(root, GUIDANCE_FILES)
}
function expand(root, list) {
  const out = []
  for (const rel of list) {
    const abs = path.join(root, rel)
    if (!fs.existsSync(abs)) {
      continue
    }
    if (!fs.statSync(abs).isDirectory()) {
      out.push(rel)
      continue
    }
    for (const f of fs.readdirSync(abs, { recursive: true }).map(String)) {
      if (f.endsWith('.md')) {
        out.push(`${rel}/${f.split(path.sep).join('/')}`)
      }
    }
  }
  return out
}

// The section headings every "section N" reference in the method files names.
const CORE_HEADINGS = [
  '## 1. Angles',
  '## 2. Writing a plan',
  '### 2.1 One site per fact',
  '### 2.2 Summary sections go stale first',
  '### 2.3 Counts and universals carry their command',
  '### 2.4 Declare every artifact the implementer creates',
  '### 2.5 Landing order',
  '### 2.6 Write the design, not its history',
  '### 2.7 Decisions are ranking tables',
  '### 2.8 Guidance documents',
  '## 3. Citations and claims',
  '## 4. Rounds, lenses and findings',
  '## 5. Revisions and loop control',
  '## 6. Stopping and the verdict',
  '## 7. Trials',
  '## 8. Consumers are verified in code',
  '## 9. Closing',
  '## 10. Timed measurement',
  '## 11. The profile',
]

function contractTables(text) {
  const required = [...text.matchAll(/^\| \d+ \| `([^`]+)` \| `([a-z0-9-]+)` \|/gm)].map(m => m[1])
  const section = (title) => {
    const start = text.indexOf(title)
    if (start < 0) {
      return []
    }
    const rest = text.slice(start)
    const end = rest.slice(1).search(/\n(Optional|##|Audit file records)/)
    const block = end < 0 ? rest : rest.slice(0, end + 1)
    return [...block.matchAll(/^\| `([^`]+)` \|/gm)].map(m => m[1])
  }
  return { required, optional: section('Optional, appended later'), audit: section('Audit file records') }
}

// Every "section N" or "rule N.N" a method document points at, with the
// document it points into: the core or the contracts, whichever the sentence
// names last before the reference, else first after it, else the document
// itself when that is the core or the contracts. Other references are skipped.
const DOC_MENTION = /AUDIT-METHOD\.md|feature-workflow-contracts\.md|\bcontracts\b/g
function sectionReferences(text, self) {
  const refs = []
  const flat = text.replace(/\s+/g, ' ')
  for (const sentence of flat.split(/(?<=[.;!?])\s|\|/)) {
    const mentions = [...sentence.matchAll(DOC_MENTION)].map(m => ({ at: m.index, doc: m[0] === 'AUDIT-METHOD.md' ? 'core' : 'contracts' }))
    for (const m of sentence.matchAll(/\b(?:[Ss]ections?|rule) (\d+(?:\.\d+)?)((?:(?:, | and | to )\d+(?:\.\d+)?)*)/g)) {
      const before = mentions.filter(x => x.at < m.index).pop()
      const after = mentions.find(x => x.at > m.index)
      const target = before?.doc ?? after?.doc ?? self
      if (!target) {
        continue
      }
      const numbers = [m[1], ...[...m[2].matchAll(/\d+(?:\.\d+)?/g)].map(x => x[0])]
      for (const n of numbers) {
        refs.push({ target, n, sentence: sentence.slice(Math.max(0, m.index - 60), m.index + 30) })
      }
    }
  }
  return refs
}

// A count written in the same sentence as the `wc -l` or `grep -c` that
// produced it, before or after the command.
function countsBesideCommands(root) {
  const command = '`[^`]*\\b(?:wc -l|grep -c)\\b[^`]*`'
  const patterns = [
    new RegExp(`\\b\\d[\\d,]*\\b[^.;]{0,160}?${command}`, 'g'),
    new RegExp(`${command}[^.;]{0,160}?\\b\\d[\\d,]*\\b`, 'g'),
  ]
  const problems = []
  for (const rel of guidanceFiles(root)) {
    const text = read(root, rel).replace(/\s+/g, ' ')
    for (const re of patterns) {
      for (const m of text.matchAll(re)) {
        problems.push(`${rel}: "${m[0].slice(0, 80)}"`)
      }
    }
  }
  return problems
}

function headingNumbers(text) {
  return new Set([...text.matchAll(/^#{2,3} (\d+(?:\.\d+)?)\.? /gm)].map(m => m[1]))
}

// The `paths:` list of a rule file's frontmatter, or null when it has none.
function rulePaths(text) {
  const m = text.match(/^---\n([\s\S]*?)\n---/)
  if (!m || !/^paths:/m.test(m[1])) {
    return null
  }
  return [...m[1].matchAll(/^\s+- "([^"]+)"$/gm)].map(x => x[1])
}

const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// Every term the profile holds that a project-neutral document must not name:
// module keys and guidance paths, code paths, convention documents, gate
// commands, hot paths, cited extensions no method file uses, and the
// identifiers the module vocabulary, the lens addenda and the plan rules name.
function profileTerms(profile) {
  const methodPaths = profile.methodFiles
  const commandWords = profile.gates
    .filter(g => !methodPaths.some(p => g.command.includes(p)))
    .map(g => g.command.replace(/^cd \S+ && /, '').split(/\s+/)[0])
  const prose = [
    ...Object.values(profile.modules).flatMap(m => [m.vocabulary, ...Object.values(m.lensAddenda ?? {})]),
    ...Object.values(profile.lenses).map(l => l.addendum),
    ...profile.planRules,
  ].join(' ')
  const identifiers = [...new Set(prose.match(/@?\b[A-Za-z_]*[a-z][A-Z][A-Za-z0-9_]*\b/g) ?? [])]
  const extensions = profile.citations.extensions.filter(e => !methodPaths.some(p => p.endsWith(`.${e}`)))
  return [
    ...Object.keys(profile.modules).map(k => ({ term: k, word: true })),
    ...Object.values(profile.modules).flatMap(m => m.guidance.map(g => ({ term: g }))),
    ...profile.codePaths.map(p => ({ term: `${p}/` })),
    ...profile.conventionDocs.map(d => ({ term: d })),
    ...commandWords.map(w => ({ term: w, word: true })),
    ...profile.hotPaths.flatMap(h => [{ term: h }, { term: h.replace(/ /g, '-') }]),
    ...extensions.map(e => ({ term: `.${e}` })),
    ...identifiers.map(i => ({ term: i, word: true, source: 'identifier' })),
  ]
}

// Each row of the core's lens table: the lens key and its stage column.
function lensStages(core) {
  return [...core.matchAll(/^\| `([a-z]+)` \| ([a-z ]+) \|/gm)].map(m => [m[1], m[2].trim()])
}

// The numbers of the core's angle list, section 1.
function angleNumbers(core) {
  const start = core.indexOf('## 1. Angles')
  const section = start < 0 ? '' : core.slice(start, core.indexOf('\n---', start))
  return [...section.matchAll(/^(\d+)\. /gm)].map(m => Number(m[1]))
}

// The angles each row of the core's lens table names at the start of its
// Sweeps cell, keyed by lens.
function tableAngles(core) {
  return Object.fromEntries([...core.matchAll(/^\| `([a-z]+)` \| [a-z ]+ \| (.*) \|$/gm)].map(m => {
    const named = m[2].match(/^Angles? (\d+(?:(?:, | and )\d+)*)/)
    return [m[1], named ? named[1].match(/\d+/g).map(Number) : []]
  }))
}

function lensTable(core) {
  const lines = core.split('\n')
  const start = lines.findIndex(l => /^#{2,3} .*\blenses\b/i.test(l))
  if (start < 0) {
    return []
  }
  const keys = []
  for (const l of lines.slice(start + 1)) {
    if (/^#/.test(l)) {
      break
    }
    const m = l.match(/^\| `([a-z]+)` \|/)
    if (m) {
      keys.push(m[1])
    }
  }
  return keys
}

const T3 = [
  ['T3a', 'the core keeps its numbered headings, by text and in order', [CORE],
    (root) => {
      const lines = read(root, CORE).split('\n').map(l => l.trimEnd())
      const problems = []
      let at = -1
      for (const heading of CORE_HEADINGS) {
        const i = lines.indexOf(heading)
        if (i < 0) {
          problems.push(`missing: ${heading}`)
        } else if (i < at) {
          problems.push(`out of order: ${heading}`)
        } else {
          at = i
        }
      }
      const extra = lines.filter(l => /^#{2,3} \d+(\.\d+)*\.? /.test(l) && !CORE_HEADINGS.includes(l))
      return problems.concat(extra.map(l => `renumbered: ${l}`))
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('## 6. Stopping and the verdict', '## 6. Stopping'))],

  ['T3b', 'the method and the workflow name no project fact the profile holds', NEUTRAL_FILES,
    (root) => {
      const terms = profileTerms(JSON.parse(read(root, PROFILE_PATH)))
      const problems = []
      for (const rel of expand(root, NEUTRAL_FILES)) {
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
      const profile = JSON.parse(read(root, PROFILE_PATH))
      const identifier = profileTerms(profile).find(t => t.source === 'identifier')
      fs.appendFileSync(path.join(root, STATUS_SKILL), `\nSee ${profile.codePaths[0]}/ and ${identifier?.term ?? ''} for an example.\n`)
    }],

  ['T3d', 'the feature-start args template names exactly what the script reads', [START],
    (root, ctx) => {
      const d = ctx.describe
      const blocks = jsonBlocks(read(root, START))
      const args = blocks.find(b => b && typeof b === 'object' && 'requirements' in b)
      if (!args) {
        return ['feature-start has no args template']
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
      const prior = blocks.find(b => b && typeof b === 'object' && 'priorFindings' in b)
      if (!sameSet(Object.keys(prior?.priorFindings?.[0] ?? {}), d.baseFindingFields)) {
        problems.push(`priorFindings template ${Object.keys(prior?.priorFindings?.[0] ?? {}).join(',')} vs script ${d.baseFindingFields.join(',')}`)
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, START), read(root, START).replace('"open_questions"', '"open_issues"'))],

  ['T3e', 'agent frontmatter matches the contracts model table', [CONTRACTS, AGENTS_DIR],
    (root) => {
      const rows = new Map([...read(root, CONTRACTS).matchAll(/^\| `([a-z-]+)` \| `([^`]+)` \| `([^`]+)` \|/gm)].map(m => [m[1], { model: m[2], effort: m[3] }]))
      const agents = fs.readdirSync(path.join(root, AGENTS_DIR)).filter(f => f.endsWith('.md'))
      const problems = []
      for (const file of agents) {
        const fm = frontmatter(read(root, `${AGENTS_DIR}/${file}`))
        const row = rows.get(fm.name)
        if (!row) {
          problems.push(`${fm.name} has no row in the model table`)
        } else if (row.model !== fm.model || row.effort !== fm.effort) {
          problems.push(`${fm.name}: frontmatter ${fm.model}/${fm.effort}, table ${row.model}/${row.effort}`)
        }
      }
      const names = agents.map(f => frontmatter(read(root, `${AGENTS_DIR}/${f}`)).name)
      for (const name of rows.keys()) {
        if (!names.includes(name)) {
          problems.push(`the model table lists ${name}, which has no agent file`)
        }
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, CONTRACTS), read(root, CONTRACTS).replace(/^(\| `plan-checklist` \| `[^`]+` \| `)[^`]+`/m, '$1high`'))],

  ['T3f', 'the contracts clean-run count matches the script', [CONTRACTS],
    (root, ctx) => {
      const m = read(root, CONTRACTS).match(/A clean run is (\d+) agents/)
      if (!m) {
        return ['no "A clean run is N agents" line in the contracts document']
      }
      return Number(m[1]) === ctx.cleanRunCount ? [] : [`the document says ${m[1]}, a clean run spawns ${ctx.cleanRunCount}`]
    },
    root => fs.writeFileSync(path.join(root, CONTRACTS), read(root, CONTRACTS).replace(/A clean run is (\d+) agents/, (_, n) => `A clean run is ${Number(n) + 1} agents`))],

  ['T3g', 'lens keys agree across the profile, the script and the core', ['doc/agents/method-profile.json', CORE],
    (root, ctx) => {
      const profileKeys = Object.keys(JSON.parse(read(root, 'doc/agents/method-profile.json')).lenses)
      const coreKeys = lensTable(read(root, CORE))
      const problems = []
      if (!sameSet(profileKeys, ctx.describe.lensKeys)) {
        problems.push(`profile ${profileKeys} vs script ${ctx.describe.lensKeys}`)
      }
      if (!sameSet(coreKeys, ctx.describe.lensKeys)) {
        problems.push(`core lens table ${coreKeys} vs script ${ctx.describe.lensKeys}`)
      }
      const stageOf = k => ctx.describe.standardLenses.includes(k) ? 'standard'
        : ctx.describe.freshLenses.includes(k) ? 'fresh' : 'after a revision'
      for (const [key, stage] of lensStages(read(root, CORE))) {
        if (stage !== stageOf(key)) {
          problems.push(`the core gives ${key} the stage ${stage}, the script ${stageOf(key)}`)
        }
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('| `timing` |', '| `tempo` |'))],

  ['T3h', 'every section an agent or skill names is defined by the contracts document', [CONTRACTS, AGENTS_DIR, START, STATUS_SKILL],
    (root) => {
      const contracts = read(root, CONTRACTS)
      const { required, optional, audit } = contractTables(contracts)
      const checklistHeadings = [...contracts.matchAll(/^## (Phase \d[^\n]*|Discovered)$/gm)].map(m => m[1])
      const problems = []
      const goals = required.indexOf('Goals & Non-Goals')
      if (required[goals + 1] !== 'Decisions') {
        problems.push('Decisions does not follow Goals & Non-Goals in the required sections')
      }
      for (const gone of ['Audit log', 'Round N Revision', 'Trial Log']) {
        if (optional.includes(gone)) {
          problems.push(`${gone} is still an optional plan section`)
        }
      }
      const norm = s => s.replace(/\d+/g, 'N')
      const known = [...required, ...optional, ...audit, ...checklistHeadings].map(norm)
      const files = [
        ...fs.readdirSync(path.join(root, AGENTS_DIR)).filter(f => f.endsWith('.md')).map(f => `${AGENTS_DIR}/${f}`),
        START, STATUS_SKILL,
      ]
      for (const rel of files) {
        for (const m of read(root, rel).matchAll(/`## ([^`]+)`/g)) {
          const name = norm(m[1])
          if (!known.some(k => k === name || k.startsWith(`${name} - `))) {
            problems.push(`${rel} names "## ${m[1]}", which the contracts document does not define`)
          }
        }
      }
      return problems
    },
    root => fs.appendFileSync(path.join(root, STATUS_SKILL), '\nAlso read `## Bogus Section`.\n')],

  ['T3i', 'no workflow agent keeps persistent memory', [CONTRACTS, AGENTS_DIR],
    (root) => {
      const problems = []
      if (!read(root, CONTRACTS).includes('No workflow agent keeps persistent memory')) {
        problems.push('the contracts document does not state that no agent keeps memory')
      }
      for (const f of fs.readdirSync(path.join(root, AGENTS_DIR)).filter(f => f.endsWith('.md'))) {
        if ('memory' in frontmatter(read(root, `${AGENTS_DIR}/${f}`))) {
          problems.push(`${AGENTS_DIR}/${f} sets memory`)
        }
      }
      if (fs.existsSync(path.join(root, MEMORY_DIR))) {
        problems.push(`${MEMORY_DIR} exists`)
      }
      return problems
    },
    root => {
      const rel = `${AGENTS_DIR}/plan-architect.md`
      fs.writeFileSync(path.join(root, rel), read(root, rel).replace('\nmodel: ', '\nmemory: project\nmodel: '))
    }],

  // An import loads at launch wherever it sits, so a path-scoped rule that
  // imports a document stops being scoped. A module's rules are the rule files
  // whose paths fall under its path patterns, and the profile must list exactly
  // those. A layer rule, whose paths name single files, loads for every source
  // file it names.
  ['T3j', 'path-scoped rules import nothing, and each module lists exactly its rules', [RULES_DIR, PROFILE_PATH],
    (root) => {
      const profile = JSON.parse(read(root, PROFILE_PATH))
      const problems = []
      const rules = fs.readdirSync(path.join(root, RULES_DIR)).filter(f => f.endsWith('.md'))
      const owned = new Map(Object.keys(profile.modules).map(k => [k, []]))
      for (const f of rules) {
        const rel = `${RULES_DIR}/${f}`
        const text = read(root, rel)
        const paths = rulePaths(text)
        if (paths === null) {
          continue
        }
        if (/(^|\s)@[A-Za-z0-9_.\/~-]+/m.test(text.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, ''))) {
          problems.push(`${rel} has paths: and an @ import`)
        }
        for (const [key, m] of Object.entries(profile.modules)) {
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
      for (const [key, m] of Object.entries(profile.modules)) {
        if (!sameSet(owned.get(key), m.guidance)) {
          problems.push(`modules.${key}.guidance ${m.guidance.join(',')} vs the rules under its paths ${owned.get(key).join(',')}`)
        }
      }
      return problems
    },
    root => {
      const rule = Object.values(JSON.parse(read(root, PROFILE_PATH)).modules)[0].guidance[0]
      fs.appendFileSync(path.join(root, rule), '\nSee @../../AGENTS.md for the rules.\n')
    }],

  ['T3k', 'the contracts resume table gives each status exactly the phases the script hands on', [CONTRACTS],
    (root, ctx) => {
      const text = read(root, CONTRACTS)
      const start = text.indexOf('| Status | The next run starts at |')
      if (start < 0) {
        return ['no resume table in the contracts document']
      }
      const rows = [...text.slice(start).split('\n\n')[0].matchAll(/^\| `([a-z-]+)` \| ([^|\n]*) \|/gm)]
      const problems = []
      if (!sameSet(rows.map(r => r[1]), ctx.describe.statuses) || rows.length !== ctx.describe.statuses.length) {
        problems.push(`table ${rows.map(r => r[1]).join(',')} vs script ${ctx.describe.statuses.join(',')}`)
      }
      for (const [, status, cell] of rows) {
        const phases = [...cell.matchAll(/`([a-z]+)`/g)].map(m => m[1])
        if (!sameSet(phases, ctx.describe.nextPhases[status] ?? [])) {
          problems.push(`${status}: table ${phases.join(',')}, script ${(ctx.describe.nextPhases[status] ?? []).join(',')}`)
        }
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, CONTRACTS), read(root, CONTRACTS).replace('| `trial-failed` | `revise` for a plan defect, otherwise `trial` |', '| `trial-failed` | `revise` |'))],

  ['T3l', 'the core names exactly the citation statuses the checker fails on', [CORE, CHECKER],
    root => {
      const failing = read(root, CHECKER).match(/^FAILING = \(([^)]*)\)/m)
      const sentence = read(root, CORE).replace(/\s+/g, ' ').match(/It fails on ([^:.]*)[:.]/)
      if (!failing || !sentence) {
        return ['no FAILING tuple in the checker, or no "It fails on" sentence in the core']
      }
      const statuses = [...failing[1].matchAll(/"([A-Z-]+)"/g)].map(m => m[1])
      const named = [...sentence[1].matchAll(/\b[A-Z][A-Z-]*[A-Z]\b/g)].map(m => m[0])
      return sameSet(named, statuses) && named.length === statuses.length ? [] : [`the core names ${named.join(',')}; the checker fails on ${statuses.join(',')}`]
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('PAST-END and DANGLING', 'DANGLING'))],

  ['T3n', 'guidance states no count before the command that produces it', GUIDANCE_FILES,
    root => countsBesideCommands(root),
    root => fs.appendFileSync(path.join(root, RULES_DIR, 'testing.md'), '\n- The suite holds 12 files (`ls test | wc -l`).\n')],

  ['T3s', 'guidance states no count after the command that produces it', GUIDANCE_FILES,
    root => countsBesideCommands(root),
    root => fs.appendFileSync(path.join(root, RULES_DIR, 'testing.md'), '\n- `ls test | wc -l` prints 12 today.\n')],

  ['T3p', 'every numbered section a method document points at exists', [...REFERRING_FILES, PROFILE_PATH],
    root => {
      const numbers = { core: headingNumbers(read(root, CORE)), contracts: headingNumbers(read(root, CONTRACTS)) }
      const problems = []
      for (const rel of expand(root, REFERRING_FILES)) {
        const self = rel === CORE ? 'core' : rel === CONTRACTS ? 'contracts' : null
        for (const { target, n, sentence } of sectionReferences(read(root, rel), self)) {
          if (!numbers[target].has(n)) {
            problems.push(`${rel} points at ${target} section ${n}: "${sentence}"`)
          }
        }
      }
      return problems
    },
    root => fs.appendFileSync(path.join(root, START), '\nSee `plans/AUDIT-METHOD.md` section 19.\n')],

  ['T3q', 'the contracts list exactly the trial result fields the Trial Log records', [CONTRACTS],
    (root, ctx) => {
      const m = read(root, CONTRACTS).replace(/\s+/g, ' ').match(/with these fields of its result: ([^.]*)\./)
      if (!m) {
        return ['no "with these fields of its result:" list in the contracts document']
      }
      const listed = [...m[1].matchAll(/`([a-z_]+)`/g)].map(x => x[1])
      return sameSet(listed, ctx.describe.trialLogFields) && listed.length === ctx.describe.trialLogFields.length
        ? [] : [`the contracts list ${listed.join(',')}; the trial logs ${ctx.describe.trialLogFields.join(',')}`]
    },
    root => fs.writeFileSync(path.join(root, CONTRACTS), read(root, CONTRACTS).replace('`section`, `branch`, `commit`, ', '`section`, `branch`, '))],

  ['T3r', 'the core restates the script\'s finding kinds and profile keys exactly', [CORE],
    (root, ctx) => {
      const core = read(root, CORE)
      // The bulleted list that follows a heading, up to the first paragraph after it.
      const bulletKeys = heading => {
        const start = core.indexOf(heading)
        if (start < 0) {
          return []
        }
        const rest = core.slice(core.indexOf('\n- ', start))
        const end = rest.search(/\n\n(?![-\s])/)
        return [...(end < 0 ? rest : rest.slice(0, end)).matchAll(/^- `([A-Za-z-]+)`:/gm)].map(m => m[1])
      }
      const problems = []
      const kinds = bulletKeys('Kinds:')
      if (!sameSet(kinds, ctx.describe.kinds) || kinds.length !== ctx.describe.kinds.length) {
        problems.push(`the core lists kinds ${kinds.join(',')}; the script ${ctx.describe.kinds.join(',')}`)
      }
      const keys = bulletKeys('## 11. The profile')
      if (!sameSet(keys, ctx.describe.profileKeys) || keys.length !== ctx.describe.profileKeys.length) {
        problems.push(`the core lists profile keys ${keys.join(',')}; the script ${ctx.describe.profileKeys.join(',')}`)
      }
      return problems
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('- `hotPaths`:', '- `hotPath`:'))],

  ['T3o', 'the contracts default budget matches the script', [CONTRACTS],
    (root, ctx) => {
      const m = read(root, CONTRACTS).replace(/\s+/g, ' ').match(/default budget of (\d+) rounds/)
      if (!m) {
        return ['no "default budget of N rounds" in the contracts document']
      }
      return Number(m[1]) === ctx.describe.defaultRounds ? [] : [`the document says ${m[1]}, the script defaults to ${ctx.describe.defaultRounds}`]
    },
    root => fs.writeFileSync(path.join(root, CONTRACTS), read(root, CONTRACTS).replace(/default budget of (\d+) rounds/, (_, n) => `default budget of ${Number(n) + 1} rounds`))],

  ['T3u', 'the standard lenses sweep every angle on the core\'s list', [CORE],
    (root, ctx) => {
      const listed = angleNumbers(read(root, CORE))
      const swept = ctx.describe.standardLenses.flatMap(k => ctx.describe.lensAngles[k])
      const unswept = listed.filter(n => !swept.includes(n))
      const unknown = swept.filter(n => !listed.includes(n))
      return listed.length === 0 ? ['no angle list in the core']
        : [...unswept.map(n => `angle ${n} is swept by no standard lens`), ...unknown.map(n => `a lens sweeps angle ${n}, which the core does not list`)]
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('10. Performance bounds', '11. An added angle.\n10. Performance bounds'))],

  ['T3v', 'the core\'s lens table names the angles each lens sweeps in the script', [CORE],
    (root, ctx) => {
      const table = tableAngles(read(root, CORE))
      return ctx.describe.lensKeys
        .filter(k => (table[k] ?? []).join() !== ctx.describe.lensAngles[k].join())
        .map(k => `${k}: the core names angles ${(table[k] ?? []).join(',')}, the script ${ctx.describe.lensAngles[k].join(',')}`)
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace(/^(\| `design` \| standard \| Angles? )\d+, /m, '$1'))],

  // The Workflow tool refuses a script holding a control character, a carriage
  // return included, and `read` strips carriage returns, so this reads bytes.
  ['T3t', 'the workflow script holds no control character but the newline', [SCRIPT_REL],
    (root) => {
      const bytes = fs.readFileSync(path.join(root, SCRIPT_REL))
      const at = bytes.findIndex(b => (b < 0x20 && b !== 0x0a) || b === 0x7f)
      return at < 0 ? [] : [`byte 0x${bytes[at].toString(16)} at offset ${at}`]
    },
    root => fs.writeFileSync(path.join(root, SCRIPT_REL), fs.readFileSync(path.join(root, SCRIPT_REL), 'utf8').replace(/\n/g, '\r\n'))],
]

function copyInto(tmp, rel) {
  const src = path.join(ROOT, rel)
  const dst = path.join(tmp, rel)
  fs.mkdirSync(path.dirname(dst), { recursive: true })
  fs.cpSync(src, dst, { recursive: true })
}

// ---- main ------------------------------------------------------------------

async function main() {
  const selected = ([id]) => !ONLY || id.startsWith(ONLY)
  for (const [id, name, body] of T1.filter(selected)) {
    const c = checker()
    try {
      await body(c)
    } catch (e) {
      c.problems.push(`threw: ${e.stack ?? e}`)
    }
    record(id, name, c.problems)
  }

  const t3 = T3.filter(selected)
  if (t3.length > 0) {
    let describe = null
    try {
      describe = await loadWorkflow(SCRIPT_PATH)({ describe: true }, null, null, () => {}, () => {})
    } catch (e) {
      record('T3', 'the script describes its single sources', [`describe failed: ${e.message}`])
    }
    if (cleanRunCount === null) {
      cleanRunCount = (await run()).labels.length
    }
    const ctx = { describe, cleanRunCount }
    const safely = (check, root) => {
      try {
        return check(root, ctx)
      } catch (e) {
        return [`threw: ${e.message}`]
      }
    }
    for (const [id, name, files, check, mutate] of t3) {
      if (!describe) {
        break
      }
      const problems = safely(check, ROOT).map(p => `on the repository: ${p}`)
      const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'fi-harness-'))
      try {
        for (const rel of new Set([...files, 'doc/agents/method-profile.json'])) {
          if (fs.existsSync(path.join(ROOT, rel))) {
            copyInto(tmp, rel)
          }
        }
        mutate(tmp)
        if (safely(check, tmp).length === 0) {
          problems.push('did not fail on a copy with one deliberate mismatch')
        }
      } catch (e) {
        problems.push(`the falsification copy could not be built: ${e.message}`)
      } finally {
        fs.rmSync(tmp, { recursive: true, force: true })
      }
      record(id, name, problems)
    }
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
