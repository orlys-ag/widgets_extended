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
const SLUG = 'harness-run'
const DATE = '2026-10-02'
const PLAN = `plans/${DATE}-${SLUG}-plan.md`
const CHECKLIST = `plans/${DATE}-${SLUG}-checklist.md`
const AUDIT = `plans/${DATE}-${SLUG}-audit.md`
const ACCEPTANCE = `plans/${DATE}-${SLUG}-acceptance.md`
const CRITERIA = ['A drag over a frozen band lands on screen, verified by test/board/x_test.dart']
const REQUEST = 'Make a drop over a frozen band land where the pointer is.'

function baseArgs(over = {}) {
  return {
    slug: SLUG,
    date: DATE,
    module: 'board',
    requirements: {
      summary: 'A harness feature.',
      user_visible_behavior: [],
      acceptance_criteria: CRITERIA,
      modules_touched: ['lib/board/board_widget.dart'],
      constraints: [],
      non_goals: [],
      open_questions: [],
    },
    profile: PROFILE,
    request: REQUEST,
    baseRef: 'abc1234',
    ...over,
  }
}

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
function critic(key, findings = []) {
  return { lens: key, plan_path: PLAN, plan_status: 'draft', summary: 'Summary.', findings }
}
function lensOf(label) {
  return label.split(':')[1]
}

// Defaults follow the schema the script passed, so a run against an earlier
// script, whose trial result has two gate booleans and whose implementer has
// no schema, still completes.
function defaultFor(label, opts, prompt, nthRevision) {
  if (label === 'plan:draft') {
    return 'Drafted.'
  }
  if (label.startsWith('plan:revise')) {
    return opts.schema ? { changed_decisions: [], snapshot: `${PLAN}.r${nthRevision}` } : 'Revised.'
  }
  if (label.startsWith('critic:') || label.startsWith('fresh:')) {
    return critic(lensOf(label))
  }
  if (label === 'trial') {
    const required = opts.schema?.required ?? []
    const result = {
      section: 'S', branch: `${SLUG}-trial`, repro_failed_before: true, repro_passes_after: true,
      commit: 'def5678', notes: '', blocking_findings: [],
    }
    if (required.includes('gates')) {
      result.gates = PROFILE.gates.map(g => ({ name: g.name, applies: true, passed: true }))
    } else {
      Object.assign(result, { analyzer_clean: true, suite_green: true })
    }
    return result
  }
  if (label === 'plan:approve') {
    return 'Stamped.'
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
    return opts.schema
      ? { changed_files: ['lib/board/board_widget.dart', 'test/board/x_test.dart', CHECKLIST], report: 'Done.' }
      : 'Done.'
  }
  if (label === 'accept') {
    return { criteria: CRITERIA.map(c => ({ criterion: c, status: 'met', evidence: 'test/board/x_test.dart passed' })), findings: [] }
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
      value = defaultFor(label, opts, prompt, revisions)
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
    expect(ids(lost.result?.unrecordedFindings ?? []) === 'kept-1', 'the round\'s findings are not in unrecordedFindings')

    const blind = await run({
      respond: label => label === 'critic:design:r1' ? critic('design', [finding({ kind: 'coverage', severity: 'blocking' })]) : undefined,
    })
    expect(blind.result?.status === 'critique-aborted-insufficient-coverage', `coverage twice: status ${blind.result?.status}`)
  }],

  ['T1h', 'every finding reaches exactly one receiver', async ({ expect }) => {
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
  }],

  ['T1j', 'a blind reviewer closes the run', async ({ expect }) => {
    const dead = await run({ respond: label => label === 'implement' ? null : undefined })
    expect(dead.result?.status === 'implementation-failed', `null implementer: status ${dead.result?.status}`)
    expect(!dead.labels.includes('accept'), 'the reviewer ran after a null implementer')

    const r = await run()
    const p = r.prompt('accept')
    expect(p.includes(REQUEST), 'the request is missing')
    expect(CRITERIA.every(c => p.includes(c)), 'a criterion is missing')
    expect(p.includes('abc1234'), 'baseRef is missing')
    expect(p.includes(ACCEPTANCE), 'the acceptance document path is missing')
    expect(p.includes('lib/board/board_widget.dart') && p.includes('test/board/x_test.dart'), 'a changed file is missing')
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
  }],

  ['T1k', 'arguments are validated before the first agent', async ({ expect }) => {
    const throwsEarly = async (args, what) => {
      const r = await run({ args })
      expect(r.error && r.calls.length === 0, `${what}: ${r.error ? 'spawned an agent first' : 'did not throw'}`)
    }
    await throwsEarly(baseArgs({ profile: undefined }), 'missing profile')
    const { gates, ...noGates } = PROFILE
    await throwsEarly(baseArgs({ profile: noGates }), 'profile without gates')
    await throwsEarly(baseArgs({ profile: { ...PROFILE, lenses: { ...PROFILE.lenses, mechanism: { reads: [], addendum: '' } } } }), 'profile with an unknown lens')
    await throwsEarly(baseArgs({ request: undefined }), 'missing request')
    await throwsEarly(baseArgs({ baseRef: ' ' }), 'blank baseRef')
    const req = baseArgs().requirements
    await throwsEarly(baseArgs({ requirements: { ...req, decisions: 'd1: use X' } }), 'non-array decisions')
    await throwsEarly(baseArgs({ requirements: { ...req, decisions: ['d1: use X', ''] } }), 'an empty decision')

    const withDecisions = await run({ args: baseArgs({ requirements: { ...req, decisions: ['Use the span index: measured 3x faster'] } }) })
    expect(withDecisions.prompt('plan:draft').includes('Use the span index'), 'decisions missing from the draft prompt')
    expect(withDecisions.prompt('critic:design:r1').includes('Use the span index'), 'decisions missing from the design prompt')
  }],

  ['T1l', 'reading lists and the requirements block follow the profile', async ({ expect }) => {
    const r = await run()
    expect(r.prompt('critic:design:r1').includes('### Acceptance Criteria'), 'the design prompt lacks the requirements block')
    expect(!r.prompt('critic:correctness:r1').includes('### Acceptance Criteria') && !r.prompt('critic:performance:r1').includes('### Acceptance Criteria'), 'another critic received the requirements block')
    const archDoc = PROFILE.modules.board.archDoc
    for (const key of ['correctness', 'performance', 'design']) {
      const expected = [...new Set(PROFILE.lenses[key].reads.flatMap(x => x === 'archDoc' ? [archDoc] : x === 'conventionDocs' ? PROFILE.conventionDocs : [x]))]
      const line = (r.prompt(`critic:${key}:r1`).match(/Also read, because this lens needs them: (.*)\./) ?? [])[1]
      expect(line === expected.join(', '), `${key} reads "${line}", expected "${expected.join(', ')}"`)
    }
  }],

  ['T1m', 'finding shapes derive from one base item', async ({ expect }) => {
    const { kind, ...noKind } = finding({ severity: 'major', kind: 'surface' })
    const r = await run({ respond: label => label === 'critic:design:r1' ? critic('design', [noKind]) : undefined })
    expect(r.schemaErrors.some(e => e.label === 'critic:design:r1' && e.errors.some(x => /missing kind/.test(x))), 'a critic finding without kind passed validation')

    const base = { id: 'b1', location: 'x', severity: 'blocking', title: 't', why: 'w', suggested_direction: 's' }
    const trial = await run({
      respond: label => label === 'trial'
        ? { ...defaultFor('trial', { schema: { required: ['gates'] } }), repro_passes_after: false, blocking_findings: [base] } : undefined,
    })
    expect(!trial.schemaErrors.some(e => e.label === 'trial'), `a base-field trial finding failed validation: ${JSON.stringify(trial.schemaErrors)}`)
    expect(trial.result?.status === 'trial-failed', `trial status ${trial.result?.status}`)
  }],

  ['T1n', 'the trial and the checklist carry the profile gates', async ({ expect }) => {
    const r = await run()
    const trialPrompt = r.prompt('trial')
    expect(PROFILE.gates.every(g => trialPrompt.includes(`- ${g.name}: \`${g.command}\``)), 'a gate is missing from the trial prompt')
    expect(trialPrompt.includes(`git status --porcelain -- ${PROFILE.codePaths.join(' ')}`), 'the trial prompt does not check the profile code paths')
    const checklistPrompt = r.prompt('checklist')
    expect(/Phase 4, in this order: one mutation item per decision/.test(checklistPrompt), 'the checklist prompt lacks the Phase 4 order')
    expect(PROFILE.gates.every(g => checklistPrompt.includes(`- ${g.name}:`)), 'a gate is missing from the checklist prompt')

    const gates = PROFILE.gates.map(g => ({ name: g.name, applies: true, passed: true }))
    const trialWith = gateList => label => label === 'trial' ? { ...defaultFor('trial', { schema: { required: ['gates'] } }), gates: gateList } : undefined
    const missingGate = await run({ respond: trialWith(gates.slice(1)) })
    expect(missingGate.result?.status === 'trial-failed', `a missing gate: status ${missingGate.result?.status}`)
    const failedGate = await run({ respond: trialWith(gates.map((g, i) => i === 0 ? { ...g, passed: false } : g)) })
    expect(failedGate.result?.status === 'trial-failed', `an applying gate failed: status ${failedGate.result?.status}`)
    const skippedGate = await run({ respond: trialWith(gates.map((g, i) => i === 0 ? { ...g, applies: false, passed: false } : g)) })
    expect(skippedGate.result?.status === 'accepted', `a gate that does not apply blocked the trial: status ${skippedGate.result?.status}`)
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
const MEMORY_DIR = '.claude/agent-memory'
const AGENTS_DIR = '.claude/agents'

// The section headings every "section N" reference in the method files names.
const CORE_HEADINGS = [
  '## 1. The two failure modes this exists to prevent',
  '## 2. Before the first round: enumerate the angles',
  '## 3. Rules for the plan document itself',
  '### 3.1 One normative site per fact',
  '### 3.2 Summary sections are a known hazard',
  '### 3.3 Citations must be re-anchorable, by a ledger not by inline tokens',
  '### 3.4 Counts and universal claims must carry their command',
  '### 3.5 Declare every public artifact the plan depends on',
  '### 3.6 State the landing order when the work spans layers',
  '## 4. The citation and claim pass',
  '## 5. What a pass is, and the consistency pass',
  '## 6. Stopping rule',
  '## 7. Verdict labeling',
  '## 8. Move the unsettleable out of prose',
  '## 9. Round checklist',
  '## 10. Trials are kept, on a branch',
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
    return [...block.matchAll(/^\| `([^`]+)` \| `([a-z0-9-]+)` \|/gm)].map(m => m[1])
  }
  return { required, optional: section('Optional, appended later'), audit: section('Audit file records') }
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
      const extra = lines.filter(l => /^## \d+\. /.test(l) && !CORE_HEADINGS.includes(l) && Number(l.match(/^## (\d+)/)[1]) <= 10)
      return problems.concat(extra.map(l => `renumbered: ${l}`))
    },
    root => fs.writeFileSync(path.join(root, CORE), read(root, CORE).replace('## 6. Stopping rule', '## 6. Stopping rules'))],

  ['T3b', 'the core names no project fact the profile holds', [CORE],
    (root) => {
      const core = read(root, CORE)
      const profile = JSON.parse(read(root, 'doc/agents/method-profile.json'))
      const methodPaths = profile.methodFiles
      const commandWords = profile.gates
        .filter(g => !methodPaths.some(p => g.command.includes(p)))
        .map(g => g.command.replace(/^cd \S+ && /, '').split(/\s+/)[0])
      const terms = [
        ...Object.keys(profile.modules).map(k => ({ term: k, word: true })),
        ...Object.values(profile.modules).map(m => ({ term: m.archDoc })),
        ...profile.codePaths.map(p => ({ term: `${p}/` })),
        ...profile.conventionDocs.map(d => ({ term: d })),
        ...commandWords.map(w => ({ term: w, word: true })),
      ]
      return terms
        .filter(({ term, word }) => word ? new RegExp(`\\b${term}\\b`, 'i').test(core) : core.includes(term))
        .map(({ term }) => `the core names ${term}`)
    },
    root => fs.appendFileSync(path.join(root, CORE), '\nSee lib/board/ for an example.\n')],

  ['T3c', 'the feature-start outcomes table lists exactly the script statuses', [START],
    (root, ctx) => {
      const text = read(root, START)
      const table = text.slice(text.indexOf('## Possible outcomes'))
      const listed = [...table.matchAll(/^\| `([a-z-]+)` \|/gm)].map(m => m[1]).filter(s => s !== 'status')
      return sameSet(listed, ctx.describe.statuses) ? [] : [`table ${listed.join(',')} vs script ${ctx.describe.statuses.join(',')}`]
    },
    root => fs.writeFileSync(path.join(root, START), read(root, START).replace(/^\| `accepted` \|.*\n/m, ''))],

  ['T3d', 'every finding and result example has exactly the schema fields', [`${AGENTS_DIR}/plan-critic.md`, `${AGENTS_DIR}/plan-implementer.md`, `${AGENTS_DIR}/plan-architect.md`, `${AGENTS_DIR}/acceptance-reviewer.md`, START],
    (root, ctx) => {
      const d = ctx.describe
      const problems = []
      const keysOf = o => (o && typeof o === 'object' ? Object.keys(o) : [])
      const check = (where, actual, expected) => {
        if (!sameSet(actual, expected)) {
          problems.push(`${where}: ${actual.join(',')} vs ${expected.join(',')}`)
        }
      }
      const blocks = rel => jsonBlocks(read(root, rel))
      const find = (rel, key) => blocks(rel).find(b => b && key in b)
      const criticExample = find(`${AGENTS_DIR}/plan-critic.md`, 'findings')
      check('plan-critic finding', keysOf(criticExample?.findings?.[0]), d.criticFindingFields)
      const trialExample = find(`${AGENTS_DIR}/plan-implementer.md`, 'blocking_findings')
      check('plan-implementer trial result', keysOf(trialExample), d.trialFields)
      check('plan-implementer trial finding', keysOf(trialExample?.blocking_findings?.[0]), d.baseFindingFields)
      check('plan-implementer result', keysOf(find(`${AGENTS_DIR}/plan-implementer.md`, 'changed_files')), d.implementerFields)
      check('plan-architect revise result', keysOf(find(`${AGENTS_DIR}/plan-architect.md`, 'changed_decisions')), d.reviseFields)
      const architect = read(root, `${AGENTS_DIR}/plan-architect.md`)
      const list = (architect.match(/JSON array of\s+`\{([^}]*)\}`/) ?? [])[1] ?? ''
      check('plan-architect revision input', list.split(',').map(s => s.trim()).filter(Boolean), d.criticFindingFields)
      const acceptance = find(`${AGENTS_DIR}/acceptance-reviewer.md`, 'criteria')
      check('acceptance-reviewer result', keysOf(acceptance), d.acceptanceFields)
      check('acceptance-reviewer finding', keysOf(acceptance?.findings?.[0]), d.baseFindingFields)
      const prior = find(START, 'priorFindings')
      check('feature-start priorFindings entry', keysOf(prior?.priorFindings?.[0]), d.baseFindingFields)
      return problems
    },
    root => {
      const rel = `${AGENTS_DIR}/plan-critic.md`
      fs.writeFileSync(path.join(root, rel), read(root, rel).replace('"defect_class"', '"defect_klass"'))
    }],

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

  ['T3i', 'agent memory holds only scoped, cross-feature lessons', [CONTRACTS, AGENTS_DIR, MEMORY_DIR, 'doc/agents/method-profile.json'],
    (root) => {
      const contracts = read(root, CONTRACTS)
      const capMatch = contracts.match(/An index has at most (\d+) lines/)
      if (!capMatch) {
        return ['no "An index has at most N lines" rule in the contracts document']
      }
      const cap = Number(capMatch[1])
      const modules = Object.keys(JSON.parse(read(root, 'doc/agents/method-profile.json')).modules)
      const scopes = new Set(['general', ...modules])
      const withMemory = new Set(fs.readdirSync(path.join(root, AGENTS_DIR))
        .filter(f => f.endsWith('.md'))
        .map(f => frontmatter(read(root, `${AGENTS_DIR}/${f}`)))
        .filter(fm => fm.memory)
        .map(fm => fm.name))
      const problems = []
      const memoryRoot = path.join(root, MEMORY_DIR)
      const dirs = fs.existsSync(memoryRoot) ? fs.readdirSync(memoryRoot) : []
      for (const dir of dirs) {
        if (!withMemory.has(dir)) {
          problems.push(`${MEMORY_DIR}/${dir} exists, but agent ${dir} keeps no memory`)
          continue
        }
        const files = fs.readdirSync(path.join(memoryRoot, dir)).filter(f => f.endsWith('.md'))
        const index = files.includes('MEMORY.md') ? read(root, `${MEMORY_DIR}/${dir}/MEMORY.md`) : ''
        const lines = index.split('\n').filter(l => l.startsWith('- '))
        if (lines.length > cap) {
          problems.push(`${dir}: ${lines.length} index lines, the limit is ${cap}`)
        }
        for (const line of lines) {
          const tag = (line.match(/^- \[([a-z_]+)\] /) ?? [])[1]
          if (!scopes.has(tag)) {
            problems.push(`${dir}: index line without a valid scope tag: ${line.slice(0, 60)}`)
          }
        }
        for (const f of files) {
          const text = read(root, `${MEMORY_DIR}/${dir}/${f}`)
          if (/[A-Za-z0-9_./-]+\.(dart|md|js|mjs|py):\d+/.test(text)) {
            problems.push(`${dir}/${f} cites a file:line`)
          }
          if (/\b20\d\d-\d\d-\d\d\b/.test(text) || /[a-z0-9]-plan\.md/.test(text)) {
            problems.push(`${dir}/${f} names a date or a plan, so it records one feature`)
          }
        }
      }
      return problems
    },
    root => {
      const index = path.join(root, MEMORY_DIR, 'plan-architect', 'MEMORY.md')
      fs.appendFileSync(index, '- Lane span expansion, 2026-09-05: see the plan.\n')
    }],
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
