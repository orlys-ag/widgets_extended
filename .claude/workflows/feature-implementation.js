export const meta = {
  name: 'feature-implementation',
  description: 'Plan, five-lens critique, revise, fresh angle, kept trial, approve, checklist, implement. Bounded rounds with a coverage floor.',
  whenToUse: 'When a widgets_extended feature or bugfix should be designed and built end to end with adversarial review and a kept trial. Pass {slug, requirements} via args; use the feature-start skill to build them.',
  phases: [
    { title: 'Plan', detail: 'Draft the plan document from the requirements.' },
    { title: 'Critique', detail: 'Five lenses in parallel, covering the ten audit angles. A revision re-runs only the lenses that blocked, plus a consistency guard.' },
    { title: 'Revise', detail: 'Address blocking findings in place.' },
    { title: 'Fresh Angle', detail: 'One lens drawn from a pool of angles that have not run yet, spent after one use. A clean standard sweep alone measures the lens, not the artifact, and neither does a lens clearing on its second pass.' },
    { title: 'Trial', detail: 'Apply the highest-risk section on a branch and run the gates. The diff is kept.' },
    { title: 'Approve', detail: 'Stamp PLAN-STATUS ready-to-implement.' },
    { title: 'Checklist', detail: 'Emit the phased checklist.' },
    { title: 'Implement', detail: 'Execute the checklist, ticking only on acceptance.' },
  ],
}

// ---- args ----------------------------------------------------------------

// The harness may deliver args as a JSON-encoded string. Normalize to object.
let argsObj = args
if (typeof argsObj === 'string') {
  try { argsObj = JSON.parse(argsObj) } catch { /* fall through to validation */ }
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

// The module decides which architecture document the architect, the critics
// and the implementer read. `doc/agents/sliver-tree-architecture.md` governs
// lib/sliver_tree and lib/sectioned_sliver_list; `doc/agents/board-architecture.md`
// governs lib/board. Loading the wrong one into five parallel critics is both
// the largest avoidable cost in a run and a source of contract findings against
// a document the plan never touched. Explicit `args.module` wins; otherwise it
// is derived from `modules_touched`, and a mix of both modules is an error the
// caller resolves rather than a guess this scope makes.
const MODULES = {
  sliver_tree: {
    archDoc: 'doc/agents/sliver-tree-architecture.md',
    vocabulary: 'Module vocabulary: nids and the *Nid hot-path variants, three coordinate spaces (sliver scroll, sliver paint, viewport scroll), five animation sources under AnimationCoordinator, exit and edge ghosts, sticky pins, pending-deletion nodes, TreeAnimationStyle families with a per-family zero kill switch.',
  },
  board: {
    archDoc: 'doc/agents/board-architecture.md',
    vocabulary: 'Module vocabulary: dense item ids in BoardStore with idOfKey/keyOfId (there are no nids and no onCapacityGrew; per-id arrays grow in lockstep in the store), TWO coordinate spaces (content and viewport-paint, plus track space for spans), the animation sources under BoardAnimationCoordinator (TrackResizeAnimator, ItemEnterExitAnimator, ItemSlideEngine, MakeRoomEngine), obtain-to-retain retention, OverlapLaneResolver lanes, the BoardDragController drag layer with BoardDropResolver, and BoardAnimationStyle families with a per-family zero kill switch. Where a lens focus names a sliver_tree construct (exit ghost, sticky pin, pending-deletion node, defunct scrollable), read it as the board analogue: an exiting item held by retention, a frozen track, an item mid-exit, an unlaid or detached port.',
  },
}
function deriveModule(paths) {
  const hits = new Set()
  for (const p of paths) {
    if (/^lib\/board\//.test(p)) hits.add('board')
    if (/^lib\/(sliver_tree|sectioned_sliver_list)\//.test(p)) hits.add('sliver_tree')
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
    throw new Error(`args.module is required when modules_touched does not name exactly one module (derived: ${derived.join(', ') || 'none'}). Pass "sliver_tree" or "board".`)
  }
  moduleKey = derived[0]
}
const MODULE = MODULES[moduleKey]
const ARCH_DOC = MODULE.archDoc

const planPath = `plans/${date}-${slug}-plan.md`
const checklistPath = `plans/${date}-${slug}-checklist.md`
const trialBranch = `${slug}-trial`

// Round 1 runs 5 critics; later rounds run the lenses that blocked, the ones
// that did not report, and the consistency guard. A clean sweep adds 1
// fresh-angle critic. Raising this raises the agent count fast.
// Both optional knobs are validated rather than coerced. `slug` and
// `requirements` throw on a wrong type; these two silently fell back to their
// defaults, so `maxRounds: "5"` ran two rounds and `trial: "false"` ran the
// trial, in both cases doing the opposite of what the caller asked with no
// message anywhere.
if (argsObj?.maxRounds !== undefined && !Number.isInteger(argsObj.maxRounds)) {
  throw new Error(`args.maxRounds must be an integer, got ${JSON.stringify(argsObj.maxRounds)}. A quoted number is not one, and would silently fall back to 2.`)
}
if (argsObj?.trial !== undefined && typeof argsObj.trial !== 'boolean') {
  throw new Error(`args.trial must be a boolean, got ${JSON.stringify(argsObj.trial)}. Any non-boolean is treated as true, so "false" would run the trial.`)
}
const MAX_ROUNDS = Number.isInteger(argsObj?.maxRounds) ? argsObj.maxRounds : 2
if (MAX_ROUNDS < 1) {
  throw new Error('args.maxRounds must be an integer >= 1; 0 would skip every critique round and return blocked with no findings')
}

// priorFindings enters the run at the revision phase, so each element has to be
// shaped like a critic finding or the architect gets prose where it expects
// fields. Validate here rather than letting it degrade silently inside a prompt.
const FINDING_FIELDS = ['id', 'location', 'severity', 'title', 'why', 'suggested_direction']
priorFindings.forEach((f, i) => {
  if (!f || typeof f !== 'object') {
    throw new Error(`args.priorFindings[${i}] must be an object with ${FINDING_FIELDS.join(', ')}`)
  }
  const gaps = FINDING_FIELDS.filter(k => typeof f[k] !== 'string' || f[k].length === 0)
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
  ].join('\n')
}

const requirementsMarkdown = renderRequirements(requirements)

// ---- lenses --------------------------------------------------------------

// The five standard lenses ARE plans/AUDIT-METHOD.md section 2's ten angles,
// merged onto five agents. A second taxonomy for "what to examine" would be a
// second normative site, which section 3.1 forbids. `reads` keeps each critic's
// context to what its lens actually needs: loading the 20KB architecture doc
// into all five in parallel is the single largest avoidable cost in a run.
const LENSES = [
  {
    key: 'mechanism',
    reads: [ARCH_DOC],
    focus: 'Angles 1, 8 and 9. Will the design do what the goals say? Logical gaps where something reads state nothing writes, ordering violations, re-entrancy (anything that can abort and re-run a layout), frame ordering and settle transitions. Lifecycle: creation, teardown, and every site that destroys the thing, including dispose, ticker cancellation and recognizer disposal. Degradation: what happens when a precondition is not met, on empty and single-element cases, under a zero-duration animation family (a kill switch that dominates explicit per-call durations), with a defunct scrollable, a pending-deletion node, hot reload, or a mutation issued mid-animation, mid-drag or inside a batch.',
  },
  {
    key: 'surface',
    reads: [],
    focus: 'Angles 2 and 3. Signatures, types, naming, exports. This package exports through explicit show clauses, so a symbol introduced without declaring its export is unnameable by app code and that is blocking. Enumerate the users of every shared declaration the plan changes, tests included, and check the plan enumerated them too. A plan that changes an interface without listing its implementers has skipped a required step.',
  },
  {
    key: 'contracts',
    reads: [ARCH_DOC],
    focus: 'Angles 4, 6 and 7. Does the plan contradict the module architecture document named in the Also read line, or change a documented contract without saying so? House conventions from AGENTS.md: double quotes except on imports, braces on every block, block bodies, no non-plain-text symbols anywhere. Does the plan obey AUDIT-METHOD.md 3.1 to 3.6, and is every geometric value tagged with its coordinate space? Citations: run python plans/check_citations.py on the plan (a non-zero exit is itself a finding), then spot-check that the cited lines say what the plan says they say. Every count carries the command that produced it, and every because, so, therefore, never, only, exactly and cannot carries its own citation.',
  },
  {
    key: 'tests',
    reads: ['doc/agents/testing-patterns.md'],
    focus: 'Angle 5. Is each named test writable, and will it fail on unfixed code? Does each INDIVIDUAL new assertion have a state that makes it fail, or is one assertion carrying the whole discrimination while its neighbours are inert? A setup sanity assertion that cannot fail is worse than none. Does each new debug counter or visibleForTesting member name the existing seam it rejected? Does each landing step name the test that goes green, or say why it cannot?',
  },
  {
    key: 'perf',
    reads: [ARCH_DOC],
    focus: 'Angle 10. What is O(what), and is the stated bound the one that can actually blow up. Hot paths that hash keys instead of using the Nid method variants. Anything that turns a targeted lookup into a full scan. Per-frame allocation. Whether a debug counter exists to pin the contract the plan claims, and whether the plan names the counter and the expected value.',
  },
]

// AUDIT-METHOD.md:237 requires "a freshly opened angle came back empty on its
// FIRST pass" before a plan is approvable. FIRST is the load-bearing word. A
// lens that reported blocking, saw a revision, and then cleared has come back
// empty on its SECOND pass, which is the shape AUDIT-METHOD.md section 6
// rejects outright: two clean passes measure the lens, not the artifact. So the
// fresh angle is drawn from a POOL and each entry is spent after one use.
//
// The pool is AUDIT-METHOD.md section 8's two named unsettleable classes, in
// its order, because those are the classes the document says inspection never
// closes. A third entry would be invented rather than derived, so an exhausted
// pool returns a status instead of approving on a repeat pass.
const FRESH_POOL = [
  {
    key: 'interaction',
    reads: [ARCH_DOC],
    focus: 'AUDIT-METHOD.md section 8, first unsettleable class: the feature crossed with every animation source, paint pass, mutator, widget layer and entry point. Look for the crossings the plan does not mention AT ALL rather than the ones it handles badly. A plan silent on what happens when its change coincides with a bulk animation, a reorder preview, an exit ghost or a sticky pin has not covered it.',
  },
  {
    key: 'timing',
    reads: [ARCH_DOC],
    focus: 'AUDIT-METHOD.md section 8, second unsettleable class: behaviour under real timing. The mechanism lens already swept frame ordering and re-entrancy as design questions, so do NOT repeat that. Ask section 8\'s own question instead: which of this plan\'s timing risks can only be closed by running a frame, and does the plan convert each one into a named test rather than into prose that argues it is fine? Section 8 says the remedy is skipped test stubs, so that "does the plan cover X" becomes a grep. Name every timing risk the plan settles by assertion instead of by a test: a settle transition whose notify order is described but not asserted, a scroll correction whose re-entrancy is reasoned about but not exercised, a tick whose paint-only or layout-triggering status is claimed but not pinned by a debug counter.',
  },
]

// After a revision the lenses that CLEARED are not re-run, because the sections
// they cleared did not change. This lens is what makes that safe: AUDIT-METHOD.md
// names the audit's own earlier fixes going wrong as the second most common
// defect class, so every re-critique round includes it.
const CONSISTENCY_LENS = {
  key: 'consistency',
  reads: [],
  focus: 'The revision that just happened, checked for self-inflicted damage. Grep the plan for the vocabulary the revision replaced; every surviving hit is either an explicit negation or a defect. Re-read the summary sections specifically: overview, landing order, testing plan, and any decisions list, since those are where staleness collects. Cross-references must resolve, numbering must be contiguous, and each fact must have exactly one normative site. You are also the guard for the lenses that were NOT re-run this round: if the revision touched a section outside the findings it was addressing, say so.',
}

// Fewer than this many lenses reporting means a round cannot be called clean.
// Clamped to the round's own lens count, since a targeted re-critique runs few.
const MIN_STANDARD_REPORTING = 4

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
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'location', 'severity', 'title', 'why', 'suggested_direction'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          location: { type: 'string' },
          severity: { type: 'string', enum: ['blocking', 'major', 'minor', 'nit'] },
          title: { type: 'string' },
          why: { type: 'string' },
          suggested_direction: { type: 'string' },
        },
      },
    },
  },
}

const TRIAL_SCHEMA = {
  type: 'object',
  required: ['section', 'branch', 'repro_failed_before', 'repro_passes_after', 'analyzer_clean', 'suite_green', 'commit', 'notes', 'blocking_findings'],
  additionalProperties: false,
  properties: {
    section: { type: 'string' },
    branch: { type: 'string' },
    repro_failed_before: { type: 'boolean' },
    repro_passes_after: { type: 'boolean' },
    analyzer_clean: { type: 'boolean' },
    suite_green: { type: 'boolean' },
    commit: { type: 'string' },
    notes: { type: 'string' },
    blocking_findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'location', 'severity', 'title', 'why', 'suggested_direction'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          location: { type: 'string' },
          severity: { type: 'string', enum: ['blocking', 'major', 'minor', 'nit'] },
          title: { type: 'string' },
          why: { type: 'string' },
          suggested_direction: { type: 'string' },
        },
      },
    },
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

// ---- helpers -------------------------------------------------------------

// Returns `{lens, result}` pairs, where `lens` is the lens object this scope
// DISPATCHED, not the `lens` string the critic reported. Correlating on the
// reported value made a model-side spelling ("Mechanism" for "mechanism") drop
// that lens from the re-critique set: the round still saw its blocking finding
// and revised on it, but the lens that raised it never re-ran to check the fix,
// and the coverage guard saw a lens that had reported. The workflow already
// knows which lens it sent; reading that back out of the payload was the bug.
function critiqueRound(lensSet, phaseTitle, round) {
  // Each critic resolves to null on failure rather than rejecting, so one
  // crashed lens degrades into the coverage floor below instead of taking the
  // whole round down. The floor is the mechanism that decides what a missing
  // lens means; a rejection would bypass it.
  return parallel(
    lensSet.map(lens => () =>
      agent(
        [
          `Plan path: ${planPath}`,
          `Module: ${moduleKey}. ${MODULE.vocabulary}`,
          `Lens: ${lens.key}`,
          `Focus: ${lens.focus}`,
          ``,
          `Read AGENTS.md and the plan.`,
          lens.reads.length > 0
            ? `Also read, because this lens needs them: ${lens.reads.join(', ')}.`
            : `Read nothing else from doc/agents/: this lens does not need it. Grep the codebase for what you do need.`,
          `Then emit structured findings via the StructuredOutput tool.`,
          `Stay in your assigned lens. Perform this review directly: do not spawn additional agents.`,
        ].join('\n'),
        {
          agentType: 'plan-critic',
          label: `${phaseTitle === 'Critique' ? 'critic' : 'fresh'}:${lens.key}:r${round}`,
          phase: phaseTitle,
          schema: FINDINGS_SCHEMA,
        },
      ).then(result => (result ? { lens, findings: result.findings ?? [], report: result } : null))
        .catch(err => {
          log(`Lens ${lens.key} failed in round ${round}: ${err?.message ?? err}`)
          return null
        }),
    ),
  )
}

async function revise(findings, round, note, advisory = []) {
  phase('Revise')
  const result = await agent(
    [
      `Mode: revision (round ${round}).`,
      `Existing plan path: ${planPath}`,
      `Module: ${moduleKey}; its architecture document is ${ARCH_DOC}.`,
      note ? `Context: ${note}` : ``,
      ``,
      `Blocking findings to address:`,
      JSON.stringify(findings, null, 2),
      // A revision is the only time majors reach the architect. Only blocking
      // findings trigger a round, so a major raised in a round that also blocked
      // is addressed here or it is never seen again. The architect's system
      // prompt already contracts for this input: address it, or move it to Open
      // Questions with a rationale.
      advisory.length > 0
        ? `Non-blocking findings raised in the same round. Address each one or move it to Open Questions with a stated rationale, per your system prompt. Do not let one expand the plan's scope:`
        : ``,
      advisory.length > 0 ? JSON.stringify(advisory, null, 2) : ``,
      ``,
      `Address each blocking finding in the relevant plan section using Edit, never a full-file Write.`,
      `Append a "Round ${round} Revision" section with anchor <a id="round-${round}-revision"></a>, one bullet per finding you addressed, naming the section that changed, and one per non-blocking finding you moved to Open Questions instead.`,
      `If a "Round ${round} Revision" section already exists (a resumed run can collide with a previous one), use the next unused round number instead, for both the heading and the anchor.`,
      `Do NOT change PLAN-STATUS.`,
      `Re-record the citation ledger afterwards: a revision adds and changes citations, and a new one is unrecorded until you record it. Follow the order in AGENTS.md, verify before --update, because a trial may already have moved the code under a citation you did not touch. Then run the consistency pass: grep the plan for the vocabulary you replaced.`,
    ].filter(Boolean).join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:revise-r${round}`,
      phase: 'Revise',
    },
  )
  // A dead reviser leaves the plan exactly as the critics found it, so the next
  // round re-raises the same blocking findings and the run ends at MAX_ROUNDS
  // with `blocked-after-revisions`. That is a survivable shape, but it reads as
  // "the architect could not fix these" when the truth is that it never ran.
  if (result === null) {
    log(`Round ${round} revision returned no result: the plan is unchanged, so the next round will re-raise the same findings.`)
  }
}

// ---- phase 1: draft ------------------------------------------------------

phase('Plan')

if (priorFindings.length > 0) {
  log(`Resuming: ${priorFindings.length} prior finding(s) supplied, revising the existing plan instead of drafting.`)
  await revise(priorFindings, 1, 'These came from a previous run\'s Discovered section.')
} else {
  const draft = await agent(
    [
      `Mode: initial draft.`,
      `Feature slug: ${slug}`,
      `Module: ${moduleKey}. The architecture document for this plan is ${ARCH_DOC}; read it instead of the other module's document. ${MODULE.vocabulary}`,
      `Output plan path: ${planPath}`,
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
      `Follow the operating procedure in your system prompt.`,
      `Write the plan with PLAN-STATUS: draft and every required section from doc/agents/feature-workflow-contracts.md section 3, each followed by its anchor.`,
      `Map every Acceptance Criteria item to a concrete test in the Testing Plan, and resolve every Open Question in the body unless it genuinely needs a user decision.`,
      `Record the citation ledger with python plans/check_citations.py ${planPath} --update, then verify it exits 0.`,
    ].join('\n'),
    {
      agentType: 'plan-architect',
      label: `plan:draft`,
      phase: 'Plan',
    },
  )
  // agent() resolves to null when the subagent dies on a terminal error. Without
  // this the run went on to spend five critics, a fresh angle, a trial and an
  // implementer on a plan path that may hold nothing; the critics do catch it
  // (their `plan-unreadable` finding), but only after the round is paid for.
  if (draft === null) {
    return {
      status: 'draft-failed',
      planPath,
      note: 'The architect returned no result, so the plan may not exist or may be partial. Nothing downstream can run against it. Re-run; if it fails again the requirements are the place to look.',
    }
  }
  if (typeof draft === 'string' && /^\s*ABORT:/.test(draft)) {
    return {
      status: 'draft-aborted',
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
const history = []

// Round 1 sweeps every standard lens. Later rounds re-run the lenses that
// reported blocking and the lenses that did not report at all, plus
// CONSISTENCY_LENS. A lens that CLEARED a section the revision did not touch
// has nothing new to say and re-running it is spend without coverage; a lens
// that never reported swept nothing, and dropping it retires an audit angle.
let pending = [...LENSES]

for (let round = 1; round <= MAX_ROUNDS; round++) {
  roundsRun = round

  phase('Critique')
  const targeted = round > 1
  log(`Round ${round}: ${pending.length} lens(es) in parallel${targeted ? ' (targeted re-critique)' : ''}: ${pending.map(l => l.key).join(', ')}.`)

  const standard = (await critiqueRound(pending, 'Critique', round)).filter(Boolean)
  const standardBlocking = standard.flatMap(c => c.findings.filter(f => f.severity === 'blocking'))
  const standardMajor = standard.flatMap(c => c.findings.filter(f => f.severity === 'major'))
  history.push({ round, stage: 'standard', critiques: standard })

  log(`Round ${round}: ${standardBlocking.length} blocking, ${standardMajor.length} major across ${standard.length}/${pending.length} lenses.`)

  // The floor is the smaller of the global minimum and this round's lens count,
  // so a targeted re-critique of two lenses is not judged against a five-lens
  // bar, while a full first round still cannot be called clean on three.
  const minReporting = Math.min(MIN_STANDARD_REPORTING, pending.length)
  const missingLenses = pending.map(l => l.key).filter(k => !standard.some(c => c.lens.key === k))
  if (standard.length < minReporting) {
    return {
      status: 'critique-aborted-insufficient-coverage',
      planPath,
      round,
      stage: 'standard',
      lensesPresent: standard.map(c => c.lens.key),
      lensesMissing: missingLenses,
      nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
      note: `Only ${standard.length}/${pending.length} lenses returned results; ${minReporting} were required. A round cannot be called clean below that.`,
    }
  }

  // The floor above decides whether enough lenses reported to TRUST the blocking
  // findings and revise on them. It does not license calling the round clean: a
  // round with no blocking findings and a missing lens has an unswept angle, and
  // AUDIT-METHOD.md section 6's coverage rule requires every angle on the
  // section 2 list to have been swept before a plan can be approved. Approving
  // here would silently ship a plan that four fifths of the sweep looked at.
  if (standardBlocking.length === 0 && missingLenses.length > 0) {
    return {
      status: 'critique-incomplete-coverage',
      planPath,
      round,
      roundsRun,
      lensesPresent: standard.map(c => c.lens.key),
      lensesMissing: missingLenses,
      nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
      note: `No blocking findings, but ${missingLenses.join(', ')} did not report. A clean round with an unswept angle cannot approve a plan, so the run stops here rather than proceeding. Re-run to sweep the missing lens; the plan is unchanged and still in draft.`,
    }
  }

  if (standardBlocking.length > 0) {
    if (round === MAX_ROUNDS) {
      log(`Hit MAX_ROUNDS (${MAX_ROUNDS}) with blocking findings still open.`)
      break
    }
    await revise(standardBlocking, round + 1, 'Standard round.', standardMajor)
    const failing = new Set(
      standard.filter(c => c.findings.some(f => f.severity === 'blocking')).map(c => c.lens.key),
    )
    // Carry forward the lenses that BLOCKED and the lenses that did not report
    // at all. Dropping a lens that crashed was how a run retired an audit angle
    // in silence: the coverage guard above only fires on a CLEAN round, so a
    // round that both blocked and lost a lens sent the survivors to revision and
    // never sweeps the lost one again. Demonstrated with a crashed `perf` lens
    // alongside a blocking `mechanism` lens: the run reached implementation with
    // angle 10 never swept.
    const carry = pending.filter(l => failing.has(l.key) || missingLenses.includes(l.key))
    pending = carry.some(l => l.key === CONSISTENCY_LENS.key)
      ? carry
      : carry.concat([CONSISTENCY_LENS])
    continue
  }

  // Clean. AUDIT-METHOD.md section 6 does not let that approve a plan on its
  // own, so open an angle that has not run yet. Spent entries are never reused:
  // the rule is "empty on its FIRST pass".
  const freshLens = FRESH_POOL[freshUsed]
  if (!freshLens) {
    return {
      status: 'fresh-angles-exhausted',
      planPath,
      roundsRun,
      freshAnglesUsed: FRESH_POOL.map(l => l.key),
      note: `The standard lenses are clean, but every fresh angle in the pool (${FRESH_POOL.map(l => l.key).join(', ')}) has already run on this plan. AUDIT-METHOD.md section 6 approves on a freshly opened angle coming back empty on its FIRST pass, and re-running a spent one would measure the lens instead of the artifact. The plan is revised and still in draft: open a new angle by hand, or accept it under section 6's yield rule.`,
    }
  }
  freshUsed += 1

  phase('Fresh Angle')
  log(`Round ${round} clean. Opening fresh angle ${freshUsed}/${FRESH_POOL.length}: ${freshLens.key}.`)
  const fresh = (await critiqueRound([freshLens], 'Fresh Angle', round)).filter(Boolean)
  const freshBlocking = fresh.flatMap(c => c.findings.filter(f => f.severity === 'blocking'))
  const freshMajor = fresh.flatMap(c => c.findings.filter(f => f.severity === 'major'))
  history.push({ round, stage: 'fresh', critiques: fresh })

  if (fresh.length === 0) {
    return {
      status: 'critique-aborted-insufficient-coverage',
      planPath,
      round,
      stage: 'fresh',
      lensesPresent: [],
      lensesMissing: [freshLens.key],
      nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
      note: `The fresh angle returned no result. Approval requires a freshly opened angle to come back empty on its first pass, and no result is not the same as empty.`,
    }
  }

  log(`Round ${round} fresh angle: ${freshBlocking.length} blocking.`)

  if (freshBlocking.length > 0) {
    if (round === MAX_ROUNDS) {
      log(`Hit MAX_ROUNDS (${MAX_ROUNDS}) with blocking findings open in the fresh-angle round.`)
      break
    }
    await revise(freshBlocking, round + 1, `Fresh-angle round (${freshLens.key}). These are findings on an angle the standard lenses never sweep, so treat them as first-pass findings on a new angle rather than as leftovers.`, freshMajor)
    pending = [CONSISTENCY_LENS]
    continue
  }

  approved = true
  // The angle that actually cleared, kept separately from the pool slice. The
  // approval prompt used to name every fresh angle that had RUN and call them
  // all clean, so a run where `interaction` blocked and `timing` later cleared
  // told the architect to record "interaction, timing both returned zero
  // blocking findings" and stamp that into the plan. Only the last one cleared.
  clearedFreshLens = freshLens.key
  log(`Round ${round}: standard lenses and the fresh angle both clean. Plan is approvable.`)
  break
}

// Every finding the critics produced, flattened once. Only blocking findings
// drive the loop, so without this the majors and minors that five xhigh critics
// were paid to find are logged as a count and then discarded: a plan reaches
// implementation carrying known serious problems that nobody ever reads.
function findingsAtOrBelow(severities) {
  return history.flatMap(h =>
    h.critiques.flatMap(c =>
      c.findings
        .filter(f => severities.includes(f.severity))
        .map(f => ({ round: h.round, stage: h.stage, lens: c.lens.key, ...f })),
    ),
  )
}

if (!approved) {
  return {
    status: 'blocked-after-revisions',
    planPath,
    roundsRun,
    blockingFindings: findingsAtOrBelow(['blocking']),
    nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
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
      `Module: ${moduleKey}. The module contracts are in ${ARCH_DOC}; read that document, not the other module's.`,
      ``,
      `A trial is the strongest form of auditing a solution: apply it, and see whether the code agrees with the text. Reading does not catch a plan whose text reads correctly and whose code does not.`,
      ``,
      `Procedure:`,
      `1. Read the plan and pick its highest-risk section: the one whose failure would be hardest to detect by reading, usually the one touching paint, hit-testing, or a pair rule.`,
      `2. Create the branch ${trialBranch} from the current HEAD (git switch -c ${trialBranch}). Do not work on the current branch.`,
      `2a. A failed trial keeps its branch, so a re-run after trial-failed will collide: git switch -c refuses an existing branch. Check first with git rev-parse --verify --quiet ${trialBranch}, and if it exists, branch as ${trialBranch}-2, then -3, and so on, using the first name that is free. Report the name you actually used in the branch field; downstream phases use that value, not the default.`,
      `2b. BEFORE branching, run git status --porcelain lib test. If anything under lib/ or test/ is modified, staged or untracked, STOP: report it in blocking_findings and set the gate booleans to false. git switch carries an uncommitted tree onto the new branch, so committing there sweeps unrelated in-progress work into the trial commit, and the trial's whole value is that its diff is exactly the plan section applied. Do not stash it either: that is someone else's work.`,
      `3. Write the section's repro test FIRST and confirm it FAILS on unfixed code. Record what the failure was. If it passes before any change, the repro does not discriminate and that is a blocking finding.`,
      `4. Apply that section's change.`,
      `5. Run the gates: the repro now passes, flutter analyze reports no new issues in lib/, and flutter test is green.`,
      `6. COMMIT the result on that branch, staging the files you changed and the new repro test BY PATH (git add <paths>). Do not use git commit -a: it stages tracked modifications only, so a brand new repro test file is untracked and would be left out, silently breaking the rule that the repro lands in the same commit. Keep the commit whether the gates passed or failed. Nothing is reverted: a reverted trial is a verified diff thrown away, which is the mistake the 2026-08-21 audit made with 13 of them.`,
      `7. Re-anchor the plan's citations, which your change to lib/ just drifted: run python plans/check_citations.py <plan> --repoint. It fixes the line numbers whose recorded text it can still find, and reports the rest. Do NOT run --update to force a clean result; it would anchor every citation to whatever your change moved into place. If --repoint leaves citations drifted, those are ones whose cited code your change removed or duplicated: say so in notes, because that is evidence about the plan, not bookkeeping.`,
      `8. Append a "## Trial Log" section with anchor <a id="trial-log"></a> to the plan, recording the section trialed, the branch, the commit sha, and each gate's outcome. Steps 7 and 8 are the only plan writes trial mode permits, and they are the exception your system prompt names: repointing drifted citation line numbers, and appending this section. Change nothing else in the plan, and never PLAN-STATUS.`,
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

  const gatesPassed = trial
    && trial.repro_failed_before
    && trial.repro_passes_after
    && trial.analyzer_clean
    && trial.suite_green

  if (!gatesPassed) {
    return {
      status: 'trial-failed',
      planPath,
      roundsRun,
      trial,
      trialBranch: trial?.branch ?? trialBranch,
      nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
      note: 'The plan read correctly and the trial did not pass its gates. Re-run this workflow with args.priorFindings set to the trial\'s blocking_findings. The trial branch is kept, so the next run\'s trial will branch under a suffixed name.',
    }
  }

  effectiveTrialBranch = trial.branch || trialBranch
  log(`Trial passed on ${effectiveTrialBranch} at ${trial.commit}.`)
}

// ---- phase 6: approval stamp --------------------------------------------

phase('Approve')

await agent(
  [
    `Mode: approval stamp.`,
    `Plan path: ${planPath}`,
    ``,
    `The standard lenses returned zero blocking findings as of round ${roundsRun}, and the fresh angle "${clearedFreshLens}" came back empty on its FIRST pass.`,
    // Only the LAST fresh angle cleared. Naming the earlier ones as clean would
    // put a false claim in the Approval block, which is the one section written
    // to justify the stamp.
    freshUsed > 1
      ? `Fresh angles that ran earlier and DID report blocking, then were revised: ${FRESH_POOL.slice(0, freshUsed - 1).map(l => l.key).join(', ')}. Record them as such; do not describe them as clean.`
      : ``,
    runTrial ? `The trial passed all gates on branch ${effectiveTrialBranch} at ${trial.commit}.` : `No trial was run for this plan.`,
    ``,
    `Use Edit for both changes, never a full-file Write.`,
    `Flip PLAN-STATUS to ready-to-implement and append the Approval section per your system prompt.`,
    ``,
    `Then run python plans/check_citations.py ${planPath} and record what it reports in the Approval block.`,
    runTrial
      ? `Do NOT require it to exit 0. The trial changed lib/ and already ran --repoint, so a citation --repoint could not place is EXPECTED here: your change deleted or duplicated the code the plan cites, which is evidence about the plan. Record those, and never run --update to force a clean exit; it re-anchors every citation to whatever moved into place and then reports itself clean.`
      : `It should exit 0. If it does not, re-record per AGENTS.md, and never with --update on drifted code.`,
  ].filter(Boolean).join('\n'),
  {
    agentType: 'plan-architect',
    label: `plan:approve`,
    phase: 'Approve',
  },
)

// ---- phase 7: checklist --------------------------------------------------

phase('Checklist')

const checklist = await agent(
  [
    `Plan path: ${planPath}`,
    `Checklist path: ${checklistPath}`,
    `Module: ${moduleKey}.`,
    ``,
    `Verify the plan is ready-to-implement, then emit the grouped checklist per your system prompt and doc/agents/feature-workflow-contracts.md section 5.`,
    `Confirm every anchor you link actually exists in the plan before emitting the link.`,
    `Report the result via StructuredOutput. Do not also write a prose summary.`,
  ].join('\n'),
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
const reportedChecklist = typeof checklist?.checklist_path === 'string'
  ? checklist.checklist_path.split(String.fromCharCode(92)).join('/')
  : null
const checklistPathMatches = reportedChecklist !== null
  && (reportedChecklist === checklistPath || reportedChecklist.endsWith('/' + checklistPath))
if (!checklist || !checklistPathMatches) {
  return {
    status: 'checklist-failed',
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

// Precondition 3, at least one unchecked item. Phase 4 alone carries the three
// mandatory gates from AUDIT-METHOD.md section 10, so a checklist below that is
// malformed rather than merely short.
const phaseCounts = checklist.phase_counts ?? {}
const totalItems = ['phase1', 'phase2', 'phase3', 'phase4']
  .reduce((n, k) => n + (Number.isInteger(phaseCounts[k]) ? phaseCounts[k] : 0), 0)
if (totalItems === 0 || (Number.isInteger(phaseCounts.phase4) && phaseCounts.phase4 < 3)) {
  return {
    status: 'checklist-malformed',
    planPath,
    checklistPath,
    roundsRun,
    trialBranch: effectiveTrialBranch,
    phaseCounts,
    nonblockingDiscoveries: checklist.nonblocking_discoveries ?? [],
    note: `The checklist has ${totalItems} phase item(s) with ${phaseCounts.phase4 ?? 0} in Phase 4. Phase 4 always carries at least the three gates from AUDIT-METHOD.md section 10, so this checklist would abort the implementer or verify nothing. Re-run the checklist phase against the approved plan.`,
  }
}

// Precondition 4, no blocking Discovered items.
const checklistBlockers = checklist.blocking_discoveries ?? []
if (checklistBlockers.length > 0) {
  return {
    status: 'checklist-blocked',
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

const implementationReport = await agent(
  [
    `Plan path: ${planPath}`,
    `Checklist path: ${checklistPath}`,
    `Module: ${moduleKey}. The module contracts are in ${ARCH_DOC}; read that document, not the other module's.`,
    runTrial ? `A trial of one section is already committed on ${effectiveTrialBranch}. Work from that branch so the trial is not duplicated or reverted.` : ``,
    ``,
    `Execute the checklist in order per your system prompt.`,
    `Tick a box only when you have run its acceptance signal and observed it pass.`,
    `Flip CHECKLIST-STATUS to complete only when every Phase 1 to 4 item is ticked AND no Discovered item has Blocking: yes.`,
  ].filter(Boolean).join('\n'),
  {
    agentType: 'plan-implementer',
    label: `implement`,
    phase: 'Implement',
  },
)

return {
  status: 'implementation-attempted',
  module: moduleKey,
  planPath,
  checklistPath,
  trialBranch: effectiveTrialBranch,
  roundsRun,
  freshAnglesRun: FRESH_POOL.slice(0, freshUsed).map(l => l.key),
  trial,
  // Only blocking findings drove the loop. These were raised by the critics and
  // never gated anything, so they reach the reader here or not at all.
  nonBlockingFindings: findingsAtOrBelow(['major', 'minor', 'nit']),
  nonblockingDiscoveries: checklist.nonblocking_discoveries ?? [],
  implementationReport,
}
