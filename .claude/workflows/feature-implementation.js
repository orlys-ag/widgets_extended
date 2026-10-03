export const meta = {
  name: 'feature-implementation',
  description: 'Plan, decision-level critique by the standard lenses, revise with re-ranking, fresh angle, kept trial, approve, checklist, implement, blind acceptance review. Bounded rounds; every lens must report.',
  whenToUse: 'When a feature or bugfix should be designed and built end to end with adversarial review, a kept trial and a blind acceptance review. Use the feature-start skill to build the args: slug, date, requirements, profile, request and baseRef.',
  phases: [
    { title: 'Plan', detail: 'Draft the plan document from the requirements, or revise it from priorFindings.' },
    { title: 'Critique', detail: 'The standard lenses in parallel, at decision level. A revision re-runs the lenses that raised a failing finding, plus a consistency guard that diffs the revision snapshot.' },
    { title: 'Revise', detail: 'Address every finding received, re-rank a decision whose ranking keeps failing, and add a check for a recurring defect class.' },
    { title: 'Fresh Angle', detail: 'One lens drawn from a pool of angles that have not run yet, spent after one use. A clean standard sweep alone measures the lens, not the artifact, and neither does a lens clearing on its second pass.' },
    { title: 'Trial', detail: 'Apply the highest-risk section on a branch and run the profile gates. The diff is kept.' },
    { title: 'Approve', detail: 'Stamp PLAN-STATUS ready-to-implement and record the clean rounds.' },
    { title: 'Checklist', detail: 'Emit the phased checklist, with the carried implementation findings and the mutation items.' },
    { title: 'Implement', detail: 'Execute the checklist, ticking only on acceptance.' },
    { title: 'Accept', detail: 'A reviewer who never reads the plan checks the request and each acceptance criterion against the changed files.' },
  ],
}

// ---- single sources ------------------------------------------------------

// Every status this script returns. The feature-start outcomes table must list
// exactly these, which the harness checks against this constant.
const STATUS = Object.freeze({
  DRAFT_FAILED: 'draft-failed',
  DRAFT_ABORTED: 'draft-aborted',
  COVERAGE: 'critique-aborted-insufficient-coverage',
  FRESH_EXHAUSTED: 'fresh-angles-exhausted',
  NEEDS_SCOPE: 'needs-scope',
  BLOCKED: 'blocked-after-revisions',
  TRIAL_FAILED: 'trial-failed',
  CHECKLIST_FAILED: 'checklist-failed',
  CHECKLIST_MALFORMED: 'checklist-malformed',
  CHECKLIST_BLOCKED: 'checklist-blocked',
  IMPLEMENTATION_FAILED: 'implementation-failed',
  ACCEPTED: 'accepted',
  ACCEPTANCE_GAPS: 'acceptance-gaps',
  ACCEPTANCE_FAILED: 'acceptance-failed',
})

// A finding's kind decides what it can do to a round (plans/AUDIT-METHOD.md,
// the finding kinds section). Only the four design-level kinds can fail one,
// and only at blocking or major; `coverage` means the critic could not review,
// which makes its lens count as not reported.
const SEVERITIES = ['blocking', 'major', 'minor', 'nit']
const KINDS = ['rank', 'surface', 'consistency', 'scope', 'implementation', 'coverage']
const FAILING_KINDS = ['rank', 'surface', 'consistency', 'scope']
const FAILING_SEVERITIES = ['blocking', 'major']

// The base finding item. Every finding shape derives from it: the trial's,
// the acceptance reviewer's and a priorFindings entry use it as is, and a
// critic's adds the three plan-relative fields.
const BASE_FINDING_PROPERTIES = {
  id: { type: 'string' },
  location: { type: 'string' },
  severity: { type: 'string', enum: SEVERITIES },
  title: { type: 'string' },
  why: { type: 'string' },
  suggested_direction: { type: 'string' },
}
const BASE_FIELDS = Object.keys(BASE_FINDING_PROPERTIES)
const CRITIC_FIELDS = [...BASE_FIELDS, 'decision', 'kind', 'defect_class']
const BASE_FINDING = {
  type: 'object',
  required: BASE_FIELDS,
  additionalProperties: false,
  properties: BASE_FINDING_PROPERTIES,
}
function criticFinding(defectClasses) {
  return {
    type: 'object',
    required: CRITIC_FIELDS,
    additionalProperties: false,
    properties: {
      ...BASE_FINDING_PROPERTIES,
      decision: { type: 'string', pattern: '^(d[0-9]+|none)$' },
      kind: { type: 'string', enum: KINDS },
      defect_class: { type: 'string', enum: [...defectClasses, 'other'] },
    },
  }
}

// The lens set. The generic focus of each lens is method text and lives here;
// what a project adds to it, and what each lens reads, come from the profile,
// whose `lenses` keys must equal these.
const LENS_DEFINITIONS = {
  correctness: {
    stage: 'standard',
    focus: 'Angles 1, 8 and 9 of the angle list in plans/AUDIT-METHOD.md section 2. Will each decision do what the goals say? Logical gaps where something reads state nothing writes, ordering violations, re-entrancy. Lifecycle: creation, teardown, and every site that destroys the thing. Degradation: what happens when a precondition is not met, on empty and single-element cases. Judge at decision level: an edge case or a missing test is kind implementation.',
  },
  performance: {
    stage: 'standard',
    ranking: true,
    focus: 'Angle 10 of the angle list in plans/AUDIT-METHOD.md section 2. What is O(what), and is the stated bound the one that can blow up? Anything that turns a targeted lookup into a full scan, and allocation on a hot path. Does each measured or computed evidence cell in a decision table support its rank, and does each counted contract name its check and expected value?',
  },
  design: {
    stage: 'standard',
    ranking: true,
    requirements: true,
    focus: 'Angles 2, 3, 4, 6 and 7 of the angle list in plans/AUDIT-METHOD.md section 2, at decision level. Interfaces: signatures, types, naming, exports, and every consumer of a changed interface verified per the core consumer rule (derive, check in code, read; a search only locates). Contracts: does the plan contradict a document it depends on, or change a documented contract without saying so? Citations and claims: run python plans/check_citations.py on the plan (a non-zero exit is itself a finding) and read that the cited lines say what the plan says; every count carries its command, and every because, only, never and exactly carries its own citation. Decisions: does each table follow the ranking rule, is a valid option missing, does each evidence cell support its rank? Requirements: is each acceptance criterion traced to a named check, and can each named check fail in the direction it claims? Is each new test seam justified against an existing one? Scope: is a requirement missing, ambiguous or in conflict (kind scope)? Guidance: does the plan change a guidance document only to state an invariant it adds or alters?',
  },
  interaction: {
    stage: 'fresh',
    focus: 'plans/AUDIT-METHOD.md section 8, first unsettleable class: the feature crossed with every other component, layer and entry point. Look for the crossings the plan does not mention AT ALL rather than the ones it handles badly. A crossing whose handling would change a decision is kind rank or surface; otherwise it is implementation.',
  },
  timing: {
    stage: 'fresh',
    focus: 'plans/AUDIT-METHOD.md section 8, second unsettleable class: behaviour under real timing. The correctness lens already swept ordering and re-entrancy as design questions, so do NOT repeat that. Ask section 8\'s own question instead: which of this plan\'s timing risks can only be closed by running the code, and does the plan convert each one into a named test rather than into prose that argues it is fine? Name every timing risk the plan settles by assertion instead of by a test.',
  },
  consistency: {
    stage: 'consistency',
    focus: 'The revision that just happened, checked for self-inflicted damage. Diff the revision snapshot against the plan. Read the summary sections specifically: overview, landing order, testing plan, and any decisions list, since those are where staleness collects; read every section that used the vocabulary the revision replaced. Cross-references must resolve, numbering must be contiguous, and each fact must have exactly one normative site. You are also the guard for the lenses that were NOT re-run this round, and for the obligations the revision was given. History or defensive prose the revision added to the plan breaks plans/AUDIT-METHOD.md rule 3.7.',
  },
}
const LENS_KEYS = Object.keys(LENS_DEFINITIONS)
const STANDARD_KEYS = LENS_KEYS.filter(k => LENS_DEFINITIONS[k].stage === 'standard')
const FRESH_KEYS = LENS_KEYS.filter(k => LENS_DEFINITIONS[k].stage === 'fresh')
const CONSISTENCY_KEY = 'consistency'

const TRIAL_REQUIRED = ['section', 'branch', 'repro_failed_before', 'repro_passes_after', 'gates', 'commit', 'notes', 'blocking_findings']
const IMPLEMENTER_REQUIRED = ['changed_files', 'report']
const ACCEPTANCE_REQUIRED = ['criteria', 'findings']
const REVISE_REQUIRED = ['changed_decisions', 'snapshot']
const PROFILE_KEYS = ['codePaths', 'conventionDocs', 'methodFiles', 'gates', 'modules', 'lenses', 'defectClasses', 'ranking', 'hotPaths', 'citations']

// ---- args ----------------------------------------------------------------

// The harness may deliver args as a JSON-encoded string. Normalize to object.
let argsObj = args
if (typeof argsObj === 'string') {
  try { argsObj = JSON.parse(argsObj) } catch { /* fall through to validation */ }
}

// The consistency harness reads the single sources above without running a
// workflow: statuses, lens keys and finding fields are compared with the
// documents that restate them.
if (argsObj?.describe === true) {
  return {
    statuses: Object.values(STATUS),
    lensKeys: LENS_KEYS,
    standardLenses: STANDARD_KEYS,
    freshLenses: FRESH_KEYS,
    consistencyLens: CONSISTENCY_KEY,
    kinds: KINDS,
    baseFindingFields: BASE_FIELDS,
    criticFindingFields: CRITIC_FIELDS,
    trialFields: TRIAL_REQUIRED,
    implementerFields: IMPLEMENTER_REQUIRED,
    acceptanceFields: ACCEPTANCE_REQUIRED,
    reviseFields: REVISE_REQUIRED,
    profileKeys: PROFILE_KEYS,
  }
}

const slug = argsObj?.slug
const requirements = argsObj?.requirements
const priorFindings = Array.isArray(argsObj?.priorFindings) ? argsObj.priorFindings : []
const runTrial = argsObj?.trial !== false

if (!slug || typeof slug !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) {
  throw new Error('feature-implementation requires args.slug: kebab-case string')
}
if (!requirements || typeof requirements !== 'object' || Array.isArray(requirements)) {
  throw new Error('feature-implementation requires args.requirements: structured object (see the feature-start skill for its shape)')
}

const REQUIRED_FIELDS = [
  'summary',
  'user_visible_behavior',
  'acceptance_criteria',
  'modules_touched',
  'constraints',
  'non_goals',
  'open_questions',
]
const missing = REQUIRED_FIELDS.filter(k => !(k in requirements))
if (missing.length > 0) {
  throw new Error(`args.requirements missing fields: ${missing.join(', ')}. Use the feature-start skill to construct args.`)
}
if (typeof requirements.summary !== 'string' || requirements.summary.length === 0) {
  throw new Error('args.requirements.summary must be a non-empty string')
}
for (const k of REQUIRED_FIELDS.filter(k => k !== 'summary')) {
  if (!Array.isArray(requirements[k])) {
    throw new Error(`args.requirements.${k} must be an array (empty [] is fine)`)
  }
}
if (requirements.acceptance_criteria.length === 0) {
  throw new Error('args.requirements.acceptance_criteria must have at least one criterion that can fail on unfixed code')
}
// Decisions the owner settled before the run, each with its evidence. The
// architect adopts each as the starting table for its decision.
if ('decisions' in requirements) {
  const decisions = requirements.decisions
  if (!Array.isArray(decisions) || decisions.some(d => typeof d !== 'string' || d.length === 0)) {
    throw new Error('args.requirements.decisions, when present, must be an array of non-empty strings')
  }
}

// The caller supplies the date; this scope cannot derive it. Workflow scripts
// run in a sandbox where argless `new Date()`, `Date.now()` and `Math.random()`
// THROW, because a resumed run has to replay identically. A default of
// `new Date().toISOString()` here threw before the first agent was spawned, on
// every run that omitted the field. `feature-start` runs in the main loop,
// where Date works, and always passes it.
const date = argsObj?.date
if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  throw new Error('feature-implementation requires args.date: a YYYY-MM-DD string. Workflow scripts cannot call new Date(), so the caller supplies it; the feature-start skill does this for you.')
}

// The request as the owner wrote it, and the commit the first launch of this
// slug started from. Both go to the acceptance reviewer, which judges the
// result against the request and diffs against that commit.
const request = argsObj?.request
if (typeof request !== 'string' || request.trim().length === 0) {
  throw new Error('feature-implementation requires args.request: the owner\'s request, verbatim. The feature-start skill records it.')
}
const baseRef = argsObj?.baseRef
if (typeof baseRef !== 'string' || baseRef.trim().length === 0) {
  throw new Error('feature-implementation requires args.baseRef: the commit the first launch of this slug started from. The feature-start skill records it in the audit file and passes it on every run.')
}

// The project profile (doc/agents/method-profile.json) holds every project
// fact this script reads. This scope has no file access, so feature-start
// reads the file and passes it here; it is validated before anything runs.
const profile = argsObj?.profile
validateProfile(profile)

function isStringArray(value, allowEmpty) {
  return Array.isArray(value)
    && (allowEmpty || value.length > 0)
    && value.every(v => typeof v === 'string' && v.length > 0)
}

function validateProfile(p) {
  const fail = msg => { throw new Error(`args.profile ${msg}. Pass doc/agents/method-profile.json as feature-start does.`) }
  if (!p || typeof p !== 'object' || Array.isArray(p)) {
    fail('is required: the project method profile object')
  }
  const absent = PROFILE_KEYS.filter(k => !(k in p))
  if (absent.length > 0) {
    fail(`is missing keys: ${absent.join(', ')}`)
  }
  for (const k of ['codePaths', 'methodFiles', 'ranking', 'hotPaths']) {
    if (!isStringArray(p[k], false)) {
      fail(`.${k} must be a non-empty array of strings`)
    }
  }
  for (const k of ['conventionDocs', 'defectClasses']) {
    if (!isStringArray(p[k], true)) {
      fail(`.${k} must be an array of strings`)
    }
  }
  if (p.defectClasses.includes('other')) {
    fail('.defectClasses must not list other; the script adds it')
  }
  if (!Array.isArray(p.gates) || p.gates.length === 0) {
    fail('.gates must be a non-empty array')
  }
  for (const g of p.gates) {
    if (!g || typeof g !== 'object' || ['name', 'command', 'pass', 'when'].some(k => typeof g[k] !== 'string' || g[k].length === 0)) {
      fail('.gates entries need non-empty name, command, pass and when strings')
    }
  }
  if (new Set(p.gates.map(g => g.name)).size !== p.gates.length) {
    fail('.gates names must be unique')
  }
  if (!p.modules || typeof p.modules !== 'object' || Object.keys(p.modules).length === 0) {
    fail('.modules must name at least one module')
  }
  for (const [key, m] of Object.entries(p.modules)) {
    if (!m || !isStringArray(m.paths, false) || typeof m.archDoc !== 'string' || typeof m.vocabulary !== 'string') {
      fail(`.modules.${key} needs paths, archDoc and vocabulary`)
    }
    for (const pattern of m.paths) {
      try { new RegExp(pattern) } catch { fail(`.modules.${key}.paths holds an invalid pattern ${JSON.stringify(pattern)}`) }
    }
  }
  if (!p.lenses || typeof p.lenses !== 'object') {
    fail('.lenses must be an object')
  }
  const lensKeys = Object.keys(p.lenses).sort()
  if (lensKeys.join(',') !== [...LENS_KEYS].sort().join(',')) {
    fail(`.lenses must have exactly the keys ${LENS_KEYS.join(', ')}, got ${lensKeys.join(', ')}`)
  }
  for (const [key, lens] of Object.entries(p.lenses)) {
    if (!lens || !isStringArray(lens.reads, true) || typeof lens.addendum !== 'string') {
      fail(`.lenses.${key} needs a reads array and an addendum string`)
    }
  }
  if (!p.citations || typeof p.citations.sdkRoot !== 'string' || !isStringArray(p.citations.extensions, false)) {
    fail('.citations needs sdkRoot and extensions')
  }
}

// The module decides which architecture document the architect, the critics
// and the implementer read. Loading the wrong one into every critic is both
// the largest avoidable cost in a run and a source of contract findings
// against a document the plan never touched. Explicit `args.module` wins;
// otherwise it is derived from `modules_touched` through the profile's path
// patterns, and a mix of modules is an error the caller resolves rather than
// a guess this scope makes.
const MODULES = profile.modules
function deriveModule(paths) {
  const hits = new Set()
  for (const p of paths) {
    for (const [key, m] of Object.entries(MODULES)) {
      if (m.paths.some(pattern => new RegExp(pattern).test(p))) {
        hits.add(key)
      }
    }
  }
  return [...hits]
}
let moduleKey = argsObj?.module
if (moduleKey !== undefined && !(moduleKey in MODULES)) {
  throw new Error(`args.module must be one of ${Object.keys(MODULES).join(', ')}, got ${JSON.stringify(moduleKey)}`)
}
if (moduleKey === undefined) {
  const derived = deriveModule(requirements.modules_touched)
  if (derived.length !== 1) {
    throw new Error(`args.module is required when modules_touched does not name exactly one module (derived: ${derived.join(', ') || 'none'}). Pass one of ${Object.keys(MODULES).join(', ')}.`)
  }
  moduleKey = derived[0]
}
const MODULE = MODULES[moduleKey]
const ARCH_DOC = MODULE.archDoc

const planPath = `plans/${date}-${slug}-plan.md`
const checklistPath = `plans/${date}-${slug}-checklist.md`
const auditPath = `plans/${date}-${slug}-audit.md`
const acceptancePath = `plans/${date}-${slug}-acceptance.md`
const trialBranch = `${slug}-trial`

// Both optional knobs are validated rather than coerced. `slug` and
// `requirements` throw on a wrong type; these two silently fell back to their
// defaults, so `maxRounds: "5"` ran the default and `trial: "false"` ran the
// trial, in both cases doing the opposite of what the caller asked with no
// message anywhere.
if (argsObj?.maxRounds !== undefined && !Number.isInteger(argsObj.maxRounds)) {
  throw new Error(`args.maxRounds must be an integer, got ${JSON.stringify(argsObj.maxRounds)}. A quoted number is not one, and would silently fall back to 4.`)
}
if (argsObj?.trial !== undefined && typeof argsObj.trial !== 'boolean') {
  throw new Error(`args.trial must be a boolean, got ${JSON.stringify(argsObj.trial)}. Any non-boolean is treated as true, so "false" would run the trial.`)
}
const MAX_ROUNDS = Number.isInteger(argsObj?.maxRounds) ? argsObj.maxRounds : 4
if (MAX_ROUNDS < 1) {
  throw new Error('args.maxRounds must be an integer >= 1; 0 would skip every critique round and return blocked with no findings')
}

// priorFindings enters the run at the revision phase, so each element has to be
// shaped like a finding or the architect gets prose where it expects fields.
// Only the base fields are required: a Discovered item, a trial's finding and an
// acceptance finding carry no plan-relative kind, and the loop rules never read
// one from a priorFindings entry.
priorFindings.forEach((f, i) => {
  if (!f || typeof f !== 'object') {
    throw new Error(`args.priorFindings[${i}] must be an object with ${BASE_FIELDS.join(', ')}`)
  }
  const gaps = BASE_FIELDS.filter(k => typeof f[k] !== 'string' || f[k].length === 0)
  if (gaps.length > 0) {
    throw new Error(`args.priorFindings[${i}] missing or empty: ${gaps.join(', ')}`)
  }
})

function renderRequirements(r) {
  const section = (title, items) => items.length === 0
    ? `### ${title}\n(none)\n`
    : `### ${title}\n${items.map(x => `- ${x}`).join('\n')}\n`
  return [
    `## Summary`,
    r.summary,
    ``,
    section('User-Visible Behavior', r.user_visible_behavior),
    section('Acceptance Criteria', r.acceptance_criteria),
    section('Modules Touched', r.modules_touched),
    section('Constraints', r.constraints),
    section('Non-Goals', r.non_goals),
    section('Open Questions (resolve in the plan)', r.open_questions),
    Array.isArray(r.decisions) ? section('Decisions Supplied by the Owner (adopt each as its starting table)', r.decisions) : ``,
  ].filter(Boolean).join('\n')
}

const requirementsMarkdown = renderRequirements(requirements)
const rankingLine = `Ranking criteria, in order (the profile's): ${profile.ranking.join(', ')}. Hot paths, the only place hot-path-performance applies: ${profile.hotPaths.join(', ')}.`
const gateLines = profile.gates.map(g => `- ${g.name}: \`${g.command}\`, passes when ${g.pass}; applies when ${g.when}.`)

// ---- lenses --------------------------------------------------------------

function readsFor(key) {
  const expanded = profile.lenses[key].reads.flatMap(r =>
    r === 'archDoc' ? [ARCH_DOC] : r === 'conventionDocs' ? profile.conventionDocs : [r])
  return [...new Set(expanded)]
}
function lens(key) {
  const addendum = profile.lenses[key].addendum
  return {
    key,
    ...LENS_DEFINITIONS[key],
    reads: readsFor(key),
    focus: addendum ? `${LENS_DEFINITIONS[key].focus} ${addendum}` : LENS_DEFINITIONS[key].focus,
  }
}
const STANDARD = STANDARD_KEYS.map(lens)
const FRESH_POOL = FRESH_KEYS.map(lens)
const CONSISTENCY_LENS = lens(CONSISTENCY_KEY)

// ---- schemas -------------------------------------------------------------

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['lens', 'plan_path', 'plan_status', 'summary', 'findings'],
  additionalProperties: false,
  properties: {
    lens: { type: 'string' },
    plan_path: { type: 'string' },
    plan_status: { type: 'string' },
    summary: { type: 'string' },
    findings: { type: 'array', items: criticFinding(profile.defectClasses) },
  },
}

const REVISE_SCHEMA = {
  type: 'object',
  required: REVISE_REQUIRED,
  additionalProperties: false,
  properties: {
    changed_decisions: { type: 'array', items: { type: 'string', pattern: '^d[0-9]+$' } },
    snapshot: { type: 'string' },
  },
}

const GATE_NAMES = profile.gates.map(g => g.name)
const TRIAL_SCHEMA = {
  type: 'object',
  required: TRIAL_REQUIRED,
  additionalProperties: false,
  properties: {
    section: { type: 'string' },
    branch: { type: 'string' },
    repro_failed_before: { type: 'boolean' },
    repro_passes_after: { type: 'boolean' },
    gates: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'applies', 'passed'],
        additionalProperties: false,
        properties: {
          name: { type: 'string', enum: GATE_NAMES },
          applies: { type: 'boolean' },
          passed: { type: 'boolean' },
        },
      },
    },
    commit: { type: 'string' },
    notes: { type: 'string' },
    blocking_findings: { type: 'array', items: BASE_FINDING },
  },
}

const CHECKLIST_SCHEMA = {
  type: 'object',
  required: ['checklist_path', 'phase_counts', 'blocking_discoveries', 'nonblocking_discoveries'],
  additionalProperties: false,
  properties: {
    checklist_path: { type: 'string' },
    phase_counts: {
      type: 'object',
      required: ['phase1', 'phase2', 'phase3', 'phase4'],
      additionalProperties: false,
      properties: {
        phase1: { type: 'integer' },
        phase2: { type: 'integer' },
        phase3: { type: 'integer' },
        phase4: { type: 'integer' },
      },
    },
    blocking_discoveries: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'plan_section', 'why'],
        additionalProperties: false,
        properties: {
          title: { type: 'string' },
          plan_section: { type: 'string' },
          why: { type: 'string' },
        },
      },
    },
    nonblocking_discoveries: { type: 'array', items: { type: 'string' } },
  },
}

const IMPLEMENTER_SCHEMA = {
  type: 'object',
  required: IMPLEMENTER_REQUIRED,
  additionalProperties: false,
  properties: {
    changed_files: { type: 'array', items: { type: 'string' } },
    report: { type: 'string' },
  },
}

const ACCEPTANCE_SCHEMA = {
  type: 'object',
  required: ACCEPTANCE_REQUIRED,
  additionalProperties: false,
  properties: {
    criteria: {
      type: 'array',
      items: {
        type: 'object',
        required: ['criterion', 'status', 'evidence'],
        additionalProperties: false,
        properties: {
          criterion: { type: 'string' },
          status: { type: 'string', enum: ['met', 'partial', 'unmet'] },
          evidence: { type: 'string' },
        },
      },
    },
    findings: { type: 'array', items: BASE_FINDING },
  },
}

// ---- run state -----------------------------------------------------------

const history = []
// Every finding raised since the last architect step. The next revision or
// the approval step receives all of them and records each in the audit file,
// so a finding of any severity has exactly one receiver. A run that ends
// before an architect step returns them as unrecordedFindings instead.
let received = []
// Every implementation finding of the run, for the checklist.
const implementationFindings = []
// Rounds in which each decision had a failing rank finding (R1), and in which
// any failing finding named it (the diagnosis of a spent budget).
const rankFailRounds = new Map()
const failRounds = new Map()
const reranked = new Set()
// Rounds in which each profile defect class was found, at any severity (R3).
const classRounds = new Map()
const mechanizeIssued = new Set()
let pendingMechanize = []
// What the last revision reported, and what it was given: the consistency
// lens of the next round checks the revision against both.
let lastRevision = null
let lastReceived = []
let lastObligations = { rerank: [], mechanize: [] }

function isFailing(f) {
  return FAILING_SEVERITIES.includes(f.severity) && FAILING_KINDS.includes(f.kind)
}

function addRound(map, key, round) {
  if (!map.has(key)) {
    map.set(key, new Set())
  }
  map.get(key).add(round)
}

// ---- helpers -------------------------------------------------------------

function consistencyContext() {
  const findingsJson = JSON.stringify(
    lastReceived.map(f => ({ id: f.id, severity: f.severity, kind: f.kind ?? null, decision: f.decision ?? null, title: f.title })),
    null, 2)
  return [
    lastRevision?.snapshot
      ? `Revision snapshot: ${lastRevision.snapshot}. Diff it against the plan with git diff --no-index ${lastRevision.snapshot} ${planPath}.`
      : `No revision snapshot exists for this round, because the revision returned no result. Read the revision's record in ${auditPath} instead, and say in your summary that scope was checked by reading.`,
    `Decisions the revision reports it changed: ${(lastRevision?.changed_decisions ?? []).join(', ') || 'none'}.`,
    `Obligations the revision was given: re-rank ${lastObligations.rerank.join(', ') || 'none'}; add a check for defect class ${lastObligations.mechanize.join(', ') || 'none'}.`,
    `An unmet obligation, or a changed decision that no finding below named and that does not depend on one that did, is a failing finding of kind consistency.`,
    `Findings the revision received:`,
    findingsJson,
  ].join('\n')
}

function criticPrompt(lens, withConsistency) {
  return [
    `Plan path: ${planPath}`,
    `Module: ${moduleKey}. ${MODULE.vocabulary}`,
    `Lens: ${lens.key}`,
    `Focus: ${lens.focus}`,
    lens.ranking ? rankingLine : ``,
    lens.requirements ? `Requirements, which this lens traces and scopes against. If this block is missing, report one finding of kind coverage instead of reviewing:` : ``,
    lens.requirements ? requirementsMarkdown : ``,
    withConsistency ? consistencyContext() : ``,
    ``,
    `Give each finding a decision (a d<N> anchor from the plan's Decisions section, or none), a kind (${KINDS.join(', ')}) and a defect_class (${[...profile.defectClasses, 'other'].join(', ')}). A finding that says you could not review is kind coverage.`,
    `Read AGENTS.md and the plan.`,
    lens.reads.length > 0
      ? `Also read, because this lens needs them: ${lens.reads.join(', ')}.`
      : `Read nothing else from doc/agents/: this lens does not need it.`,
    `To verify a consumer, read the code that uses it; a search only locates what to read.`,
    `Then emit structured findings via the StructuredOutput tool.`,
    `Stay in your assigned lens. Perform this review directly: do not spawn additional agents.`,
  ].filter(Boolean).join('\n')
}

// A lens that returns no result, or reports that it could not review, is
// dispatched once more in the same round. A lens that still cannot review
// ends the run: a round cannot be called clean on an angle nobody swept, and
// carrying the gap forward is how a run once reached implementation with
// angle 10 never swept.
async function runLens(lens, phaseTitle, round, withConsistency) {
  const label = `${phaseTitle === 'Critique' ? 'critic' : 'fresh'}:${lens.key}:r${round}`
  let findings = []
  for (let attempt = 1; attempt <= 2; attempt++) {
    let result = null
    try {
      result = await agent(criticPrompt(lens, withConsistency), {
        agentType: 'plan-critic',
        label,
        phase: phaseTitle,
        schema: FINDINGS_SCHEMA,
      })
    } catch (err) {
      log(`Lens ${lens.key} failed in round ${round}: ${err?.message ?? err}`)
    }
    findings = result?.findings ?? []
    const blind = !result || findings.some(f => f.kind === 'coverage')
    if (!blind) {
      return { lens, findings, reported: true }
    }
    log(`Lens ${lens.key} ${result ? 'could not review' : 'returned no result'} in round ${round} (attempt ${attempt}).`)
  }
  return { lens, findings, reported: false }
}

// Returns `{lens, findings, reported}` per lens, where `lens` is the lens
// object this scope DISPATCHED, not the `lens` string the critic reported.
// Correlating on the reported value made a model-side capitalisation of a lens
// key drop that lens from the re-critique set: the round still saw its finding
// and revised on it, but the lens that raised it never re-ran to check the fix.
function critiqueRound(lenses, phaseTitle, round) {
  return parallel(lenses.map(l => () => runLens(l, phaseTitle, round, l.key === CONSISTENCY_KEY)))
}

function collect(critiques, round, stage) {
  history.push({ round, stage, critiques: critiques.map(c => ({ lens: c.lens.key, findings: c.findings })) })
  const flat = critiques.flatMap(c => c.findings.map(f => ({ round, stage, lens: c.lens.key, ...f })))
  received = received.concat(flat)
  for (const f of flat) {
    if (f.kind === 'implementation') {
      implementationFindings.push(f)
    }
  }
  return flat
}

// The loop rules (plans/AUDIT-METHOD.md, the loop control section), applied
// after every round, standard or fresh. Returns the decisions R1 obliges the
// next revision to re-rank; R3's obligations accumulate in pendingMechanize.
function applyRules(round, findings) {
  for (const f of findings) {
    if (profile.defectClasses.includes(f.defect_class)) {
      addRound(classRounds, f.defect_class, round)
    }
  }
  for (const [defectClass, rounds] of classRounds) {
    if (rounds.size >= 2 && !mechanizeIssued.has(defectClass) && !pendingMechanize.includes(defectClass)) {
      pendingMechanize.push(defectClass)
    }
  }
  const failing = findings.filter(isFailing)
  const changed = new Set(lastRevision?.changed_decisions ?? [])
  const rerank = new Set()
  for (const f of failing.filter(f => f.kind === 'rank' && f.decision !== 'none')) {
    const earlier = [...(rankFailRounds.get(f.decision) ?? [])].some(r => r < round)
    if (earlier || changed.has(f.decision)) {
      rerank.add(f.decision)
    }
  }
  for (const f of failing) {
    addRound(failRounds, f.decision, round)
    if (f.kind === 'rank' && f.decision !== 'none') {
      addRound(rankFailRounds, f.decision, round)
    }
  }
  return [...rerank]
}

function diagnosis() {
  return [...failRounds].map(([decision, rounds]) => ({
    decision,
    rounds: [...rounds].sort((a, b) => a - b),
    reranked: reranked.has(decision),
  }))
}

async function revise(findings, round, note, obligations) {
  phase('Revise')
  const result = await agent(
    [
      `Mode: revision (round ${round}).`,
      `Existing plan path: ${planPath}`,
      `Audit file: ${auditPath}`,
      `Module: ${moduleKey}; its architecture document is ${ARCH_DOC}.`,
      note ? `Context: ${note}` : ``,
      rankingLine,
      ``,
      `If the plan's first line is <!-- PLAN-STATUS: ready-to-implement -->, first replace it with <!-- PLAN-STATUS: draft -->: a revision reopens an approved plan. Change PLAN-STATUS in no other way.`,
      `Before editing, copy the plan to the first free ${planPath}.r<N> (N = 1, 2, ...) and report that path as snapshot.`,
      ``,
      `Findings received, every finding raised since the last architect step, at every severity:`,
      JSON.stringify(findings, null, 2),
      ``,
      `Address each failing finding (blocking or major, of kind rank, surface, consistency or scope) in the plan using Edit, never a full-file Write. Fix a non-failing finding, or leave it open with a reason. An implementation finding is carried, because the checklist turns it into an item: leave the plan alone for it unless it shows the plan wrong. Reject a finding only with evidence from the source.`,
      obligations.rerank.length > 0
        ? `Re-rank these decisions, do not patch them: ${obligations.rerank.join(', ')}. For each, add the findings to its table as evidence, re-apply the gate and the ranking criteria (the snapshot holds the option it replaces), record which option now ranks first and why (keeping rank 1 is allowed when the record says why), and update its dependents.`
        : ``,
      obligations.mechanize.length > 0
        ? `These defect classes recurred in two rounds: ${obligations.mechanize.join(', ')}. Add a check for each, preferring a code check per the core consumer rule (derive, check in code, read; a search only locates), and name it in your record.`
        : ``,
      `A fix rewrites the sentence that was wrong; it never appends a note, and the plan never says what it used to say (plans/AUDIT-METHOD.md rule 3.7).`,
      `Append a record of this round to ${auditPath}, creating the file with a one-line title if it does not exist: one line per finding received, giving its id, lens, kind, severity and outcome (fixed, naming the section; re-ranked; rejected, with the evidence; carried; or left open, with the reason). No other prose.`,
      `Record the citations the revision added with --record-new, and --accept any existing one you corrected after re-reading its code; --update refuses an existing ledger. Then run the consistency pass: write down the vocabulary you replaced and read every section that used it.`,
      `Report via StructuredOutput: changed_decisions (the d<N> anchors whose decision text or table you changed) and snapshot.`,
    ].filter(Boolean).join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:revise-r${round}`,
      phase: 'Revise',
      schema: REVISE_SCHEMA,
    },
  )
  lastReceived = findings
  lastObligations = obligations
  for (const d of obligations.rerank) {
    reranked.add(d)
  }
  for (const c of obligations.mechanize) {
    mechanizeIssued.add(c)
  }
  // A dead reviser leaves the plan exactly as the critics found it, so the next
  // round re-raises the same findings. That is a survivable shape, but it reads
  // as "the architect could not fix these" when the truth is that it never ran.
  // With no result there is no snapshot and no changed_decisions: the next
  // consistency prompt says so, and R1's second clause cannot fire.
  if (result === null) {
    log(`Round ${round} revision returned no result: the plan is unchanged, so the next round will re-raise the same findings.`)
    lastRevision = null
  } else {
    lastRevision = { round, changed_decisions: result.changed_decisions, snapshot: result.snapshot }
  }
}

function takeObligations(rerank) {
  const mechanize = pendingMechanize
  pendingMechanize = []
  return { rerank, mechanize }
}

// ---- phase 1: draft ------------------------------------------------------

phase('Plan')

if (priorFindings.length > 0) {
  log(`Resuming: ${priorFindings.length} prior finding(s) supplied, revising the existing plan instead of drafting.`)
  await revise(priorFindings, 1, 'These came from a previous run: a Discovered section, a trial, or an acceptance review.', { rerank: [], mechanize: [] })
} else {
  const draft = await agent(
    [
      `Mode: initial draft.`,
      `Feature slug: ${slug}`,
      `Module: ${moduleKey}. The architecture document for this plan is ${ARCH_DOC}; read it instead of another module's document. ${MODULE.vocabulary}`,
      `Output plan path: ${planPath}`,
      `Audit file: ${auditPath}`,
      ``,
      // This scope has no filesystem access, so it cannot check for a collision
      // itself. `feature-start` checks, but the workflow can also be invoked
      // directly, and then a re-run with the same slug and date arrives here in
      // initial-draft mode against an existing file. Your system prompt permits
      // Write in this mode, so nothing else stops it from replacing an approved
      // plan; that is how the source implementation lost a 547-line one.
      `FIRST, check whether ${planPath} already exists. If it does, emit "ABORT: plan already exists at ${planPath}" and write nothing. Do not Write over it and do not silently switch to revision mode: a re-run against an existing plan is a caller mistake, and the caller re-runs with args.priorFindings when a revision is what they wanted.`,
      ``,
      `Requirements:`,
      requirementsMarkdown,
      ``,
      rankingLine,
      `Follow the operating procedure in your system prompt.`,
      `Write the plan with PLAN-STATUS: draft and every required section from doc/agents/feature-workflow-contracts.md section 3, each followed by its anchor. Every architecture, performance or algorithm choice goes in the Decisions section as a ranking table, per plans/AUDIT-METHOD.md. Write the design, not its history (rule 3.7): concise, final-state, nothing an implementer or reviewer does not need.`,
      `Map every Acceptance Criteria item to a concrete check in the Testing Plan, and resolve every Open Question in the body unless it genuinely needs a user decision.`,
      `Create the audit file ${auditPath} with a one-line title if it does not exist.`,
      `Record the citation ledger with python plans/check_citations.py ${planPath} --update, then verify it exits 0.`,
    ].join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:draft`,
      phase: 'Plan',
    },
  )
  // agent() resolves to null when the subagent dies on a terminal error. Without
  // this the run went on to spend every critic, a fresh angle, a trial and an
  // implementer on a plan path that may hold nothing; the critics do catch it
  // (their coverage finding), but only after the round is paid for.
  if (draft === null) {
    return {
      status: STATUS.DRAFT_FAILED,
      planPath,
      note: 'The architect returned no result, so the plan may not exist or may be partial. Nothing downstream can run against it. Re-run; if it fails again the requirements are the place to look.',
    }
  }
  if (typeof draft === 'string' && /^\s*ABORT:/.test(draft)) {
    return {
      status: STATUS.DRAFT_ABORTED,
      planPath,
      note: `The architect refused to draft: ${draft.trim().slice(0, 300)}`,
    }
  }
  log(`Draft written to ${planPath}`)
}

// ---- phases 2 to 4: critique, revise, fresh angle -------------------------

let approved = false
let roundsRun = 0
let freshUsed = 0
let clearedFreshLens = null

function coverageReturn(round, stage, critiques) {
  return {
    status: STATUS.COVERAGE,
    planPath,
    auditPath,
    round,
    stage,
    lensesPresent: critiques.filter(c => c.reported).map(c => c.lens.key),
    lensesMissing: critiques.filter(c => !c.reported).map(c => c.lens.key),
    unrecordedFindings: received,
    note: `A lens could not review on two attempts, so this round has an unswept angle and cannot be called clean. Re-run; this is an infrastructure failure or a missing input, not a plan defect. The findings raised since the last architect step are in unrecordedFindings; feature-start records them in ${auditPath}.`,
  }
}

function scopeReturn(round, flat) {
  return {
    status: STATUS.NEEDS_SCOPE,
    planPath,
    auditPath,
    round,
    scopeFindings: flat.filter(f => isFailing(f) && f.kind === 'scope'),
    unrecordedFindings: received,
    note: 'A requirement is missing, ambiguous or in conflict. The owner settles it, then re-runs with these findings as priorFindings.',
  }
}

// Round 1 sweeps every standard lens. Later rounds re-run the lenses that
// raised a failing finding, plus CONSISTENCY_LENS. A lens that CLEARED a
// section the revision did not touch has nothing new to say, and re-running it
// is spend without coverage; the consistency lens guards those sections.
let pending = [...STANDARD]

for (let round = 1; round <= MAX_ROUNDS; round++) {
  roundsRun = round

  phase('Critique')
  log(`Round ${round}: ${pending.length} lens(es) in parallel: ${pending.map(l => l.key).join(', ')}.`)

  const standard = await critiqueRound(pending, 'Critique', round)
  const standardFlat = collect(standard, round, 'standard')
  if (standard.some(c => !c.reported)) {
    return coverageReturn(round, 'standard', standard)
  }
  const standardRerank = applyRules(round, standardFlat)
  const standardFailing = standardFlat.filter(isFailing)
  log(`Round ${round}: ${standardFailing.length} failing finding(s) across ${standard.length} lens(es).`)

  if (standardFailing.some(f => f.kind === 'scope')) {
    return scopeReturn(round, standardFlat)
  }

  if (standardFailing.length > 0) {
    if (round === MAX_ROUNDS) {
      log(`Hit MAX_ROUNDS (${MAX_ROUNDS}) with failing findings still open.`)
      break
    }
    const findings = received
    received = []
    await revise(findings, round + 1, 'Standard round.', takeObligations(standardRerank))
    const failingLenses = new Set(standard.filter(c => c.findings.some(isFailing)).map(c => c.lens.key))
    pending = pending.filter(l => failingLenses.has(l.key) && l.key !== CONSISTENCY_KEY).concat([CONSISTENCY_LENS])
    continue
  }

  // Clean. plans/AUDIT-METHOD.md section 6 does not let that approve a plan on
  // its own, so open an angle that has not run yet. Spent entries are never
  // reused: the rule is "empty on its FIRST pass".
  const freshLens = FRESH_POOL[freshUsed]
  if (!freshLens) {
    return {
      status: STATUS.FRESH_EXHAUSTED,
      planPath,
      auditPath,
      roundsRun,
      freshAnglesUsed: FRESH_POOL.map(l => l.key),
      unrecordedFindings: received,
      note: `The standard lenses are clean, but every fresh angle in the pool (${FRESH_POOL.map(l => l.key).join(', ')}) has already run on this plan. plans/AUDIT-METHOD.md section 6 approves on a freshly opened angle coming back clean on its FIRST pass, and re-running a spent one would measure the lens instead of the artifact. The plan is revised and still in draft: open a new angle by hand, or accept it under section 6's yield rule.`,
    }
  }
  freshUsed += 1

  phase('Fresh Angle')
  log(`Round ${round} clean. Opening fresh angle ${freshUsed}/${FRESH_POOL.length}: ${freshLens.key}.`)
  const fresh = await critiqueRound([freshLens], 'Fresh Angle', round)
  const freshFlat = collect(fresh, round, 'fresh')
  if (fresh.some(c => !c.reported)) {
    return coverageReturn(round, 'fresh', fresh)
  }
  const freshRerank = applyRules(round, freshFlat)
  const freshFailing = freshFlat.filter(isFailing)
  log(`Round ${round} fresh angle: ${freshFailing.length} failing finding(s).`)

  if (freshFailing.some(f => f.kind === 'scope')) {
    return scopeReturn(round, freshFlat)
  }

  if (freshFailing.length > 0) {
    if (round === MAX_ROUNDS) {
      log(`Hit MAX_ROUNDS (${MAX_ROUNDS}) with failing findings open in the fresh-angle round.`)
      break
    }
    const findings = received
    received = []
    await revise(findings, round + 1, `Fresh-angle round (${freshLens.key}). These are findings on an angle the standard lenses never sweep, so treat them as first-pass findings on a new angle rather than as leftovers.`, takeObligations(freshRerank))
    pending = [CONSISTENCY_LENS]
    continue
  }

  approved = true
  // The angle that actually cleared, kept separately from the pool slice. The
  // approval prompt used to name every fresh angle that had RUN and call them
  // all clean, so a run where `interaction` failed and `timing` later cleared
  // told the architect to record both as clean and stamp that into the plan.
  // Only the last one cleared.
  clearedFreshLens = freshLens.key
  log(`Round ${round}: standard lenses and the fresh angle both clean. Plan is approvable.`)
  break
}

if (!approved) {
  return {
    status: STATUS.BLOCKED,
    planPath,
    auditPath,
    roundsRun,
    diagnosis: diagnosis(),
    unrecordedFindings: received,
    note: 'The round budget ran out with failing findings open. The diagnosis lists each failing decision, the rounds it failed in, and whether R1 re-ranked it. The findings of the last round are in unrecordedFindings; feature-start records them.',
  }
}

// ---- phase 5: trial ------------------------------------------------------

let trial = null
// The trial reports the branch it actually used, which is not `trialBranch`
// when the default name was already taken by an earlier failed trial. Every
// downstream mention has to follow the reported name, or the implementer is
// pointed at a branch that does not exist.
let effectiveTrialBranch = null

if (runTrial) {
  phase('Trial')
  trial = await agent(
    [
      `Apply plans/AUDIT-METHOD.md section 10 to the approved plan at ${planPath}.`,
      `Module: ${moduleKey}. The module contracts are in ${ARCH_DOC}; read that document, not another module's.`,
      ``,
      `A trial is the strongest form of auditing a solution: apply it, and see whether the code agrees with the text. Reading does not catch a plan whose text reads correctly and whose code does not.`,
      ``,
      `Gates, from the project profile. Run each whose condition applies, and report every one by name in gates, with applies and passed:`,
      ...gateLines,
      ``,
      `Procedure:`,
      `1. Read the plan and pick its highest-risk section: the one whose failure would be hardest to detect by reading.`,
      `2. Create the branch ${trialBranch} from the current HEAD (git switch -c ${trialBranch}). Do not work on the current branch.`,
      `2a. A failed trial keeps its branch, so a re-run after trial-failed will collide: git switch -c refuses an existing branch. Check first with git rev-parse --verify --quiet ${trialBranch}, and if it exists, branch as ${trialBranch}-2, then -3, and so on, using the first name that is free. Report the name you actually used in the branch field; downstream phases use that value, not the default.`,
      `2b. BEFORE branching, run git status --porcelain -- ${profile.codePaths.join(' ')}. If anything there is modified, staged or untracked, STOP: report it in blocking_findings and report every gate as not passed. git switch carries an uncommitted tree onto the new branch, so committing there sweeps unrelated in-progress work into the trial commit, and the trial's whole value is that its diff is exactly the plan section applied. Do not stash it either: that is someone else's work.`,
      `3. Write the section's repro test FIRST and confirm it FAILS on unfixed code. Record what the failure was. If it passes before any change, the repro does not discriminate and that is a blocking finding.`,
      `4. Apply that section's change.`,
      `5. Run the repro again, then the gates above.`,
      `6. COMMIT the result on that branch, staging the files you changed and the new repro test BY PATH (git add <paths>). Do not use git commit -a: it stages tracked modifications only, so a brand new repro test file is untracked and would be left out, silently breaking the rule that the repro lands in the same commit. Keep the commit whether the gates passed or failed. Nothing is reverted: a reverted trial is a verified diff thrown away, which is the mistake the 2026-08-21 audit made with 13 of them.`,
      `7. Leave the plan's citations alone: do not repoint or re-record them. Run python plans/check_citations.py <plan> and say in notes which citations it reports GONE: those are lines your change removed or rewrote, which is evidence about the plan, not bookkeeping.`,
      `8. Append a "## Trial Log" record to the audit file ${auditPath}, creating it with a one-line title if it does not exist: the section trialed, the branch, the commit sha, and each gate's outcome. Never modify the plan.`,
      ``,
      `If a gate fails in a way that reveals a plan defect rather than an implementation slip, record it in blocking_findings so the plan can be revised. Do not invent design to make a gate pass.`,
      ``,
      `Emit the outcome via the StructuredOutput tool.`,
    ].join('\n'),
    {
      agentType: 'plan-implementer',
      label: `trial`,
      phase: 'Trial',
      schema: TRIAL_SCHEMA,
    },
  )

  // Every profile gate is reported exactly once by name, and every one that
  // applies passed. A missing name is a gate nobody ran.
  const reported = trial?.gates ?? []
  const namesMatch = reported.length === GATE_NAMES.length
    && GATE_NAMES.every(n => reported.filter(g => g.name === n).length === 1)
  const gatesPassed = Boolean(trial)
    && trial.repro_failed_before
    && trial.repro_passes_after
    && namesMatch
    && reported.every(g => !g.applies || g.passed)

  if (!gatesPassed) {
    return {
      status: STATUS.TRIAL_FAILED,
      planPath,
      auditPath,
      roundsRun,
      trial,
      trialBranch: trial?.branch ?? trialBranch,
      unrecordedFindings: received,
      note: 'The plan read correctly and the trial did not pass its gates. Re-run this workflow with args.priorFindings set to the trial\'s blocking_findings. The trial branch is kept, so the next run\'s trial will branch under a suffixed name.',
    }
  }

  effectiveTrialBranch = trial.branch || trialBranch
  log(`Trial passed on ${effectiveTrialBranch} at ${trial.commit}.`)
}

// ---- phase 6: approval stamp --------------------------------------------

phase('Approve')

const approvalFindings = received
received = []
await agent(
  [
    `Mode: approval stamp.`,
    `Plan path: ${planPath}`,
    `Audit file: ${auditPath}`,
    ``,
    `The standard lenses returned no failing finding as of round ${roundsRun}, and the fresh angle "${clearedFreshLens}" came back clean on its FIRST pass.`,
    // Only the LAST fresh angle cleared. Naming the earlier ones as clean would
    // put a false claim in the Approval block, which is the one section written
    // to justify the stamp.
    freshUsed > 1
      ? `Fresh angles that ran earlier and DID fail, then were revised: ${FRESH_POOL.slice(0, freshUsed - 1).map(l => l.key).join(', ')}. Record them as such; do not describe them as clean.`
      : ``,
    runTrial ? `The trial passed all gates on branch ${effectiveTrialBranch} at ${trial.commit}.` : `No trial was run for this plan.`,
    ``,
    `Findings received since the last revision, none of them failing. Append a record of these rounds to the audit file, creating it with a one-line title if it does not exist: one line per finding, giving its id, lens, kind, severity and outcome (carried for an implementation finding, otherwise left open with a reason):`,
    approvalFindings.length > 0 ? JSON.stringify(approvalFindings, null, 2) : `(none)`,
    ``,
    `In the plan, use Edit for both changes, never a full-file Write: flip PLAN-STATUS to ready-to-implement and append the Approval section per your system prompt. Change nothing else in the plan.`,
    ``,
    `Then run python plans/check_citations.py ${planPath} and record what it reports in the Approval block.`,
    runTrial
      ? `Do NOT require it to exit 0. The trial changed code, so a GONE citation is EXPECTED where the trial rewrote or removed code the plan cites: that is evidence about the plan. Record those, and never delete or re-record the ledger to force a clean exit.`
      : `It should exit 0. If it reports a GONE citation, record it in the Approval block as an open finding; never delete or re-record the ledger to clear it.`,
  ].filter(Boolean).join('\n'),
  {
    agentType: 'plan-architect',
    label: `plan:approve`,
    phase: 'Approve',
  },
)

// ---- phase 7: checklist --------------------------------------------------

phase('Checklist')

const outstandingMechanize = pendingMechanize
const checklist = await agent(
  [
    `Plan path: ${planPath}`,
    `Checklist path: ${checklistPath}`,
    `Module: ${moduleKey}.`,
    ``,
    `If a checklist already exists at the checklist path, rename it to the first free ${checklistPath.replace(/\.md$/, '')}.superseded-<n>.md before writing: a reopened plan keeps the record of what its last checklist ticked.`,
    `Verify the plan is ready-to-implement, then emit the grouped checklist per your system prompt and doc/agents/feature-workflow-contracts.md section 5.`,
    `Phase 4, in this order: one mutation item per decision whose Components & State entry names a file under ${profile.codePaths.join(', ')}; then one item per gate below whose condition applies; then the Ledger retired item.`,
    ...gateLines,
    `Carried implementation findings from the audit. Make each an item whose acceptance is a test shown to fail first, a mutation, or the code check the core consumer rule names for a consumer. List one that no longer applies to the approved plan under Discovered with Blocking: no and the reason:`,
    implementationFindings.length > 0 ? JSON.stringify(implementationFindings, null, 2) : `(none)`,
    outstandingMechanize.length > 0
      ? `These defect classes recurred in two rounds and no revision followed to add a check: ${outstandingMechanize.join(', ')}. Add an item for each that adds one, preferring a code check.`
      : ``,
    `Confirm every anchor you link actually exists in the plan before emitting the link.`,
    `Report the result via StructuredOutput. Do not also write a prose summary.`,
  ].filter(Boolean).join('\n'),
  {
    agentType: 'plan-checklist',
    label: `checklist`,
    phase: 'Checklist',
    schema: CHECKLIST_SCHEMA,
  },
)

// The implementer aborts on four preconditions, and three of them are knowable
// from here. Spawning it into one of those burns a frontier agent to be told
// what this scope already knows, so each is a return instead.

// Precondition 2, checklist exists and pairs with the plan. No structured result
// means the agent aborted (its own precondition 1 fires when the approval stamp
// did not land) or crashed, and in either case no checklist file is on disk.
// The path is checked, not just the presence of a string. The implementer is
// handed `checklistPath` and aborts on its own precondition 2 when the file is
// not there or its CHECKLIST-FOR does not pair, so a checklist written
// somewhere else is the same outcome one agent later.
// The agent may report the path absolute or with backslashes, and both name
// the same file. Normalise separators and accept a path that ends with the
// expected repo-relative one; a mismatch on the trailing segments is still a
// checklist written somewhere else.
function normalisePath(p) {
  return p.split(String.fromCharCode(92)).join('/')
}
const reportedChecklist = typeof checklist?.checklist_path === 'string'
  ? normalisePath(checklist.checklist_path)
  : null
const checklistPathMatches = reportedChecklist !== null
  && (reportedChecklist === checklistPath || reportedChecklist.endsWith('/' + checklistPath))
if (!checklist || !checklistPathMatches) {
  return {
    status: STATUS.CHECKLIST_FAILED,
    planPath,
    checklistPath,
    roundsRun,
    trialBranch: effectiveTrialBranch,
    reportedChecklistPath: checklist?.checklist_path ?? null,
    note: checklist && typeof checklist.checklist_path === 'string'
      ? `The checklist agent wrote ${checklist.checklist_path}, not ${checklistPath}. The implementer is handed the second path and would abort on its CHECKLIST-FOR pairing precondition, so the run stops here instead. Re-run the checklist phase against the approved plan.`
      : 'The checklist agent returned no structured result, so no checklist was written. The usual cause is the approval stamp not landing, which fires the checklist agent\'s own PLAN-STATUS precondition. Check the plan\'s first line before re-running.',
  }
}

// Precondition 3, at least one unchecked item. Phase 4 always carries the
// always-applying gates and the ledger item, at least three with any profile
// whose analyzer and test gates always apply, so a checklist below that is
// malformed rather than merely short.
const phaseCounts = checklist.phase_counts ?? {}
const totalItems = ['phase1', 'phase2', 'phase3', 'phase4']
  .reduce((n, k) => n + (Number.isInteger(phaseCounts[k]) ? phaseCounts[k] : 0), 0)
if (totalItems === 0 || (Number.isInteger(phaseCounts.phase4) && phaseCounts.phase4 < 3)) {
  return {
    status: STATUS.CHECKLIST_MALFORMED,
    planPath,
    checklistPath,
    roundsRun,
    trialBranch: effectiveTrialBranch,
    phaseCounts,
    nonblockingDiscoveries: checklist.nonblocking_discoveries ?? [],
    note: `The checklist has ${totalItems} phase item(s) with ${phaseCounts.phase4 ?? 0} in Phase 4. Phase 4 always carries the applying gates and the ledger item, so this checklist would abort the implementer or verify nothing. Re-run the checklist phase against the approved plan.`,
  }
}

// Precondition 4, no blocking Discovered items.
const checklistBlockers = checklist.blocking_discoveries ?? []
if (checklistBlockers.length > 0) {
  return {
    status: STATUS.CHECKLIST_BLOCKED,
    planPath,
    checklistPath,
    roundsRun,
    trialBranch: effectiveTrialBranch,
    blockingDiscoveries: checklistBlockers,
    note: 'The checklist could not derive every item from the plan. Re-run with args.priorFindings built from these so the architect fills the gaps.',
  }
}

// ---- phase 8: implement --------------------------------------------------

phase('Implement')

const implementation = await agent(
  [
    `Plan path: ${planPath}`,
    `Checklist path: ${checklistPath}`,
    `Module: ${moduleKey}. The module contracts are in ${ARCH_DOC}; read that document, not another module's.`,
    runTrial ? `A trial of one section is already committed on ${effectiveTrialBranch}. Work from that branch so the trial is not duplicated or reverted.` : ``,
    ``,
    `Gates, from the project profile:`,
    ...gateLines,
    ``,
    `Execute the checklist in order per your system prompt.`,
    `Tick a box only when you have run its acceptance signal and observed it pass.`,
    `Flip CHECKLIST-STATUS to complete only when every Phase 1 to 4 item is ticked AND no Discovered item has Blocking: yes.`,
    `Report via StructuredOutput: changed_files (every file you created or modified, repository-relative, the checklist included) and report (items ticked, Discovered items appended with their blocking flags, and each gate's outcome).`,
  ].filter(Boolean).join('\n'),
  {
    agentType: 'plan-implementer',
    label: `implement`,
    phase: 'Implement',
    schema: IMPLEMENTER_SCHEMA,
  },
)

// An implementer that died or aborted produced nothing a reviewer could check,
// and the script knows it here: spawning the reviewer would burn an agent to
// report every criterion unmet.
if (implementation === null) {
  return {
    status: STATUS.IMPLEMENTATION_FAILED,
    planPath,
    checklistPath,
    roundsRun,
    trialBranch: effectiveTrialBranch,
    note: 'The implementer returned no result: it aborted on a precondition or died. Read the checklist for what was ticked, then re-run the implementation or the workflow.',
  }
}

// ---- phase 9: acceptance -------------------------------------------------

phase('Accept')

// The reviewer judges the result against the request without the plan's
// framing, so nothing under plans/ reaches it except the path it writes.
const reviewFiles = (implementation.changed_files ?? [])
  .map(normalisePath)
  .filter(p => !p.startsWith('plans/'))
const acceptance = await agent(
  [
    `Request, verbatim:`,
    request,
    ``,
    `Acceptance criteria, verbatim:`,
    ...requirements.acceptance_criteria.map(c => `- ${c}`),
    ``,
    `Base commit: ${baseRef}`,
    `Files the implementer reports it changed:`,
    ...(reviewFiles.length > 0 ? reviewFiles.map(p => `- ${p}`) : [`(none)`]),
    ``,
    `Write your acceptance document to ${acceptancePath}. Read nothing else under plans/.`,
    `Read each file above in full. For each one git tracks, run git diff ${baseRef} -- <file>. Run the tests the criteria name.`,
    `In the document, quote each criterion and mark it met, partial or unmet with the evidence you observed: the test you ran or the file:line you read. Then list your findings about the code.`,
    `Report via StructuredOutput: criteria (one per criterion, with status and evidence) and findings.`,
  ].join('\n'),
  {
    agentType: 'acceptance-reviewer',
    label: `accept`,
    phase: 'Accept',
    schema: ACCEPTANCE_SCHEMA,
  },
)

const base = {
  module: moduleKey,
  planPath,
  checklistPath,
  auditPath,
  acceptancePath,
  trialBranch: effectiveTrialBranch,
  roundsRun,
  freshAnglesRun: FRESH_POOL.slice(0, freshUsed).map(l => l.key),
  trial,
  implementation,
  nonblockingDiscoveries: checklist.nonblocking_discoveries ?? [],
}

if (acceptance === null) {
  return {
    status: STATUS.ACCEPTANCE_FAILED,
    ...base,
    note: 'The acceptance reviewer returned no result. Re-run the review; the implementation is in place.',
  }
}

const allMet = acceptance.criteria.length > 0 && acceptance.criteria.every(c => c.status === 'met')
const serious = acceptance.findings.filter(f => FAILING_SEVERITIES.includes(f.severity))
return {
  status: allMet && serious.length === 0 ? STATUS.ACCEPTED : STATUS.ACCEPTANCE_GAPS,
  ...base,
  acceptance,
  note: allMet && serious.length === 0
    ? 'Every acceptance criterion is met and the reviewer raised no blocking or major finding.'
    : 'Gaps remain: fix them by hand, or start a successor run through feature-start with them as its requirements.',
}
