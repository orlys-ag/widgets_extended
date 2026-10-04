export const meta = {
  name: 'feature-implementation',
  description: 'Plan, decision-level critique by the standard lenses, revise with re-ranking, fresh angle, kept trial, approve, checklist, implement, blind acceptance review. Bounded rounds; every lens must report.',
  whenToUse: 'When a feature or bugfix should be designed and built end to end with adversarial review, a kept trial and a blind acceptance review. Use the feature-start skill to build the args: slug, date, requirements, profile, request and baseRef.',
  phases: [
    { title: 'Plan', detail: 'Draft the plan document from the requirements, or revise it from priorFindings.' },
    { title: 'Critique', detail: 'The standard lenses in parallel, at decision level; after a revision, the lenses plans/AUDIT-METHOD.md section 4 names.' },
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
  APPROVAL_FAILED: 'approval-failed',
  IMPLEMENTATION_STOPPED: 'implementation-stopped',
})

// The phases a run moves through, in order. A run starts at the first, or
// where the state it resumes from says; every result's state names the phase
// the next run starts at, and `done` ends the feature.
const PHASES = ['draft', 'revise', 'critique', 'trial', 'approve', 'checklist', 'implement', 'accept', 'done']
const RESUMABLE = PHASES.filter(p => p !== 'done')
const STATE_VERSION = 1
const DEFAULT_ROUNDS = 4

// The phases each status may hand the next run. end() refuses any other, and
// the contracts document's resume table must list exactly these.
const NEXT_PHASES = Object.freeze({
  [STATUS.DRAFT_FAILED]: ['draft'],
  [STATUS.DRAFT_ABORTED]: ['revise'],
  [STATUS.COVERAGE]: ['critique'],
  [STATUS.FRESH_EXHAUSTED]: ['trial'],
  [STATUS.NEEDS_SCOPE]: ['revise'],
  [STATUS.BLOCKED]: ['revise'],
  [STATUS.TRIAL_FAILED]: ['revise', 'trial'],
  [STATUS.APPROVAL_FAILED]: ['approve'],
  [STATUS.CHECKLIST_FAILED]: ['checklist'],
  [STATUS.CHECKLIST_MALFORMED]: ['checklist'],
  [STATUS.CHECKLIST_BLOCKED]: ['revise'],
  [STATUS.IMPLEMENTATION_FAILED]: ['implement'],
  [STATUS.IMPLEMENTATION_STOPPED]: ['revise', 'implement'],
  [STATUS.ACCEPTANCE_FAILED]: ['accept'],
  [STATUS.ACCEPTED]: ['done'],
  [STATUS.ACCEPTANCE_GAPS]: ['done'],
})

// The run record feature-start writes at a slug's first launch, before any
// result exists. Every other run record is a result's full state.
const INITIAL_RECORD_KEYS = ['baseRef', 'phase', 'version']

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
    focus: 'Angles 1, 8 and 9 of the angle list in plans/AUDIT-METHOD.md section 1. Will each decision do what the goals say? Logical gaps where something reads state nothing writes, ordering violations, re-entrancy. Lifecycle: creation, teardown, and every site that destroys the thing. Degradation: what happens when a precondition is not met, on empty and single-element cases. Judge at decision level: an edge case or a missing test is kind implementation.',
  },
  performance: {
    stage: 'standard',
    ranking: true,
    focus: 'Angle 10 of the angle list in plans/AUDIT-METHOD.md section 1. What is O(what), and is the stated bound the one that can blow up? Anything that turns a targeted lookup into a full scan, and allocation on a hot path. Does each measured or computed evidence cell in a decision table support its rank, and does each counted contract name its check and expected value?',
  },
  design: {
    stage: 'standard',
    ranking: true,
    requirements: true,
    focus: 'Angles 2, 3, 4, 6 and 7 of the angle list in plans/AUDIT-METHOD.md section 1, at decision level. Interfaces: signatures, types, naming, exports, and every consumer of a changed interface verified per plans/AUDIT-METHOD.md section 8 (derive, check in code, read; a search only locates). Contracts: does the plan contradict a document it depends on, or change a documented contract without saying so? Citations and claims: run python plans/check_citations.py on the plan (a non-zero exit is itself a finding) and read that the cited lines say what the plan says; every count carries its command, and every because, only, never and exactly carries its own citation. Decisions: does each table follow the ranking rule, is a valid option missing, does each evidence cell support its rank? Requirements: is each acceptance criterion traced to a named check, and can each named check fail in the direction it claims? Is each new test seam justified against an existing one? Scope: is a requirement missing, ambiguous or in conflict (kind scope)? Guidance: does the plan change a guidance document only to state an invariant it adds or alters?',
  },
  interaction: {
    stage: 'fresh',
    focus: 'The interaction lens of plans/AUDIT-METHOD.md section 4: the feature crossed with every other component, layer and entry point. Look for the crossings the plan does not mention AT ALL rather than the ones it handles badly. A crossing whose handling would change a decision is kind rank or surface; otherwise it is implementation.',
  },
  timing: {
    stage: 'fresh',
    focus: 'The timing lens of plans/AUDIT-METHOD.md section 4: behaviour under real timing. The correctness lens already swept ordering and re-entrancy as design questions, so do NOT repeat that. Ask instead which of this plan\'s timing risks only running the code can close, and whether the plan turns each one into a named test rather than prose that argues it is fine. Name every timing risk the plan settles by assertion instead of by a test.',
  },
  consistency: {
    stage: 'consistency',
    focus: 'The revision that just happened, checked for self-inflicted damage, and against the obligations plans/AUDIT-METHOD.md section 5 gives it. Diff the revision snapshot against the plan. Read the summary sections specifically: overview, landing order, testing plan, and any decisions list, since those are where staleness collects; read every section that used the vocabulary the revision replaced. Cross-references must resolve, numbering must be contiguous, and each fact must have exactly one normative site. You are also the guard for the lenses that were NOT re-run this round, and for the obligations the revision was given. History or defensive prose the revision added to the plan breaks plans/AUDIT-METHOD.md rule 2.6.',
  },
}
const LENS_KEYS = Object.keys(LENS_DEFINITIONS)
const STANDARD_KEYS = LENS_KEYS.filter(k => LENS_DEFINITIONS[k].stage === 'standard')
const FRESH_KEYS = LENS_KEYS.filter(k => LENS_DEFINITIONS[k].stage === 'fresh')
const CONSISTENCY_KEY = 'consistency'

const TRIAL_REQUIRED = ['section', 'branch', 'repro_failed_before', 'repro_passes_after', 'gates', 'commit', 'notes', 'blocking_findings']
// The trial result's fields its Trial Log record carries: everything the
// script's pass decision reads, so a reader of the log can tell the outcome.
const TRIAL_LOG_FIELDS = TRIAL_REQUIRED.filter(f => f !== 'notes')
const IMPLEMENTER_REQUIRED = ['changed_files', 'report', 'branch', 'commit', 'complete', 'blocking_discoveries']
const APPROVE_REQUIRED = ['stamped']
const ACCEPTANCE_REQUIRED = ['criteria', 'findings']
const REVISE_REQUIRED = ['changed_decisions', 'snapshot']
const PROFILE_KEYS = ['codePaths', 'conventionDocs', 'methodFiles', 'gates', 'modules', 'lenses', 'defectClasses', 'ranking', 'hotPaths', 'citations', 'planRules']
// The requirement fields every run carries; `decisions` is optional.
const REQUIRED_FIELDS = ['summary', 'user_visible_behavior', 'acceptance_criteria', 'modules_touched', 'constraints', 'non_goals', 'open_questions']
// Every argument the script reads. An unknown name is a caller's typo, which
// would otherwise fall back to a default with no message anywhere.
const ARG_NAMES = ['slug', 'date', 'request', 'baseRef', 'profile', 'requirements', 'module', 'maxRounds', 'trial', 'priorFindings', 'resume', 'start', 'ownerApproval', 'killed']
const REQUIRED_ARGS = ['slug', 'date', 'request', 'baseRef', 'profile', 'requirements']

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
    trialLogFields: TRIAL_LOG_FIELDS,
    nextPhases: NEXT_PHASES,
    implementerFields: IMPLEMENTER_REQUIRED,
    acceptanceFields: ACCEPTANCE_REQUIRED,
    reviseFields: REVISE_REQUIRED,
    approveFields: APPROVE_REQUIRED,
    profileKeys: PROFILE_KEYS,
    phases: PHASES,
    argNames: ARG_NAMES,
    requiredArgs: REQUIRED_ARGS,
    requirementFields: [...REQUIRED_FIELDS, 'decisions'],
    defaultRounds: DEFAULT_ROUNDS,
  }
}

if (argsObj && typeof argsObj === 'object') {
  const unknown = Object.keys(argsObj).filter(k => !ARG_NAMES.includes(k))
  if (unknown.length > 0) {
    throw new Error(`Unknown args: ${unknown.join(', ')}. The workflow reads ${ARG_NAMES.join(', ')}.`)
  }
}
const absentArgs = REQUIRED_ARGS.filter(k => argsObj?.[k] === undefined)
if (absentArgs.length > 0) {
  throw new Error(`feature-implementation requires args ${absentArgs.join(', ')}; the feature-start skill builds them.`)
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

// The caller supplies the date: a workflow script cannot call argless
// `new Date()`, `Date.now()` or `Math.random()`, so that a resumed run replays
// identically. `feature-start` passes it.
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
  for (const k of ['conventionDocs', 'defectClasses', 'planRules']) {
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
    if (!m || !isStringArray(m.paths, false) || !isStringArray(m.guidance, false) || typeof m.vocabulary !== 'string') {
      fail(`.modules.${key} needs paths, guidance and vocabulary`)
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

// The module decides which architecture rules the architect, the critics
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
const GUIDANCE = MODULE.guidance.join(', ')

const planPath = `plans/${date}-${slug}-plan.md`
const checklistPath = `plans/${date}-${slug}-checklist.md`
const auditPath = `plans/${date}-${slug}-audit.md`
const acceptancePath = `plans/${date}-${slug}-acceptance.md`
const trialBranch = `${slug}-trial`

// Both optional knobs are validated rather than coerced: a quoted number or a
// quoted boolean would otherwise select the default silently.
if (argsObj?.maxRounds !== undefined && !Number.isInteger(argsObj.maxRounds)) {
  throw new Error(`args.maxRounds must be an integer, got ${JSON.stringify(argsObj.maxRounds)}. A quoted number is not one, and would silently fall back to ${DEFAULT_ROUNDS}.`)
}
if (argsObj?.trial !== undefined && typeof argsObj.trial !== 'boolean') {
  throw new Error(`args.trial must be a boolean, got ${JSON.stringify(argsObj.trial)}. Any non-boolean is treated as true, so "false" would run the trial.`)
}
const MAX_ROUNDS = Number.isInteger(argsObj?.maxRounds) ? argsObj.maxRounds : DEFAULT_ROUNDS
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

// The run record: the state the last result returned, which feature-start keeps
// at plans/<date>-<slug>-run.json and passes back. It carries what a run would
// otherwise lose: the round count, the spent fresh angles, the loop history,
// the findings no architect step has received, the carried implementation
// findings and the workflow branch.
const resume = argsObj?.resume ?? null
const STATE_ARRAYS = ['freshSpent', 'reranked', 'mechanizeIssued', 'pendingMechanize', 'pendingRerank', 'lastReceived', 'received', 'revise', 'carried', 'previousBranches', 'changedFiles']
const STATE_MAPS = ['rankFailRounds', 'failRounds', 'classRounds']
const initialRecord = resume !== null && typeof resume === 'object' && !Array.isArray(resume)
  && Object.keys(resume).sort().join(',') === INITIAL_RECORD_KEYS.join(',')
if (resume !== null) {
  const fail = msg => { throw new Error(`args.resume ${msg}. Pass the run record, as feature-start does.`) }
  if (typeof resume !== 'object' || Array.isArray(resume)) {
    fail('must be an object')
  }
  if (resume.version !== STATE_VERSION) {
    fail(`has version ${JSON.stringify(resume.version)}, expected ${STATE_VERSION}`)
  }
  if (!RESUMABLE.includes(resume.phase)) {
    fail(`.phase must be one of ${RESUMABLE.join(', ')}, got ${JSON.stringify(resume.phase)}`)
  }
  if (resume.baseRef !== baseRef) {
    fail(`.baseRef ${JSON.stringify(resume.baseRef)} is not args.baseRef ${JSON.stringify(baseRef)}`)
  }
  if (initialRecord && resume.phase !== 'draft') {
    fail(`is an initial record, whose phase is draft, not ${JSON.stringify(resume.phase)}`)
  }
}
if (resume !== null && !initialRecord) {
  const fail = msg => { throw new Error(`args.resume ${msg}. Pass the run record, as feature-start does.`) }
  if (!Number.isInteger(resume.roundsRun) || resume.roundsRun < 0) {
    fail('.roundsRun must be a non-negative integer')
  }
  for (const k of STATE_ARRAYS) {
    if (!Array.isArray(resume[k])) {
      fail(`.${k} must be an array`)
    }
  }
  for (const k of STATE_MAPS) {
    const m = resume[k]
    if (!m || typeof m !== 'object' || Object.values(m).some(v => !Array.isArray(v) || !v.every(Number.isInteger))) {
      fail(`.${k} must map each key to round numbers`)
    }
  }
  if (resume.freshSpent.some(k => !FRESH_KEYS.includes(k))) {
    fail(`.freshSpent may hold only ${FRESH_KEYS.join(', ')}`)
  }
  const roundKeys = [...STANDARD_KEYS, CONSISTENCY_KEY]
  if (resume.pendingLenses !== null && (!Array.isArray(resume.pendingLenses) || resume.pendingLenses.length === 0
    || resume.pendingLenses.some(k => !roundKeys.includes(k)))) {
    fail(`.pendingLenses must be null or a non-empty array of ${roundKeys.join(', ')}`)
  }
  if (resume.clearedFresh !== null && !FRESH_KEYS.includes(resume.clearedFresh)) {
    fail(`.clearedFresh must be null or one of ${FRESH_KEYS.join(', ')}`)
  }
  for (const k of ['branch', 'trialCommit']) {
    if (resume[k] !== null && typeof resume[k] !== 'string') {
      fail(`.${k} must be a string or null`)
    }
  }
  if (resume.lastRevision !== null && (typeof resume.lastRevision !== 'object' || !Array.isArray(resume.lastRevision.changed_decisions))) {
    fail('.lastRevision must be null or a revision record')
  }
  const o = resume.lastObligations
  if (!o || !Array.isArray(o.rerank) || !Array.isArray(o.mechanize)) {
    fail('.lastObligations must hold rerank and mechanize arrays')
  }
  resume.revise.forEach((f, i) => {
    if (!f || typeof f !== 'object' || BASE_FIELDS.some(k => typeof f[k] !== 'string' || f[k].length === 0)) {
      fail(`.revise[${i}] must carry ${BASE_FIELDS.join(', ')}`)
    }
  })
}

// Where this run starts: the resumed state's phase, or the owner's choice of
// another, or the revision when only priorFindings are given.
if (argsObj?.start !== undefined) {
  if (resume === null) {
    throw new Error('args.start needs args.resume: a run starts past the draft only from its run record.')
  }
  if (!RESUMABLE.includes(argsObj.start)) {
    throw new Error(`args.start must be one of ${RESUMABLE.join(', ')}, got ${JSON.stringify(argsObj.start)}`)
  }
}
const START = resume !== null ? (argsObj.start ?? resume.phase) : priorFindings.length > 0 ? 'revise' : 'draft'
if (priorFindings.length > 0 && START !== 'revise') {
  throw new Error(`args.priorFindings go to a revision, but this run starts at ${START}. Pass start: "revise" with them.`)
}
// Queued revision findings, and failing findings no architect step has
// received, reach an agent only through a revision.
if (resume !== null && PHASES.indexOf(START) > PHASES.indexOf('revise')) {
  const owed = (resume.revise ?? []).length + (resume.received ?? []).filter(isFailing).length
  if (owed > 0) {
    throw new Error(`args.start ${START} would skip ${owed} finding(s) the next revision must receive. Start at revise.`)
  }
}
// A run that starts past the critique without a fresh angle that cleared needs
// the owner's stated basis (plans/AUDIT-METHOD.md section 6).
const ownerApproval = argsObj?.ownerApproval
if (PHASES.indexOf(START) > PHASES.indexOf('critique') && !resume?.clearedFresh
  && (typeof ownerApproval !== 'string' || ownerApproval.trim().length === 0)) {
  throw new Error(`args.ownerApproval is required to start at ${START}: no fresh angle has cleared this version of the plan, so the owner states why it is approved.`)
}
// A run killed before it returned left no state, so the record is older than
// what it did. Resumed from that record, it would dispatch a fresh angle the
// killed run may already have opened, and count a second pass as a first.
if (argsObj?.killed !== undefined && typeof argsObj.killed !== 'boolean') {
  throw new Error(`args.killed must be a boolean, got ${JSON.stringify(argsObj.killed)}.`)
}
const killed = argsObj?.killed === true
if (killed && resume === null) {
  throw new Error('args.killed needs args.resume: a killed run resumes from its run record.')
}

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
// The project's rules for a plan: the architect writes to them, and the design
// lens checks them.
const planRulesBlock = profile.planRules.length > 0
  ? `Project plan rules, which the plan must meet:\n${profile.planRules.map(r => `- ${r}`).join('\n')}`
  : ``
const conventionsLine = `House conventions, read before writing code or tests: ${profile.conventionDocs.join(', ')}.`

// ---- lenses --------------------------------------------------------------

function readsFor(key) {
  const expanded = profile.lenses[key].reads.flatMap(r =>
    r === 'moduleGuidance' ? MODULE.guidance : r === 'conventionDocs' ? profile.conventionDocs : [r])
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
    branch: { type: 'string' },
    commit: { type: 'string' },
    complete: { type: 'boolean' },
    blocking_discoveries: { type: 'array', items: BASE_FINDING },
  },
}

const APPROVE_SCHEMA = {
  type: 'object',
  required: APPROVE_REQUIRED,
  additionalProperties: false,
  properties: {
    stamped: { type: 'boolean' },
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

// The loop state survives between runs in the run record, which feature-start
// keeps at plans/<date>-<slug>-run.json and passes back as args.resume. Every
// result carries the state the next run starts from.
const S = resume ?? {}
const mapOfSets = o => new Map(Object.entries(o ?? {}).map(([k, v]) => [k, new Set(v)]))
const plain = m => Object.fromEntries([...m].map(([k, v]) => [k, [...v].sort((a, b) => a - b)]))

// Every finding raised since the last architect step. The next revision or
// the approval step receives all of them and records each in the audit file.
// A run that ends before an architect step carries them in its state to the
// next run's first one, and returns them as unrecordedFindings.
let received = [...(S.received ?? [])]
// Findings from outside the critics that the next revision receives: a
// trial's, the checklist's or the implementer's blocking findings.
let pendingRevise = [...(S.revise ?? [])]
// Every implementation finding of the plan's audit, for the checklist.
const implementationFindings = [...(S.carried ?? [])]
// Rounds in which each decision had a failing rank finding (R1), and in which
// any failing finding named it (the diagnosis of a spent budget).
const rankFailRounds = mapOfSets(S.rankFailRounds)
const failRounds = mapOfSets(S.failRounds)
const reranked = new Set(S.reranked ?? [])
// Rounds in which each profile defect class was found, at any severity (R3).
const classRounds = mapOfSets(S.classRounds)
const mechanizeIssued = new Set(S.mechanizeIssued ?? [])
let pendingMechanize = [...(S.pendingMechanize ?? [])]
// R1 obligations of a round that no revision followed in the same run.
let pendingRerank = [...(S.pendingRerank ?? [])]
// What the last revision reported, and what it was given: the consistency
// lens of the next round checks the revision against both.
let lastRevision = S.lastRevision ?? null
let lastReceived = S.lastReceived ?? []
let lastObligations = S.lastObligations ?? { rerank: [], mechanize: [] }
let roundsRun = S.roundsRun ?? 0
// The fresh angles already run on this plan, in any run. Each is spent once.
const freshSpent = [...(S.freshSpent ?? [])]
let clearedFreshLens = S.clearedFresh ?? null
// After a kill, the angle the killed run would have opened next counts as
// spent whenever this run can reach the critique, opened or not.
if (killed && PHASES.indexOf(START) <= PHASES.indexOf('critique')) {
  const maybeOpened = FRESH_POOL.find(l => !freshSpent.includes(l.key))
  if (maybeOpened) {
    freshSpent.push(maybeOpened.key)
    log(`Resuming after a kill: the fresh angle ${maybeOpened.key} counts as spent.`)
  }
}
// The lenses of a round a coverage failure cut short, which the next run
// dispatches again.
let pendingLenses = S.pendingLenses ?? null
// The branch the run's commits are on, the trial's commit, the branches an
// earlier revision retired, and every file an implementer reported changing.
let workflowBranch = S.branch ?? null
let trialCommit = S.trialCommit ?? null
const previousBranches = [...(S.previousBranches ?? [])]
let changedFiles = [...(S.changedFiles ?? [])]

function exportState(next) {
  return {
    version: STATE_VERSION,
    phase: next,
    baseRef,
    roundsRun,
    freshSpent: [...freshSpent],
    clearedFresh: clearedFreshLens,
    pendingLenses,
    rankFailRounds: plain(rankFailRounds),
    failRounds: plain(failRounds),
    reranked: [...reranked],
    classRounds: plain(classRounds),
    mechanizeIssued: [...mechanizeIssued],
    pendingMechanize: [...pendingMechanize],
    pendingRerank: [...pendingRerank],
    lastRevision,
    lastReceived,
    lastObligations,
    received,
    revise: pendingRevise,
    carried: implementationFindings,
    branch: workflowBranch,
    trialCommit,
    previousBranches: [...previousBranches],
    changedFiles: [...changedFiles],
  }
}

// Every result: its status, its fields, and the state whose phase is where the
// next run starts.
function end(status, next, fields) {
  if (!NEXT_PHASES[status]?.includes(next)) {
    throw new Error(`${status} cannot start the next run at ${next}; NEXT_PHASES allows ${NEXT_PHASES[status]?.join(', ')}`)
  }
  return { status, ...fields, state: exportState(next) }
}

function isFailing(f) {
  return FAILING_SEVERITIES.includes(f.severity) && FAILING_KINDS.includes(f.kind)
}

function addRound(map, key, round) {
  if (!map.has(key)) {
    map.set(key, new Set())
  }
  map.get(key).add(round)
}

function normalisePath(p) {
  return p.split(String.fromCharCode(92)).join('/')
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
    lens.requirements ? `Requirements, which this lens traces and scopes against:` : ``,
    lens.requirements ? requirementsMarkdown : ``,
    lens.requirements ? planRulesBlock : ``,
    withConsistency ? consistencyContext() : ``,
    ``,
    `Give each finding a decision (a d<N> anchor from the plan's Decisions section, or none), a kind (${KINDS.join(', ')}) and a defect_class (${[...profile.defectClasses, 'other'].join(', ')}).`,
    lens.reads.length > 0 ? `Also read: ${lens.reads.join(', ')}.` : ``,
    `Report via StructuredOutput.`,
  ].filter(Boolean).join('\n')
}

// A lens that returns no result, or reports that it could not review, is
// dispatched once more in the same round. A lens that still cannot review
// ends the run: a round cannot be called clean on an angle nobody swept.
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
// object this scope DISPATCHED, not the `lens` string the critic reported, so
// a model-side spelling of a lens key cannot drop it from the re-critique set.
function critiqueRound(lenses, phaseTitle, round) {
  return parallel(lenses.map(l => () => runLens(l, phaseTitle, round, l.key === CONSISTENCY_KEY)))
}

function collect(critiques, round, stage) {
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

// A revision changes the plan, so the evidence about an earlier version no
// longer stands: the workflow branch is retired, the next trial or
// implementation branches from the base commit, and no fresh angle has cleared
// the new version.
async function revise(findings, round, note, obligations) {
  phase('Revise')
  retireBranch()
  clearedFreshLens = null
  const result = await agent(
    [
      `Mode: revision (round ${round}).`,
      `Existing plan path: ${planPath}`,
      `Audit file: ${auditPath}`,
      `Module: ${moduleKey}; its architecture rules are ${GUIDANCE}.`,
      note ? `Context: ${note}` : ``,
      rankingLine,
      ``,
      `Requirements, as the owner last settled them; the revised plan must meet them:`,
      requirementsMarkdown,
      planRulesBlock,
      ``,
      `If the plan's first non-empty line is <!-- PLAN-STATUS: ready-to-implement -->, first replace it with <!-- PLAN-STATUS: draft -->: a revision reopens an approved plan. Change PLAN-STATUS in no other way.`,
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
        ? `These defect classes recurred in two rounds: ${obligations.mechanize.join(', ')}. Add a check for each, preferring a code check per plans/AUDIT-METHOD.md section 8 (derive, check in code, read; a search only locates), and name it in your record.`
        : ``,
      `A fix rewrites the sentence that was wrong; it never appends a note, and the plan never says what it used to say (plans/AUDIT-METHOD.md rule 2.6).`,
      `Append a "## Round ${round - 1}" record to ${auditPath}, creating the file with a one-line title if it does not exist: one line per finding received, giving its id, lens, kind, severity and outcome (fixed, naming the section; re-ranked; rejected, with the evidence; carried; or left open, with the reason). No other prose.`,
      `Run the consistency pass: write down the vocabulary you replaced and read every section that used it. Then run python plans/check_citations.py ${planPath} --rebase, naming with --accept each CHANGED citation whose claim you re-read and kept at its number; it must exit 0.`,
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
  // A dead reviser leaves the plan as the critics found it, so the next round
  // re-raises the same findings and the obligations stay owed. With no result
  // there is no snapshot and no changed_decisions: the next consistency prompt
  // says so, and R1's second clause cannot fire.
  if (result === null) {
    log(`Round ${round} revision returned no result: the plan is unchanged, so the next round will re-raise the same findings.`)
    lastRevision = null
    pendingRerank = [...new Set([...pendingRerank, ...obligations.rerank])]
    pendingMechanize = [...new Set([...pendingMechanize, ...obligations.mechanize])]
    return
  }
  for (const d of obligations.rerank) {
    reranked.add(d)
  }
  for (const c of obligations.mechanize) {
    mechanizeIssued.add(c)
  }
  lastRevision = { round, changed_decisions: result.changed_decisions, snapshot: result.snapshot }
}

function retireBranch() {
  if (workflowBranch) {
    previousBranches.push(workflowBranch)
    workflowBranch = null
    trialCommit = null
  }
}

function takeObligations(rerank) {
  const merged = [...new Set([...pendingRerank, ...rerank])]
  pendingRerank = []
  const mechanize = pendingMechanize
  pendingMechanize = []
  return { rerank: merged, mechanize }
}

const reaches = p => PHASES.indexOf(START) <= PHASES.indexOf(p)

// ---- phase 1: draft, or the revision a resumed run opens with --------------

phase('Plan')

let openedWithRevision = false
if (START === 'draft') {
  const draft = await agent(
    [
      `Mode: initial draft.`,
      `Feature slug: ${slug}`,
      `Module: ${moduleKey}. The architecture rules for this plan are ${GUIDANCE}; read them instead of another module's. ${MODULE.vocabulary}`,
      `Output plan path: ${planPath}`,
      `Audit file: ${auditPath}`,
      ``,
      // This scope has no filesystem access, so it cannot check for a collision
      // itself, and the architect's system prompt permits Write in this mode.
      `FIRST, check whether ${planPath} already exists. If it does, emit "ABORT: plan already exists at ${planPath}" and write nothing. Do not Write over it and do not silently switch to revision mode: a re-run against an existing plan is a caller mistake, and the caller resumes from the run record when a revision is what they wanted.`,
      ``,
      `Requirements:`,
      requirementsMarkdown,
      planRulesBlock,
      ``,
      rankingLine,
      `Write the plan with PLAN-STATUS: draft and every required section from doc/agents/feature-workflow-contracts.md section 3, each followed by its anchor. Every architecture, performance or algorithm choice goes in the Decisions section as a ranking table, per plans/AUDIT-METHOD.md. Write the design, not its history (rule 2.6): concise, final-state, nothing an implementer or reviewer does not need.`,
      `Map every Acceptance Criteria item to a concrete check in the Testing Plan, and resolve every Open Question in the body unless it genuinely needs a user decision.`,
      `Create the audit file ${auditPath} with a one-line title if it does not exist.`,
      `Stamp the citations with python plans/check_citations.py ${planPath} --stamp; it must exit 0.`,
    ].join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:draft`,
      phase: 'Plan',
    },
  )
  // agent() resolves to null when the subagent dies on a terminal error, and
  // nothing downstream can run against a plan that may hold nothing.
  if (draft === null) {
    return end(STATUS.DRAFT_FAILED, 'draft', {
      planPath,
      note: 'The architect returned no result, so the plan may not exist or may be partial. Delete a partial plan and resume to draft again; if it fails again the requirements are the place to look.',
    })
  }
  if (typeof draft === 'string' && /^\s*ABORT:/m.test(draft)) {
    return end(STATUS.DRAFT_ABORTED, 'revise', {
      planPath,
      note: `The architect refused to draft: ${draft.trim().slice(0, 300)}`,
    })
  }
  log(`Draft written to ${planPath}`)
} else if (START === 'revise') {
  const findings = [...received, ...pendingRevise, ...priorFindings]
  received = []
  pendingRevise = []
  log(`Resuming at the revision with ${findings.length} finding(s).`)
  await revise(findings, roundsRun + 1, 'These came from an earlier run or from the owner: critics, a trial, the checklist, the implementer or an acceptance review.', takeObligations([]))
  openedWithRevision = true
}

// ---- phases 2 to 4: critique, revise, fresh angle -------------------------

// A run that starts past the critique runs on a plan an earlier run approved,
// or that the owner approved (args.ownerApproval).
let approved = !reaches('critique')

// The whole round is dispatched again, so its findings so far are dropped
// rather than received twice, and so is what the loop rules recorded from them:
// a fresh round's coverage failure follows its standard half's applyRules.
function coverageReturn(round, stage, critiques, lenses) {
  roundsRun = round - 1
  pendingLenses = lenses.map(l => l.key)
  received = received.filter(f => f.round !== round)
  for (let i = implementationFindings.length - 1; i >= 0; i--) {
    if (implementationFindings[i].round === round) {
      implementationFindings.splice(i, 1)
    }
  }
  for (const map of [classRounds, failRounds, rankFailRounds]) {
    for (const [key, rounds] of map) {
      rounds.delete(round)
      if (rounds.size === 0) {
        map.delete(key)
      }
    }
  }
  pendingMechanize = pendingMechanize.filter(c => (classRounds.get(c)?.size ?? 0) >= 2)
  return end(STATUS.COVERAGE, 'critique', {
    planPath,
    auditPath,
    round,
    stage,
    lensesPresent: critiques.filter(c => c.reported).map(c => c.lens.key),
    lensesMissing: critiques.filter(c => !c.reported).map(c => c.lens.key),
    unrecordedFindings: received,
    note: `A lens could not review on two attempts, so this round has an unswept angle and cannot be called clean. This is an infrastructure failure or a missing input, not a plan defect. Resume to dispatch the round again with all its lenses; the findings of this attempt are discarded.`,
  })
}

function scopeReturn(round, flat, rerank) {
  pendingRerank = [...new Set([...pendingRerank, ...rerank])]
  return end(STATUS.NEEDS_SCOPE, 'revise', {
    planPath,
    auditPath,
    round,
    scopeFindings: flat.filter(f => isFailing(f) && f.kind === 'scope'),
    unrecordedFindings: received,
    note: 'A requirement is missing, ambiguous or in conflict. The owner settles it in the requirements, then resumes: the revision receives these findings and the settled requirements.',
  })
}

if (!approved) {
  // The first round sweeps every standard lens, plus the consistency lens when
  // a revision opened the run. Later rounds re-run the lenses that raised a
  // failing finding, plus the consistency lens. A lens that CLEARED a section
  // the revision did not touch has nothing new to say; the consistency lens
  // guards those sections.
  const byKey = k => (k === CONSISTENCY_KEY ? CONSISTENCY_LENS : STANDARD.find(l => l.key === k))
  let pending = pendingLenses ? pendingLenses.map(byKey).filter(Boolean) : [...STANDARD]
  if (openedWithRevision && !pending.includes(CONSISTENCY_LENS)) {
    pending.push(CONSISTENCY_LENS)
  }
  pendingLenses = null
  const firstRound = roundsRun + 1
  const lastRound = roundsRun + MAX_ROUNDS

  for (let round = firstRound; round <= lastRound; round++) {
    roundsRun = round

    phase('Critique')
    log(`Round ${round}: ${pending.length} lens(es) in parallel: ${pending.map(l => l.key).join(', ')}.`)

    const standard = await critiqueRound(pending, 'Critique', round)
    const standardFlat = collect(standard, round, 'standard')
    if (standard.some(c => !c.reported)) {
      return coverageReturn(round, 'standard', standard, pending)
    }
    const standardRerank = applyRules(round, standardFlat)
    const standardFailing = standardFlat.filter(isFailing)
    log(`Round ${round}: ${standardFailing.length} failing finding(s) across ${standard.length} lens(es).`)

    if (standardFailing.some(f => f.kind === 'scope')) {
      return scopeReturn(round, standardFlat, standardRerank)
    }

    if (standardFailing.length > 0) {
      if (round === lastRound) {
        pendingRerank = [...new Set([...pendingRerank, ...standardRerank])]
        log(`Hit the round budget (${MAX_ROUNDS}) with failing findings still open.`)
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
    // its own, so open an angle that has not run on this plan. Spent entries are
    // never reused: the rule is "empty on its FIRST pass".
    const freshLens = FRESH_POOL.find(l => !freshSpent.includes(l.key))
    if (!freshLens) {
      return end(STATUS.FRESH_EXHAUSTED, 'trial', {
        planPath,
        auditPath,
        roundsRun,
        freshAnglesUsed: [...freshSpent],
        unrecordedFindings: received,
        note: `The standard lenses are clean, but every fresh angle in the pool (${FRESH_POOL.map(l => l.key).join(', ')}) has already run on this plan. plans/AUDIT-METHOD.md section 6 approves on a freshly opened angle coming back clean on its FIRST pass, and re-running a spent one would measure the lens instead of the artifact. The plan is in draft. Approve it by resuming with args.ownerApproval stating the basis: an angle opened by hand that came back clean on its first pass, or section 6's yield rule. Findings from an angle opened by hand go to a revision first, as priorFindings.`,
      })
    }
    freshSpent.push(freshLens.key)

    phase('Fresh Angle')
    log(`Round ${round} clean. Opening fresh angle ${freshLens.key}.`)
    const fresh = await critiqueRound([freshLens], 'Fresh Angle', round)
    const freshFlat = collect(fresh, round, 'fresh')
    if (fresh.some(c => !c.reported)) {
      // An angle that could not review is not spent.
      freshSpent.pop()
      return coverageReturn(round, 'fresh', fresh, pending)
    }
    const freshRerank = applyRules(round, freshFlat)
    const freshFailing = freshFlat.filter(isFailing)
    log(`Round ${round} fresh angle: ${freshFailing.length} failing finding(s).`)

    if (freshFailing.some(f => f.kind === 'scope')) {
      return scopeReturn(round, freshFlat, freshRerank)
    }

    if (freshFailing.length > 0) {
      if (round === lastRound) {
        pendingRerank = [...new Set([...pendingRerank, ...freshRerank])]
        log(`Hit the round budget (${MAX_ROUNDS}) with failing findings open in the fresh-angle round.`)
        break
      }
      const findings = received
      received = []
      await revise(findings, round + 1, `Fresh-angle round (${freshLens.key}). These are findings on an angle the standard lenses never sweep, so treat them as first-pass findings on a new angle rather than as leftovers.`, takeObligations(freshRerank))
      pending = [CONSISTENCY_LENS]
      continue
    }

    approved = true
    clearedFreshLens = freshLens.key
    log(`Round ${round}: standard lenses and the fresh angle both clean. Plan is approvable.`)
    break
  }

  if (!approved) {
    return end(STATUS.BLOCKED, 'revise', {
      planPath,
      auditPath,
      roundsRun,
      diagnosis: diagnosis(),
      unrecordedFindings: received,
      note: 'The round budget ran out with failing findings open. The diagnosis lists each failing decision, the rounds it failed in, and whether R1 re-ranked it. Resuming revises with the last round\'s findings and a fresh budget; usually the requirements were underspecified.',
    })
  }
}

// ---- phase 5: trial ------------------------------------------------------

let trial = null
if (runTrial && reaches('trial')) {
  phase('Trial')
  retireBranch()
  trial = await agent(
    [
      `Mode: trial.`,
      `Apply plans/AUDIT-METHOD.md section 7 to the plan at ${planPath}.`,
      `Module: ${moduleKey}. The module contracts are in ${GUIDANCE}; read those, not another module's.`,
      conventionsLine,
      ``,
      `Gates, from the project profile. Run each whose condition applies, and report every one by name in gates, with applies and passed:`,
      ...gateLines,
      ``,
      `Procedure (doc/agents/feature-workflow-contracts.md section 9 gives the reasons):`,
      `1. Read the plan and pick its highest-risk section: the one whose failure would be hardest to detect by reading.`,
      `2. Run git status --porcelain -- ${profile.codePaths.join(' ')}. If anything there is modified, staged or untracked, stop: report every gate as not passed and say so in notes. Do not stash it: it is someone else's work, not a plan defect.`,
      `3. Create the branch ${trialBranch} from the base commit (git switch -c ${trialBranch} ${baseRef}), or ${trialBranch}-2, -3 when that name is taken (git rev-parse --verify --quiet). Report the name in branch.`,
      `4. Write the section's repro test first and confirm it fails on unfixed code; record the failure. A repro that passes before any change is a blocking finding.`,
      `5. Apply that section's change.`,
      `6. Run the repro again, then the gates above.`,
      `7. Commit on that branch whether or not the gates passed.`,
      `8. Run python plans/check_citations.py ${planPath}, without rebasing, and say in notes which citations it reports CHANGED: lines your change edited or removed, which is evidence about the plan.`,
      `9. Append a "## Trial Log" record to ${auditPath}, creating it with a one-line title if it does not exist, with these fields of your result: ${TRIAL_LOG_FIELDS.join(', ')}.`,
      ``,
      `A plan defect, as opposed to an implementation slip, goes in blocking_findings. Do not invent design to make a gate pass.`,
      `Report via StructuredOutput.`,
    ].join('\n'),
    {
      agentType: 'plan-implementer',
      label: `trial`,
      phase: 'Trial',
      schema: TRIAL_SCHEMA,
    },
  )

  // Every profile gate is reported exactly once by name, every one that
  // applies passed, and the trial found no plan defect. A missing name is a
  // gate nobody ran.
  const reported = trial?.gates ?? []
  const namesMatch = reported.length === GATE_NAMES.length
    && GATE_NAMES.every(n => reported.filter(g => g.name === n).length === 1)
  const passed = Boolean(trial)
    && trial.repro_failed_before
    && trial.repro_passes_after
    && namesMatch
    && reported.every(g => !g.applies || g.passed)
    && trial.blocking_findings.length === 0
  // Only a passing trial becomes the workflow branch. A failed one is kept as a
  // retired branch, so no later phase reads it as evidence or builds on it.
  if (!passed) {
    if (trial?.branch) {
      previousBranches.push(trial.branch)
    }
    pendingRevise = trial?.blocking_findings ?? []
    return end(STATUS.TRIAL_FAILED, pendingRevise.length > 0 ? 'revise' : 'trial', {
      planPath,
      auditPath,
      roundsRun,
      trial,
      trialBranch: trial?.branch ?? null,
      unrecordedFindings: received,
      note: trial === null
        ? 'The trial agent returned no result: it died or was skipped, possibly after switching branches. Restore the checkout (feature-start, "Restoring the checkout"), then resume to run the trial again.'
        : pendingRevise.length > 0
          ? 'The trial exposed plan defects, which go to the next revision with the run state. Resume to revise; the trial branch is kept, and the next trial branches from the base commit under a suffixed name.'
          : 'The trial did not pass its gates and reported no plan defect. Read its notes, then resume to run the trial again.',
    })
  }
  workflowBranch = trial.branch
  trialCommit = trial.commit
  log(`Trial passed on ${workflowBranch} at ${trialCommit}.`)
}

// ---- phase 6: approval stamp --------------------------------------------

if (reaches('approve')) {
  phase('Approve')
  const approvalFindings = received
  received = []
  const ranEarlier = freshSpent.filter(k => k !== clearedFreshLens)
  const approval = await agent(
    [
      `Mode: approval stamp.`,
      `Plan path: ${planPath}`,
      `Audit file: ${auditPath}`,
      ``,
      clearedFreshLens
        ? `The standard lenses returned no failing finding as of round ${roundsRun}, and the fresh angle "${clearedFreshLens}" came back clean on its FIRST pass.`
        : `The owner approved this version of the plan without a fresh angle the workflow saw clear, on this basis (plans/AUDIT-METHOD.md section 6): ${ownerApproval}. Record it, in those words, as the basis of the stamp.`,
      // Only the angle that cleared is called clean; the Approval block is the
      // one section written to justify the stamp.
      ranEarlier.length > 0
        ? `Fresh angles that ran on an earlier version of this plan, which a revision followed: ${ranEarlier.join(', ')}. Record them as such; do not describe them as clearing this version.`
        : ``,
      trialCommit ? `The trial passed all gates on branch ${workflowBranch} at ${trialCommit}.` : `No trial was run for this version of the plan.`,
      ``,
      `Findings received since the last revision, none of them failing. Append a "## Round ${roundsRun}" record to the audit file, creating it with a one-line title if it does not exist: one line per finding, giving its id, lens, kind, severity and outcome (carried for an implementation finding, otherwise left open with a reason):`,
      approvalFindings.length > 0 ? JSON.stringify(approvalFindings, null, 2) : `(none)`,
      ``,
      `In the plan, use Edit for both changes, never a full-file Write: flip PLAN-STATUS to ready-to-implement and append the Approval section per your system prompt. Change nothing else in the plan.`,
      ``,
      `Then run python plans/check_citations.py ${planPath} and record what it reports in the Approval block. A CHANGED citation there is an open finding; never rebase or edit the marker to clear it.`,
      `Report via StructuredOutput: stamped, true once the plan's first non-empty line reads <!-- PLAN-STATUS: ready-to-implement -->.`,
    ].filter(Boolean).join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:approve`,
      phase: 'Approve',
      schema: APPROVE_SCHEMA,
    },
  )
  if (!approval?.stamped) {
    received = approvalFindings.concat(received)
    return end(STATUS.APPROVAL_FAILED, 'approve', {
      planPath,
      auditPath,
      roundsRun,
      unrecordedFindings: received,
      note: 'The approval step returned no result or did not stamp the plan. Check the plan\'s status line, then resume to run the approval again; its findings are carried to it.',
    })
  }
}

// ---- phase 7: checklist --------------------------------------------------

let checklist = null
if (reaches('checklist')) {
  phase('Checklist')

  const outstandingMechanize = pendingMechanize
  checklist = await agent(
    [
      `Plan path: ${planPath}`,
      `Checklist path: ${checklistPath}`,
      `Module: ${moduleKey}.`,
      ``,
      `If a checklist already exists at the checklist path, rename it to the first free ${checklistPath.replace(/\.md$/, '')}.superseded-<n>.md before writing: a reopened plan keeps the record of what its last checklist ticked.`,
      `Verify the plan is ready-to-implement, then emit the grouped checklist per your system prompt and doc/agents/feature-workflow-contracts.md section 5.`,
      `Phase 4, in this order: one item per decision, a mutation when its code site, as its Decisions subsection names it, lies under ${profile.codePaths.join(', ')}, and otherwise the check plans/AUDIT-METHOD.md section 8 names for it; then one item per gate below whose condition applies.`,
      ...gateLines,
      `Carried implementation findings from the audit. Make each an item whose acceptance is a test shown to fail first, a mutation, or the check plans/AUDIT-METHOD.md section 8 names for a consumer. List one that no longer applies to the approved plan under Discovered with Blocking: no and the reason:`,
      implementationFindings.length > 0 ? JSON.stringify(implementationFindings, null, 2) : `(none)`,
      outstandingMechanize.length > 0
        ? `These defect classes recurred in two rounds and no revision followed to add a check: ${outstandingMechanize.join(', ')}. Add an item for each that adds one, preferring a code check.`
        : ``,
      `Report via StructuredOutput: checklist_path (the file you wrote), phase_counts (the items in each of Phase 1 to 4), blocking_discoveries (each Discovered item with Blocking: yes, with its title, plan_section and why) and nonblocking_discoveries (the titles of the others). The workflow reads only that value.`,
    ].filter(Boolean).join('\n'),
    {
      agentType: 'plan-checklist',
      label: `checklist`,
      phase: 'Checklist',
      schema: CHECKLIST_SCHEMA,
    },
  )

  // The implementer stops on four preconditions, and three of them are
  // knowable from here, so each is a return instead of a spawned implementer.

  // Precondition 2, checklist exists and pairs with the plan. No structured
  // result means the agent died or was skipped. The agent may report the path
  // absolute or with backslashes; a mismatch on the trailing segments is a
  // checklist written somewhere else, which the implementer would refuse on
  // its pairing check.
  const reportedChecklist = typeof checklist?.checklist_path === 'string'
    ? normalisePath(checklist.checklist_path)
    : null
  const checklistPathMatches = reportedChecklist !== null
    && (reportedChecklist === checklistPath || reportedChecklist.endsWith('/' + checklistPath))
  if (!checklist || !checklistPathMatches) {
    return end(STATUS.CHECKLIST_FAILED, 'checklist', {
      planPath,
      checklistPath,
      roundsRun,
      branch: workflowBranch,
      reportedChecklistPath: checklist?.checklist_path ?? null,
      note: checklist && typeof checklist.checklist_path === 'string'
        ? `The checklist agent wrote ${checklist.checklist_path}, not ${checklistPath}, and the implementer would refuse that pairing. Resume to run the checklist phase again.`
        : 'The checklist agent returned no structured result: it died or was skipped. Resume to run the checklist phase again.',
    })
  }

  // Precondition 4, no blocking Discovered items. Each goes to the next
  // revision as a finding. It is checked before the item count because the
  // checklist agent reports a failed precondition of its own as a blocking
  // discovery with no items.
  const checklistBlockers = checklist.blocking_discoveries ?? []
  if (checklistBlockers.length > 0) {
    pendingRevise = checklistBlockers.map((d, i) => ({
      id: `checklist-${i + 1}`,
      location: d.plan_section,
      severity: 'blocking',
      title: d.title,
      why: d.why,
      suggested_direction: 'Revise the plan so the checklist can derive this item.',
    }))
    return end(STATUS.CHECKLIST_BLOCKED, 'revise', {
      planPath,
      checklistPath,
      roundsRun,
      branch: workflowBranch,
      blockingDiscoveries: checklistBlockers,
      note: 'The checklist could not derive every item from the plan, or the plan failed a checklist precondition. Resume to revise: the gaps go to the architect as findings.',
    })
  }

  // Precondition 3, at least one unchecked item. Phase 4 always carries one
  // item per gate that always applies.
  const phase4Floor = profile.gates.filter(g => g.when === 'always').length
  const phaseCounts = checklist.phase_counts ?? {}
  const totalItems = ['phase1', 'phase2', 'phase3', 'phase4']
    .reduce((n, k) => n + (Number.isInteger(phaseCounts[k]) ? phaseCounts[k] : 0), 0)
  if (totalItems === 0 || (Number.isInteger(phaseCounts.phase4) && phaseCounts.phase4 < phase4Floor)) {
    return end(STATUS.CHECKLIST_MALFORMED, 'checklist', {
      planPath,
      checklistPath,
      roundsRun,
      branch: workflowBranch,
      phaseCounts,
      nonblockingDiscoveries: checklist.nonblocking_discoveries ?? [],
      note: `The checklist has ${totalItems} phase item(s) with ${phaseCounts.phase4 ?? 0} in Phase 4, below the ${phase4Floor} gates that always apply. Resume to run the checklist phase again; the plan is approved and unchanged.`,
    })
  }
}

// ---- phase 8: implement --------------------------------------------------

let implementation = null
if (reaches('implement')) {
  phase('Implement')

  // The branch is named before the implementer runs, so a run whose implementer
  // dies keeps it in its state and the next implementer continues on it. It is
  // the passing trial's branch, or the first implementation branch no earlier
  // version of the plan used.
  if (!workflowBranch) {
    let n = 1
    const name = k => (k === 1 ? `${slug}-impl` : `${slug}-impl-${k}`)
    while (previousBranches.includes(name(n))) {
      n += 1
    }
    workflowBranch = name(n)
  }
  implementation = await agent(
    [
      `Mode: checklist.`,
      `Plan path: ${planPath}`,
      `Checklist path: ${checklistPath}`,
      `Base commit: ${baseRef}`,
      `Module: ${moduleKey}. The module contracts are in ${GUIDANCE}; read those, not another module's.`,
      conventionsLine,
      `First run git status --porcelain -- ${profile.codePaths.join(' ')}. If anything there is modified, staged or untracked, stop without changing anything: set complete false and say so in report. It is someone else's work, not a plan defect.`,
      `Then work on branch ${workflowBranch}: git switch ${workflowBranch} when it exists, since it then holds this plan version's trial or earlier work, which you continue rather than duplicate or revert; otherwise git switch -c ${workflowBranch} ${baseRef}.`,
      previousBranches.length > 0
        ? `Earlier versions of this plan were trialed or implemented on ${previousBranches.join(', ')}. Reuse what still matches the plan; nothing there is authoritative.`
        : ``,
      ``,
      `Gates, from the project profile:`,
      ...gateLines,
      ``,
      `Execute the unticked checklist items in order. Flip CHECKLIST-STATUS to complete only when every Phase 1 to 4 item is ticked AND no Discovered item has Blocking: yes.`,
      `Commit each item's files on that branch when its acceptance signal passes, before you tick it, and commit any remaining change before you stop for any reason, staging every file you changed that git does not ignore. Confirming the run authorized these commits.`,
      `Report via StructuredOutput: changed_files (every file you created or modified, repository-relative, the checklist and ignored files included), report (items ticked, Discovered items appended with their blocking flags, and each gate's outcome), branch (the branch you worked on), commit (the last sha you committed, or an empty string when nothing changed), complete (true only when CHECKLIST-STATUS is complete), and blocking_discoveries (each Discovered item with Blocking: yes, as a finding whose location is its Plan section).`,
    ].filter(Boolean).join('\n'),
    {
      agentType: 'plan-implementer',
      label: `implement`,
      phase: 'Implement',
      schema: IMPLEMENTER_SCHEMA,
    },
  )

  // An implementer that died or was skipped produced nothing a reviewer could
  // check, so the run returns rather than spawning one.
  if (implementation === null) {
    return end(STATUS.IMPLEMENTATION_FAILED, 'implement', {
      planPath,
      checklistPath,
      roundsRun,
      branch: workflowBranch,
      note: `The implementer returned no result: it died or was skipped, possibly after switching branches. Restore the checkout (feature-start, "Restoring the checkout"), then resume: the implementation continues on ${workflowBranch} from the first unticked item.`,
    })
  }
  workflowBranch = implementation.branch || workflowBranch
  changedFiles = [...new Set([...changedFiles, ...implementation.changed_files.map(normalisePath)])]

  // A stopped implementation is not reviewed: a blocking discovery is a plan
  // defect, which the next revision receives; without one, the next run
  // continues the implementation.
  if (!implementation.complete) {
    pendingRevise = implementation.blocking_discoveries
    return end(STATUS.IMPLEMENTATION_STOPPED, pendingRevise.length > 0 ? 'revise' : 'implement', {
      planPath,
      checklistPath,
      roundsRun,
      branch: workflowBranch,
      implementation,
      note: pendingRevise.length > 0
        ? 'The implementer stopped on blocking Discovered items, which go to the next revision. Its work is committed on the branch. Resume to revise the plan.'
        : 'The implementer stopped before the checklist was complete, with no blocking discovery: on a precondition, such as a dirty tree, with nothing changed, or part-way, with its work committed on the branch. Its report says which. Clear a failed precondition, then resume to continue the implementation.',
    })
  }
}

// ---- phase 9: acceptance -------------------------------------------------

phase('Accept')

// The reviewer judges the result against the request without the plan's
// framing, so nothing under plans/ reaches it except the path it writes.
const reviewFiles = changedFiles.filter(p => !/(^|\/)plans\//.test(p))
const diffTarget = workflowBranch ?? 'HEAD'
const acceptance = await agent(
  [
    `Request, verbatim:`,
    request,
    ``,
    `Acceptance criteria, verbatim:`,
    ...requirements.acceptance_criteria.map(c => `- ${c}`),
    ``,
    `Base commit: ${baseRef}`,
    `The run's work is committed on ${diffTarget}. Run git diff --name-only ${baseRef} ${diffTarget} for every file it changed.`,
    `Files the implementer also reports changing, some of which git ignores:`,
    ...(reviewFiles.length > 0 ? reviewFiles.map(p => `- ${p}`) : [`(none)`]),
    ``,
    `The module's architecture rules: ${GUIDANCE}. House conventions: ${profile.conventionDocs.join(', ')}.`,
    `Write your acceptance document to ${acceptancePath}.`,
    `Read each changed file in full. For each one git tracks, run git diff ${baseRef} ${diffTarget} -- <file>. Run the tests the criteria name with ${diffTarget} checked out.`,
    `In the document, quote each criterion verbatim and mark it met, partial or unmet with the evidence you observed: the test you ran or the file:line you read. Then list your findings about the code.`,
    `Report via StructuredOutput: criteria (one per criterion, quoted verbatim, with status and evidence) and findings.`,
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
  branch: workflowBranch,
  roundsRun,
  freshAnglesRun: [...freshSpent],
  trial,
  implementation,
  nonblockingDiscoveries: checklist?.nonblocking_discoveries ?? [],
}

if (acceptance === null) {
  return end(STATUS.ACCEPTANCE_FAILED, 'accept', {
    ...base,
    note: 'The acceptance reviewer returned no result: it died or was skipped, possibly after switching branches. Restore the checkout (feature-start, "Restoring the checkout"), then resume to run the review again; the implementation is committed on the branch.',
  })
}

// Every criterion is judged by its verbatim quote, so one the reviewer left
// out or reworded counts as not met.
const words = s => s.trim().replace(/\s+/g, ' ')
const judged = c => acceptance.criteria.find(j => words(j.criterion) === words(c))
const allMet = requirements.acceptance_criteria.every(c => judged(c)?.status === 'met')
const serious = acceptance.findings.filter(f => FAILING_SEVERITIES.includes(f.severity))
return end(allMet && serious.length === 0 ? STATUS.ACCEPTED : STATUS.ACCEPTANCE_GAPS, 'done', {
  ...base,
  acceptance,
  note: allMet && serious.length === 0
    ? 'Every acceptance criterion is met and the reviewer raised no blocking or major finding.'
    : 'Gaps remain: a criterion is not met, was not quoted verbatim, or the reviewer raised a blocking or major finding. Fix them by hand, or start a successor run through feature-start with them as its requirements.',
})
