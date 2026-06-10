# Cotor 모듈 경계

원문: [README.md](README.md)

소스 구조, public entrypoint, route payload, domain 간 import를 바꿀 때 이 문서를 먼저 봅니다. 이 문서는 [docs/ARCHITECTURE.ko.md](../ARCHITECTURE.ko.md)를 보완하며, AI assistant가 편집 전에 빠르게 읽을 수 있을 정도로 짧게 유지합니다.

## 경계 규칙

- UI와 route adapter는 application/domain service를 호출합니다. 낮은 계층이 SwiftUI, route DTO, desktop view state를 import하면 안 됩니다.
- `DesktopAppService.kt`는 회사 workflow policy를 조율합니다. execution, provider, GitHub, policy, evidence, store module을 호출할 수 있지만, 그 하위 module이 desktop product UX를 결정하면 안 됩니다.
- Public API 변경은 compatibility shim 또는 migration note를 포함하고, Kotlin DTO, Swift DTO, 문서, 테스트를 함께 갱신해야 합니다.
- 새 폴더를 만들 때 `utils`, `helpers`, `common`, `misc`, `manager`, `service`처럼 책임이 흐린 이름만 쓰지 않습니다. domain 책임을 이름에 드러냅니다.
- source 또는 documentation 변경 뒤에는 `graphify update .`를 실행합니다. 큰 경계 이동 뒤에는 `graphify cluster-only .`도 실행합니다.

## 모듈 맵

| 모듈 | 책임 | Public entrypoint | 테스트 |
| --- | --- | --- | --- |
| CLI and presentation | 명령 파싱, interactive/TUI 실행, web adapter, 출력 formatting | `src/main/kotlin/com/cotor/Main.kt`, `src/main/kotlin/com/cotor/presentation/cli/Commands.kt`, `src/main/kotlin/com/cotor/presentation/cli/InteractiveCommand.kt` | `src/test/kotlin/com/cotor/presentation/cli/`, CLI 중심 integration test |
| App server and company workflow | localhost `/api/app` route, 회사 dashboard/runtime/goals/issues/reviews/reports/operator chat, 내장 Test Center, runtime retention | `src/main/kotlin/com/cotor/app/AppServer.kt`, `src/main/kotlin/com/cotor/app/DesktopAppService.kt`, `src/main/kotlin/com/cotor/app/CotorTestCenterService.kt`, `src/main/kotlin/com/cotor/app/DesktopModels.kt`, `src/main/kotlin/com/cotor/app/AppApiModels.kt`, `src/main/kotlin/com/cotor/app/CompanyRuntimeRetention.kt` | `src/test/kotlin/com/cotor/app/` |
| Generic pipeline runtime | pipeline orchestration, stage execution, deterministic guard, stuck/conflict detection, condition, aggregation, checkpoint | `src/main/kotlin/com/cotor/domain/orchestrator/`, `src/main/kotlin/com/cotor/domain/executor/` | `src/test/kotlin/com/cotor/` 아래 domain/orchestrator/executor test |
| Agent/provider execution | provider plugin, local process 실행, model routing, OpenCode/Codex/local model adapter | `src/main/kotlin/com/cotor/data/plugin/`, `src/main/kotlin/com/cotor/data/process/`, `src/main/kotlin/com/cotor/model/` | plugin/model/process test |
| Runtime evidence and memory | durable action, provenance, knowledge memory, verification bundle, A2A context | `src/main/kotlin/com/cotor/runtime/`, `src/main/kotlin/com/cotor/provenance/`, `src/main/kotlin/com/cotor/knowledge/`, `src/main/kotlin/com/cotor/verification/`, `src/main/kotlin/com/cotor/context/` | runtime/provenance/knowledge/verification test |
| Policy and security | action allow/deny/approval 판정, executable allow-list, path/destructive command 검증 | `src/main/kotlin/com/cotor/policy/`, `src/main/kotlin/com/cotor/security/` | policy/security test |
| GitHub and external integrations | GitHub branch/PR/check 상태, Linear mirror, external provider 경계 | `src/main/kotlin/com/cotor/providers/github/`, `src/main/kotlin/com/cotor/integrations/linear/`, `src/main/kotlin/com/cotor/app/GitWorkspaceService.kt` | GitWorkspace/AppServer/provider test |
| macOS desktop | SwiftUI shell, DTO decode, HTTP client, embedded backend launcher, meeting-room projection | `macos/Sources/CotorDesktopApp/DesktopAPI.swift`, `macos/Sources/CotorDesktopApp/DesktopStore.swift`, `macos/Sources/CotorDesktopApp/Models.swift`, `macos/Sources/CotorDesktopApp/ContentView.swift` | `macos/Tests/CotorDesktopAppTests/` |
| Packaging and install | shell launcher, desktop app bundle, Homebrew formula, packaged runtime layout | `shell/cotor`, `shell/install-desktop-app.sh`, `shell/build-desktop-app-bundle.sh`, `Formula/cotor.rb` | install/packaging smoke와 관련 Kotlin test |
| Graphify and docs corpus | graph report, query workflow, generated graph output, assistant source-of-truth docs | `graphify-out/GRAPH_REPORT.md`, `.graphifyignore`, `AGENTS.md`, `CLAUDE.md`, `docs/README.md` | `graphify update .`, path/link check |

## 상세 모듈 노트

### CLI and presentation

- 책임: 명령과 interactive/web surface를 노출하되 회사 workflow rule은 소유하지 않습니다.
- Public entrypoint: `Main.kt`, `Commands.kt`, `InteractiveCommand.kt`, presentation web route.
- 내부 전용: presentation adapter 안에서만 쓰는 formatter와 command helper.
- 의존 가능: config loading, domain runtime, app lifecycle helper.
- 의존 금지: macOS Swift file, desktop view state, source truth처럼 취급한 generated `.cotor` runtime data.
- 자주 바꾸는 작업: 새 command, flag, help text, lifecycle command. command test, README/README.ko, user-facing이면 docs/QUICK_START를 갱신합니다.

### App server and company workflow

- 책임: 회사 상태, app-server payload, runtime tick, retention cleanup, 목표, 이슈, review queue, report, Test Center 실행, memory, operator command를 조율합니다.
- Public entrypoint: `AppServer.kt`, `DesktopAppService.kt`, `CotorTestCenterService.kt`, `DesktopModels.kt`, `AppApiModels.kt`, `GitWorkspaceService.kt`, `CompanyRuntimeRetention.kt`.
- 내부 전용: route/test가 명시적으로 소비하지 않는 `src/main/kotlin/com/cotor/app/runtime/` runtime disposition/projection helper.
- 의존 가능: domain runtime, provider adapter, GitHub integration, policy, evidence, verification, state store.
- 의존 금지: SwiftUI 구현 세부사항과 UI-only copy.
- 자주 바꾸는 작업: route field, dashboard card, test-run payload, runtime state transition, retention cleanup, GitHub readiness, blocked reason. Kotlin test, Swift DTO/store, desktop docs를 함께 갱신합니다.

### Generic pipeline runtime

- 책임: desktop company product layer와 독립적인 configured pipeline 실행. deterministic guard 검사와 conflict-safe parallel batching도 포함합니다.
- Public entrypoint: orchestrator/executor package와 validation/config API.
- 내부 전용: stage aggregation, loop/condition 내부, checkpoint 내부.
- 의존 가능: config, validation, monitoring, provider execution interface.
- 의존 금지: `app/DesktopAppService.kt`, `/api/app` DTO, macOS DTO.
- 자주 바꾸는 작업: pipeline semantics, stage execution, guard/stuck/conflict behavior, retry behavior, checkpoint output. pipeline test와 command docs를 갱신합니다.

### Agent/provider execution

- 책임: agent/model 선택을 실제 local process 또는 provider plugin 호출로 변환합니다.
- Public entrypoint: provider plugin class, process manager abstraction, model catalog/default.
- 내부 전용: provider별 parsing helper와 command builder.
- 의존 가능: process execution, config, 필요한 경우 security/policy check.
- 의존 금지: company UI lane name이나 dashboard-only status text.
- 자주 바꾸는 작업: 새 model, provider, local runner, output parser, no-diff handling. plugin test와 provider docs를 갱신합니다.

### Runtime evidence and memory

- 책임: verification, audit, A2A handoff, autonomous discovery에 필요한 evidence와 memory를 보존합니다.
- Public entrypoint: runtime action API, provenance/knowledge store, verification bundle service, context builder.
- 내부 전용: serialization detail과 retention helper.
- 의존 가능: app state snapshot, provider output summary, file-backed state store.
- 의존 금지: Swift view layout과 presentation-only string.
- 자주 바꾸는 작업: memory layer, evidence schema, verification gate, retention policy. public이면 app-server payload, execution-log test, docs를 갱신합니다.

### Policy and security

- 책임: action이 automatic, denied, approval-required 중 무엇인지 결정하고 위험 실행 표면을 검증합니다.
- Public entrypoint: policy decision service와 security validator.
- 내부 전용: 낮은 수준의 pattern matcher와 allow-list 구현.
- 의존 가능: typed action request와 project configuration.
- 의존 금지: provider stdout text를 유일한 권위로 삼는 것.
- 자주 바꾸는 작업: 새 capability, marketing/browser exception, destructive action rule. capability docs와 focused test를 갱신합니다.

### macOS desktop

- 책임: desktop shell render, app-server payload decode, 사용자 interaction state 유지, embedded backend launch.
- Public entrypoint: `DesktopAPI`, `DesktopStore`, `Models`, `ContentView`, backend launcher.
- 내부 전용: app target 밖에서 공유하지 않는 view fragment와 derived view model.
- 의존 가능: HTTP를 통한 Kotlin app-server DTO contract.
- 의존 금지: packaged runtime에서 repo-local Kotlin build file.
- 자주 바꾸는 작업: 새 sidebar surface, DTO field, runtime control, meeting-room visualization. Swift test와 실제 app smoke를 실행합니다.
- live company event stream은 잘못된 NDJSON 한 줄 때문에 앱을 offline으로 보이면 안 됩니다. backend lifecycle 소유권은 `DesktopStore` 중심으로 유지합니다.

### Packaging and install

- 책임: source-checkout과 packaged/Homebrew layout에 CLI/desktop artifact를 설치합니다.
- Public entrypoint: shell script, Homebrew formula, desktop lifecycle Kotlin command.
- 내부 전용: generated bundle content와 local runtime state.
- 의존 가능: built artifact와 documented install layout.
- 의존 금지: packaged runtime에 source checkout file이 존재한다고 가정하는 것.
- 자주 바꾸는 작업: app bundle layout, launcher behavior, update/delete flow. source와 packaged 가정을 검증합니다.

### Graphify and docs corpus

- 책임: AI assistant source-of-truth docs와 graph output을 코드 구조와 맞춥니다.
- Public entrypoint: `graphify-out/GRAPH_REPORT.md`, `docs/ARCHITECTURE.md`, 이 module guide, `AGENTS.md`, `CLAUDE.md`.
- 내부 전용: machine graph data인 `graphify-out/graph.json`; prompt나 docs에 통째로 붙여 넣지 않습니다.
- 의존 가능: 현재 repository source와 tracked docs.
- 의존 금지: stale historical record를 현재 truth로 취급하는 것.
- 자주 바꾸는 작업: refactor, module split, documentation refresh. `graphify update .`를 실행하고 갱신된 report를 architecture/module docs와 비교합니다.

## 마이그레이션 노트

이번 문서 갱신은 public import path, route path, config path, generated artifact location을 이동하지 않습니다. compatibility shim이나 사용자 migration은 필요 없습니다. 향후 PR에서 이런 경계를 이동하면 `docs/CHANGELOG.md`, PR summary, 영향받는 API/CLI docs에 migration note를 남깁니다.
