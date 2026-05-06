# CEO Continuous Improvement Cycle #1 -- Product Strategy Review

Date: 2026-05-04
Role: Product Strategist
Source: Full E2E QA 20260504-202848

---

## 1. Company State Assessment

Cotor is a Kotlin-based local-first AI workflow runner that has evolved into a company-style AI operating system. The core delivers CLI/TUI orchestration, a macOS desktop shell, a localhost web editor, and an app-server API -- all sharing one Kotlin runtime. A multi-company operations layer sits on top with goals, issues, review queues, a runtime loop, activity feeds, and per-agent git worktree isolation.

### What is production-ready

- Pipeline execution (SEQUENTIAL, PARALLEL, DAG) with validation, linting, status, stats, checkpoints, and template generation
- Company-mode operations: create companies, define agents, set goals, decompose into issues, delegate and run, review and merge
- macOS Desktop with Company shell, Meeting Room, Board/Canvas, Chat Control, runtime panel, and TUI mode
- Policy engine v1 with validate/simulate/enforcement and audit trails
- Capability-based security model with action classification (GIT_READ/GIT_WRITE, PACKAGE_INSTALL, TEST_RUN, BUILD_RUN, etc.)
- GitHub control-plane v1 with state sync, mergeability checks, and PR lifecycle management
- Evidence/provenance graph v1, structured knowledge store v1, verification bundles
- Read-only MCP runtime exposure through app-server
- Estimated AI spend tracking with daily/monthly cost guardrails
- Multi-agent execution with per-company agent roster, model overrides, and parallel dispatch
- Autonomous runtime loop: decomposes goals, delegates, executes, QA-reviews, and progresses toward merge -- all without user intervention after goal input

### What is partial / needs hardening

- Company issue/review durable continuation beyond default issue-run inspection
- CheckpointManager stores flat stage summaries rather than a causal execution graph
- Policy DSL is file-backed v1 -- richer expressions (runtime windows, secret scopes, budget-native clauses) are missing
- GitHub sync is `gh`-driven rather than webhook-native -- no merge queue awareness, no required-check semantics, no branch protection modeling
- Knowledge retrieval is read-oriented with shallow planner/reviewer depth -- no vector retrieval, no conflict resolution
- `DesktopAppService.kt` remains a large concentration point for side effects
- Side-effect store/interceptor migration is not complete across all mutating paths
- Draft docs and current code disagree in some places (follow-up generation, remote runners)

---

## 2. Recent Wins

### Cycle #1 QA yielded verified progress across every surface

| Area | Status | Key Result |
|---|---|---|
| Gradle build + test | PASS | `formatCheck test shadowJar` -- all green |
| Swift/macOS | PASS | 44 tests pass, build complete |
| CLI full surface | PASS | `init`, `run`, `validate`, `lint`, `provider scan`, `agent`, `capability`, `skill`, `policy simulate` -- all verified |
| App-server API | PASS | 20+ routes verified including company CRUD, runtime control, capability simulation, MCP read-only split |
| macOS Desktop | PASS | Company shell, Meeting Room, Board, Chat Control, TUI mode all QA'd with screenshots |
| Autonomous Company | PASS | Gemma4 sandbox: goal decomposition, runtime auto-start, multi-issue planning verified |
| Policy enforcement | PASS | All default capability DISABLED/APPROVAL_REQUIRED states confirmed across git, browser, video, MCP actions |
| Web editor | PASS | Read-only mode, company dashboard rendering -- no console errors |

### Specific regressions fixed this cycle

- **Capability guard regression**: `cotor run` starter pipeline was blocked by `AgentCapabilityGuard` for generic unscoped agent execution. Fixed: subject-required GitHub/Git publish mutations stay guarded but generic pipeline execution is restored. Regression test added: `unscoped generic agent execution stays outside company capability authority`.
- **Map file existence guard**: macOS raw file error was leaking on Meeting Room map view when `graph.json` was absent. Fixed with pre-existence check.
- **UI terminology**: Technical terms like `Brain Structure`, `graphify`, `graph.json` removed from default and empty-state views.

### Infrastructure hardening

- Internal A2A v1 routes under `/api/a2a/v1/*` with session open, message post, FIFO pull, snapshot, and artifact metadata registration
- In-memory dedupe via `dedupeKey` and lightweight A2A envelope/session models
- Desktop issue detail now renders recent A2A handoffs and thread activity
- CI job/step timeouts plus `--stacktrace` on Gradle test execution
- Shared test shutdown registry for `DesktopAppService`
- `DesktopStateStore` lock acquisition hardened with bounded retries and lock-holder diagnostics
- `git diff --check` passes -- no whitespace/merge issues
- Graphify regeneration: 3793 nodes, 4769 edges, 285 communities

---

## 3. Unresolved Product Gaps (Ranked by Strategic Impact)

### P0: Must address in Cycle #2

**3.1 Durable Runtime Continuation (Company/Run Lifecycle)**

The core checkpoint/resume machinery works for generic pipelines, but company issue and review workflow continuation is incomplete. When a company run is interrupted (app-server crash, process exit, manual stop), re-queueing works but the full `continue/fork/approve` path for company issues is experimental. Dead-letter and quarantine UI do not exist -- operators cannot inspect or retry permanently failed runs through a UI surface.

*Impact*: Operational reliability. Without full durable continuation, the autonomous company claim is incomplete -- a crash mid-workflow can lose causal context even if re-queue recovers the raw task.

**3.2 GitHub Control Plane: Webhook-Native Ingestion**

The current GitHub integration is `gh`-driven: it polls or syncs on explicit commands. This means merge queue awareness, required-check semantics, and branch protection modeling are absent. PR state can drift between sync cycles. Self-review edge cases and stale merge-conflict detection work but add latency.

*Impact*: Multi-company autonomous operation at scale. `gh`-driven sync cannot match the responsiveness of webhook-native flows, and merge queue awareness is required for real CI/CD integration.

**3.3 Policy Engine: Richer DSL and Authoring UX**

The v1 policy engine works for action-level allow/deny/approval with scoped path and network heuristics. But richer policy expressions -- runtime windows, secret scopes, budget-native clauses, per-goal/per-agent policy overrides, and a dedicated authoring UI -- do not exist.

*Impact*: Security and governance depth. As companies grow in autonomy, flat policy configurations will not express the nuanced rules operators need. Budget-native policies in particular are a differentiator.

### P1: Should address in Cycle #2-3

**3.4 Knowledge Layer Depth**

The knowledge store is structured, attributable, and freshness-aware, but retrieval is read-oriented. Planner and reviewer prompts access shallow context. There is no vector retrieval, no conflict resolution workflow, and no way to merge conflicting knowledge across agents.

*Impact*: Agent quality. Shallow retrieval means agents make decisions with incomplete context, especially in multi-issue portfolios where cross-issue knowledge matters.

**3.5 Side-Effect Interceptor Migration**

An action store/interceptor substrate exists for key agent/git/github paths, but not every mutating path is migrated. `DesktopAppService.kt` remains a large concentration point for side effects.

*Impact*: Auditability and replay correctness. Every un-migrated path bypasses the action store, creating blind spots in the evidence graph and replay safety.

**3.6 Provenance Graph Visual/Export Surface**

The evidence/provenance graph v1 persists contract and outcome state locally. But there is no visual UI to explore the graph and no export surface for external audit or compliance.

*Impact*: Observability. The data exists but operators cannot visually trace goal-issue-run-review-merge lineage.

### P2: Deferred to Cycle #3+

**3.7 Dead-letter / Quarantine UI** -- needed for operational reliability but gated on durable runtime maturity.

**3.8 Write-capable MCP Tools** -- read-only MCP is shipped, write tools are deferred to ensure the control token/auth model is right.

**3.9 Richer Capability UI** -- per-agent capability management works in the desktop app, but batch operations, risk preview, and policy simulation from UI are missing.

**3.10 Remote Runner / Multi-Machine Execution** -- the architecture anticipates remote runners but the implementation is partial. This is a scale concern, not a correctness concern.

---

## 4. Strategic Recommendations for Cycle #2

### Focus: Complete the autonomous company loop

The biggest gap between what Cotor claims and what it delivers operationally is durable continuation. A company goal should survive any single-process failure, any app restart, any machine reboot -- and continue from exactly where it left off. Cycle #2 should harden this path before investing in new features.

### Order of investment

| Priority | Area | Estimated Effort | Risk |
|---|---|---|---|
| 1 | Durable company issue/review continuation | 2-3 weeks | Medium (touches runtime core) |
| 2 | Policy DSL v2 with budget-native clauses | 2-3 weeks | Low (parallel to runtime) |
| 3 | Provenance visual UI | 1-2 weeks | Low (frontend-only) |
| 4 | Webhook-native GitHub ingestion design | 1 week design | Low (design phase only) |

### What not to build yet

- Remote runners / multi-machine execution -- the local-first story needs to be fully reliable first
- Write-capable MCP tools -- let the control token model season
- Linear/GitLab integrations -- one GitHub integration at full depth beats two at half depth

### Risk note

The `DesktopAppService.kt` concentration point is a gradual risk. Every cycle should move one or two paths into the interceptor substrate. If this is deferred for three cycles, the refactor cost becomes prohibitive.

---

## 5. Branch Outcome Validation

This review was produced in the `cotor-full-e2e-qa-20260504-202848` worktree context. The findings draw from:

- `CURRENT_STATE.md` -- current company state assessment
- `GAP_ANALYSIS.md` -- highest-leverage missing capabilities
- `IMPLEMENTED_NOW.md` -- completed work in this slice
- `CHECKPOINT_FIX_SUMMARY.md` -- checkpoint integration verification
- `docs/FULL_E2E_QA_RESULTS.ko.md` -- full E2E QA results (2026-05-04)
- `docs/FULL_E2E_QA_CHECKLIST.ko.md` -- exhaustive QA checklist
- `docs/CHANGELOG.md` -- unreleased changelog
- `docs/IMPROVEMENT_ISSUES.md` -- historical improvement tracker

All references are to the main cotor repository at `/Users/Projects/bssm-oss/cotor-organization/cotor/`.

**Validation**: Gradle formatCheck + test + shadowJar will be run after all changes in this cycle are complete.
