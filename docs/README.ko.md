# Cotor 문서 안내

이 문서는 현재 코드베이스 기준의 문서 진입점입니다. 현재 문서와 과거 기록을 구분하려면 [INDEX.md](INDEX.md) 또는 [INDEX.ko.md](INDEX.ko.md)를 먼저 보십시오.

한글 동반 문서가 있는 경우 같은 경로에서 `.ko.md` 이름을 사용합니다.

## 먼저 볼 문서

- [QUICK_START.ko.md](QUICK_START.ko.md): 빠른 설치와 첫 실행
- [ARCHITECTURE.ko.md](ARCHITECTURE.ko.md): 현재 런타임 경계와 데이터 흐름
- [modules/README.ko.md](modules/README.ko.md): 모듈 책임, 진입점, 허용 의존 방향
- [FEATURES.ko.md](FEATURES.ko.md): 코드 기준 기능 목록
- [DESKTOP_APP.ko.md](DESKTOP_APP.ko.md): `app-server`와 macOS 셸
- [CAPABILITIES.ko.md](CAPABILITIES.ko.md): 회사 에이전트 capability, skill, policy gate
- [TEST_PLAN.ko.md](TEST_PLAN.ko.md): 자동/수동 검증 매트릭스
- [TESTSPRITE.ko.md](TESTSPRITE.ko.md): TestSprite MCP 설정, PRD/API 입력, 안전 경계
- [TROUBLESHOOTING.ko.md](TROUBLESHOOTING.ko.md): desktop, GitHub, company runtime, QA/CEO, interactive 복구 경로
- [team-ops/README.ko.md](team-ops/README.ko.md): 온보딩과 유지보수 운영

## 코드 기준 진실 앵커

- CLI bootstrap: `src/main/kotlin/com/cotor/Main.kt`
- CLI 명령: `src/main/kotlin/com/cotor/presentation/cli/`
- 로컬 HTTP API: `src/main/kotlin/com/cotor/app/AppServer.kt`
- 회사 워크플로 서비스: `src/main/kotlin/com/cotor/app/DesktopAppService.kt`
- 내장 Test Center: `src/main/kotlin/com/cotor/app/CotorTestCenterService.kt`
- app-server DTO: `src/main/kotlin/com/cotor/app/DesktopModels.kt`, `src/main/kotlin/com/cotor/app/AppApiModels.kt`
- 일반 파이프라인 런타임: `src/main/kotlin/com/cotor/domain/`
- 런타임 상태, action, replay: `src/main/kotlin/com/cotor/runtime/`
- policy/evidence/memory: `src/main/kotlin/com/cotor/policy/`, `src/main/kotlin/com/cotor/provenance/`, `src/main/kotlin/com/cotor/knowledge/`
- provider/process adapter: `src/main/kotlin/com/cotor/data/plugin/`, `src/main/kotlin/com/cotor/data/process/`, `src/main/kotlin/com/cotor/providers/`
- macOS 셸: `macos/Sources/CotorDesktopApp/`

문서와 코드가 다르면 코드 기준으로 문서를 고치십시오. 코드가 제품 의도와 다르게 보이면 문서를 코드에 끼워 맞추지 말고 PR risk note에 남깁니다.

## 실제 CLI 명령 체계

현재 최상위 명령:

`init`, `run`, `dash`, `interactive`, `validate`, `test`, `template`, `resume`, `checkpoint`, `stats`, `doctor`, `status`, `list`, `web`, `app-server`, `lint`, `explain`, `plugin`, `agent`, `company`, `auth`, `policy`, `capability`, `provider`, `skill`, `browser`, `video`, `evidence`, `github`, `knowledge`, `mcp`, `version`, `completion`

현재 서브커맨드:

- `agent add`, `agent list`
- `auth codex-oauth login|status|logout`
- `company ...`: 회사, 에이전트, 목표, 이슈, 리뷰, 런타임, 백엔드, 컨텍스트 운영
- `plugin init`
- `checkpoint gc`
- `policy validate`, `policy simulate`
- `capability list`, `capability inspect`, `capability simulate`
- `provider list`, `provider scan`, `provider test`
- `skill list`, `skill inspect`, `skill validate`, `skill run`
- `browser smoke`: backend capability gate를 통과한 브라우저 스모크 계획
- `video plan`, `video render`, `video transcode`, `video generate-remote`: backend capability gate를 통과한 비디오 작업 계획
- `evidence run`, `evidence file`, `evidence pr`
- `github sync`, `github inspect-pr`, `github list`, `github events`
- `knowledge inspect`
- `mcp serve --readonly`

현재 템플릿 종류:

- `compare`
- `chain`
- `review`
- `consensus`
- `fanout`
- `selfheal`
- `verified`
- `blocked-escalation`
- `custom`

## Graphify 워크플로

Graphify는 architecture/debug/refactor 질문의 빠른 진입점입니다.

- 전체 repo를 읽기 전에 `graphify-out/GRAPH_REPORT.md`를 먼저 봅니다.
- 구체적인 질문은 `graphify query`, `graphify path`, `graphify explain`으로 관련 subgraph를 좁힙니다.
- `graphify-out/graph.json` 전체는 prompt나 문서에 붙여넣지 않습니다. 이 파일은 추적되는 graph data입니다.

프로젝트 루트 기준 명령:

```bash
graphify .                  # 초기 graph 생성
graphify update .           # 코드/문서 변경 후 갱신
graphify cluster-only .     # 큰 구조 변경 후 community 재계산
graphify hook status
graphify hook install
graphify claude install
graphify codex install
graphify opencode install
```

assistant slash-command 환경에서는 같은 흐름이 `/graphify .`, `/graphify . --update`, `/graphify . --cluster-only`로 노출될 수 있습니다.

## 검증 명령

```bash
cotor version
./gradlew formatCheck
./gradlew test -x jacocoTestReport -x jacocoTestCoverageVerification
swift build --package-path macos
swift test --package-path macos
graphify update .
```

## 과거 기록

전체 라우터는 [INDEX.ko.md](INDEX.ko.md)를 사용하십시오. `docs/reports/`, `docs/release/`, `docs/changes/`, `docs/rfcs/` 아래 파일은 현재 문서에서 다시 연결하지 않는 한 과거 기록 또는 release-scoped 문서입니다.
