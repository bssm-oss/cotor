# Cotor Module Boundaries

Use this guide when changing source layout, public entrypoints, route payloads, or cross-domain imports. It complements [docs/ARCHITECTURE.md](../ARCHITECTURE.md) and should stay concise enough for AI assistants to read before editing.

## Boundary Rules

- UI and route adapters call into application/domain services; lower layers do not import SwiftUI, route DTOs, or desktop view state.
- `DesktopAppService.kt` coordinates company workflow policy. It can call execution, provider, GitHub, policy, evidence, and store modules, but those modules should not encode desktop product UX.
- Public API changes must include a compatibility shim or migration note and update Kotlin DTOs, Swift DTOs, docs, and tests together.
- Avoid new folders named only `utils`, `helpers`, `common`, `misc`, `manager`, or `service`. Name modules by domain responsibility.
- After source or documentation changes, run `graphify update .`; after large boundary moves, also run `graphify cluster-only .`.

## Module Map

| Module | Responsibility | Public entrypoints | Tests |
| --- | --- | --- | --- |
| CLI and presentation | command parsing, interactive/TUI launch, web adapters, output formatting | `src/main/kotlin/com/cotor/Main.kt`, `src/main/kotlin/com/cotor/presentation/cli/Commands.kt`, `src/main/kotlin/com/cotor/presentation/cli/InteractiveCommand.kt` | `src/test/kotlin/com/cotor/presentation/cli/`, CLI-focused integration tests |
| App server and company workflow | localhost `/api/app` routes, company dashboard/runtime/goals/issues/reviews/reports/operator chat, native Test Center, runtime retention | `src/main/kotlin/com/cotor/app/AppServer.kt`, `src/main/kotlin/com/cotor/app/DesktopAppService.kt`, `src/main/kotlin/com/cotor/app/CotorTestCenterService.kt`, `src/main/kotlin/com/cotor/app/DesktopModels.kt`, `src/main/kotlin/com/cotor/app/AppApiModels.kt`, `src/main/kotlin/com/cotor/app/CompanyRuntimeRetention.kt` | `src/test/kotlin/com/cotor/app/` |
| Generic pipeline runtime | pipeline orchestration, stage execution, deterministic guards, stuck/conflict detection, conditions, aggregation, checkpoints | `src/main/kotlin/com/cotor/domain/orchestrator/`, `src/main/kotlin/com/cotor/domain/executor/` | domain/orchestrator and executor tests under `src/test/kotlin/com/cotor/` |
| Agent/provider execution | provider plugins, local process execution, model routing, OpenCode/Codex/local model adapters | `src/main/kotlin/com/cotor/data/plugin/`, `src/main/kotlin/com/cotor/data/process/`, `src/main/kotlin/com/cotor/model/` | plugin/model/process tests under `src/test/kotlin/com/cotor/` |
| Runtime evidence and memory | durable actions, provenance, knowledge memory, verification bundles, A2A context | `src/main/kotlin/com/cotor/runtime/`, `src/main/kotlin/com/cotor/provenance/`, `src/main/kotlin/com/cotor/knowledge/`, `src/main/kotlin/com/cotor/verification/`, `src/main/kotlin/com/cotor/context/` | runtime/provenance/knowledge/verification tests |
| Policy and security | action allow/deny/approval decisions, executable allow-list, path and destructive command checks | `src/main/kotlin/com/cotor/policy/`, `src/main/kotlin/com/cotor/security/` | policy/security tests |
| GitHub and external integrations | GitHub branch/PR/check state, Linear mirror, external provider boundaries | `src/main/kotlin/com/cotor/providers/github/`, `src/main/kotlin/com/cotor/integrations/linear/`, `src/main/kotlin/com/cotor/app/GitWorkspaceService.kt` | GitWorkspace/AppServer/provider tests |
| macOS desktop | SwiftUI shell, DTO decode, HTTP client, embedded backend launcher, meeting-room projection | `macos/Sources/CotorDesktopApp/DesktopAPI.swift`, `macos/Sources/CotorDesktopApp/DesktopStore.swift`, `macos/Sources/CotorDesktopApp/Models.swift`, `macos/Sources/CotorDesktopApp/ContentView.swift` | `macos/Tests/CotorDesktopAppTests/` |
| Packaging and install | shell launcher, desktop app bundle, Homebrew formula, packaged runtime layout | `shell/cotor`, `shell/install-desktop-app.sh`, `shell/build-desktop-app-bundle.sh`, `Formula/cotor.rb` | install/packaging smoke plus relevant Kotlin tests |
| Graphify and docs corpus | graph report, query workflow, generated graph outputs, assistant source-of-truth docs | `graphify-out/GRAPH_REPORT.md`, `.graphifyignore`, `AGENTS.md`, `CLAUDE.md`, `docs/README.md` | `graphify update .`, path/link checks |

## Detailed Module Notes

### CLI and presentation

- Responsibility: expose commands and interactive/web surfaces without owning company workflow rules.
- Public entrypoints: `Main.kt`, `Commands.kt`, `InteractiveCommand.kt`, presentation web routes.
- Internal-only files: formatter and command helpers that are only used by presentation adapters.
- May depend on: config loading, domain runtime, app lifecycle helpers.
- Must not depend on: macOS Swift files, desktop view state, generated `.cotor` runtime data as source truth.
- Common changes: new command, flag, help text, lifecycle command. Update command tests, README/README.ko, and docs/QUICK_START if user-facing.

### App server and company workflow

- Responsibility: maintain company state, route app-server payloads, coordinate runtime ticks, retention cleanup, goals, issues, review queue, reports, Test Center runs, memory, and operator commands.
- Public entrypoints: `AppServer.kt`, `DesktopAppService.kt`, `CotorTestCenterService.kt`, `DesktopModels.kt`, `AppApiModels.kt`, `GitWorkspaceService.kt`, `CompanyRuntimeRetention.kt`.
- Internal-only files: runtime disposition/projection helpers under `src/main/kotlin/com/cotor/app/runtime/` unless their API is explicitly consumed by routes/tests.
- May depend on: domain runtime, provider adapters, GitHub integration, policy, evidence, verification, state stores.
- Must not depend on: SwiftUI implementation details or UI-only copy.
- Common changes: route field, dashboard card, test-run payload, runtime state transition, retention cleanup, GitHub readiness, blocked reason. Update Kotlin tests, Swift DTOs/store, and desktop docs together.

### Generic pipeline runtime

- Responsibility: execute configured pipelines independently from the desktop company product layer, including deterministic guard checks and conflict-safe parallel batching.
- Public entrypoints: orchestrator/executor packages and validation/config APIs.
- Internal-only files: stage aggregation, loop/condition internals, checkpoint internals.
- May depend on: config, validation, monitoring, provider execution interfaces.
- Must not depend on: `app/DesktopAppService.kt`, `/api/app` DTOs, macOS DTOs.
- Common changes: pipeline semantics, stage execution, guard/stuck/conflict behavior, retry behavior, checkpoint output. Update pipeline tests and command docs.

### Agent/provider execution

- Responsibility: translate agent/model choices into concrete local processes or provider plugin invocations.
- Public entrypoints: provider plugin classes, process manager abstractions, model catalog/defaults.
- Internal-only files: provider-specific parsing helpers and command builders.
- May depend on: process execution, config, security/policy checks where required.
- Must not depend on: company UI lane names or dashboard-only status text.
- Common changes: new model, provider, local runner, output parser, no-diff handling. Update plugin tests and provider docs.

### Runtime evidence and memory

- Responsibility: preserve evidence and memory required for verification, audit, A2A handoff, and autonomous discovery.
- Public entrypoints: runtime action APIs, provenance/knowledge stores, verification bundle services, context builders.
- Internal-only files: serialization details and retention helpers.
- May depend on: app state snapshots, provider output summaries, file-backed state stores.
- Must not depend on: Swift view layout or presentation-only strings.
- Common changes: memory layer, evidence schema, verification gate, retention policy. Update app-server payloads, execution-log tests, and docs when public.

### Policy and security

- Responsibility: decide whether actions are automatic, denied, or require approval, and validate dangerous execution surfaces.
- Public entrypoints: policy decision services and security validators.
- Internal-only files: low-level pattern matchers and allow-list implementation details.
- May depend on: typed action requests and project configuration.
- Must not depend on: provider stdout text as the only source of authority.
- Common changes: new capability, marketing/browser exception, destructive action rule. Update capability docs and focused tests.

### macOS desktop

- Responsibility: render the desktop shell, decode app-server payloads, keep user interaction state, and launch the embedded backend.
- Public entrypoints: `DesktopAPI`, `DesktopStore`, `Models`, `ContentView`, backend launcher.
- Internal-only files: view fragments and derived view models that are not shared outside the app target.
- May depend on: Kotlin app-server DTO contract through HTTP only.
- Must not depend on: repo-local Kotlin build files at packaged runtime.
- Common changes: new sidebar surface, DTO field, runtime control, meeting-room visualization. Update Swift tests and run a hands-on app smoke for user-facing flows.
- Live company event streams should tolerate malformed NDJSON lines without marking the app offline; backend lifecycle ownership should stay centered in `DesktopStore`.

### Packaging and install

- Responsibility: install CLI/desktop artifacts in source-checkout and packaged/Homebrew layouts.
- Public entrypoints: shell scripts, Homebrew formula, desktop lifecycle Kotlin commands.
- Internal-only files: generated bundle contents and local runtime state.
- May depend on: built artifacts and documented install layout.
- Must not depend on: source checkout files existing in packaged runtime.
- Common changes: app bundle layout, launcher behavior, update/delete flow. Verify source and packaged assumptions.

### Graphify and docs corpus

- Responsibility: keep AI-assistant source-of-truth docs and graph outputs aligned with code structure.
- Public entrypoints: `graphify-out/GRAPH_REPORT.md`, `docs/ARCHITECTURE.md`, this module guide, `AGENTS.md`, `CLAUDE.md`.
- Internal-only files: `graphify-out/graph.json` as machine graph data; do not paste it into prompts or docs.
- May depend on: current repository source and tracked docs.
- Must not depend on: stale historical records as current truth.
- Common changes: refactor, module split, documentation refresh. Run `graphify update .` and compare the refreshed report against architecture/module docs.

## Migration Notes

This documentation refresh does not move public import paths, route paths, configuration paths, or generated artifact locations. No compatibility shim or user migration is required. If a future PR moves one of those boundaries, add a migration note to `docs/CHANGELOG.md`, the PR summary, and any affected API/CLI docs.
