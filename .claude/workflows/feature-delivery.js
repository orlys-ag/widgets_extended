export const meta = {
  name: 'feature-delivery',
  description: 'Draft a plan, probe the premises reading cannot settle, critique it with every lens at once and converge, extract its steps, build them on one branch with a commit and gates per step, then a blind acceptance review with a bounded fix loop.',
  whenToUse: 'When a feature or bugfix spanning several components should be designed, critiqued, built and judged end to end. Use the delivery-start skill to build the args: slug, date, request, baseRef, profile and requirements.',
  phases: [
    { title: 'Plan', detail: 'Draft the plan, or revise it with every finding raised since the last revision.' },
    { title: 'Probe', detail: 'Settle each premise reading cannot settle with the smallest experiment, on a scratch branch.' },
    { title: 'Critique', detail: 'Round 1 runs every lens in parallel; a re-round runs the lenses that raised a failing finding and the consistency lens, told what changed.' },
    { title: 'Steps', detail: 'Extract the landing steps, the decision pins, the criteria map and the carried findings, and check them.' },
    { title: 'Build', detail: 'Repros first, then each step with its signal, its gates and its own commit; then one mutation per decision and the final gates.' },
    { title: 'Accept', detail: 'A reviewer who never reads the plan judges each criterion; gaps go to a bounded fix loop.' },
  ],
}

// ---- single sources ------------------------------------------------------

const WORKFLOW = 'feature-delivery'
const STATE_VERSION = 1

// The phases a run moves through. A run starts at the first, or where the
// state it resumes from says; `done` ends the feature.
const PHASES = ['draft', 'revise', 'critique', 'steps', 'build', 'accept', 'done']
const RESUMABLE = PHASES.filter(p => p !== 'done')

// Every status this script returns: what it means, the phases the next run may
// start at, and what the owner does. The status tables of the method document
// and of the start skill are generated from this.
const STATUS_INFO = {
  'accepted': {
    meaning: 'Every acceptance criterion is met and the reviewer raised no blocking or major finding.',
    next: ['done'],
    action: 'Review the branch diff and the acceptance document. Merging is the owner\'s decision.',
  },
  'acceptance-gaps': {
    meaning: 'After the fix budget a criterion is still not met or a blocking or major finding remains, or a fix needs the plan changed.',
    next: ['done'],
    action: 'Read `acceptance`; fix by hand, or start a successor run with the gaps as its requirements once this branch is merged.',
  },
  'needs-scope': {
    meaning: 'The draft or a revision returned scope questions, or a round raised a failing scope finding.',
    next: ['revise'],
    action: 'Settle every question and scope finding with the owner, correct `requirements`, then resume.',
  },
  'budget-spent': {
    meaning: 'The critique revisions or the implementation revisions of this launch are spent with failing findings open.',
    next: ['revise', 'steps'],
    action: 'Read `diagnosis`. Resume to revise with a fresh budget, or approve the plan with `ownerApproval` and `start: "steps"`.',
  },
  'failed': {
    meaning: 'An agent returned nothing (it was skipped or died), a result broke its contract twice, a precondition failed, or the probe could not run an experiment; `reason` says which.',
    next: RESUMABLE,
    action: 'Clear the reason (restore the checkout when an agent died after switching branches), then resume: the run starts at the phase its state names.',
  },
}
const STATUSES = Object.keys(STATUS_INFO)

// A finding's kind decides what it can do to a round. Only the four
// design-level kinds can fail one, and only at blocking or major; `coverage`
// means the critic could not review, so its lens counts as not reported.
const SEVERITIES = ['blocking', 'major', 'minor', 'nit']
const KIND_INFO = {
  rank: 'It changes which option ranks first in a decision table, adds a valid option the table lacks, or shows false a statement a ranking rests on (a citation, a count or a premise included).',
  surface: 'It changes the public surface, or breaks a format another component reads.',
  consistency: 'The plan disagrees with itself or with the code it describes (a landing step that cannot be done or committed as written included), breaks a writing rule of section 2, or a revision did not do what section 7 requires of it.',
  scope: 'A requirement is missing, ambiguous, or in conflict with another.',
  implementation: 'Anything else: an edge case, a consumer, a rule no test pins, an inert assertion. It is carried to the step it lands in.',
  coverage: 'The critic could not review; its lens counts as not reported.',
}
const KINDS = Object.keys(KIND_INFO)
const FAILING_KINDS = ['rank', 'surface', 'consistency', 'scope']
const FAILING_SEVERITIES = ['blocking', 'major']
const OUTCOMES = ['fixed', 're-ranked', 'rejected', 'carried', 'left-open']

// What the probe reports for a premise, and what each outcome does. The probe
// schema and the method document's list are generated from this.
const PREMISE_OUTCOMES = {
  'held': 'The experiment ran and its result shows the claim true.',
  'not-held': 'The experiment ran and its result shows the claim false: a major rank finding on its decision.',
  'not-run': 'The environment kept the experiment from producing a result (a gate that reports it could not run, a missing tool, a crashed process): the premise stays open, and the run ends failed with what was observed.',
  'undecided': 'The experiment ran, or cannot run as the plan writes it, and its result does not settle the claim (a difference within noise included): a major consistency finding on its decision.',
}

// The base finding item. Every finding shape derives from it: the builder's
// and the reviewer's use it as is, and a critic's adds three plan-relative
// fields.
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

// The agent file each role runs. Model and effort come from the profile's
// `roles`, per call, so the agent files set neither.
const ROLE_AGENTS = {
  planner: 'delivery-planner',
  critic: 'delivery-critic',
  extractor: 'delivery-extractor',
  builder: 'delivery-builder',
  reviewer: 'delivery-reviewer',
}
const ROLES = Object.keys(ROLE_AGENTS)
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']

// The lens pool. Each lens's generic focus is method text and lives here; the
// profile adds a project addendum and reading list per lens, switches a core
// lens off, or adds a project lens. The flags say what a lens's prompt carries.
const CONSISTENCY = 'consistency'
const EXECUTABILITY = 'executability'
const LENS_DEFINITIONS = {
  correctness: {
    summary: 'Mechanism, failure paths, lifecycle and re-entrancy',
    focus: 'Will each decision do what the goals say? Logical gaps where something reads state nothing writes, ordering violations, re-entrancy. Lifecycle: creation, teardown, and every site that destroys the thing. Degradation: what happens when a precondition is not met, on empty and single-element cases. Judge at decision level: an edge case or a missing test is kind implementation.',
  },
  performance: {
    summary: 'Bounds, hot paths, and the evidence behind each performance rank',
    ranking: true,
    focus: 'What is O(what), and is the stated bound the one that can blow up? Anything that turns a targeted lookup into a full scan, and allocation on a hot path. Does each measured or computed evidence cell in a decision table support its rank (method section 3), and does each counted contract name its check and expected value?',
  },
  surface: {
    summary: 'The public surface, every consumer verified in code, agreement with the documents the plan depends on, house conventions and the plan rules',
    planRules: true,
    focus: 'Signatures, types, naming and exports. Every consumer of a changed interface verified per method section 5 (derive, check in code, read; a search only locates). Does the plan contradict a document it depends on, or change a documented contract without saying so? Does it follow the house conventions and the project plan rules below, and declare every artifact the builder creates (method section 2.5)?',
  },
  claims: {
    summary: 'Each decision table against the ranking rule and its missing options; every citation, count and framework claim against the source; the plan checks',
    ranking: true,
    planChecks: true,
    focus: 'Does each decision table follow method section 3, and does it lack a valid option? Run every plan check below (a non-zero exit is itself a finding) and read that each cited line says what the plan says. Run the command behind every count and universal (method section 2.4), and verify every framework or engine claim against its source: recall is a hypothesis.',
  },
  acceptance: {
    summary: 'Each criterion traced to a named check that fails on the base commit; missing, ambiguous or conflicting requirements',
    requirements: true,
    focus: 'Is each acceptance criterion below traced to a named check in the Testing Plan that fails on the base commit, and can each check fail in the direction it claims? Is each new test seam justified against an existing one? Is a requirement missing, ambiguous or in conflict with another? That, or a criterion the plan cannot meet, is kind scope.',
  },
  executability: {
    summary: 'Each landing step done and committed from the base commit as written: its gates pass, its documents stay true, its commands run, its test seams exist',
    gates: true,
    focus: 'Can each landing step be done and committed from the base commit as written (method section 2.7)? Its files exist or are declared, its commands run, its test seams exist, its signal can pass at that step and not before, the gates below that its files trigger pass at its commit, and every document and comment is true at its commit. Read the code each step touches at the base commit. A step that cannot be done or committed as written is kind consistency; one whose fix changes a decision is kind rank.',
  },
  integration: {
    summary: 'Crossings with other components the plan never mentions, and timing risks only running code settles, each turned into a named test',
    focus: 'The feature crossed with every other component, layer and entry point: look for the crossings the plan does not mention at all rather than the ones it handles badly. Then timing: which of the plan\'s ordering, settle or visibility risks can only running code close, and is each turned into a named test rather than an argument that it is fine? A crossing or timing risk whose handling would change a decision is kind rank or surface; a missing named test is kind implementation.',
  },
  consistency: {
    summary: 'The last revision against its snapshot, the findings it received and their outcomes, and its obligations; runs only after a revision',
    focus: 'The revision that just happened, checked for self-inflicted damage and against what method section 7 requires of it. Diff the snapshot against the plan. Read the summary sections (overview, landing order, testing plan, the decisions list), where staleness collects, and every section that used the vocabulary the revision replaced. Cross-references resolve, numbering is contiguous, and each fact has one site. A received finding with no outcome, a re-rank obligation not met, or a changed decision that no received finding named and that depends on none that did, is a failing consistency finding. History or defensive prose the revision added breaks method section 2.6. You also guard the lenses the prompt lists as not re-run this round.',
  },
}
const CORE_LENSES = Object.keys(LENS_DEFINITIONS)
const SWEEP_CORE = CORE_LENSES.filter(k => k !== CONSISTENCY)

// Every profile key, whether it is required, and what reads it. The method
// document's profile section is generated from this.
const PROFILE_KEYS = {
  version: { required: true, about: 'The profile format: 1.' },
  artifactsDir: { required: true, about: 'The directory, relative to the repository root, holding each run\'s plan, snapshots, audit file, acceptance document and run record.' },
  codePaths: { required: true, about: 'The directories and files a run may change: every path a gate\'s `when` or a module\'s `paths` matches lies under one, and `.` is the whole tree. The probe and the builder stop when anything there is uncommitted.' },
  isolation: { required: true, about: '`checkout` runs every agent in the launching checkout; `worktree` runs the probe, the builder and the reviewer each in a git worktree of their own.' },
  preflight: { required: false, about: 'Each with `name`, `command` and `pass`: a check of the environment the start skill runs before every launch, which launches only when each passes.' },
  conventionDocs: { required: false, about: 'The house convention documents the planner, the builder and the reviewer read.' },
  modules: { required: false, about: 'Each with `paths` (regular expressions over repository paths), `guidance` (its architecture rules) and `vocabulary`. A run reads the guidance of every module its files match.' },
  gates: { required: true, about: 'Each with `name`, `command` (in which `{base}` stands for the base commit), `pass` (its pass condition), `when` (`"always"`, or `{"paths": [...]}`, regular expressions matched against the changed files) and `scope` (`step`: at each step\'s commit; `final`: once, after the mutations).' },
  lenses: { required: false, about: 'Per lens, optional `reads` (the files it reads; `moduleGuidance` and `conventionDocs` expand to those lists; default `moduleGuidance`), `addendum` (project text appended to its focus) and `enabled` (false switches a core lens off; never `consistency`). Any other key adds a project lens, which needs a `focus`. The planner receives every enabled lens\'s reads and addendum, and a project lens\'s focus; the builder and the reviewer receive the `performance` lens\'s addendum and the `hotPaths`.' },
  ranking: { required: true, about: 'The ranking criteria, in order (section 3).' },
  hotPaths: { required: false, about: 'Where the hot-path performance criterion applies.' },
  planRules: { required: false, about: 'The project\'s own requirements for a plan: the planner writes to them and the surface lens checks them.' },
  planChecks: { required: false, about: 'Each with `name` and `verify`, a command that exits 0 when the plan passes, and optionally `stamp` (run on a new plan), `rebase` (run after a revision) and `note` (how to act on its output); `{plan}` stands for the plan path.' },
  citations: { required: false, about: 'An object of settings that a plan check reads from this file itself; the workflow accepts it unread.' },
  defectClasses: { required: false, about: 'The defect classes a finding may name; the result counts them per run.' },
  roles: { required: false, about: 'Per role (planner, critic, extractor, builder, reviewer), optional `model` and `effort` for its agents.' },
  budget: { required: true, about: '`rounds` (critique revisions per launch), `implementationRevisions` (revisions after approval per launch) and `fixLoops` (fix rounds after a review), all integers.' },
}
const BUDGET_KEYS = ['rounds', 'implementationRevisions', 'fixLoops']

// Every argument the script reads. An unknown name is a caller's typo, which
// would otherwise fall back to a default with no message anywhere.
const ARG_NAMES = ['slug', 'date', 'request', 'baseRef', 'profile', 'requirements', 'resume', 'start', 'priorFindings', 'ownerApproval', 'budget']
const REQUIRED_ARGS = ['slug', 'date', 'request', 'baseRef', 'profile', 'requirements']
// The requirement fields every run carries; `decisions` is optional.
const REQUIRED_FIELDS = ['summary', 'user_visible_behavior', 'acceptance_criteria', 'modules_touched', 'constraints', 'non_goals', 'open_questions']

// The run state every result carries, and the record the start skill writes at
// a slug's first launch, before any result exists.
const STATE_KEYS = ['workflow', 'version', 'phase', 'baseRef', 'round', 'swept', 'pendingLenses', 'decisions', 'premises', 'scopeQuestions', 'received', 'carried', 'rankFailRounds', 'failRounds', 'reranked', 'pendingRerank', 'revisions', 'lastRevision', 'approval', 'steps', 'stepGaps', 'build', 'metrics']
const INITIAL_KEYS = ['baseRef', 'phase', 'version', 'workflow']

// A clean run: the draft, every core sweep lens in round 1, the extractor, the
// builder and the reviewer.
const CLEAN_RUN = ['planner', ...SWEEP_CORE.map(() => 'critic'), 'extractor', 'builder', 'reviewer']

// What the harness reads to generate and check the documents.
function describe() {
  return {
    workflow: WORKFLOW,
    stateVersion: STATE_VERSION,
    statuses: STATUSES,
    statusInfo: STATUS_INFO,
    kinds: KINDS,
    kindInfo: KIND_INFO,
    premiseOutcomes: PREMISE_OUTCOMES,
    baseFindingFields: BASE_FIELDS,
    roles: ROLE_AGENTS,
    lenses: CORE_LENSES.map(key => ({ key, summary: LENS_DEFINITIONS[key].summary, afterRevisionOnly: key === CONSISTENCY })),
    profileKeys: PROFILE_KEYS,
    argNames: ARG_NAMES,
    requiredArgs: REQUIRED_ARGS,
    requirementFields: [...REQUIRED_FIELDS, 'decisions'],
    cleanRun: CLEAN_RUN,
  }
}

// ---- args ----------------------------------------------------------------

// The runtime may deliver args as a JSON-encoded string. Normalize to object.
let argsObj = args
if (typeof argsObj === 'string') {
  try { argsObj = JSON.parse(argsObj) } catch { /* fall through to validation */ }
}

// The harness reads the single sources above without running a workflow.
if (argsObj?.describe === true) {
  return describe()
}

const isObject = v => v !== null && typeof v === 'object' && !Array.isArray(v)
const isStringArray = (v, allowEmpty) => Array.isArray(v)
  && (allowEmpty || v.length > 0)
  && v.every(x => typeof x === 'string' && x.length > 0)
const nonEmpty = v => typeof v === 'string' && v.trim().length > 0
const validRegex = p => { try { new RegExp(p); return true } catch { return false } }

// The literal text every path a pattern matches starts with: what follows `^`
// up to the first character that is not literal, less one when a quantifier
// makes that last one optional. A pattern without `^` fixes nothing.
function literalPrefix(pattern) {
  const m = pattern.match(/^\^((?:\\[^A-Za-z0-9]|[^\\.*+?()[\]{}|^$])*)([*?{]?)/)
  if (!m) {
    return ''
  }
  const text = m[1].replace(/\\(.)/g, '$1')
  return m[2] ? text.slice(0, -1) : text
}
const underAny = (prefix, roots) => roots.map(r => r.replace(/\/+$/, '')).some(r => r === '.' || prefix === r || prefix.startsWith(`${r}/`))

if (isObject(argsObj)) {
  const unknown = Object.keys(argsObj).filter(k => !ARG_NAMES.includes(k))
  if (unknown.length > 0) {
    throw new Error(`Unknown args: ${unknown.join(', ')}. The workflow reads ${ARG_NAMES.join(', ')}.`)
  }
}
const absentArgs = REQUIRED_ARGS.filter(k => argsObj?.[k] === undefined)
if (absentArgs.length > 0) {
  throw new Error(`${WORKFLOW} requires args ${absentArgs.join(', ')}; the delivery-start skill builds them.`)
}

const slug = argsObj.slug
if (typeof slug !== 'string' || !/^[a-z0-9]+(-[a-z0-9]+)*$/.test(slug)) {
  throw new Error('args.slug must be a kebab-case string')
}
// A workflow script cannot call argless `new Date()`, so that a resumed run
// replays identically; the caller supplies the date.
const date = argsObj.date
if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  throw new Error('args.date must be a YYYY-MM-DD string; the delivery-start skill supplies it.')
}
// The request as the owner wrote it, and the commit the first launch of this
// slug started from: the reviewer judges the result against the request and
// diffs against that commit.
const request = argsObj.request
if (!nonEmpty(request)) {
  throw new Error('args.request must be the owner\'s request, verbatim.')
}
const baseRef = argsObj.baseRef
if (!nonEmpty(baseRef)) {
  throw new Error('args.baseRef must be the commit the first launch of this slug started from.')
}

const requirements = argsObj.requirements
if (!isObject(requirements)) {
  throw new Error('args.requirements must be an object (see the delivery-start skill for its shape)')
}
const missingFields = REQUIRED_FIELDS.filter(k => !(k in requirements))
if (missingFields.length > 0) {
  throw new Error(`args.requirements is missing ${missingFields.join(', ')}`)
}
const unknownFields = Object.keys(requirements).filter(k => !REQUIRED_FIELDS.includes(k) && k !== 'decisions')
if (unknownFields.length > 0) {
  throw new Error(`args.requirements has unknown fields ${unknownFields.join(', ')}`)
}
if (!nonEmpty(requirements.summary)) {
  throw new Error('args.requirements.summary must be a non-empty string')
}
for (const k of REQUIRED_FIELDS.filter(k => k !== 'summary')) {
  if (!isStringArray(requirements[k], true)) {
    throw new Error(`args.requirements.${k} must be an array of non-empty strings (empty [] is fine)`)
  }
}
if (requirements.acceptance_criteria.length === 0) {
  throw new Error('args.requirements.acceptance_criteria needs at least one criterion that fails on the base commit')
}
// Decisions the owner settled before the run, each with its evidence. The
// planner adopts each as the starting table for its decision.
if ('decisions' in requirements && !isStringArray(requirements.decisions, true)) {
  throw new Error('args.requirements.decisions, when present, must be an array of non-empty strings')
}

// The project profile holds every project fact this script reads. This scope
// has no file access, so the start skill reads the file and passes it here.
const profile = argsObj.profile
validateProfile(profile)

function validateProfile(p) {
  const fail = msg => { throw new Error(`args.profile ${msg}. Pass the parsed project profile, as delivery-start does.`) }
  if (!isObject(p)) {
    fail('is required: the project profile object')
  }
  const unknown = Object.keys(p).filter(k => !(k in PROFILE_KEYS))
  if (unknown.length > 0) {
    fail(`has unknown keys ${unknown.join(', ')}`)
  }
  const absent = Object.keys(PROFILE_KEYS).filter(k => PROFILE_KEYS[k].required && !(k in p))
  if (absent.length > 0) {
    fail(`is missing keys ${absent.join(', ')}`)
  }
  if (p.version !== 1) {
    fail(`.version must be 1, got ${JSON.stringify(p.version)}`)
  }
  if (!nonEmpty(p.artifactsDir) || /^\/|^[A-Za-z]:|\\|\/$|(^|\/)\.\.?(\/|$)/.test(p.artifactsDir)) {
    fail('.artifactsDir must be a relative path with forward slashes and no trailing slash')
  }
  if (!isStringArray(p.codePaths, false)) {
    fail('.codePaths must be a non-empty array of strings')
  }
  if (!['checkout', 'worktree'].includes(p.isolation)) {
    fail('.isolation must be checkout or worktree')
  }
  if (!isStringArray(p.ranking, false)) {
    fail('.ranking must be a non-empty array of strings')
  }
  for (const k of ['conventionDocs', 'hotPaths', 'planRules', 'defectClasses']) {
    if (k in p && !isStringArray(p[k], true)) {
      fail(`.${k} must be an array of strings`)
    }
  }
  if ((p.defectClasses ?? []).includes('other')) {
    fail('.defectClasses must not list other; the script adds it')
  }
  if ('modules' in p) {
    if (!isObject(p.modules)) {
      fail('.modules must be an object')
    }
    for (const [key, m] of Object.entries(p.modules)) {
      if (!isObject(m) || !isStringArray(m.paths, false) || !isStringArray(m.guidance, true) || typeof m.vocabulary !== 'string') {
        fail(`.modules.${key} needs paths, guidance and vocabulary`)
      }
      if (!m.paths.every(validRegex)) {
        fail(`.modules.${key}.paths holds an invalid regular expression`)
      }
    }
  }
  if (!Array.isArray(p.gates) || p.gates.length === 0) {
    fail('.gates must be a non-empty array')
  }
  for (const g of p.gates) {
    if (!isObject(g) || !['name', 'command', 'pass'].every(k => nonEmpty(g[k]))) {
      fail('.gates entries need non-empty name, command and pass strings')
    }
    const pathsWhen = isObject(g.when) && Object.keys(g.when).join() === 'paths' && isStringArray(g.when.paths, false) && g.when.paths.every(validRegex)
    if (g.when !== 'always' && !pathsWhen) {
      fail(`.gates ${g.name}: when must be "always" or {"paths": [regular expressions]}`)
    }
    if (!['step', 'final'].includes(g.scope)) {
      fail(`.gates ${g.name}: scope must be step or final`)
    }
  }
  if (new Set(p.gates.map(g => g.name)).size !== p.gates.length) {
    fail('.gates names must be unique')
  }
  // A gate's `when` and a module's `paths` name what a run may change, and the
  // probe and the builder find someone else's uncommitted work only under the
  // code paths, so each must lie under one.
  const watched = [...p.gates.flatMap(g => g.when === 'always' ? [] : g.when.paths), ...Object.values(p.modules ?? {}).flatMap(m => m.paths)]
  const outside = watched.filter(w => !underAny(literalPrefix(w), p.codePaths))
  if (outside.length > 0) {
    fail(`.codePaths must cover every path a gate or a module matches, and miss ${[...new Set(outside)].join(', ')}`)
  }
  if ('preflight' in p && (!Array.isArray(p.preflight)
    || p.preflight.some(c => !isObject(c) || Object.keys(c).sort().join() !== 'command,name,pass' || !['name', 'command', 'pass'].every(k => nonEmpty(c[k]))))) {
    fail('.preflight entries need exactly name, command and pass, all non-empty strings')
  }
  if ('lenses' in p) {
    if (!isObject(p.lenses)) {
      fail('.lenses must be an object')
    }
    for (const [key, l] of Object.entries(p.lenses)) {
      const core = CORE_LENSES.includes(key)
      const allowed = core ? ['reads', 'addendum', 'enabled'] : ['focus', 'reads', 'addendum']
      if (!isObject(l) || Object.keys(l).some(k => !allowed.includes(k))) {
        fail(`.lenses.${key} may hold only ${allowed.join(', ')}`)
      }
      if (!core && (!/^[a-z][a-z-]*$/.test(key) || !nonEmpty(l.focus))) {
        fail(`.lenses.${key} is a project lens: it needs a kebab-case key and a focus`)
      }
      if ('reads' in l && !isStringArray(l.reads, true)) {
        fail(`.lenses.${key}.reads must be an array of strings`)
      }
      if ('addendum' in l && typeof l.addendum !== 'string') {
        fail(`.lenses.${key}.addendum must be a string`)
      }
      if ('enabled' in l && typeof l.enabled !== 'boolean') {
        fail(`.lenses.${key}.enabled must be a boolean`)
      }
    }
    if (p.lenses[CONSISTENCY]?.enabled === false) {
      fail('.lenses.consistency cannot be switched off: it is the only check of a revision')
    }
  }
  if ('planChecks' in p) {
    if (!Array.isArray(p.planChecks)) {
      fail('.planChecks must be an array')
    }
    for (const c of p.planChecks) {
      if (!isObject(c) || !nonEmpty(c.name) || !nonEmpty(c.verify)
        || ['stamp', 'rebase', 'note'].some(k => k in c && !nonEmpty(c[k]))
        || Object.keys(c).some(k => !['name', 'verify', 'stamp', 'rebase', 'note'].includes(k))) {
        fail('.planChecks entries need name and verify, and optionally stamp, rebase and note, all non-empty strings')
      }
    }
  }
  if ('citations' in p && !isObject(p.citations)) {
    fail('.citations must be an object')
  }
  if ('roles' in p) {
    if (!isObject(p.roles)) {
      fail('.roles must be an object')
    }
    for (const [role, r] of Object.entries(p.roles)) {
      if (!ROLES.includes(role) || !isObject(r) || Object.keys(r).some(k => !['model', 'effort'].includes(k))
        || ('model' in r && !nonEmpty(r.model)) || ('effort' in r && !EFFORTS.includes(r.effort))) {
        fail(`.roles.${role} must be one of ${ROLES.join(', ')}, with an optional model string and effort in ${EFFORTS.join(', ')}`)
      }
    }
  }
  if (!isObject(p.budget) || Object.keys(p.budget).sort().join() !== [...BUDGET_KEYS].sort().join()
    || !Number.isInteger(p.budget.rounds) || p.budget.rounds < 1
    || !Number.isInteger(p.budget.implementationRevisions) || p.budget.implementationRevisions < 0
    || !Number.isInteger(p.budget.fixLoops) || p.budget.fixLoops < 0) {
    fail(`.budget must hold exactly ${BUDGET_KEYS.join(', ')}: integers, rounds at least 1`)
  }
}

// A launch may override the profile's budget; a quoted number is rejected
// rather than coerced, since it would otherwise select the default silently.
const BUDGET = { ...profile.budget }
if (argsObj.budget !== undefined) {
  const b = argsObj.budget
  if (!isObject(b) || Object.keys(b).some(k => !BUDGET_KEYS.includes(k)) || Object.values(b).some(v => !Number.isInteger(v) || v < 0)) {
    throw new Error(`args.budget may hold only ${BUDGET_KEYS.join(', ')}, as non-negative integers`)
  }
  Object.assign(BUDGET, b)
  if (BUDGET.rounds < 1) {
    throw new Error('args.budget.rounds must be at least 1')
  }
}

// The guidance of every module the requirements' files match. A profile with
// modules that matches none is a module missing from the profile, which the
// caller adds rather than a guess this scope makes.
const MODULES = profile.modules ?? {}
const matchedModules = Object.entries(MODULES)
  .filter(([, m]) => requirements.modules_touched.some(f => m.paths.some(p => new RegExp(p).test(f))))
  .map(([key]) => key)
if (Object.keys(MODULES).length > 0 && matchedModules.length === 0) {
  throw new Error(`args.requirements.modules_touched matches no module of the profile (${Object.keys(MODULES).join(', ')}). Add the module to the profile, or correct modules_touched.`)
}
const GUIDANCE = [...new Set(matchedModules.flatMap(k => MODULES[k].guidance))]
const VOCABULARY = matchedModules.map(k => MODULES[k].vocabulary).filter(Boolean).join(' ')
const moduleLine = matchedModules.length > 0
  ? `Modules: ${matchedModules.join(', ')}. Their architecture rules: ${GUIDANCE.join(', ') || '(none)'}. ${VOCABULARY}`.trim()
  : 'No module guidance applies to this change.'
// A critic reads only its lens's reading list, so its module line names no
// other file.
const criticModuleLine = matchedModules.length > 0
  ? `Modules: ${matchedModules.join(', ')}. ${VOCABULARY}`.trim()
  : 'No module guidance applies to this change.'

const DIR = profile.artifactsDir
const planPath = `${DIR}/${date}-${slug}-plan.md`
const auditPath = `${DIR}/${date}-${slug}-audit.md`
const acceptancePath = `${DIR}/${date}-${slug}-acceptance.md`
const buildBranch = slug
const probeBranch = `${slug}-probe`
const WORKTREE = profile.isolation === 'worktree'
const ISOLATE = WORKTREE ? { isolation: 'worktree' } : {}
const worktreeLine = WORKTREE
  ? `You run in a git worktree of your own. ${DIR}/ is in the main checkout, not in your worktree; the main checkout is the parent directory of \`git rev-parse --path-format=absolute --git-common-dir\`.`
  : ``

// priorFindings enter the run at the revision, so each needs the base fields.
const priorFindings = argsObj.priorFindings ?? []
if (!Array.isArray(priorFindings)) {
  throw new Error('args.priorFindings must be an array of findings')
}
priorFindings.forEach((f, i) => {
  const gaps = isObject(f) ? BASE_FIELDS.filter(k => !nonEmpty(f[k])) : BASE_FIELDS
  if (gaps.length > 0) {
    throw new Error(`args.priorFindings[${i}] is missing or empties ${gaps.join(', ')}`)
  }
  if (!SEVERITIES.includes(f.severity)) {
    throw new Error(`args.priorFindings[${i}].severity must be one of ${SEVERITIES.join(', ')}`)
  }
})
if (new Set(priorFindings.map(f => f.id)).size !== priorFindings.length) {
  throw new Error('args.priorFindings ids must be unique: a revision records its outcome for each by id')
}

// The run record: the state the last result returned, which the start skill
// keeps beside the plan and passes back, or the initial record of a first
// launch.
const resume = argsObj.resume ?? null
const initialRecord = isObject(resume) && Object.keys(resume).sort().join() === INITIAL_KEYS.join()
if (resume !== null) {
  const fail = msg => { throw new Error(`args.resume ${msg}. Pass the run record, as delivery-start does.`) }
  if (!isObject(resume)) {
    fail('must be an object')
  }
  if (resume.workflow !== WORKFLOW) {
    fail(`belongs to workflow ${JSON.stringify(resume.workflow)}, not ${WORKFLOW}`)
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
    fail('is an initial record, whose phase is draft')
  }
  if (!initialRecord) {
    const absent = STATE_KEYS.filter(k => !(k in resume))
    if (absent.length > 0) {
      fail(`is missing ${absent.join(', ')}`)
    }
    if (!Number.isInteger(resume.round) || !Number.isInteger(resume.revisions)) {
      fail('.round and .revisions must be integers')
    }
    for (const k of ['swept', 'decisions', 'premises', 'scopeQuestions', 'received', 'carried', 'reranked', 'pendingRerank', 'stepGaps']) {
      if (!Array.isArray(resume[k])) {
        fail(`.${k} must be an array`)
      }
    }
    for (const k of ['rankFailRounds', 'failRounds']) {
      if (!isObject(resume[k]) || Object.values(resume[k]).some(v => !Array.isArray(v) || !v.every(Number.isInteger))) {
        fail(`.${k} must map each decision to round numbers`)
      }
    }
    if (resume.pendingLenses !== null && !isStringArray(resume.pendingLenses, true)) {
      fail('.pendingLenses must be null or an array of lens keys')
    }
    for (const k of ['lastRevision', 'approval', 'steps']) {
      if (resume[k] !== null && !isObject(resume[k])) {
        fail(`.${k} must be null or an object`)
      }
    }
    if (!isObject(resume.build) || !isObject(resume.metrics)) {
      fail('.build and .metrics must be objects')
    }
  }
}

// Where this run starts: the owner's choice, else the resumed state's phase,
// else the revision when only priorFindings are given, else the draft.
if (argsObj.start !== undefined) {
  if (resume === null) {
    throw new Error('args.start needs args.resume: a run starts past the draft only from its run record.')
  }
  if (!RESUMABLE.includes(argsObj.start)) {
    throw new Error(`args.start must be one of ${RESUMABLE.join(', ')}, got ${JSON.stringify(argsObj.start)}`)
  }
}
const START = argsObj.start ?? resume?.phase ?? (priorFindings.length > 0 ? 'revise' : 'draft')
if (priorFindings.length > 0 && START !== 'revise') {
  throw new Error(`args.priorFindings go to a revision, but this run starts at ${START}. Pass start: "revise" with them.`)
}
const ownerApproval = argsObj.ownerApproval
if (ownerApproval !== undefined && !nonEmpty(ownerApproval)) {
  throw new Error('args.ownerApproval must state the owner\'s basis for approving the plan')
}
const reaches = p => PHASES.indexOf(START) <= PHASES.indexOf(p)
const pastCritique = PHASES.indexOf(START) > PHASES.indexOf('critique')
// A failing finding reaches the plan only through a revision, so a run that
// starts past one either receives it there or the owner says why not.
const owedFailing = (resume?.received ?? []).filter(f => FAILING_SEVERITIES.includes(f.severity) && (!f.kind || FAILING_KINDS.includes(f.kind)))
if (pastCritique && owedFailing.length > 0 && ownerApproval === undefined) {
  throw new Error(`args.start ${START} would skip ${owedFailing.length} failing finding(s) the next revision must receive. Start at revise, or pass ownerApproval.`)
}
if (pastCritique && !resume?.approval && ownerApproval === undefined) {
  throw new Error(`args.ownerApproval is required to start at ${START}: no clean round approved this version of the plan.`)
}
if (['build', 'accept'].includes(START) && !resume?.steps) {
  throw new Error(`args.start ${START} needs the extracted steps, which the run record lacks. Start at steps.`)
}

// ---- prompt blocks -------------------------------------------------------

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
const rankingLine = `Ranking criteria, in order: ${profile.ranking.join(', ')}.${(profile.hotPaths ?? []).length > 0 ? ` Hot paths, the only place a hot-path performance criterion applies: ${profile.hotPaths.join(', ')}.` : ''}`
const planRulesBlock = (profile.planRules ?? []).length > 0
  ? `Project plan rules, which the plan must meet:\n${profile.planRules.map(r => `- ${r}`).join('\n')}`
  : ``
const conventionsLine = (profile.conventionDocs ?? []).length > 0
  ? `House conventions, read before writing code or tests: ${profile.conventionDocs.join(', ')}.`
  : ``
const reviewConventionsLine = (profile.conventionDocs ?? []).length > 0
  ? `House conventions to judge the code against: ${profile.conventionDocs.join(', ')}.`
  : ``
const codePathsList = profile.codePaths.join(' ')
const whenText = g => g.when === 'always' ? 'always' : `when a changed file matches ${g.when.paths.map(p => `\`${p}\``).join(' or ')}`
const gatesBlock = `Gates (method section 8.3):\n${profile.gates.map(g => `- ${g.name} (${g.scope} scope, ${whenText(g)}): \`${g.command.split('{base}').join(baseRef)}\`, passes when ${g.pass}.`).join('\n')}`
const checks = profile.planChecks ?? []
function planChecksBlock(which) {
  if (checks.length === 0) {
    return ``
  }
  const command = c => c[which] ?? c.verify
  return [
    `Plan checks; run each and require exit 0:`,
    ...checks.map(c => `- ${c.name}: \`${command(c).split('{plan}').join(planPath)}\`${c.note ? `. ${c.note}` : ''}`),
  ].join('\n')
}

const normalisePath = p => p.split(String.fromCharCode(92)).join('/').replace(/^\.\//, '')
const gateApplies = (g, files) => g.when === 'always' || files.some(f => g.when.paths.some(p => new RegExp(p).test(normalisePath(f))))
const requiredGates = (scope, files) => profile.gates.filter(g => (scope === 'any' || g.scope === scope) && gateApplies(g, files))
const GATE_NAMES = profile.gates.map(g => g.name)

// ---- lenses --------------------------------------------------------------

function expandReads(list) {
  return [...new Set(list.flatMap(r => r === 'moduleGuidance' ? GUIDANCE : r === 'conventionDocs' ? (profile.conventionDocs ?? []) : [r]))]
}
function lensFrom(key) {
  const def = LENS_DEFINITIONS[key]
  const custom = profile.lenses?.[key] ?? {}
  return {
    key,
    core: Boolean(def),
    focus: [def ? def.focus : custom.focus, custom.addendum].filter(Boolean).join(' '),
    reads: expandReads(custom.reads ?? ['moduleGuidance']),
    addendum: custom.addendum ?? '',
    ranking: Boolean(def?.ranking),
    requirements: Boolean(def?.requirements),
    planRules: Boolean(def?.planRules),
    planChecks: Boolean(def?.planChecks),
    gates: Boolean(def?.gates),
  }
}
const POOL = [
  ...CORE_LENSES.filter(k => profile.lenses?.[k]?.enabled !== false),
  ...Object.keys(profile.lenses ?? {}).filter(k => !CORE_LENSES.includes(k)),
].map(lensFrom)
const SWEEP = POOL.filter(l => l.key !== CONSISTENCY)
const CONSISTENCY_LENS = POOL.find(l => l.key === CONSISTENCY)
const EXECUTABILITY_LENS = POOL.find(l => l.key === EXECUTABILITY) ?? null
const lensByKey = k => POOL.find(l => l.key === k) ?? null
if (SWEEP.length === 0) {
  throw new Error('args.profile switches off every lens but consistency; a round needs at least one sweeping lens')
}

// The planner is given what the critics review the plan against beyond the
// method and the plan rules, derived from the pool so that no lens grades a
// plan on an input its author never had.
const PLANNER_READS = [...new Set([...(profile.conventionDocs ?? []), ...POOL.flatMap(l => l.reads)])].filter(r => !GUIDANCE.includes(r))
const lensTexts = POOL.filter(l => !l.core || nonEmpty(l.addendum)).map(l => `- ${l.key}: ${l.core ? l.addendum : l.focus}`)
const reviewedAgainstBlock = [
  PLANNER_READS.length > 0 ? `House conventions and the other documents the critics read: ${PLANNER_READS.join(', ')}.` : ``,
  gatesBlock,
  lensTexts.length > 0 ? `What the lenses check in this project, beside the sweeps of method section 6.1. Design for it; prose that only answers a critic breaks method section 2.6:\n${lensTexts.join('\n')}` : ``,
].filter(Boolean).join('\n')

// The builder and the reviewer judge code rather than a plan, so they are told
// the hot paths and the project's performance rules, the performance lens's
// addendum; with no addendum there are no rules to tell.
const performanceRules = lensByKey('performance')?.addendum ?? ''
const hotPathBlock = nonEmpty(performanceRules)
  ? `${(profile.hotPaths ?? []).length > 0 ? `Hot paths: ${profile.hotPaths.join(', ')}. ` : ''}The project's performance rules: ${performanceRules}`
  : ``

// ---- schemas -------------------------------------------------------------

const str = { type: 'string' }
const bool = { type: 'boolean' }
const int = { type: 'integer' }
const arr = items => ({ type: 'array', items })
const obj = (properties, required = Object.keys(properties)) => ({ type: 'object', required, additionalProperties: false, properties })
const DECISION_LIST = arr({ type: 'string', pattern: '^d[0-9]+$' })
const PREMISE_ITEM = obj({ id: str, decision: { type: 'string', pattern: '^(d[0-9]+|none)$' }, claim: str, experiment: str })
const SCOPE_ITEM = obj({ question: str, options: arr(str), recommendation: str })
const GATE_RUN = obj({ name: { type: 'string', enum: GATE_NAMES }, passed: bool })
const DEFECT_CLASSES = [...(profile.defectClasses ?? []), 'other']

const FINDINGS_SCHEMA = obj({
  findings: arr(obj({
    ...BASE_FINDING_PROPERTIES,
    decision: { type: 'string', pattern: '^(d[0-9]+|none)$' },
    kind: { type: 'string', enum: KINDS },
    defect_class: { type: 'string', enum: DEFECT_CLASSES },
  }, CRITIC_FIELDS)),
})
const DRAFT_SCHEMA = obj({ aborted: str, decisions: DECISION_LIST, premises: arr(PREMISE_ITEM), scope_questions: arr(SCOPE_ITEM) })
const REVISE_SCHEMA = obj({
  snapshot: str,
  changed_decisions: DECISION_LIST,
  decisions: DECISION_LIST,
  outcomes: arr(obj({ id: str, outcome: { type: 'string', enum: OUTCOMES }, note: str })),
  premises: arr(PREMISE_ITEM),
  scope_questions: arr(SCOPE_ITEM),
})
const PROBE_SCHEMA = obj({ precondition: str, branch: str, premises: arr(obj({ id: str, outcome: { type: 'string', enum: Object.keys(PREMISE_OUTCOMES) }, observed: str })) })
const STEPS_SCHEMA = obj({
  decisions: DECISION_LIST,
  repros: arr(str),
  steps: arr(obj({ n: int, title: str, anchor: str, decisions: DECISION_LIST, files: arr(str), signal: str, group: str })),
  pins: arr(obj({ decision: { type: 'string', pattern: '^d[0-9]+$' }, codeSite: str, test: str })),
  criteria: arr(obj({ number: int, steps: arr(int) })),
  carried: arr(obj({ id: str, step: int, obsolete: str })),
  gaps: arr(obj({ title: str, location: str, why: str })),
})
const BUILD_SCHEMA = obj({
  precondition: str,
  branch: str,
  approval_recorded: bool,
  plan_checks: arr(obj({ name: str, passed: bool, note: str })),
  repros: arr(obj({ test: str, failed_on_base: bool })),
  steps: arr(obj({
    n: int,
    status: { type: 'string', enum: ['built', 'kept'] },
    signal_passed: bool,
    gates: arr(GATE_RUN),
    changed_files: arr(str),
    commit: str,
  })),
  carried: arr(obj({ id: str, addressed: bool, evidence: str })),
  mutations: arr(obj({ decision: { type: 'string', pattern: '^d[0-9]+$' }, test: str, test_failed: bool, sha_before: str, sha_after: str })),
  final_gates: arr(GATE_RUN),
  changed_files: arr(str),
  complete: bool,
  last_step: int,
  blocking_findings: arr(BASE_FINDING),
  discoveries: arr(str),
})
const FIX_SCHEMA = obj({
  precondition: str,
  fixed: arr(str),
  needs_plan_change: arr(obj({ id: str, why: str })),
  gates: arr(GATE_RUN),
  changed_files: arr(str),
})
const ACCEPTANCE_SCHEMA = obj({
  criteria: arr(obj({ number: int, status: { type: 'string', enum: ['met', 'partial', 'unmet'] }, evidence: str })),
  findings: arr(BASE_FINDING),
})

// ---- run state -----------------------------------------------------------

const S = initialRecord || resume === null ? {} : resume
const mapOfSets = o => new Map(Object.entries(o ?? {}).map(([k, v]) => [k, new Set(v)]))
const plain = m => Object.fromEntries([...m].map(([k, v]) => [k, [...v].sort((a, b) => a - b)]))
const emptyBuild = () => ({ branch: null, lastStep: -1, verified: [], addressed: [], repros: [], mutations: {}, changedFiles: [], discoveries: [], rework: null })
const emptyMetrics = () => ({ launches: 0, statuses: {}, agents: {}, implementationRevisions: 0, fixLoops: 0, handovers: 0, failingByLens: {}, defectClasses: {} })

// Critique rounds run so far, cumulative across launches.
let round = S.round ?? 0
// Lenses that have reported on some version of the plan (approval rule 2), and
// the lenses the next round must run, when a run ended before running them.
const swept = new Set(S.swept ?? [])
let pendingLenses = S.pendingLenses ?? null
let decisions = [...(S.decisions ?? [])]
// Each premise: open until the probe settles it, then held or not held.
const premises = (S.premises ?? []).map(p => ({ ...p }))
// The scope questions the last needs-scope result returned, which the next
// revision is told the owner settled.
let scopeQuestions = [...(S.scopeQuestions ?? [])]
// Every finding raised since the last revision: the next revision receives all
// of them, or the Approval record lists them when no revision follows.
let received = [...(S.received ?? [])]
// The implementation findings, which the extractor places in steps.
const carried = [...(S.carried ?? [])]
// Rounds in which each decision had a failing rank finding (R1), and in which
// any failing finding named it (the diagnosis of a spent budget).
const rankFailRounds = mapOfSets(S.rankFailRounds)
const failRounds = mapOfSets(S.failRounds)
const reranked = new Set(S.reranked ?? [])
let pendingRerank = [...(S.pendingRerank ?? [])]
let revisions = S.revisions ?? 0
let lastRevision = S.lastRevision ?? null
let approval = S.approval ?? null
let steps = S.steps ?? null
// The gaps the last extraction reported, each with the outcome the revision
// that received it recorded: the next extraction answers them rather than
// reporting them again blind.
let stepGaps = (S.stepGaps ?? []).map(g => ({ ...g }))
const build = { ...emptyBuild(), ...(S.build ?? {}) }
const metrics = { ...emptyMetrics(), ...(S.metrics ?? {}) }
metrics.launches += 1
// What this launch has spent of its budget.
const spent = { rounds: 0, implementationRevisions: 0, fixLoops: 0 }
let stepsCalls = 0
let buildCalls = 0

function exportState(next) {
  return {
    workflow: WORKFLOW,
    version: STATE_VERSION,
    phase: next,
    baseRef,
    round,
    swept: [...swept],
    pendingLenses,
    decisions,
    premises,
    scopeQuestions,
    received,
    carried,
    rankFailRounds: plain(rankFailRounds),
    failRounds: plain(failRounds),
    reranked: [...reranked],
    pendingRerank,
    revisions,
    lastRevision,
    approval,
    steps,
    stepGaps,
    build,
    metrics,
  }
}

// A result ends the run through a thrown Stop, which the main flow catches:
// every phase can end it from inside a helper.
class Stop {
  constructor(result) {
    this.result = result
  }
}
function stop(status, next, fields) {
  if (!STATUS_INFO[status]?.next.includes(next)) {
    throw new Error(`${status} cannot start the next run at ${next}; STATUS_INFO allows ${STATUS_INFO[status]?.next.join(', ')}`)
  }
  metrics.statuses[status] = (metrics.statuses[status] ?? 0) + 1
  throw new Stop({
    status,
    phase: next,
    planPath,
    auditPath,
    acceptancePath,
    branch: build.branch,
    modules: matchedModules,
    ...fields,
    state: exportState(next),
  })
}
function failed(at, reason) {
  stop('failed', at, { reason, note: STATUS_INFO.failed.action })
}

const isFailing = f => FAILING_SEVERITIES.includes(f.severity) && FAILING_KINDS.includes(f.kind)
const unique = list => [...new Set(list)]
const uniqueLenses = list => list.filter((l, i) => l && list.findIndex(x => x?.key === l.key) === i)
// The prompts number the acceptance criteria from 1, and the extractor and the
// reviewer name each by its number: the entries each criterion has, and the
// numbers no criterion has.
const numberedCriteria = requirements.acceptance_criteria.map((c, i) => `${i + 1}. ${c}`)
function byNumber(items) {
  const all = requirements.acceptance_criteria
  const outside = unique(items.map(x => x.number).filter(k => k < 1 || k > all.length))
  return {
    entries: all.map((c, i) => items.filter(x => x.number === i + 1)),
    problems: outside.length > 0 ? [`criteria ${outside.join(', ')} do not exist: the criteria are numbered 1 to ${all.length}`] : [],
  }
}
const label = (base, n) => (n === 1 ? base : `${base}-${n}`)

function addRound(map, key, at) {
  if (!map.has(key)) {
    map.set(key, new Set())
  }
  map.get(key).add(at)
}

function roleOpts(role) {
  const r = profile.roles?.[role] ?? {}
  return { ...(r.model ? { model: r.model } : {}), ...(r.effort ? { effort: r.effort } : {}) }
}

// A result `accept` refuses is dispatched once more; `prompt(rejected)` builds
// the prompt, and on the retry can tell the agent what was refused. An agent
// that returns nothing was skipped by the owner or died after the runtime's own
// retries, so it is not dispatched again. Either failure returns null, which
// the caller turns into a `failed` result that resumes at its phase.
async function dispatch(role, agentLabel, prompt, schema, phaseTitle, extra = {}, accept = () => true) {
  const opts = { agentType: ROLE_AGENTS[role], label: agentLabel, phase: phaseTitle, schema, ...roleOpts(role), ...extra }
  let rejected = null
  for (let attempt = 1; attempt <= 2; attempt++) {
    metrics.agents[role] = (metrics.agents[role] ?? 0) + 1
    let result = null
    try {
      result = await agent(prompt(rejected), opts)
    } catch (err) {
      log(`${agentLabel} failed: ${err?.message ?? err}`)
    }
    if (result === null || result === undefined) {
      log(`${agentLabel} returned nothing: it was skipped or died.`)
      return null
    }
    if (accept(result)) {
      return result
    }
    rejected = result
    log(`${agentLabel} was refused (attempt ${attempt}).`)
  }
  return null
}

// ---- critique ------------------------------------------------------------

// A critic carries no memory of an earlier round, so it is told what is
// already settled: the carried implementation findings and the owner's
// decisions. A lens given the requirements reads the decisions there.
function settledBlock(lens) {
  const owner = requirements.decisions ?? []
  if (carried.length === 0 && owner.length === 0) {
    return ``
  }
  const listed = lens.requirements ? [] : owner
  return [
    `Already settled: ${[carried.length > 0 ? 'the carried findings listed below' : '', owner.length > 0 ? `the owner's decisions ${lens.requirements ? 'in the requirements above' : 'listed below'}` : ''].filter(Boolean).join(' and ')}. Raise a finding that restates one only when the plan now contradicts it, and name the one it contradicts in its why.`,
    carried.length > 0 ? `Implementation findings carried to the steps they land in:` : ``,
    ...carried.map(f => `- ${f.id} (${f.lens}, round ${f.round}, ${f.location}): ${f.title}`),
    listed.length > 0 ? `The owner's decisions:` : ``,
    ...listed.map(d => `- ${d}`),
  ].filter(Boolean).join('\n')
}

function outcomeLine(f) {
  const o = lastRevision?.outcomes?.[f.id]
  return `- ${f.id} (${f.lens ?? 'owner'}, ${f.severity}${f.kind ? ` ${f.kind}` : ''}${f.decision ? ` ${f.decision}` : ''}): ${f.title} -> ${o ? `${o.outcome}: ${o.note}` : 'no outcome recorded'}`
}

function consistencyContext(roundLenses) {
  if (!lastRevision) {
    return `No revision precedes this round. Report coverage.`
  }
  const idle = SWEEP.filter(l => swept.has(l.key) && !roundLenses.some(x => x.key === l.key))
  return [
    `${revisionName()} (${lastRevision.origin}). Snapshot: ${lastRevision.snapshot}. Diff it against the plan with git diff --no-index ${lastRevision.snapshot} ${planPath}.`,
    `Decisions the revision reports it changed: ${lastRevision.changed_decisions.join(', ') || 'none'}.`,
    `Re-rank obligations it was given: ${lastRevision.rerank.join(', ') || 'none'}.`,
    `Findings it received, with the outcome it recorded for each:`,
    ...(lastRevision.received.length > 0 ? lastRevision.received.map(outcomeLine) : ['(none)']),
    idle.length > 0 ? `Lenses that reviewed an earlier version and did not re-run this round; check that the revision broke nothing they cleared:` : ``,
    ...idle.map(l => `- ${l.key}: ${LENS_DEFINITIONS[l.key]?.summary ?? l.focus}`),
  ].filter(Boolean).join('\n')
}

// The revision, or the chain of revisions, the next round checks.
function revisionName() {
  return lastRevision.first === lastRevision.number ? `Revision ${lastRevision.number}` : `Revisions ${lastRevision.first} to ${lastRevision.number}`
}

// A lens that ran on an earlier version is told what changed since, so it
// reviews the change instead of re-reading the whole plan blind.
function rerunContext(lens) {
  if (!lastRevision || !swept.has(lens.key)) {
    return ``
  }
  const own = lastRevision.received.filter(f => f.lens === lens.key)
  return [
    `This lens reviewed an earlier version of the plan. ${revisionName()} changed: ${lastRevision.changed_decisions.join(', ') || 'no decision'}. See every edit with git diff --no-index ${lastRevision.snapshot} ${planPath}. Review the changed decisions, everything that depends on them, and the sites of your earlier findings; report anything else you see.`,
    own.length > 0 ? `Your earlier findings, with the outcome the revision recorded:` : `You raised no finding on the earlier version.`,
    ...own.map(outcomeLine),
  ].join('\n')
}

function criticPrompt(lens, roundLenses) {
  return [
    `Plan: ${planPath}`,
    criticModuleLine,
    `Lens: ${lens.key}`,
    `Focus: ${lens.focus}`,
    lens.ranking ? rankingLine : ``,
    lens.requirements ? `Requirements, which this lens traces and scopes against:` : ``,
    lens.requirements ? requirementsMarkdown : ``,
    lens.planRules ? planRulesBlock : ``,
    lens.planChecks ? planChecksBlock('verify') : ``,
    lens.gates ? gatesBlock : ``,
    lens.gates ? `Base commit: ${baseRef}.` : ``,
    lens.key === CONSISTENCY ? consistencyContext(roundLenses) : rerunContext(lens),
    settledBlock(lens),
    ``,
    `Give each finding a decision (a d<N> anchor from the plan's Decisions section, or none), a kind (${KINDS.join(', ')}; coverage only when you could not review the plan at all, never for missing tests) and a defect_class (${DEFECT_CLASSES.join(', ')}).`,
    lens.reads.length > 0 ? `Also read: ${lens.reads.join(', ')}.` : ``,
    `Report via StructuredOutput.`,
  ].filter(Boolean).join('\n')
}

// A lens that reports it could not review is dispatched once more in the same
// round, told the cause it gave. A lens that still cannot review, or that
// returns nothing, ends the run: a round cannot be called clean on an angle
// nobody swept.
const coverageCauses = r => (r?.findings ?? []).filter(f => f.kind === 'coverage').map(f => f.title)
async function runLens(lens, at, roundLenses) {
  let last = null
  const result = await dispatch('critic', `critic:${lens.key}:r${at}`, rejected => [
    coverageCauses(rejected).length > 0
      ? `A previous dispatch of this lens reported it could not review: ${coverageCauses(rejected).join('; ')}. If that was a passing failure, review now; if the input is really missing, report coverage again.`
      : ``,
    criticPrompt(lens, roundLenses),
  ].filter(Boolean).join('\n'), FINDINGS_SCHEMA, 'Critique', {}, r => {
    last = r
    return coverageCauses(r).length === 0
  })
  return result
    ? { lens, findings: result.findings, reported: true }
    : { lens, findings: [], reported: false, cause: coverageCauses(last).join('; ') || 'returned nothing: it was skipped or died' }
}

// A critic picks its own ids, and two critics can pick the same one, so the
// script assigns each finding an id by its lens, round and position: outcomes
// and placements keyed by id can then never merge two findings.
function collect(critiques, at) {
  const flat = critiques.flatMap(c => c.findings.map((f, i) => ({ round: at, lens: c.lens.key, ...f, id: `${c.lens.key}-r${at}-${i + 1}` })))
  received = received.concat(flat)
  for (const f of flat) {
    if (f.kind === 'implementation') {
      carried.push(f)
    }
    if (isFailing(f)) {
      metrics.failingByLens[f.lens] = (metrics.failingByLens[f.lens] ?? 0) + 1
    }
    if (f.defect_class && f.defect_class !== 'other') {
      metrics.defectClasses[f.defect_class] = (metrics.defectClasses[f.defect_class] ?? 0) + 1
    }
  }
  return flat
}

// R1, re-rank: a decision with a failing rank finding is re-ranked when it had
// one in an earlier round, or the previous revision changed it.
function applyRerank(at, findings) {
  const failing = findings.filter(isFailing)
  const changed = new Set(lastRevision?.changed_decisions ?? [])
  const rerank = new Set()
  for (const f of failing.filter(f => f.kind === 'rank' && f.decision !== 'none')) {
    const earlier = [...(rankFailRounds.get(f.decision) ?? [])].some(r => r < at)
    if (earlier || changed.has(f.decision)) {
      rerank.add(f.decision)
    }
  }
  for (const f of failing) {
    addRound(failRounds, f.decision ?? 'none', at)
    if (f.kind === 'rank' && f.decision !== 'none') {
      addRound(rankFailRounds, f.decision, at)
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

// ---- probe ---------------------------------------------------------------

function probePrompt(open) {
  return [
    `Mode: probe.`,
    `Plan: ${planPath}`,
    `Audit file: ${auditPath}`,
    `Base commit: ${baseRef}`,
    worktreeLine,
    ``,
    `Premises to settle (method section 8.2):`,
    JSON.stringify(open.map(({ id, decision, claim, experiment }) => ({ id, decision, claim, experiment })), null, 2),
    ``,
    `1. Run git status --porcelain -- ${codePathsList}. If anything there is modified, staged or untracked, stop: describe it in precondition and change nothing. It is someone else's work.`,
    `2. Create ${probeBranch} from the base commit (git switch -c ${probeBranch} ${baseRef}), or ${probeBranch}-2, -3 when that name is taken (git rev-parse --verify --quiet). Report the name in branch.`,
    `3. For each premise, write the smallest code that settles it, not the feature, and run only the commands its experiment needs.`,
    `4. Commit the scratch code on that branch, staging by path, then switch back to the branch you started on.`,
    `5. Append a "## Probe" record to ${auditPath}: one line per premise, giving its id, its outcome and what you observed.`,
    `Report via StructuredOutput: precondition ('' unless you stopped), branch, and premises (one per premise: id, outcome, one of ${Object.keys(PREMISE_OUTCOMES).join(', ')} as method section 8.2 defines them, and observed: the output that decides it).`,
  ].filter(Boolean).join('\n')
}

// Runs every open premise's experiment. A premise that does not hold, or that
// its experiment leaves undecided, becomes a major finding on its decision,
// which joins the round's findings; one the environment kept from running stays
// open and fails the probe. It returns a failure instead of stopping, because
// it may run inside parallel(), which turns a throw into null.
async function probe(at) {
  const open = premises.filter(p => p.status === 'open')
  const r = await dispatch('builder', `probe:r${at}`, () => probePrompt(open), PROBE_SCHEMA, 'Probe', ISOLATE)
  if (r === null) {
    return { failure: 'The probe returned nothing: it was skipped or died.' }
  }
  if (nonEmpty(r.precondition)) {
    return { failure: `The probe stopped on a precondition: ${r.precondition}` }
  }
  const unreported = open.filter(p => !r.premises.some(x => x.id === p.id))
  if (unreported.length > 0) {
    return { failure: `The probe did not report premise(s) ${unreported.map(p => p.id).join(', ')}.` }
  }
  const findings = []
  const notRun = []
  for (const p of open) {
    const res = r.premises.find(x => x.id === p.id)
    p.observed = res.observed
    if (res.outcome === 'not-run') {
      notRun.push(`${p.id} (${res.observed})`)
      continue
    }
    p.status = res.outcome
    if (res.outcome !== 'held') {
      const notHeld = res.outcome === 'not-held'
      findings.push({
        round: at,
        lens: 'probe',
        id: `premise-${p.id}`,
        location: p.decision === 'none' ? 'premises' : p.decision,
        severity: 'major',
        title: `Premise ${p.id} ${notHeld ? 'does not hold' : 'is not settled by its experiment'}: ${p.claim}`,
        why: res.observed,
        suggested_direction: notHeld
          ? 'Re-rank the decision with this evidence, or replace the premise.'
          : 'Replace the experiment with one whose result decides the claim, settle the claim by reading, or re-rank the decision so it does not rest on it.',
        decision: p.decision,
        kind: notHeld ? 'rank' : 'consistency',
        defect_class: 'other',
      })
    }
  }
  log(`Probe: ${open.map(p => `${p.id} ${r.premises.find(x => x.id === p.id).outcome}`).join(', ')}.`)
  return notRun.length > 0
    ? { findings, failure: `The probe could not run the experiment of premise(s) ${notRun.join('; ')}. It is not a plan defect: clear the cause and resume; the premise stays open.` }
    : { findings }
}

// A probe that fails keeps what it settled: those premises are closed, so
// their findings enter the run now, and the re-run round probes only the open
// ones.
function probeFailed(at, pending, probed) {
  const found = probed.findings ?? []
  received = received.concat(found)
  pendingRerank = unique([...pendingRerank, ...applyRerank(at, found)])
  pendingLenses = pending.map(l => l.key)
  failed('critique', probed.failure)
}

// ---- revise --------------------------------------------------------------

function revisePrompt(number, findings, obligations, origin) {
  const fromBuild = origin === 'build'
  return [
    `Mode: revision ${number} (${origin}).`,
    `Plan: ${planPath}`,
    `Audit file: ${auditPath}`,
    moduleLine,
    rankingLine,
    ``,
    `Requirements, as the owner last settled them; the revised plan must meet them:`,
    requirementsMarkdown,
    planRulesBlock,
    reviewedAgainstBlock,
    scopeQuestions.length > 0 ? `The owner settled these scope questions; the requirements above hold the answers:\n${scopeQuestions.map(q => `- ${q.question}`).join('\n')}` : ``,
    ``,
    `Before editing, copy the plan to ${planPath}.r${number} and report that path as snapshot. If ${planPath}.r${number} already exists, a dispatch of this revision that did not finish made it and may have edited the plan: report it as snapshot, read the plan against it, and finish the revision rather than starting another.`,
    ``,
    `Findings received, every finding raised since the last revision, at every severity:`,
    findings.length > 0 ? JSON.stringify(findings, null, 2) : `(none)`,
    ``,
    `Address each failing finding (blocking or major, of kind rank, surface, consistency or scope) in the plan using Edit, never a full-file Write. Fix a non-failing finding, or leave it open with a reason. An implementation finding is carried to the step it lands in: leave the plan alone for it unless it shows the plan wrong. A finding without a kind (from the steps, the builder or the owner) is failing when it is blocking or major. Reject a finding only with evidence from the source.`,
    fromBuild ? `These findings came from building the approved plan: the builder committed steps through ${build.lastStep} on ${build.branch ?? buildBranch}. Change the plan where it is wrong; the builder reworks the committed steps that carry a decision you change.` : ``,
    obligations.length > 0
      ? `Re-rank these decisions, do not patch them: ${obligations.join(', ')}. For each, add the findings to its table as evidence, re-apply the gate and the ranking criteria (the snapshot holds the option it replaces), record which option now ranks first and why (keeping rank 1 is allowed when the record says why), and update its dependents.`
      : ``,
    `A fix rewrites the sentence that was wrong; it never appends a note, and the plan never says what it used to say (method section 2.6).`,
    `Append a "## Revision ${number}" record to ${auditPath}, creating the file with a one-line title if it does not exist: one line per finding received, giving its id, its source (lens and round, or probe, steps, build or owner), kind, severity and outcome. No other prose.`,
    `Run the consistency pass of method section 7.`,
    planChecksBlock('rebase'),
    `Report via StructuredOutput: snapshot; changed_decisions (the d<N> anchors whose decision text or table you changed); decisions (every d<N> anchor now in the plan); outcomes (one per finding received: its id, an outcome of ${OUTCOMES.join(', ')}, and a note naming the section or the evidence); premises (each new premise this revision rests on, per method section 2.8); scope_questions (each requirement conflict or gap you could not resolve, with its options and your recommendation).`,
  ].filter(Boolean).join('\n')
}

async function revise(origin, rerank) {
  phase('Plan')
  const number = revisions + 1
  const findings = received
  const obligations = unique([...pendingRerank, ...rerank])
  const r = await dispatch('planner', `plan:revise-${number}`, () => revisePrompt(number, findings, obligations, origin), REVISE_SCHEMA, 'Plan')
  if (r === null) {
    pendingRerank = obligations
    failed('revise', 'The planner returned nothing during a revision: it was skipped or died. The findings it was given are still owed to the next one.')
  }
  revisions = number
  received = []
  pendingRerank = []
  for (const d of obligations) {
    reranked.add(d)
  }
  decisions = r.decisions
  for (const p of r.premises) {
    const id = premises.some(x => x.id === p.id) ? `${p.id}-r${number}` : p.id
    premises.push({ ...p, id, status: 'open', observed: '' })
  }
  // A revision no round has checked yet (one that stopped for a scope
  // question) is chained into this one: the next consistency lens diffs from
  // the earlier snapshot and is told both revisions' changes and outcomes.
  const prev = lastRevision && !lastRevision.checked ? lastRevision : null
  lastRevision = {
    number,
    first: prev ? prev.first : number,
    origin: prev ? `${prev.origin}, ${origin}` : origin,
    changed_decisions: unique([...(prev?.changed_decisions ?? []), ...r.changed_decisions]),
    snapshot: prev ? prev.snapshot : r.snapshot,
    received: [
      ...(prev?.received ?? []),
      ...findings.map(f => ({ id: f.id, lens: f.lens ?? null, severity: f.severity, kind: f.kind ?? null, decision: f.decision ?? null, title: f.title })),
    ],
    outcomes: { ...(prev?.outcomes ?? {}), ...Object.fromEntries(r.outcomes.map(o => [o.id, { outcome: o.outcome, note: o.note }])) },
    rerank: unique([...(prev?.rerank ?? []), ...obligations]),
    checked: false,
  }
  for (const g of stepGaps) {
    g.outcome = g.outcome ?? lastRevision.outcomes[g.id] ?? null
  }
  // A revision after steps were verified: each verified step that carries a
  // changed decision can no longer be kept; the builder reworks it and mutates
  // its decision again.
  const changed = r.changed_decisions
  const stale = build.verified.filter(v => v.decisions.some(d => changed.includes(d)))
  if (stale.length > 0 || (build.rework && changed.length > 0)) {
    build.verified = build.verified.filter(v => !stale.includes(v))
    build.rework = {
      decisions: unique([...(build.rework?.decisions ?? []), ...changed]),
      steps: [...(build.rework?.steps ?? []), ...stale],
    }
  }
  // The rework replaces the code that addressed a carried finding placed in a
  // reworked step, so that finding is owed again.
  const reworked = (steps?.list ?? []).filter(s => stale.some(v => v.title === s.title)).map(s => s.n)
  const owed = new Set((steps?.carried ?? []).filter(c => reworked.includes(c.step)).map(c => c.id))
  build.addressed = build.addressed.filter(id => !owed.has(id))
  for (const d of changed) {
    delete build.mutations[d]
  }
  scopeQuestions = []
  approval = null
  if (r.scope_questions.length > 0) {
    scopeQuestions = r.scope_questions
    stop('needs-scope', 'revise', {
      scopeQuestions: r.scope_questions,
      note: 'The revision found a requirement it could not settle. ' + STATUS_INFO['needs-scope'].action,
    })
  }
}

// ---- convergence ---------------------------------------------------------

// Runs critique rounds until one raises no failing finding with every lens of
// the pool swept and no premise open. Round 1 runs every lens; after a
// revision the next round runs the lenses that raised a failing finding plus
// the consistency lens, any lens that has not yet reported, and, when the
// revision changed a decision, the lenses that grade a decision's rank.
async function converge(initial) {
  let pending = initial
  for (;;) {
    const at = round + 1
    const rerankers = lastRevision && !lastRevision.checked && lastRevision.changed_decisions.length > 0 ? SWEEP.filter(l => l.ranking) : []
    pending = uniqueLenses([...pending, ...rerankers, ...SWEEP.filter(l => !swept.has(l.key))])
    const probing = premises.some(p => p.status === 'open')
    phase('Critique')
    log(`Round ${at}: ${pending.map(l => l.key).join(', ')}${probing ? ', and the probe' : ''}.`)

    // The critics read the working tree, so in a single checkout the probe,
    // which switches branches, runs before them; in a worktree it runs beside them.
    let probed = null
    if (probing && !WORKTREE) {
      probed = await probe(at)
      if (probed.failure) {
        probeFailed(at, pending, probed)
      }
    }
    const thunks = pending.map(l => () => runLens(l, at, pending))
    if (probing && WORKTREE) {
      thunks.push(() => probe(at))
    }
    const results = await parallel(thunks)
    if (probing && WORKTREE) {
      probed = results.pop() ?? { failure: 'The probe failed.' }
      if (probed.failure) {
        probeFailed(at, pending, probed)
      }
    }
    const critiques = results.map((c, i) => c ?? { lens: pending[i], findings: [], reported: false })
    if (critiques.some(c => !c.reported)) {
      // The round runs again whole, so this attempt's findings are dropped
      // rather than received twice. The probe's settle premises, so they stay,
      // and enter the re-rank history now: the re-run round will not probe.
      pendingLenses = pending.map(l => l.key)
      const probeFindings = probed?.findings ?? []
      received = received.concat(probeFindings)
      pendingRerank = unique([...pendingRerank, ...applyRerank(at, probeFindings)])
      stop('failed', 'critique', {
        reason: `Lens(es) could not review: ${critiques.filter(c => !c.reported).map(c => `${c.lens.key} (${c.cause})`).join(', ')}.`,
        lensesMissing: critiques.filter(c => !c.reported).map(c => c.lens.key),
        note: 'This is an infrastructure failure or a missing input, not a plan defect. Resume to run the round again with all its lenses.',
      })
    }

    round = at
    for (const c of critiques) {
      swept.add(c.lens.key)
    }
    if (lastRevision && critiques.some(c => c.lens.key === CONSISTENCY)) {
      lastRevision.checked = true
    }
    received = received.concat(probed?.findings ?? [])
    const probeFailing = (probed?.findings ?? []).filter(isFailing).length
    if (probeFailing > 0) {
      metrics.failingByLens.probe = (metrics.failingByLens.probe ?? 0) + probeFailing
    }
    const flat = [...collect(critiques, at), ...(probed?.findings ?? [])]
    const rerank = applyRerank(at, flat)
    const failing = received.filter(isFailing)
    const failingLenses = unique(failing.map(f => f.lens)).map(lensByKey).filter(l => l && l.key !== CONSISTENCY)
    log(`Round ${at}: ${failing.length} failing finding(s).`)

    if (failing.some(f => f.kind === 'scope')) {
      pendingRerank = unique([...pendingRerank, ...rerank])
      pendingLenses = failingLenses.map(l => l.key)
      stop('needs-scope', 'revise', {
        round: at,
        scopeFindings: received.filter(f => f.kind === 'scope'),
        note: STATUS_INFO['needs-scope'].action,
      })
    }
    if (failing.length === 0) {
      pendingLenses = null
      return
    }
    if (spent.rounds >= BUDGET.rounds) {
      pendingRerank = unique([...pendingRerank, ...rerank])
      pendingLenses = failingLenses.map(l => l.key)
      stop('budget-spent', 'revise', {
        round: at,
        budget: 'rounds',
        diagnosis: diagnosis(),
        note: `The ${BUDGET.rounds} critique revision(s) of this launch are spent with failing findings open. ${STATUS_INFO['budget-spent'].action}`,
      })
    }
    spent.rounds += 1
    pendingLenses = failingLenses.map(l => l.key)
    await revise('critique', rerank)
    pending = [...failingLenses, CONSISTENCY_LENS]
    pendingLenses = null
  }
}

// ---- approval ------------------------------------------------------------

// The plan is approved by this script, not by an agent: the record lists the
// basis, the premises and the findings of the clean rounds, and the builder
// appends it to the audit file before its first step.
function approve(basis) {
  const lines = [
    `## Approval`,
    ``,
    `Round ${round}. Basis: ${basis}`,
    `Premises: ${premises.length > 0 ? premises.map(p => `${p.id} ${p.status}`).join('; ') : 'none'}.`,
    `Findings since the last revision:`,
    ...(received.length > 0
      ? received.map(f => `- ${f.id}, ${f.lens ?? 'owner'}, ${f.kind ?? 'no kind'}, ${f.severity}: ${f.kind === 'implementation' ? 'carried'
        : FAILING_SEVERITIES.includes(f.severity) && (!f.kind || FAILING_KINDS.includes(f.kind)) ? 'not revised, by the owner\'s approval' : 'left open'}`)
      : ['- (none)']),
  ]
  approval = { round, basis, recorded: false, text: lines.join('\n') }
  received = []
  log(`Plan approved at round ${round}.`)
}

// ---- steps ---------------------------------------------------------------

function stepsPrompt(problems, reported) {
  return [
    `Plan: ${planPath}`,
    `Acceptance criteria, verbatim:`,
    ...numberedCriteria,
    `Carried implementation findings, to place:`,
    carried.length > 0 ? JSON.stringify(carried.map(f => ({ id: f.id, location: f.location, title: f.title })), null, 2) : `(none)`,
    ``,
    `Read the plan's Landing Order, Decisions and Testing Plan.`,
    stepGaps.length > 0
      ? [
          `The previous extraction reported these gaps, and a revision recorded the outcome after each. Read the plan where each outcome's note points. Report a gap again only when the plan still lacks it, and then say in its why what the note misses:`,
          ...stepGaps.map(g => `- ${g.id} (${g.location}): ${g.title} -> ${g.outcome ? `${g.outcome.outcome}: ${g.outcome.note}` : 'no outcome recorded'}`),
        ].join('\n')
      : ``,
    problems.length > 0 ? `Your previous result had these problems. Correct each from the plan; where the plan does not state what is needed, report it as a gap:\n${problems.map(p => `- ${p}`).join('\n')}` : ``,
    reported.length > 0 ? `The previous extraction reported these gaps. Re-read the plan at each gap's location, and report it again when the plan still does not state it:\n${reported.map(g => `- ${g.location}: ${g.title} (${g.why})`).join('\n')}` : ``,
    `Report via StructuredOutput:`,
    `- decisions: every d<N> anchor of the plan's Decisions section.`,
    `- repros: the tests the Testing Plan names as repros failing on the base commit, by name.`,
    `- steps: one per Landing Order step, numbered as the plan numbers them from 1: n, title, anchor (the plan anchor that defines the step), decisions (the d<N> it implements), files (the paths it creates or changes), signal (the named test or exact command that passes when it lands), group ('' or a label shared by the steps the plan marks as not independently verifiable together).`,
    `- pins: one per decision: decision, codeSite (where its rule lands), test (the named test that pins it, or the check the plan names when it lands only in documents).`,
    `- criteria: one per acceptance criterion: number (its number above) and steps (the step numbers whose signals check it, 0 for a repro).`,
    `- carried: one per carried finding: id, step (the step it lands in, or -1), obsolete ('' or why it no longer applies).`,
    `- gaps: each thing above the plan does not state, with title, location (the plan anchor where it belongs) and why (what the plan says there, quoted, and what it lacks). Never infer a file list, a signal or a pin the plan lacks.`,
  ].filter(Boolean).join('\n')
}

// The script checks the extraction itself: the decisions the plan anchors are
// the ones the run recorded, the steps are contiguous, each with files and a
// signal, every decision is pinned, every criterion mapped, every carried
// finding placed. What the plan lacks is a gap for a revision. The decisions
// are read from the plan rather than told, so a run record older than the plan
// (a resumed run that a killed one overtook) is caught here.
function stepProblems(r) {
  const problems = []
  const anchored = unique(r.decisions).sort()
  if (anchored.join() !== [...decisions].sort().join()) {
    problems.push(`the plan's Decisions section anchors ${anchored.join(', ') || 'no decision'}, but the run recorded ${[...decisions].sort().join(', ') || 'none'}`)
  }
  const numbers = r.steps.map(s => s.n).sort((a, b) => a - b)
  if (numbers.length === 0) {
    problems.push('the extraction holds no landing step')
  }
  if (numbers.some((n, i) => n !== i + 1)) {
    problems.push(`the steps are not numbered 1 to ${numbers.length} without gaps: ${numbers.join(', ')}`)
  }
  for (const s of r.steps) {
    if (s.files.length === 0 || !nonEmpty(s.signal) || !nonEmpty(s.anchor)) {
      problems.push(`step ${s.n} lacks files, a signal or an anchor`)
    }
  }
  for (const d of unique([...decisions, ...anchored])) {
    const pins = r.pins.filter(p => p.decision === d)
    if (pins.length !== 1 || !nonEmpty(pins[0].codeSite) || !nonEmpty(pins[0].test)) {
      problems.push(`${d} needs exactly one pin with a code site and a test`)
    }
  }
  const valid = new Set([...numbers, ...(r.repros.length > 0 ? [0] : [])])
  const mapped = byNumber(r.criteria)
  problems.push(...mapped.problems)
  mapped.entries.forEach((m, i) => {
    const at = `criterion ${i + 1} ("${requirements.acceptance_criteria[i].slice(0, 80)}")`
    if (m.length > 1) {
      problems.push(`${at} is mapped ${m.length} times`)
    } else if (m.length === 0 || m[0].steps.length === 0 || m[0].steps.some(n => !valid.has(n))) {
      problems.push(`${at} is not mapped to a step that exists`)
    }
  })
  for (const f of carried) {
    const m = r.carried.find(x => x.id === f.id)
    if (!m || (m.step === -1 ? !nonEmpty(m.obsolete) : !valid.has(m.step))) {
      problems.push(`carried finding ${f.id} is not placed in a step or marked obsolete with a reason`)
    }
  }
  return problems
}

// Returns the gaps for a revision, or none once the steps are stored.
async function extract() {
  phase('Steps')
  let problems = []
  let reported = []
  for (let attempt = 1; attempt <= 2; attempt++) {
    stepsCalls += 1
    const r = await dispatch('extractor', label('steps', stepsCalls), () => stepsPrompt(problems, reported), STEPS_SCHEMA, 'Steps')
    if (r === null) {
      failed('steps', 'The extractor returned nothing: it was skipped or died.')
    }
    problems = stepProblems(r)
    if (problems.length === 0 && r.gaps.length === 0) {
      stepGaps = []
      steps = { repros: r.repros, list: r.steps, pins: r.pins, criteria: r.criteria, carried: r.carried }
      log(`Steps: ${r.steps.length}, with ${r.repros.length} repro(s) and ${r.pins.length} pin(s).`)
      return []
    }
    // A problem or a gap may be the extractor's own slip, so the first
    // extraction that has one earns a retry, told them. What remains after it
    // goes to the revision together.
    if (attempt === 1) {
      reported = r.gaps
      log(`The extraction has ${problems.length} problem(s) and ${r.gaps.length} gap(s); dispatching it once more.`)
      continue
    }
    // Ids carry the revision count, so the outcome a revision records for one
    // gap is never read as another's.
    const at = `steps-r${revisions}`
    const gaps = [
      ...r.gaps.map((g, i) => ({ id: `${at}-gap-${i + 1}`, location: g.location, severity: 'blocking', title: g.title, why: g.why, suggested_direction: 'State it in the plan so the step can be built from it.', lens: 'steps' })),
      ...problems.map((p, i) => ({ id: `${at}-problem-${i + 1}`, location: 'landing-order', severity: 'blocking', title: p, why: 'The extraction could not take it from the plan on two attempts.', suggested_direction: 'Make the Landing Order, the decision pins and the Testing Plan state it.', lens: 'steps' })),
    ]
    stepGaps = gaps.map(g => ({ id: g.id, location: g.location, title: g.title, outcome: null }))
    return gaps
  }
}

// ---- build ---------------------------------------------------------------

const stepLine = v => `- ${v.title} (${v.commit}), carrying ${v.decisions.join(', ') || 'no decision'}`

// Why a pin's recorded mutation does not show its rule pinned, or null when it
// does.
function mutationProblem(p) {
  const m = build.mutations[p.decision]
  return !m ? `${p.decision} has no mutation`
    : !m.test_failed ? `${p.decision}'s mutation left ${m.test} passing`
    : !nonEmpty(m.sha_before) || m.sha_before !== m.sha_after ? `${p.decision}'s code site was not restored to its recorded SHA-256`
    : null
}

function buildPrompt(problems) {
  const rework = build.rework
  // What earlier dispatches settled is listed as done, so a builder that takes
  // over runs no repro, mutation or carried finding a second time.
  const split = (list, done) => [list.filter(x => !done(x)), list.filter(done)]
  const [reprosLeft, reprosDone] = split(steps.repros, t => build.repros.includes(t))
  const [pinsLeft, pinsDone] = split(steps.pins, p => mutationProblem(p) === null)
  const [carriedLeft, carriedDone] = split(steps.carried, c => build.addressed.includes(c.id))
  // The extractor places each carried finding; its text lives only in the run
  // state, so the builder gets both.
  const carriedText = carriedLeft.map(c => {
    const f = carried.find(x => x.id === c.id) ?? {}
    return { id: c.id, step: c.step, obsolete: c.obsolete, title: f.title ?? '', location: f.location ?? '', why: f.why ?? '', suggested_direction: f.suggested_direction ?? '' }
  })
  return [
    `Mode: build.`,
    `Plan: ${planPath}`,
    `Audit file: ${auditPath}`,
    `Base commit: ${baseRef}`,
    `Branch: ${buildBranch}`,
    moduleLine,
    conventionsLine,
    worktreeLine,
    ``,
    `First run git status --porcelain -- ${codePathsList}. If anything there is modified, staged or untracked on any branch but ${buildBranch}, stop: describe it in precondition and change nothing. It is someone else's work.`,
    `Then git switch ${buildBranch} when it exists, since it holds this run's committed steps; otherwise git switch -c ${buildBranch} ${baseRef}.`,
    approval && !approval.recorded ? `Append this Approval record to ${auditPath} verbatim, creating the file with a one-line title if it does not exist, and report approval_recorded true:\n${approval.text}` : `The Approval record is already in ${auditPath}; report approval_recorded true.`,
    ``,
    planChecksBlock('verify'),
    checks.length > 0 ? `Run the plan checks before the first step and report each in plan_checks. A failure on a line this branch's own commits changed is the plan being applied; re-read any other, and if its claim no longer holds, report a blocking finding.` : ``,
    hotPathBlock,
    hotPathBlock ? `On a hot path, add none of the costs these rules name unless the plan's decision for that code accepts it; a step that cannot be built without one shows the plan wrong.` : ``,
    ``,
    `Steps, from the approved plan. The plan is the source: read the section each step's anchor names, and every citation it holds.`,
    JSON.stringify(steps.list.map(s => ({ ...s, gates: requiredGates('step', s.files).map(g => g.name) })), null, 2),
    `Each step's gates are the step-scope gates its declared files trigger. Final gates the declared files trigger: ${requiredGates('final', unique(steps.list.flatMap(s => s.files))).map(g => g.name).join(', ') || 'none'}. A file you change outside a step's declared list may trigger more: the conditions below decide.`,
    steps.repros.length === 0 ? `The plan names no repro, so there is no step 0.` : ``,
    reprosLeft.length > 0 ? `Step 0, the repros: ${reprosLeft.join(', ')}. Commit them first, and run each on the base commit's code: each must fail. A repro that passes there is a blocking finding.` : ``,
    reprosDone.length > 0 ? `Repros an earlier dispatch committed and recorded failing on the base commit, which you do not run again: ${reprosDone.join(', ')}.` : ``,
    pinsLeft.length > 0 ? `Pins, one mutation each after the last step:\n${JSON.stringify(pinsLeft, null, 2)}` : ``,
    pinsDone.length > 0 ? `Pins an earlier dispatch mutated, which you do not mutate again: ${pinsDone.map(p => `${p.decision} (${p.test})`).join(', ')}.` : ``,
    carriedLeft.length > 0 ? `Carried findings. Address each in the step it lands in, by a test shown to fail first, a mutation, or the check method section 5 names; one marked obsolete: confirm its reason against the plan and the code, and report it addressed with that reason as its evidence; if the reason does not hold, address it in the step whose files it concerns:\n${JSON.stringify(carriedText, null, 2)}` : ``,
    carriedDone.length > 0 ? `Carried findings an earlier dispatch addressed, which you do not address again: ${carriedDone.map(c => c.id).join(', ')}.` : ``,
    build.verified.length > 0
      ? `Steps verified in earlier dispatches, by title and commit. One the list still asks for unchanged, under the same title, may be reported kept with that commit once its signal passes again:\n${build.verified.map(stepLine).join('\n')}`
      : ``,
    rework
      ? `The plan was revised after these steps were committed, and a decision each carries changed (${rework.decisions.join(', ') || 'none'}). Rebuild what the list now asks of them in new commits; none of them may be reported kept:\n${rework.steps.map(stepLine).join('\n') || '(none)'}`
      : ``,
    rework || build.verified.length > 0 ? `A revision may have renumbered the steps: match committed work to the list by its content, never by the number in its Step: trailer.` : ``,
    problems.length > 0 ? `Your previous result broke the build contract in these ways. Correct each and report again:\n${problems.map(p => `- ${p}`).join('\n')}` : ``,
    ``,
    gatesBlock,
    ``,
    `Procedure (method section 8.3):`,
    `1. Build, in order, every step of the list that no verified step above covers. The Step: trailers on the branch (git log ${baseRef}..${buildBranch} --format=%B) show where an earlier dispatch stopped; a step committed there but not listed as verified is reported built, after you run its signal and gates again, and a commit whose message says its step is unfinished holds partial work: finish that step from it.`,
    `2. For each step: make the change; run its signal; run every step-scope gate whose condition matches the files the step changed; commit the step's files, staging by path, with a message whose last line is the trailer Step: <n>. Every document and comment the step touches must be true at its commit.`,
    `3. After the last step, one mutation per pin listed to mutate: record the code site file's SHA-256, break the rule there, run the pin's test and observe it fail, restore the file, record the SHA-256 again. A test that stays green is a blocking finding: the rule is unpinned.`,
    `4. Then run every final-scope gate whose condition matches the files changed since the base commit.`,
    `A failure that shows the plan wrong stops you: report it in blocking_findings, with your last committed step in last_step. A minor slip you fix within its step and list in discoveries.`,
    `Report via StructuredOutput: precondition ('' unless you stopped); branch; approval_recorded; plan_checks (each plan check by name, with passed and a note); repros (each repro you ran on the base commit: test, failed_on_base); steps (EVERY step of the list: n, status built or kept, signal_passed, gates you ran with name and passed, changed_files, commit); carried (each carried finding listed to address: id, addressed, and evidence, the test or check that shows it, or the confirmed reason it is obsolete); mutations (each mutation you made: decision, test, test_failed, sha_before, sha_after); final_gates; changed_files (git diff --name-only ${baseRef}..${buildBranch}); complete (true only after the final gates); last_step; blocking_findings; discoveries.`,
  ].filter(Boolean).join('\n')
}

function mergeBuild(r) {
  build.branch = r.branch || build.branch
  build.lastStep = r.last_step
  // A step this dispatch built is verified when its signal and every gate its
  // files trigger passed. Only a verified step may be kept by a later dispatch.
  for (const rep of r.steps.filter(x => x.status !== 'kept')) {
    const s = steps.list.find(x => x.n === rep.n)
    const gatesPassed = requiredGates('step', rep.changed_files).every(g => rep.gates.some(x => x.name === g.name && x.passed))
    if (s && rep.signal_passed && gatesPassed && nonEmpty(rep.commit)) {
      build.verified = [
        ...build.verified.filter(v => !(v.commit === rep.commit && v.title === s.title)),
        { commit: rep.commit, title: s.title, decisions: s.decisions },
      ]
    }
  }
  build.addressed = unique([...build.addressed, ...r.carried.filter(c => c.addressed && nonEmpty(c.evidence)).map(c => c.id)])
  build.repros = unique([...build.repros, ...r.repros.filter(x => x.failed_on_base).map(x => x.test)])
  for (const m of r.mutations) {
    build.mutations[m.decision] = m
  }
  build.changedFiles = unique([...build.changedFiles, ...r.changed_files.map(normalisePath)])
  build.discoveries = unique([...build.discoveries, ...r.discoveries])
  if (r.approval_recorded && approval) {
    approval.recorded = true
  }
}

// The builder's report is checked against the profile and the steps: every
// step reported, each step it built with its signal and the gates its files
// trigger, each step it kept verified before and passing its signal again,
// every carried finding addressed, every repro failing on the base, every pin
// mutated, the final gates. `verifiedBefore` holds the steps, by title and
// commit, that earlier dispatches verified.
function buildProblems(r, verifiedBefore) {
  const problems = []
  for (const t of steps.repros) {
    if (!build.repros.includes(t)) {
      problems.push(`repro ${t} is not recorded failing on the base commit`)
    }
  }
  for (const s of steps.list) {
    const rep = r.steps.find(x => x.n === s.n)
    if (!rep) {
      problems.push(`step ${s.n} is not reported`)
      continue
    }
    if (!nonEmpty(rep.commit)) {
      problems.push(`step ${s.n} names no commit`)
    }
    if (rep.status === 'kept') {
      if (!verifiedBefore.some(v => v.commit === rep.commit && v.title === s.title)) {
        problems.push(`step ${s.n} is reported kept, but commit ${rep.commit} was not verified as this step ("${s.title}") in an earlier dispatch, or carries a changed decision: build it`)
      } else if (!rep.signal_passed) {
        problems.push(`step ${s.n} is reported kept, but its signal did not pass again`)
      }
      continue
    }
    if (!rep.signal_passed) {
      problems.push(`step ${s.n}'s signal did not pass`)
    }
    for (const g of requiredGates('step', rep.changed_files)) {
      const ran = rep.gates.find(x => x.name === g.name)
      if (!ran) {
        problems.push(`step ${s.n} changed files that trigger ${g.name}, which it did not run`)
      } else if (!ran.passed) {
        problems.push(`step ${s.n} failed ${g.name}`)
      }
    }
  }
  for (const c of steps.carried) {
    if (!build.addressed.includes(c.id)) {
      problems.push(`carried finding ${c.id} is not reported addressed with evidence`)
    }
  }
  problems.push(...steps.pins.map(mutationProblem).filter(Boolean))
  for (const c of checks.filter(c => !r.plan_checks.some(x => x.name === c.name))) {
    problems.push(`plan check ${c.name} was not reported`)
  }
  for (const g of requiredGates('final', r.changed_files)) {
    const ran = r.final_gates.find(x => x.name === g.name)
    if (!ran) {
      problems.push(`the change triggers final gate ${g.name}, which did not run`)
    } else if (!ran.passed) {
      problems.push(`final gate ${g.name} failed`)
    }
  }
  if (approval && !approval.recorded) {
    problems.push('the Approval record was not appended to the audit file')
  }
  return problems
}

// The steps of the list some build report verified, by the title mergeBuild
// records, and the pins with a recorded mutation. Neither can shrink within a
// build phase, and both are bounded by the steps and the pins.
const settled = () => steps.list.filter(s => build.verified.some(v => v.title === s.title)).length
  + steps.pins.filter(p => build.mutations[p.decision]).length

// Returns the builder's blocking findings for a revision, or none once the
// build is complete. A builder whose context is compacted hands over: an
// incomplete report that settled something is continued by a fresh builder,
// and only a report that broke the contract spends the one retry.
async function buildPhase() {
  phase('Build')
  let problems = []
  let breaches = 0
  for (;;) {
    buildCalls += 1
    const r = await dispatch('builder', label('build', buildCalls), () => buildPrompt(problems), BUILD_SCHEMA, 'Build', ISOLATE)
    if (r === null) {
      failed('build', `The builder returned nothing: it was skipped or died. Its committed steps are on ${build.branch ?? buildBranch}; the next builder continues after the last one.`)
    }
    const verifiedBefore = [...build.verified]
    const settledBefore = settled()
    mergeBuild(r)
    if (nonEmpty(r.precondition)) {
      failed('build', `The builder stopped on a precondition: ${r.precondition}`)
    }
    if (r.blocking_findings.length > 0) {
      return r.blocking_findings.map((f, i) => ({ ...f, id: `build-r${revisions}-${i + 1}`, lens: 'build' }))
    }
    if (!r.complete && settled() > settledBefore) {
      metrics.handovers += 1
      problems = []
      log(`The builder handed over after step ${r.last_step}; a fresh builder continues.`)
      continue
    }
    problems = r.complete ? buildProblems(r, verifiedBefore) : ['you stopped before the final gates with no blocking finding and no precondition: continue from your last committed step']
    if (problems.length === 0) {
      build.rework = null
      log(`Build complete on ${build.branch}.`)
      return []
    }
    breaches += 1
    if (breaches === 2) {
      failed('build', `The build result broke its contract twice: ${problems.join('; ')}`)
    }
    log(`The build result has ${problems.length} problem(s); dispatching the builder once more.`)
  }
}

// A revision after approval: the planner revises, then a re-round of the
// consistency and executability lenses (and any lens that fails) converges,
// and the plan is approved again. The builder later reworks the committed
// steps that carry a changed decision.
async function implementationRevision(findings, origin) {
  received = received.concat(findings)
  pendingLenses = EXECUTABILITY_LENS ? [EXECUTABILITY] : null
  if (spent.implementationRevisions >= BUDGET.implementationRevisions) {
    stop('budget-spent', 'revise', {
      budget: 'implementationRevisions',
      diagnosis: diagnosis(),
      note: `The ${BUDGET.implementationRevisions} implementation revision(s) of this launch are spent; the ${origin} raised blocking findings. ${STATUS_INFO['budget-spent'].action}`,
    })
  }
  spent.implementationRevisions += 1
  metrics.implementationRevisions += 1
  await revise(origin, [])
  pendingLenses = null
  await converge([CONSISTENCY_LENS, EXECUTABILITY_LENS].filter(Boolean))
  approve(`converged after implementation revision ${revisions}: the last round raised no failing finding.`)
  steps = null
}

// ---- accept --------------------------------------------------------------

function reviewPrompt(loop, previous) {
  const reviewFiles = build.changedFiles.filter(p => !p.startsWith(`${DIR}/`))
  const branch = build.branch ?? buildBranch
  // The reviewer judges against what the owner asked for. The open questions
  // and the owner's decisions are settled in the plan, which it never reads.
  const ownerLists = [
    ['User-visible behaviour the owner requires', requirements.user_visible_behavior],
    ['Constraints the owner requires', requirements.constraints],
    ['Non-goals the owner excluded', requirements.non_goals],
  ].filter(([, items]) => items.length > 0).map(([title, items]) => [`${title}:`, ...items.map(x => `- ${x}`)].join('\n'))
  return [
    `Request, verbatim:`,
    request,
    ...ownerLists,
    ``,
    `Acceptance criteria, verbatim:`,
    ...numberedCriteria,
    ``,
    `Base commit: ${baseRef}`,
    `The change is committed on ${branch}. Run git diff --name-only ${baseRef} ${branch} for every file it changed.`,
    `Files the builder reports changing:`,
    ...(reviewFiles.length > 0 ? reviewFiles.map(p => `- ${p}`) : [`(none)`]),
    worktreeLine,
    ``,
    GUIDANCE.length > 0 ? `The architecture rules of the modules it touches: ${GUIDANCE.join(', ')}.` : ``,
    reviewConventionsLine,
    hotPathBlock,
    previous.length > 0 ? `Review ${loop}. The previous review raised the findings below, and a fix followed. Judge every criterion again from scratch, and say in each finding's evidence whether a previous one is resolved:\n${JSON.stringify(previous, null, 2)}` : ``,
    `Write your acceptance document to ${acceptancePath}, replacing any earlier one.`,
    `Read each changed file in full. For each one git tracks, run git diff ${baseRef} ${branch} -- <file>. Run the tests the criteria name with ${branch} checked out, then switch back to the branch you started on.`,
    `In the document, quote each criterion verbatim and mark it met, partial or unmet with the evidence you observed: the test you ran or the file:line you read. Then list your findings about the code.`,
    `Report via StructuredOutput: criteria (one per criterion: its number above, status and evidence) and findings.`,
  ].filter(Boolean).join('\n')
}

// A review judges each criterion exactly once, by its number.
function judgementProblems(r) {
  const judged = byNumber(r.criteria)
  return [...judged.problems, ...judged.entries.flatMap((m, i) => m.length === 1 ? [] : [`criterion ${i + 1} is judged ${m.length} times, not once`])]
}

function fixPrompt(loop, gaps) {
  const branch = build.branch ?? buildBranch
  return [
    `Mode: fix ${loop}.`,
    `Plan: ${planPath}`,
    `Base commit: ${baseRef}`,
    `Branch: ${branch}`,
    moduleLine,
    conventionsLine,
    worktreeLine,
    ``,
    `First run git status --porcelain -- ${codePathsList}. If anything there is modified, staged or untracked on any branch but ${branch}, stop: describe it in precondition and change nothing.`,
    `Then git switch ${branch}.`,
    `The acceptance reviewer, who never reads the plan, reported these gaps:`,
    JSON.stringify(gaps, null, 2),
    `Fix each on ${branch} in new commits whose message ends with the trailer Fix: ${loop}, staging by path, and root-cause each one. A gap whose fix needs the plan changed is not yours: list it in needs_plan_change with why.`,
    hotPathBlock,
    hotPathBlock ? `On a hot path, a fix adds none of the costs these rules name; a gap that cannot be fixed without one needs the plan changed.` : ``,
    gatesBlock,
    `Run every gate, of either scope, whose condition matches the files you changed, and report each. Then switch back to the branch you started on.`,
    `Report via StructuredOutput: precondition ('' unless you stopped), fixed (the ids of the gaps you fixed), needs_plan_change, gates, changed_files.`,
  ].filter(Boolean).join('\n')
}

async function fix(loop, gaps) {
  let problems = []
  for (let attempt = 1; attempt <= 2; attempt++) {
    const r = await dispatch('builder', label('fix', loop) + (attempt === 2 ? '-again' : ''), () => [
      fixPrompt(loop, gaps),
      problems.length > 0 ? `Your previous result had these problems; correct each:\n${problems.map(p => `- ${p}`).join('\n')}` : ``,
    ].filter(Boolean).join('\n'), FIX_SCHEMA, 'Accept', ISOLATE)
    if (r === null) {
      failed('accept', 'The fixer returned nothing: it was skipped or died. Its commits, if any, are on the branch; resuming reviews it again.')
    }
    if (nonEmpty(r.precondition)) {
      failed('accept', `The fixer stopped on a precondition: ${r.precondition}`)
    }
    build.changedFiles = unique([...build.changedFiles, ...r.changed_files.map(normalisePath)])
    if (r.needs_plan_change.length > 0) {
      return { needsPlanChange: r.needs_plan_change }
    }
    problems = [
      ...gaps.filter(g => !r.fixed.includes(g.id)).map(g => `gap ${g.id} is neither fixed nor sent to the plan`),
      ...requiredGates('any', r.changed_files).flatMap(g => {
        const ran = r.gates.find(x => x.name === g.name)
        return !ran ? [`the fix changed files that trigger ${g.name}, which it did not run`] : !ran.passed ? [`${g.name} failed after the fix`] : []
      }),
    ]
    if (problems.length === 0) {
      return {}
    }
  }
  failed('accept', `The fix result broke its contract twice: ${problems.join('; ')}`)
}

async function acceptPhase() {
  phase('Accept')
  let previous = []
  for (let loop = 1; ; loop++) {
    // A review that does not judge each criterion once is refused and
    // dispatched again, told why: a judgement it left out is its own slip, not
    // a gap in the code. The result quotes each criterion from the requirements.
    let last = null
    const review = await dispatch('reviewer', label('accept', loop), rejected => [
      rejected ? `A previous review's result was refused: ${judgementProblems(rejected).join('; ')}. Review from scratch.` : ``,
      reviewPrompt(loop, previous),
    ].filter(Boolean).join('\n'), ACCEPTANCE_SCHEMA, 'Accept', ISOLATE, r => {
      last = r
      return judgementProblems(r).length === 0
    })
    if (review === null) {
      failed('accept', last ? `The acceptance reviewer's result broke its contract: ${judgementProblems(last).join('; ')}` : 'The acceptance reviewer returned nothing: it was skipped or died.')
    }
    const judged = byNumber(review.criteria).entries
    const criteria = requirements.acceptance_criteria.map((c, i) => ({ number: i + 1, criterion: c, status: judged[i][0].status, evidence: judged[i][0].evidence }))
    const unmet = criteria.filter(x => x.status !== 'met')
    const serious = review.findings.filter(f => FAILING_SEVERITIES.includes(f.severity)).map((f, i) => ({ ...f, id: `review-${loop}-${i + 1}` }))
    const fields = { acceptance: { criteria, findings: review.findings }, discoveries: build.discoveries }
    if (unmet.length === 0 && serious.length === 0) {
      stop('accepted', 'done', { ...fields, note: 'Every acceptance criterion is met and the reviewer raised no blocking or major finding.' })
    }
    if (spent.fixLoops >= BUDGET.fixLoops) {
      stop('acceptance-gaps', 'done', { ...fields, note: `Gaps remain after ${spent.fixLoops} fix round(s). ${STATUS_INFO['acceptance-gaps'].action}` })
    }
    spent.fixLoops += 1
    metrics.fixLoops += 1
    const gaps = [
      ...unmet.map(x => ({ id: `criterion-${x.number}`, location: 'acceptance criteria', severity: 'blocking', title: `Criterion not met: ${x.criterion}`, why: `${x.status}: ${x.evidence}`, suggested_direction: 'Make the criterion hold, shown by the check it names.' })),
      ...serious,
    ]
    const outcome = await fix(loop, gaps)
    if (outcome.needsPlanChange) {
      stop('acceptance-gaps', 'done', { ...fields, needsPlanChange: outcome.needsPlanChange, note: `A gap needs the plan changed. ${STATUS_INFO['acceptance-gaps'].action}` })
    }
    previous = gaps
  }
}

// ---- main ----------------------------------------------------------------

function draftPrompt() {
  return [
    `Mode: draft.`,
    `Feature slug: ${slug}`,
    moduleLine,
    `Plan: ${planPath}`,
    `Audit file: ${auditPath}`,
    `Base commit: ${baseRef}`,
    ``,
    `FIRST, check whether ${planPath} exists. If it does, write nothing and say so in aborted: a draft never overwrites a plan.`,
    ``,
    `Requirements:`,
    requirementsMarkdown,
    planRulesBlock,
    reviewedAgainstBlock,
    ``,
    rankingLine,
    `Write the plan per method section 2: every section of section 2.1 with its anchor, every architecture, performance or algorithm choice as a ranking table (section 3), and a Landing Order per section 2.7. Write the design, not its history (section 2.6).`,
    `Map every acceptance criterion to a named check in the Testing Plan that fails on the base commit, and resolve every open question in the body unless it needs the owner.`,
    `Create the audit file ${auditPath} with a one-line title if it does not exist.`,
    planChecksBlock('stamp'),
    `Report via StructuredOutput: aborted ('' unless you refused); decisions (every d<N> anchor in the plan); premises (method section 2.8: each load-bearing runtime or engine claim that reading the source cannot settle, with its decision and the smallest experiment that settles it; read the source first); scope_questions (each requirement conflict or gap you could not resolve, with its options and your recommendation).`,
  ].filter(Boolean).join('\n')
}

async function draft() {
  phase('Plan')
  const d = await dispatch('planner', 'plan:draft', draftPrompt, DRAFT_SCHEMA, 'Plan')
  if (d === null) {
    failed('draft', 'The planner returned nothing: it was skipped or died. Delete a partial plan, then resume to draft again.')
  }
  if (nonEmpty(d.aborted)) {
    failed('draft', `The planner refused to draft: ${d.aborted}. Pick another slug, or resume with start "revise" and priorFindings.`)
  }
  decisions = d.decisions
  for (const p of d.premises) {
    premises.push({ ...p, status: 'open', observed: '' })
  }
  log(`Draft written to ${planPath}: ${decisions.length} decision(s), ${d.premises.length} premise(s).`)
  if (d.scope_questions.length > 0) {
    scopeQuestions = d.scope_questions
    stop('needs-scope', 'revise', { scopeQuestions: d.scope_questions, note: STATUS_INFO['needs-scope'].action })
  }
}

async function main() {
  if (START === 'draft') {
    await draft()
  }
  let opened = false
  if (START === 'revise') {
    received = received.concat(priorFindings.map(f => ({ ...f, id: `owner-r${revisions}-${f.id}`, lens: 'owner' })))
    log(`Resuming at the revision with ${received.length} finding(s).`)
    await revise(priorFindings.length > 0 ? 'owner' : 'resume', [])
    opened = true
  }
  if (reaches('critique')) {
    const queued = (pendingLenses ?? []).map(lensByKey).filter(Boolean)
    pendingLenses = null
    await converge(opened ? [...queued, CONSISTENCY_LENS] : queued.length > 0 ? queued : SWEEP)
    approve(`converged: the last round raised no failing finding, these lenses have reported on a version of this plan: ${POOL.filter(l => swept.has(l.key)).map(l => l.key).join(', ')}, and no premise is open.`)
  } else if (ownerApproval !== undefined) {
    approve(`the owner's approval: ${ownerApproval}`)
  }
  if (START !== 'accept') {
    // Steps are extracted from the plan as approved now; only a resumed build
    // continues against the steps it was given.
    if (START !== 'build') {
      steps = null
    }
    for (;;) {
      if (!steps) {
        const gaps = await extract()
        if (gaps.length > 0) {
          await implementationRevision(gaps, 'steps')
          continue
        }
      }
      const blocking = await buildPhase()
      if (blocking.length === 0) {
        break
      }
      await implementationRevision(blocking, 'build')
    }
  }
  await acceptPhase()
}

try {
  await main()
  throw new Error('the run ended without a result')
} catch (e) {
  if (e instanceof Stop) {
    return e.result
  }
  throw e
}
