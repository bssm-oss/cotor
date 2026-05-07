# Cotor Documentation

This directory is the current documentation entrypoint for the Cotor repository.
Historical reports and older design drafts are useful context, but current behavior must match the Kotlin, Swift, and shell sources listed below.

Korean companion documents use the same path with `.ko.md` when available.

## Start Here

- [Quick Start](QUICK_START.md): install and first run
- [Architecture](ARCHITECTURE.md): current runtime boundaries and data flow
- [Module Boundaries](modules/README.md): ownership, entrypoints, and allowed dependency directions
- [Desktop App](DESKTOP_APP.md): localhost app-server and macOS shell behavior
- [Features](FEATURES.md): code-backed capability inventory
- [Capabilities](CAPABILITIES.md): company agent capabilities, skills, and policy gates
- [Test Plan](TEST_PLAN.md): automated, CLI, desktop, and company runtime validation
- [Troubleshooting](TROUBLESHOOTING.md): recovery paths for desktop, GitHub, company runtime, QA/CEO, and interactive sessions
- [Team Ops](team-ops/README.md): maintainer and review workflows

## Codebase Truth Anchors

- CLI bootstrap: `src/main/kotlin/com/cotor/Main.kt`
- CLI commands: `src/main/kotlin/com/cotor/presentation/cli/`
- local HTTP API: `src/main/kotlin/com/cotor/app/AppServer.kt`
- company workflow service: `src/main/kotlin/com/cotor/app/DesktopAppService.kt`
- app-server DTOs: `src/main/kotlin/com/cotor/app/DesktopModels.kt`
- generic pipeline runtime: `src/main/kotlin/com/cotor/domain/`
- runtime state, actions, and replay: `src/main/kotlin/com/cotor/runtime/`
- policy/evidence/memory: `src/main/kotlin/com/cotor/policy/`, `src/main/kotlin/com/cotor/provenance/`, `src/main/kotlin/com/cotor/knowledge/`
- provider and process adapters: `src/main/kotlin/com/cotor/data/plugin/`, `src/main/kotlin/com/cotor/data/process/`, `src/main/kotlin/com/cotor/providers/`
- macOS shell: `macos/Sources/CotorDesktopApp/`

When docs and code disagree, fix the docs from the code. If code appears to violate the intended product model, document the risk in the PR instead of rewriting the product story around the bug.

## Graphify Workflow

Graphify is the fast path for architecture/debug/refactor questions.

- Read `graphify-out/GRAPH_REPORT.md` before broad repo exploration.
- Use `graphify query`, `graphify path`, or `graphify explain` to narrow a subgraph for specific questions.
- Do not paste `graphify-out/graph.json` into prompts or docs. It is tracked graph data, not human documentation.

Commands from the repository root:

```bash
graphify .                  # initial graph build
graphify update .           # refresh after code or documentation changes
graphify cluster-only .     # recompute communities after larger structure changes
graphify hook status
graphify hook install
graphify claude install
graphify codex install
graphify opencode install
```

Assistant slash-command environments may expose the same flow as `/graphify .`, `/graphify . --update`, and `/graphify . --cluster-only`.

## Validation Commands

```bash
cotor version
./gradlew formatCheck
./gradlew test -x jacocoTestReport -x jacocoTestCoverageVerification
swift build --package-path macos
swift test --package-path macos
graphify update .
```

## Historical Records

Use [INDEX.md](INDEX.md) for the full router. Files under `docs/reports/`, `docs/release/`, `docs/changes/`, and `docs/rfcs/` are historical or release-scoped unless linked from current docs.
