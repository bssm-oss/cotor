# Cotor Full E2E QA 결과

검증일: 2026-05-04

## 결론

안전하게 실행 가능한 자동/수동 E2E 표면은 통과했습니다. 실제 비용, 외부 계정 변경, GitHub PR 변경, 앱 설치/삭제처럼 되돌리기 어렵거나 외부 부작용이 있는 항목은 실행하지 않고 정책 차단 또는 승인 필요 상태를 확인했습니다.

## 발견 및 수정한 Blocker

- `cotor run` starter pipeline이 company/agent subject가 없는 일반 `agent.exec`를 capability guard에서 차단하던 회귀를 발견했습니다.
- `AgentCapabilityGuard`를 수정해 subject가 필요한 GitHub/Git publish mutation은 계속 차단하고, 일반 unscoped pipeline agent execution은 기존 CLI surface처럼 허용하도록 했습니다.
- 회귀 테스트를 추가했습니다: `unscoped generic agent execution stays outside company capability authority`.

## 자동 검증

- `./gradlew formatCheck test shadowJar` 통과.
- `swift test` 통과: 44개 테스트 통과. Swift Testing dependency deprecation warning은 기존 경고로 남아 있습니다.
- `git diff --check` 통과.
- `graphify update .` 통과: `3793 nodes`, `4769 edges`, `285 communities` 재생성.
- macOS app bundle 재빌드 통과: `/tmp/cotor-desktop-qa-20260504-020901/bundle-build-v4/Cotor Desktop.app`.

## CLI E2E

- `cotor init --starter-template`로 신규 임시 프로젝트 생성 통과.
- `cotor validate cotor-project-starter -c cotor.yaml` 통과.
- `cotor lint -c cotor.yaml` 통과.
- `cotor run cotor-project-starter -c cotor.yaml --output-format text` 통과.
- `provider list`, `provider scan`, `provider test opencode` 통과.
- `cotor agent add opencode --local --yes`가 기본 모델 `opencode-go/deepseek-v4-flash`를 쓰는 것을 확인.
- 존재하지 않는 provider 테스트는 실패 exit로 정상 처리됨.
- `capability list`, `capability inspect`, `skill list`, `skill inspect graphify` 통과.
- 존재하지 않는 skill 파일 검증은 실패 exit로 정상 처리됨.

## Capability / Browser / Video Policy E2E

샌드박스 company/agent 기준으로 다음 정책 결과를 확인했습니다.

- `shell.exec` + `git status`: `GIT_READ`, approval 불필요.
- `shell.exec` + `git push`: `GIT_WRITE`, approval 필요.
- `github.merge`: 기본값 `GITHUB_MERGE_EXECUTE` disabled로 차단.
- malformed browser URL `not-a-url`: `DENIED`.
- external browser URL + screenshot: browser capability disabled로 `DENIED`.
- `video plan`: `VIDEO_SCRIPT_WRITE` approval 필요.
- `video render-local`: `VIDEO_RENDER_LOCAL` disabled로 차단.
- `video generate-remote`: `VIDEO_GENERATE_REMOTE` disabled로 차단.

## App-server API E2E

기존 desktop app-server singleton lock이 실제 기본 app home에서 정상 차단되는 것을 확인했습니다. 이후 `COTOR_APP_HOME`/`COTOR_DESKTOP_APP_HOME`을 임시 디렉터리로 격리해 새 app-server를 실행했습니다.

- `/health`: 200, `ok=true`.
- token 없는 요청: 401.
- 잘못된 token 요청: 401.
- `/api/app/providers`: provider 20개 반환.
- `/api/app/providers/scan`: scan result 20개 반환.
- `/api/app/capabilities/catalog`: capability 44개 반환.
- company 생성, agent 생성 통과.
- agent capability 조회 통과.
- `/api/app/skills`, `/api/app/skills/graphify` 통과.
- `/api/app/companies/{companyId}/github/status` 통과.
- browser/video/capability simulation API에서 위 정책 차단/approval 결과 확인.
- `/api/app/agents/models?agent=opencode`가 `opencode-go/deepseek-v4-flash`를 포함해 반환하는 것을 확인.

## macOS Desktop Native QA

샌드박스 app-server를 `http://127.0.0.1:8796`에서 실행하고, 빌드한 `Cotor Desktop.app`을 실제 macOS GUI로 띄워 screenshot과 AX/좌표 기반 클릭 증거를 수집했습니다.

- 실행 번들: `/tmp/cotor-desktop-qa-20260504-020901/bundle-build-v4/Cotor Desktop.app`.
- 연결 상태: 상단 상태가 `연결됨`으로 표시됨.
- screenshot: `/tmp/cotor-desktop-qa-20260504-020901/manual-20260504/screens/native-v4-meeting-room-map.png`.
- 회사 상태 표시 통과: `QA Autonomous Company`, `실행 중`, `HEALTHY`, 목표/이슈 카운트가 UI에 표시됨.
- UI 용어 개선 확인: `Brain Structure`, `graphify`, `graph.json`은 기본 화면과 Map empty state에 노출되지 않음.
- 회사 요약은 `대표 에이전트`, `도움`처럼 쉬운 용어로 표시됨.
- `미팅룸` 클릭 후 `플로어`/`지도` 컨트롤과 `지도` empty state가 표시되는 것을 확인했습니다.
- Map 파일이 없는 상태에서 macOS 원시 파일 오류가 보이지 않도록 파일 존재 여부를 먼저 확인하게 수정했습니다.

## Autonomous Company / Gemma4 Sandbox QA

같은 샌드박스에서 API로 실제 company, Gemma4 agent, goal을 만들고 desktop UI에서 상태를 확인했습니다.

- company 생성 통과: `QA Autonomous Company`, root `/private/tmp/cotor-desktop-qa-20260504-020901/company-root`, `autonomyEnabled=true`.
- Gemma4 agent 생성/저장 통과: `Local Model Executor`, `agentCli=gemma4`, `model=gemma4:e2b`.
- goal 생성 통과: `Verify first-run company flow stays simple`, `autonomyEnabled=true`.
- 런타임 자동 시작 확인: runtime `RUNNING`, backend `healthy`, `lastAction=resuming-interrupted-issues`.
- 자율 분해 확인: 목표 1개에서 planning issue 1개와 execution issue 4개가 생성됨.
- 현재 남은 상태: planning issue 1개는 policy block 상태, execution issue 4개는 planned/pending 상태. 실제 외부/장기 agent execution 완료까지는 이번 sandbox smoke에서 끝까지 밀지 않았습니다.
- model API 확인:
  - `/api/app/agents/models?agent=gemma4` -> `["gemma4:e2b"]`.
  - `/api/app/agents/models?agent=ollama` -> 로컬 Ollama 모델 목록 반환.
  - `/api/app/agents/models?agent=lmstudio` -> fallback `["gemma4:e2b"]`.
  - agent query 없는 요청 -> 400.

## Web / Browser QA

`cotor web --read-only`를 localhost에서 띄우고 Chrome DevTools로 실제 브라우저 조작을 수행했습니다.

- `/` 소개 페이지 렌더링 통과.
- `웹 에디터 시작하기` 링크 클릭 후 `/editor` 이동 통과.
- editor의 read-only 입력 상태 확인.
- `/company` 직접 이동 통과.
- `Load Dashboard` 클릭 후 dashboard JSON 렌더링 통과.
- console warning/error 없음.
- screenshot 저장: `/tmp/cotor-web-company-console-qa.png`.

## 실행하지 않은 항목

다음 항목은 외부 부작용, 비용, 사용자 환경 변경, 파괴적 동작이 있어 실행하지 않았습니다.

- 실제 GitHub PR comment/review/close/merge.
- 실제 `git push` 또는 remote 변경.
- Homebrew/release 설치, `cotor install`, `cotor update`, `cotor delete`.
- `/Applications` 또는 `~/Applications`의 실제 app bundle 변경.
- 유료/외부 provider 호출.
- external browser automation, login flow, recording.
- remote video generation, upload, deploy.

## 남은 제약

- Kotlin LSP diagnostics는 실행하지 못했습니다. 현재 `kotlin-lsp`가 initialize timeout을 내며 `kotlin-lsp.sh is deprecated` 경고를 출력합니다. 대신 Gradle compile/test/shadowJar 검증으로 Kotlin 변경의 컴파일 및 테스트 통과를 확인했습니다.
- macOS desktop native app은 설치하지 않고 임시 빌드 번들을 직접 실행했습니다. 실제 `/Applications` 설치/업데이트/삭제는 사용자 환경 변경이므로 수행하지 않았습니다.
- AppleScript 좌표 클릭은 일부 SwiftUI 버튼 전환을 안정적으로 열지 못했습니다. window ID screenshot과 API readback으로 핵심 상태는 검증했지만, `Meeting Room` 내부 Map 화면 클릭 전환은 추가 수동/AX identifier 보강이 필요합니다.
