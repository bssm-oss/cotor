# Cotor Full E2E QA 체크리스트

이 문서는 Cotor의 현재 코드 기준 기능 표면을 full E2E로 검증하기 위한 실행 체크리스트입니다. 모든 항목은 `PASS`, `FAIL`, `BLOCKED`, `N/A` 중 하나로 기록하고, `PASS`는 실제 명령 출력이나 화면 관찰 증거가 있을 때만 표시합니다.

## 0. QA 원칙

- [ ] 테스트는 가능하면 샌드박스 워크스페이스 `/Users/Projects/bssm-oss/cotor-organization/cotor-test`에서 수행한다.
- [ ] 실제 GitHub PR 생성/댓글/리뷰/머지는 테스트 전용 repository와 branch에서만 수행한다.
- [ ] 실제 외부 API 호출, 유료 모델 호출, 원격 비디오 생성, 업로드, 배포, `brew install`, package install은 명시 승인 없이는 실행하지 않는다.
- [ ] secret 값은 로그, 스크린샷, evidence, docs, CLI output에 남기지 않는다.
- [ ] `originUrl`, app token, control token, provider token, OAuth token이 출력에 노출되지 않는지 확인한다.
- [ ] 실패는 command, stdout/stderr, 화면 상태, 기대/실제 결과, 재현 단계와 함께 기록한다.
- [ ] macOS Desktop/Company 항목은 실제 Mac 화면에서 앱을 직접 조작한 경우에만 `PASS`로 표시한다. 코드/API 응답만 본 경우는 `PARTIAL` 또는 `BLOCKED` 사유로 기록한다.
- [ ] desktop manual QA는 클릭 경로, 입력값, 화면 관찰 결과, backend/API 대조 결과, 스크린샷 또는 화면 녹화 위치를 함께 남긴다.
- [ ] 회사 기능은 실제 제품 의도대로 검증한다: 사용자는 앱 실행 -> 폴더 선택/회사 생성 -> 목표 입력까지만 직접 수행하고, 이후 이슈 생성/분해, 위임, 실행, QA/CEO 리뷰, 머지 게이트, 런타임 계속 동작, 재시작 후 복구는 회사형 에이전트 런타임이 자동으로 진행하는지 관찰한다.

## 1. 사전 준비

### 1.1 환경 확인

- [ ] `java -version`이 JDK 17 이상이다.
- [ ] `./shell/cotor version`이 정상 출력된다.
- [ ] `git status --short`로 작업트리 상태를 기록한다.
- [ ] `gh --version`이 출력된다.
- [ ] `gh auth status`가 테스트 계정으로 인증되어 있다. 인증이 없으면 GitHub side-effect 항목은 `BLOCKED`로 둔다.
- [ ] `swift --version`이 출력된다.
- [ ] macOS desktop 테스트 환경에서 `xcode-select -p`가 정상이다.
- [ ] `graphify --help` 또는 `graphify update .` 실행 가능 여부를 확인한다.
- [ ] 선택 provider availability를 기록한다: `opencode`, `codex`, `claude`, `ollama`, `lms`, `ffmpeg`, `playwright-cli`, `node`, `python3`.

### 1.2 샌드박스 준비

- [ ] `/Users/Projects/bssm-oss/cotor-organization/cotor-test`가 존재한다.
- [ ] 샌드박스 repo에 테스트용 `origin`이 설정되어 있다.
- [ ] 테스트용 GitHub repo가 production repo가 아님을 확인한다.
- [ ] local uncommitted user work가 없는 별도 branch/worktree를 사용한다.
- [ ] 필요 시 `.cotor/` runtime state를 백업한다.
- [ ] `COTOR_APP_TOKEN`과 `COTOR_APP_CONTROL_TOKEN`은 테스트용 임의 값으로 설정한다.

### 1.3 macOS 직접 조작 QA 준비

- [ ] QA용 macOS 사용자 세션에서 `Cotor Desktop.app`을 실제로 열 수 있다.
- [ ] 화면 녹화 또는 스크린샷 저장 위치를 정한다. 예: `/tmp/cotor-desktop-manual-qa-<date>/`.
- [ ] 앱 실행 방식(source `swift run`, source-built app bundle, packaged app bundle)을 기록한다.
- [ ] 테스트 중 사용할 app-server URL, token, app home, sandbox company root를 기록한다.
- [ ] Finder 또는 앱의 folder picker로 선택할 sandbox root를 미리 준비한다.
- [ ] 테스트 중 실제 GitHub/Linear/외부 provider mutation은 sandbox approval 전까지 실행하지 않는다.
- [ ] 클릭 QA 중 backend 상태를 대조할 curl/CLI 명령을 별도 터미널에 준비한다.

## 2. 자동화 기준선

### 2.1 Kotlin/Gradle

- [ ] `./gradlew formatCheck test shadowJar`
  - PASS 기준: exit code 0, `BUILD SUCCESSFUL`.
  - FAIL 기록: 실패 task, test class, stack trace 첫 원인.
- [ ] `./gradlew test --tests com.cotor.app.AgentCapabilityGuardTest`
  - PASS 기준: capability default, allowlist, subject, approval regression 통과.
- [ ] `./gradlew test --tests com.cotor.app.AppServerTest`
  - PASS 기준: app-server route regression 통과.
- [ ] `./gradlew test --tests com.cotor.presentation.cli.CompanyCommandTest`
  - PASS 기준: CLI JSON 출력 regression 통과.

### 2.2 Swift/macOS

- [ ] `swift test` in `macos/`
  - PASS 기준: DesktopStore, MeetingRoom, model tests 모두 통과.
- [ ] `swift build` in `macos/`
  - PASS 기준: build complete.

### 2.3 Repository hygiene

- [ ] `git diff --check`
  - PASS 기준: 출력 없음.
- [ ] Kotlin LSP diagnostics를 시도한다.
  - PASS 기준: changed Kotlin files에 error 없음.
  - BLOCKED 기준: local Kotlin LSP initialize timeout 같은 환경 문제. 이 경우 Gradle compile/test 결과를 대체 증거로 기록한다.
- [ ] docs-only 변경이면 참조한 command/path/file이 실제 존재하는지 확인한다.

## 3. CLI 전체 표면

각 명령은 help 출력, 정상 happy path, 잘못된 입력 negative path를 최소 1회씩 확인한다.

### 3.1 기본 진입점

- [ ] `./shell/cotor`
  - 기대: interactive/TUI가 열린다. transcript와 `interactive.log`가 생성된다.
- [ ] `./shell/cotor tui`
  - 기대: `interactive` alias로 동작한다.
- [ ] `./shell/cotor help`
- [ ] `./shell/cotor help --lang ko`
- [ ] `./shell/cotor help ai`
- [ ] `./shell/cotor help web`
- [ ] `./shell/cotor version`
- [ ] unknown first arg fallback: 테스트 pipeline 이름을 주면 direct pipeline 실행으로 연결된다.

### 3.2 Pipeline/config/lint/test

- [ ] `./shell/cotor init --starter-template`를 임시 디렉터리에서 실행한다.
- [ ] 생성된 `cotor.yaml`과 `pipelines/default.yaml`이 존재한다.
- [ ] `./shell/cotor validate cotor-project-starter -c cotor.yaml`
- [ ] `./shell/cotor lint cotor-project-starter -c cotor.yaml`
- [ ] `./shell/cotor test --help`
- [ ] `./shell/cotor run cotor-project-starter -c cotor.yaml --output-format text`
- [ ] invalid config path를 넘겼을 때 user-friendly error가 나온다.

### 3.3 Inventory/help commands

- [ ] `./shell/cotor list --help`
- [ ] `./shell/cotor status --help`
- [ ] `./shell/cotor stats --help`
- [ ] `./shell/cotor doctor`
- [ ] `./shell/cotor dash --help`
- [ ] `./shell/cotor template --list`
- [ ] `./shell/cotor resume inspect <run-id>`
- [ ] `COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1 ./shell/cotor resume continue <run-id> --config cotor.yaml`
  - 기대: replay-unsafe side effect가 있으면 approval 전까지 pause한다.
- [ ] `COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1 ./shell/cotor resume fork <run-id> --from <checkpoint-id> --config cotor.yaml`
- [ ] `COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1 ./shell/cotor resume approve <run-id> --checkpoint <checkpoint-id>`
- [ ] `./shell/cotor explain --help`
- [ ] `./shell/cotor completion zsh`
- [ ] `./shell/cotor plugin init --help`

### 3.4 Agent/auth/provider/model commands

- [ ] `./shell/cotor agent list`
- [ ] `./shell/cotor agent add opencode --name qa-opencode`
- [ ] `./shell/cotor agent add graphify --name qa-graphify`
- [ ] `./shell/cotor agent add gemma4 --name qa-gemma4`
- [ ] `./shell/cotor agent add ollama --name qa-ollama`
- [ ] `./shell/cotor agent add lmstudio --name qa-lmstudio`
- [ ] 생성된 agent config가 provider/model defaults를 보존한다.
- [ ] `./shell/cotor auth codex-oauth status`
- [ ] OAuth login/logout은 실제 테스트 계정 준비 시에만 수행한다.
- [ ] `./shell/cotor provider list`
- [ ] `./shell/cotor provider scan`
- [ ] `./shell/cotor provider test opencode`
- [ ] `./shell/cotor provider test ffmpeg`
- [ ] 존재하지 않는 provider id는 명확한 error를 반환한다.
- [ ] provider scan/test가 login, install, model pull, remote refresh, paid call을 실행하지 않는지 확인한다.

### 3.5 Policy/capability/skill commands

- [ ] `./shell/cotor policy validate --help`
- [ ] `./shell/cotor policy simulate --help`
- [ ] `./shell/cotor capability list`
- [ ] `./shell/cotor capability inspect GITHUB_MERGE_EXECUTE`
- [ ] `./shell/cotor capability inspect browser.external-domain`
- [ ] `./shell/cotor capability simulate --company <companyId> --agent <agentId> --action shell.exec --command "git status"`
  - 기대: `GIT_READ`, allowed.
- [ ] `./shell/cotor capability simulate --company <companyId> --agent <agentId> --action shell.exec --command "git push"`
  - 기대: `GIT_WRITE`, approval required 또는 denied.
- [ ] `./shell/cotor capability simulate --company <companyId> --agent <agentId> --action github.merge`
  - 기대: default `GITHUB_MERGE_EXECUTE` disabled.
- [ ] `./shell/cotor company agent capabilities <agentId> --company-id <companyId>`
- [ ] `./shell/cotor company agent capability <agentId> BROWSER_READ --company-id <companyId> --mode AUTO`
- [ ] 여러 capability를 순차 변경해도 기존 custom setting이 reset되지 않는다.
- [ ] `./shell/cotor skill list`
- [ ] `./shell/cotor skill inspect graphify`
- [ ] `./shell/cotor skill validate <valid-skill-file>`
- [ ] `./shell/cotor skill validate <missing-file>`가 error를 반환한다.
- [ ] `./shell/cotor skill run graphify --company <companyId> --agent <agentId> --input "map repository"`
  - 기대: `READY`, `DENIED`, `APPROVAL_REQUIRED` 중 backend gate 결과가 명확하다.

### 3.6 Browser/video/evidence/knowledge/runtime commands

- [ ] `./shell/cotor browser smoke --company <companyId> --agent <agentId> --url not-a-url`
  - 기대: `DENIED`, unsupported URL.
- [ ] `./shell/cotor browser smoke --company <companyId> --agent <agentId> --url http://127.0.0.1:3000`
  - 기대: local URL 계획 결과. capability에 따라 `READY` 또는 명확한 denial.
- [ ] `./shell/cotor browser smoke --company <companyId> --agent <agentId> --url https://example.com --screenshot`
  - 기대: external domain capability 없으면 denied.
- [ ] `./shell/cotor video plan --company <companyId> --agent <agentId>`
- [ ] `./shell/cotor video render --company <companyId> --agent <agentId> --provider remotion`
  - 기대: default disabled이면 denied.
- [ ] `./shell/cotor video transcode --company <companyId> --agent <agentId> --input <allowed/input.mov> --output <outside/output.mp4>`
  - 기대: output path allowlist 위반 시 denied.
- [ ] `./shell/cotor video generate-remote --company <companyId> --agent <agentId> --provider remote-demo`
  - 기대: default denied.
- [ ] `./shell/cotor evidence run <runId>`
- [ ] `./shell/cotor evidence file <path>`
- [ ] `./shell/cotor evidence pr <pullRequestNumber>`
  - 기대: PR/file/branch evidence가 나오고 secret/token이 없다.
- [ ] `./shell/cotor knowledge inspect`
- [ ] `./shell/cotor verification inspect --help`
- [ ] `./shell/cotor runtime inspect --help`
- [ ] `./shell/cotor mcp serve --readonly --help`

## 4. App-server E2E

### 4.1 서버 시작/인증

- [ ] `COTOR_APP_TOKEN=qa-token ./shell/cotor app-server --port 8787`
- [ ] token 없이 protected route 호출 시 unauthorized가 나온다.
- [ ] wrong bearer token 호출 시 unauthorized가 나온다.
- [ ] correct bearer token 호출 시 JSON response가 나온다.
- [ ] app-server shutdown 시 프로세스가 정상 종료된다.

### 4.2 Core routes

- [ ] `GET /api/app/dashboard`
- [ ] `GET /api/app/settings`
- [ ] `PATCH /api/app/settings` with harmless local setting
- [ ] `GET /api/app/repositories`
- [ ] `POST /api/app/repositories/scan` 또는 repository registration route가 정상 동작한다.
- [ ] `GET /api/app/workspaces`
- [ ] `PATCH /api/app/workspaces/{workspaceId}/base-branch`
- [ ] invalid id는 4xx + JSON error를 반환한다.

### 4.3 Company routes

이 섹션은 app-server API surface 회귀 검증이다. `runtime/start`, `runtime/stop` 같은 route를 직접 호출하는 것은 pause/recovery/control API 테스트이며, 회사 happy path의 이슈 분해/위임/실행을 사용자가 수동으로 진행한다는 뜻이 아니다.

- [ ] `GET /api/app/companies`
- [ ] `POST /api/app/companies` with sandbox root.
- [ ] `GET /api/app/companies/{companyId}`
- [ ] `PATCH /api/app/companies/{companyId}`
- [ ] `GET /api/app/companies/{companyId}/agents`
- [ ] `POST /api/app/companies/{companyId}/agents`
- [ ] `PATCH /api/app/companies/{companyId}/agents/{agentId}`
- [ ] `GET /api/app/companies/{companyId}/projects`
- [ ] `GET /api/app/companies/{companyId}/goals`
- [ ] `POST /api/app/companies/{companyId}/goals`
- [ ] `GET /api/app/companies/{companyId}/issues`
- [ ] `GET /api/app/companies/{companyId}/review-queue`
- [ ] `GET /api/app/companies/{companyId}/activity`
- [ ] `GET /api/app/companies/{companyId}/dashboard`
- [ ] `GET /api/app/companies/{companyId}/contexts`
- [ ] `GET /api/app/companies/{companyId}/runtime`
- [ ] `POST /api/app/companies/{companyId}/runtime/start`
- [ ] `POST /api/app/companies/{companyId}/runtime/stop`
- [ ] `GET /api/app/companies/{companyId}/events` 또는 SSE live event stream이 연결된다.
- [ ] `GET /api/app/companies/{companyId}/memory-snapshot`
- [ ] `GET /api/app/companies/{companyId}/issue-graph`
- [ ] `GET /api/app/companies/{companyId}/topology`
- [ ] `GET /api/app/companies/{companyId}/decisions`
- [ ] `GET /api/app/companies/{companyId}/budget`
- [ ] `GET /api/app/companies/{companyId}/messages`
- [ ] `GET /api/app/issues/{issueId}/runs`
- [ ] `GET /api/app/issues/{issueId}/execution-details`
- [ ] `GET /api/app/execution-log` 또는 issue/task scoped execution log route가 정상 응답한다.
- [ ] `PATCH /api/app/companies/{companyId}/linear`
- [ ] `POST /api/app/companies/{companyId}/linear/resync`
- [ ] runtime stop이 sticky하게 유지된다.

### 4.4 New capability/provider/skill/browser/video/evidence routes

- [ ] `GET /api/app/capabilities/catalog`
- [ ] `GET /api/app/companies/{companyId}/agents/{agentId}/capabilities`
- [ ] `PATCH /api/app/companies/{companyId}/agents/{agentId}/capabilities`
- [ ] `POST /api/app/companies/{companyId}/agents/{agentId}/capabilities/simulate`
- [ ] `GET /api/app/providers`
- [ ] `POST /api/app/providers/scan`
- [ ] `POST /api/app/providers/{providerId}/test`
- [ ] `GET /api/app/skills`
- [ ] `GET /api/app/skills/{name}`
- [ ] `POST /api/app/skills/{name}/validate`
- [ ] `POST /api/app/skills/{name}/run`
- [ ] `POST /api/app/browser/smoke`
- [ ] `POST /api/app/video/plan`
- [ ] `POST /api/app/video/render-local`
- [ ] `POST /api/app/video/transcode`
- [ ] `POST /api/app/video/generate-remote`
- [ ] `GET /api/app/evidence/pull-requests/{pullRequestNumber}`
- [ ] `GET /api/app/companies/{companyId}/github/status`
- [ ] GitHub status response가 credential-bearing `origin`을 redaction한다.

### 4.5 MCP routes

- [ ] `GET /api/app/mcp` 또는 read-only MCP route가 normal token으로 동작한다.
- [ ] mutating MCP control route가 `COTOR_APP_CONTROL_TOKEN` 없이 거부된다.
- [ ] control token이 있어야 `/api/app/mcp/control` mutating tool이 접근 가능하다.
- [ ] MCP control test는 harmless operation만 사용한다.

### 4.6 App-server singleton/lifecycle

- [ ] 같은 app home에서 app-server를 두 번 띄우면 singleton lock 때문에 중복 실행이 막히거나 기존 instance 정보가 명확히 표시된다.
- [ ] app-server 시작 시 `app-server.instance.json` 같은 instance metadata가 생성된다.
- [ ] 정상 shutdown 후 stale lock/instance 파일 때문에 재시작이 막히지 않는다.
- [ ] non-loopback host로 띄울 때 token 없이 시작하려 하면 거부된다.

## 5. macOS Desktop E2E

### 5.1 Launch/lifecycle

- [ ] `swift run --package-path macos CotorDesktopApp`로 앱이 열린다.
- [ ] Dock 또는 실행 중 앱 목록에 Cotor Desktop이 표시된다.
- [ ] 첫 화면 screenshot을 저장하고 실행 방식/source-packaged 여부를 기록한다.
- [ ] `COTOR_APP_SERVER_URL` override가 적용된다.
- [ ] `COTOR_APP_TOKEN`이 backend와 desktop client 양쪽에서 일치한다.
- [ ] app boot 시 dashboard가 로드되거나 명확한 offline 상태를 보여준다.
- [ ] 앱을 foreground/background로 전환해도 선택 company와 shell mode가 유지된다.
- [ ] 앱 창 resize 시 Company summary, sidebar, board, detail drawer가 겹치거나 잘리지 않는다.
- [ ] 마지막 desktop window를 닫으면 launcher-managed backend가 종료된다.
- [ ] backend process가 죽으면 desktop이 기존 snapshot을 유지하고 reconnect 상태를 보여준다.
- [ ] backend를 다시 띄우면 수동 새로고침 또는 자동 reconnect 후 최신 snapshot으로 복구된다.

### 5.2 Company shell 사용자 최소 입력 플로우

- [ ] 기본 shell mode가 `Company`다.
- [ ] 왼쪽 또는 상단 shell mode control에서 `Company`가 선택되어 있음을 육안으로 확인한다.
- [ ] company selector가 기존 company 목록을 보여준다.
- [ ] company selector를 클릭해 dropdown/list가 열리고, 각 항목의 이름/root/status가 읽기 가능하다.
- [ ] 기존 company를 하나 선택하면 summary, goals, issues, activity, runtime 상태가 같은 company id로 갱신된다.
- [ ] 없는 company 상태 또는 빈 목록 상태가 깨지지 않고 company 생성 CTA를 보여준다.
- [ ] 새 company 생성 시 root path/default branch가 저장된다.
- [ ] 새 company 생성 버튼을 클릭한다.
- [ ] company name을 입력한다.
- [ ] folder picker 또는 path 입력으로 sandbox root를 선택한다.
- [ ] default branch가 자동 감지되거나 직접 입력한 값으로 저장된다.
- [ ] 생성 직후 새 company가 selector에 추가되고 자동 선택된다.
- [ ] 동일 root로 중복 company를 만들 때 중복/검증 메시지가 명확하다.
- [ ] 잘못된 root path 또는 git repo가 아닌 path를 입력했을 때 user-friendly error가 나온다.
- [ ] company settings에서 GitHub readiness card가 보인다.
- [ ] settings/advanced settings를 클릭해 GitHub readiness card까지 스크롤한다.
- [ ] `gh`, auth, origin readiness 상태가 backend response와 일치한다.
- [ ] credential 포함 origin URL이 UI에 그대로 노출되지 않는다.
- [ ] daily/monthly cost guardrail이 표시되고 저장된다.
- [ ] daily budget 입력값을 변경하고 저장한 뒤 dashboard/settings 재진입 후 유지되는지 확인한다.
- [ ] monthly budget 입력값을 변경하고 저장한 뒤 dashboard/settings 재진입 후 유지되는지 확인한다.
- [ ] 숫자가 아닌 budget 입력 또는 음수 입력이 거부되거나 안전하게 normalize된다.
- [ ] runtime summary banner가 health, blocked count, review attention, latest signal을 compact하게 보여준다.
- [ ] live event stream disconnect 시 stale decode error 대신 re-sync 메시지가 보인다.
- [ ] company 삭제 또는 제거 flow가 있다면 destructive confirmation 문구가 표시되고, 취소 시 상태가 바뀌지 않는다.

### 5.3 Agent roster/model/capability 관찰 및 설정 UI 회귀

- [ ] 회사 생성 직후 미리 준비된 기본 에이전트 roster가 보인다.
- [ ] 기본 roster가 CEO/lead, execution, QA/review, graph/context 역할처럼 회사 운영에 필요한 상하관계를 표현한다.
- [ ] happy path QA에서는 사용자가 issue 분해/위임/실행용 agent를 새로 만들지 않아도 목표 처리가 시작된다.
- [ ] 기본 roster만으로 목표 입력 후 자율 런타임이 시작되지 않으면 `FAIL`로 기록한다.
- [ ] 아래 agent 생성/수정 항목은 happy path 필수 조작이 아니라 설정 UI 회귀 검증으로만 수행한다.
- [ ] agent-definition composer로 agent 생성이 가능하다.
- [ ] agent roster/agents 화면을 연다.
- [ ] 새 agent 버튼을 클릭한다.
- [ ] title, agent CLI, role summary를 입력한다.
- [ ] specialty/tag 입력이 있으면 하나 이상 추가하고 제거도 확인한다.
- [ ] 저장 전 validation error가 필요한 필수값에서 표시된다.
- [ ] 저장 후 roster에 새 agent가 나타난다.
- [ ] agent CLI 선택 시 provider default model이 설정된다.
- [ ] agent CLI를 `opencode`, `codex`, `ollama`, `lmstudio`, `gemma4`로 바꾸며 model picker/default가 갱신되는지 확인한다.
- [ ] Codex/OpenCode/Ollama/LM Studio/Gemma4 model override가 저장된다.
- [ ] model override를 선택/입력하고 저장한 뒤 agent detail을 닫았다 다시 열어 유지되는지 확인한다.
- [ ] agent enabled toggle을 끄고 켠 뒤 roster/filter/runtime 대상에 반영되는지 확인한다.
- [ ] batch edit에서 explicit model/capability가 유지된다.
- [ ] agent 여러 개를 선택하고 batch edit drawer/panel을 연다.
- [ ] batch edit에서 CLI만 바꿀 때 model override가 의도 없이 지워지지 않는다.
- [ ] batch edit에서 capability만 바꿀 때 specialties/model/enabled가 의도 없이 지워지지 않는다.
- [ ] capability/provider UI가 backend payload와 일치한다.
- [ ] capability detail을 열어 `AUTO`, `APPROVAL_REQUIRED`, `DISABLED` 같은 mode를 직접 바꿔 저장한다.
- [ ] 저장 후 `cotor company agent capabilities` 또는 app-server API로 같은 값인지 대조한다.
- [ ] 위험 capability를 `AUTO`로 켜려고 할 때 approval/risk 설명이 UI에 표시된다.
- [ ] provider scan/availability 상태가 UI에서 read-only로 보이고, scan이 install/login/network를 유발하지 않는다.
- [ ] secret value를 저장하거나 표시하지 않고 secret reference name만 다룬다.
- [ ] token/password처럼 보이는 값을 입력할 수 있는 칸이 있다면 실제 값 저장 대신 secret reference만 저장되는지 확인한다.

> Agent 생성/수정 항목은 설정 UI 회귀 검증이다. 회사 happy path에서는 사용자가 agent hierarchy를 매번 직접 구성하는 것이 아니라, 준비된 roster가 목표를 받아 24시간 무인 자율 실행해야 한다.

### 5.4 Meeting Room / Map

- [ ] Meeting Room이 기본적으로 쉬운 `Map`/`지도` 화면을 연다.
- [ ] Company navigation에서 Meeting Room을 클릭한다.
- [ ] 첫 진입 tab이 `Map`/`지도`인지 확인한다.
- [ ] 지도 데이터가 있는 repo에서 저장소 지도가 렌더링된다.
- [ ] 기술적인 `graphify-out/graph.json` 같은 파일 경로가 기본 UI에 보이지 않는다.
- [ ] 지도 항목/연결이 화면 중앙에 표시되고 빈 회색 화면으로 남지 않는다.
- [ ] zoom/pan 또는 scroll이 가능하면 조작 후 UI가 깨지지 않는다.
- [ ] 지도 항목 클릭/detail sheet가 열린다.
- [ ] detail sheet에 항목 이름, 파일, 유형, 그룹 같은 쉬운 식별 정보가 표시된다.
- [ ] detail sheet 닫기 동작이 정상이다.
- [ ] 지도 데이터가 없을 때도 깨지지 않고 readable empty state를 보여준다.
- [ ] live floor map tab으로 전환 가능하다.
- [ ] floor view가 runtime/backend/review/session wall events와 seat presence를 보여준다.
- [ ] Map -> Floor Map -> Map 왕복 후 선택 company와 지도 상태가 유지된다.
- [ ] runtime/review/session 이벤트가 없는 빈 회사에서도 Meeting Room이 빈 상태를 안정적으로 보여준다.

### 5.5 Board/canvas/detail drawer

- [ ] goal list와 goal creation이 동작한다.
- [ ] Goals 화면에서 새 goal 버튼을 클릭한다.
- [ ] title, description, success metrics를 입력한다.
- [ ] autonomy toggle을 켜고 끈 뒤 저장 결과를 확인한다.
- [ ] 생성된 goal을 클릭하면 selected goal detail이 열린다.
- [ ] goal 수정 후 목록과 detail이 같은 값으로 갱신된다.
- [ ] 빈 goal title 같은 invalid input이 저장되지 않는다.
- [ ] issue board lane이 fixed surface 안에서 스크롤된다.
- [ ] Planned/In Progress/Review/Done/Blocked lane이 화면 높이를 넘어갈 때 lane 내부 스크롤로 카드가 접근 가능하다.
- [ ] board/canvas switch 후 selected issue가 유지된다.
- [ ] Board에서 issue를 선택한 뒤 Canvas로 전환한다.
- [ ] Canvas에서 같은 issue가 선택/강조되어 있는지 확인한다.
- [ ] Canvas에서 Board로 돌아와도 detail drawer context가 유지된다.
- [ ] issue card click 시 detail drawer/context가 갱신된다.
- [ ] 서로 다른 issue card를 연속 클릭해 drawer title/status/assignee가 즉시 바뀌는지 확인한다.
- [ ] detail drawer에서 changes/files/ports/browser/review metadata가 열리고 닫힌다.
- [ ] 각 drawer section을 펼치고 접으며 스크롤 위치와 선택 issue가 유지되는지 확인한다.
- [ ] issue execution detail에 agent CLI, model, backend kind, pid, prompt, stdout/stderr, branch, PR link, publish summary가 보인다.
- [ ] 실행 detail 로딩 중 다른 issue를 선택했을 때 이전 issue의 늦은 응답이 현재 issue에 덮어쓰지 않는다.
- [ ] 긴 stdout/stderr가 drawer layout을 깨지 않고 스크롤/접기 상태로 표시된다.

### 5.6 Chat Control

- [ ] Chat Control surface가 열린다.
- [ ] Company navigation에서 Chat Control을 클릭한다.
- [ ] live conversation/context와 backend memory snapshot이 표시된다.
- [ ] memory snapshot refresh를 눌러 로딩/성공/빈 상태를 확인한다.
- [ ] 사용자가 자연어 목표를 입력하면 goal intent가 생성되거나 goal 생성 proposal만 표시된다.
- [ ] 목표 입력/confirm 뒤 사용자가 별도 분해 버튼을 누르지 않아도 runtime이 goal을 처리 대상으로 인식한다.
- [ ] Chat Control은 에이전트가 만든 계획, 이슈, 실행, QA/CEO 상태를 관찰할 수 있게 보여준다.
- [ ] goal decomposition, issue creation, delegation, execution, QA/CEO verdict는 happy path에서 사용자가 직접 confirm해서 진행시키는 단계가 아니다. runtime이 자동으로 만들고, UI는 상태와 evidence를 보여준다.
- [ ] 위험하거나 외부 부작용이 있는 merge/backend/company-agent 변경만 명시적 confirmation gate를 요구한다.
- [ ] confirmation gate에서 cancel을 누르면 해당 위험 action만 취소되고, 회사 runtime 전체가 멈추지 않는다.
- [ ] confirmation gate에서 confirm을 누르면 backend policy/approval/evidence 기록 뒤에만 action이 진행된다.
- [ ] runtime start/stop control은 사용자가 회사를 일시정지/재개할 때만 쓰며, goal 처리 happy path의 각 단계를 수동으로 advance하는 버튼이 아니다.
- [ ] backend restart/control proposal은 위험 동작 설명과 confirmation을 요구한다.
- [ ] 대표 에이전트와 도움 에이전트 선택이 proposal에 반영된다.
- [ ] 대표 에이전트와 도움 에이전트 선택은 다음 goal 처리 정책에 반영되지만, 사용자가 개별 issue를 직접 위임하지 않아도 runtime이 roster에 맞춰 배정한다.

### 5.7 TUI mode

- [ ] top-level `TUI` mode로 전환된다.
- [ ] Company mode에서 TUI mode로 전환한 뒤 Company state가 사라지거나 섞이지 않는다.
- [ ] folder-backed standalone session을 생성한다.
- [ ] folder picker로 sandbox root를 선택한다.
- [ ] 새 TUI session이 session strip에 나타난다.
- [ ] 여러 TUI session이 parallel로 유지된다.
- [ ] 두 번째 folder-backed session을 만들고 두 session 사이를 클릭 전환한다.
- [ ] 선택한 session의 terminal이 center surface에 dominant하게 표시된다.
- [ ] terminal에 help 또는 safe command를 입력하고 출력이 보이는지 확인한다.
- [ ] base branch update 후 backend workspace가 갱신되고 TUI session이 재시작된다.
- [ ] TUI mode에서 다시 Company mode로 돌아가도 마지막 선택 company가 유지된다.

### 5.8 실제 macOS 앱 클릭 QA 증거 수집

- [ ] 각 주요 flow마다 최소 1장 screenshot을 저장한다: launch, company create, 기본 agent roster, goal 입력, runtime 자동 시작, 자동 생성 issue board, Chat Control 관찰 화면, Meeting Room, runtime panel, settings/GitHub readiness.
- [ ] 가능하면 전체 회사 happy path를 화면 녹화한다.
- [ ] screenshot/recording 파일명에 날짜, 앱 실행 방식, company id 또는 sandbox 이름을 포함한다.
- [ ] click QA 중 발견한 UI latency, focus loss, stale state, layout clipping, unreadable empty/error state를 별도 failure 템플릿으로 기록한다.
- [ ] UI에서 보인 값과 app-server/CLI 조회 값이 다르면 둘 다 evidence로 남긴다.

### 5.9 실제 앱 UI/UX 개선 루프

이 섹션은 한 번의 스모크 테스트로 끝내지 않는다. 실제 앱을 띄워 누르고 캡처한 뒤, 결함을 고치고 같은 화면을 다시 눌러 개선 여부를 확인하는 반복 루프다.

- [ ] QA 시작 전 실행 환경을 기록한다: source/package, app version, commit, app-server URL, app home, sandbox root, screen size, light/dark mode, 언어 설정.
- [ ] 앱을 실제 foreground로 띄우고 첫 화면 screenshot을 저장한다.
- [ ] app launch 후 5초 안에 사용자가 다음 행동을 이해할 수 있는지 확인한다.
- [ ] 빈 상태에서 `회사 만들기`, `폴더 선택`, `목표 입력`으로 이어지는 primary CTA가 한 화면에서 명확하다.
- [ ] 회사가 이미 있을 때 최근 회사/선택 회사/런타임 상태가 즉시 이해된다.
- [ ] 클릭 가능한 카드와 읽기 전용 상태 카드가 시각적으로 구분된다.
- [ ] 모든 주요 버튼에 hover, pressed, disabled 상태가 보인다.
- [ ] keyboard focus ring이 버튼, 입력창, picker, tab, 카드에서 보인다.
- [ ] `Tab` 키만으로 회사 생성, 목표 입력, Meeting Room, Board, Runtime, Settings의 핵심 컨트롤을 순회할 수 있다.
- [ ] `Esc`로 modal/sheet/detail을 닫을 수 있거나 닫는 방법이 명확하다.
- [ ] 입력 중 `Enter` 동작이 저장/줄바꿈/무동작 중 무엇인지 UI 맥락상 명확하다.
- [ ] 작은 창 크기(920x700)에서 sidebar, summary, board, drawer가 겹치지 않는다.
- [ ] 기본 창 크기(1480x920)에서 핵심 정보가 과도하게 흩어지지 않는다.
- [ ] 큰 창/전체화면에서 line length가 너무 길어지지 않고 카드 밀도가 유지된다.
- [ ] light mode screenshot과 dark mode screenshot을 각각 저장한다.
- [ ] 한국어/영어 전환 후 레이블이 잘리거나 버튼 폭이 깨지지 않는다.
- [ ] 긴 company name, 긴 root path, 긴 goal title, 긴 issue title screenshot을 저장한다.
- [ ] 긴 stdout/stderr, 긴 activity detail, 긴 PR URL이 layout을 깨지 않고 scroll/truncate/copy 가능하게 표시된다.
- [ ] loading 상태가 skeleton/spinner/text 중 하나로 명확하고, 빈 화면으로 방치되지 않는다.
- [ ] error 상태는 원인, 다음 행동, 재시도 방법을 보여준다.
- [ ] offline/reconnect 상태에서 마지막 snapshot은 유지되고, 사용자가 데이터가 사라졌다고 오해하지 않는다.
- [ ] action 성공 후 toast/banner/activity/screen update 중 하나로 피드백이 온다.
- [ ] destructive action은 색상, 문구, 취소 경로가 명확하다.
- [ ] 외부 부작용이 있는 approval gate는 어떤 action이 왜 멈췄는지 한 문장으로 설명한다.
- [ ] screenshot review 후 P0/P1/P2/P3 severity를 매기고, P0/P1은 같은 QA 루프에서 바로 수정한다.
- [ ] 수정 후 같은 클릭 경로와 같은 screenshot angle로 before/after를 저장한다.
- [ ] 수정 후 app-server/CLI state와 UI state가 같은지 다시 대조한다.
- [ ] 반복 루프 결과를 QA 결과 리포트에 남긴다: 발견 결함, 수정 여부, before/after screenshot, 남은 리스크.

## 6. Company workflow E2E

이 섹션은 API/CLI만으로 통과 처리하지 않는다. 최소 1회는 macOS Desktop에서 실제 사용자 플로우대로 수행한다. 핵심 기준은 사용자가 폴더에 맞춰 회사를 만들고 목표를 입력하면, 미리 준비된 회사형 에이전트들이 상하관계와 역할에 맞춰 24시간 자율 런타임으로 이슈 생성/분해, 위임, 실행, QA/CEO 리뷰, 머지 게이트를 진행하는 것이다. 사용자는 happy path에서 각 단계를 버튼으로 직접 advance하지 않고, 앱에서 진행 상황과 evidence를 관찰한다.

### 6.1 Happy path: company goal to autonomous execution

- [ ] 사용자가 앱을 연다.
- [ ] 사용자가 sandbox root folder를 선택한다.
- [ ] 사용자가 sandbox company를 생성한다.
- [ ] macOS 앱에서 sandbox company를 선택한다.
- [ ] 선택 company summary의 root/default branch/runtime 상태를 기록한다.
- [ ] 미리 준비된 CEO/lead, execution, QA/review, graph/context agent roster가 자동으로 보인다.
- [ ] 기본 agent roster가 비어 있지 않고, 사용자가 별도 agent를 만들지 않아도 goal 처리 가능한 상태다.
- [ ] 사용자가 목표 title/description/success metric만 입력한다.
- [ ] goal 저장 또는 goal 제출 후 summary/count/activity가 갱신된다.
- [ ] 사용자가 decomposition/delegation/execution 버튼을 누르지 않아도 runtime이 goal을 처리 대상으로 잡는다.
- [ ] goal 생성 후 회사 runtime이 자동으로 `RUNNING` 또는 실행 준비 상태가 된다. 명시적으로 sticky stop 상태가 아닌데 사용자가 start를 눌러야만 진행되면 `FAIL`로 기록한다.
- [ ] runtime이 goal을 다중 issue portfolio로 자동 분해하는지 관찰한다.
- [ ] 생성된 issue들이 board lane과 goal detail 양쪽에 나타난다.
- [ ] issue title/priority/kind/goal linkage가 app-server 조회 결과와 일치한다.
- [ ] runtime이 issue를 agent 역할/상하관계에 맞춰 자동 위임한다.
- [ ] delegated issue에 assignee/profile/status가 자동 반영된다.
- [ ] assignee가 roster의 실제 agent id/title과 일치한다.
- [ ] 사용자가 `cotor company issue run <issue-id>`나 앱의 issue execution 버튼을 누르지 않아도 runtime이 실행을 시작한다.
- [ ] 실행 중 status, spinner/progress, activity feed event가 표시된다.
- [ ] linked task/run이 생성된다.
- [ ] issue detail drawer에서 linked run/task를 클릭하거나 펼쳐 볼 수 있다.
- [ ] run detail에 stdout/stderr, branch, worktree, PR/publish metadata가 표시된다.
- [ ] branch/worktree 경로가 sandbox 내부 또는 Cotor-managed 경로인지 확인한다.
- [ ] stdout/stderr에 secret/token이 없는지 확인한다.
- [ ] `cotor resume inspect <run-id>`가 company issue durable snapshot을 보여준다.
- [ ] qualifying state에서 runtime이 review queue item을 자동 생성한다.
- [ ] review queue count가 summary banner와 review surface에서 같은 값이다.
- [ ] review item detail이 source issue/run과 연결된다.
- [ ] QA/review agent가 자동으로 QA issue 또는 verdict를 생성하고 execution issue와 lineage가 맞는다.
- [ ] lineage mismatch를 만들 수 있는 stale result가 있으면 현재 issue state를 덮어쓰지 않는지 확인한다.
- [ ] CEO/merge gate는 default policy에 따라 자동으로 merge-ready까지 진행하거나, 외부 부작용 전 명시적 approval gate에서 멈춘다.
- [ ] app을 몇 시간 이상 켜 두었을 때 새 work가 생기면 runtime이 계속 wake/dispatch한다는 evidence를 남긴다.
- [ ] 24시간 soak 동안 사용자가 추가 조작하지 않아도 runtime tick, activity feed, issue transition, budget 상태가 계속 갱신되는지 시간대별로 기록한다.

### 6.1.1 사용자 최소 입력 + 자율 회사 관찰 체크리스트

- [ ] 앱 실행 후 `Company` 모드 진입.
- [ ] company selector 열기.
- [ ] sandbox company 선택 또는 새로 생성.
- [ ] summary banner 확인.
- [ ] agents/roster 열기.
- [ ] execution/QA/CEO/graphify agent가 준비되어 있는지 확인.
- [ ] Meeting Room 열기.
- [ ] Map 지도 항목 클릭.
- [ ] Floor Map으로 전환.
- [ ] Goals 열기.
- [ ] 사용자가 목표 입력/생성.
- [ ] goal이 runtime 처리 대상으로 들어갔는지 확인.
- [ ] runtime이 자동으로 실행/대기 상태로 전환되는지 확인.
- [ ] Board 열기.
- [ ] runtime이 issue를 자동 생성할 때까지 관찰.
- [ ] 생성된 issue card 클릭.
- [ ] detail drawer의 각 section 펼치기.
- [ ] runtime이 issue를 자동 위임하는지 관찰.
- [ ] runtime이 issue를 자동 실행하는지 관찰.
- [ ] activity feed에서 실행 이벤트 확인.
- [ ] review queue 열기.
- [ ] QA/CEO agent 결과가 자동으로 반영되는지 관찰.
- [ ] merge-ready 또는 approval-needed gate가 자동으로 표시되는지 확인.
- [ ] Chat Control 또는 activity feed에서 에이전트들이 만든 계획/이슈/실행/리뷰 상태를 관찰한다.
- [ ] runtime panel에서 24시간 회사 런타임 상태가 계속 살아 있는지 확인.
- [ ] runtime stop/start 버튼은 별도 일시정지/재개 테스트에서만 클릭한다.
- [ ] settings/GitHub readiness/budget guardrail은 관찰 또는 설정 회귀 테스트로 별도 확인하고, happy path 진행 조건으로 삼지 않는다.
- [ ] 앱 종료 후 재실행.
- [ ] 선택 company, sticky stop, goal/issue/review state 유지 확인.

### 6.2 QA/CEO review lanes

- [ ] QA PASS verdict가 execution issue를 `READY_FOR_CEO`로 이동시킨다.
- [ ] QA PASS verdict는 happy path에서 사용자가 직접 누르는 버튼이 아니라 QA/review agent 결과로 반영된다.
- [ ] verdict 반영 후 board lane, review queue, activity feed가 일관되게 갱신된다.
- [ ] QA CHANGES_REQUESTED가 execution issue를 remediation/retry lane으로 되돌린다.
- [ ] QA CHANGES_REQUESTED는 runtime이 retry/remediation work를 자동 생성하거나 재위임하게 만든다.
- [ ] stale QA task result는 workflow lineage mismatch 시 무시된다.
- [ ] CEO APPROVE verdict가 merge-ready 상태를 만든다.
- [ ] CEO APPROVE verdict는 CEO/chief agent 결과로 반영된다.
- [ ] CEO APPROVE 후 GitHub merge capability/approval 상태가 명확히 보인다.
- [ ] CEO CHANGES_REQUESTED가 execution issue를 remediation/retry lane으로 되돌린다.
- [ ] CEO CHANGES_REQUESTED 후 runtime이 새 remediation issue를 만들거나 원 execution issue를 retry lane으로 되돌리고 lineage를 유지한다.
- [ ] stale CEO task result는 workflow lineage mismatch 시 무시된다.
- [ ] GitHub self-review 금지 상황에서 self-authored approval이 무한 실패하지 않고 skip/metadata refresh로 처리된다.
- [ ] review queue item을 클릭해 source issue, QA verdict, CEO verdict, merge readiness가 한 화면에서 추적 가능하다.
- [ ] review queue가 비어 있을 때 empty state가 다음 action을 안내한다.
- [ ] 사용자가 QA/CEO verdict를 수동으로 조작하지 않아도 에이전트 결과가 상태 전이를 만든다는 evidence를 남긴다.

### 6.3 Runtime loop

- [ ] company 생성/goal 입력 후 runtime이 자동으로 실행 중인 회사형 agent 상태가 된다.
- [ ] 명시적으로 수동 중지된 상태가 아닌데 runtime start 버튼을 눌러야만 goal 처리가 시작되면 `FAIL`로 기록한다.
- [ ] runtime 상태, summary banner, runtime detail이 `RUNNING` 계열로 바뀐다.
- [ ] app-server `GET /runtime` 결과와 UI 상태가 일치한다.
- [ ] global app connectivity가 runtime stop/start와 혼동되지 않는다.
- [ ] runtime stop 후에도 app global connection/offline banner가 잘못 뜨지 않는다.
- [ ] runtime stop이 sticky하게 유지된다.
- [ ] runtime stop 버튼 클릭 후 manual stop timestamp 또는 stopped indicator가 표시된다.
- [ ] app restart 후 stop 상태가 유지된다.
- [ ] 앱을 완전히 종료하고 다시 열어도 같은 company runtime이 자동 재시작되지 않는다.
- [ ] runtime이 issue/task/review transition 직후 wake한다.
- [ ] goal 입력 후 자동 issue 생성 또는 review transition 직후 activity feed/runtime last action이 갱신된다.
- [ ] 여러 runnable issue가 서로 다른 role/agent slot에서 병렬 dispatch된다.
- [ ] 병렬 dispatch 중 session strip/running sessions가 실제 agent별로 분리되어 표시된다.
- [ ] active runs가 있을 때 fast monitoring cadence로 stale `RUNNING`을 reconcile한다.
- [ ] app-server shutdown 중 active work가 interrupted issue로 requeue된다.
- [ ] backend를 종료했을 때 UI는 마지막 snapshot과 reconnect 메시지를 보여준다.
- [ ] app-server 재시작 후 queued delegated work가 resume되고 activity feed에 기록된다.
- [ ] 재시작 후 runtime panel, activity feed, issue lane이 같은 복구 상태를 보여준다.

### 6.3.1 24시간 무인 자율 운영 soak

- [ ] 사용자가 목표를 입력한 뒤 24시간 동안 추가 분해/위임/실행/리뷰 조작을 하지 않는다.
- [ ] 관찰 또는 read-only refresh 외의 사용자 action 없이 runtime이 목표를 계속 처리한다.
- [ ] 0분, 15분, 1시간, 4시간, 8시간, 24시간 시점의 runtime status, activity count, issue lane count, running session count, budget 상태를 기록한다.
- [ ] 각 기록 시점마다 앱 screenshot을 저장한다: summary, board, activity, runtime panel.
- [ ] 각 기록 시점마다 app-server dashboard/runtime JSON 또는 CLI runtime status를 함께 저장한다.
- [ ] 24시간 동안 사용자가 앱을 열어두지 않아도 backend runtime이 계속 처리하는지 확인한다.
- [ ] 앱을 닫았다가 다시 열었을 때 runtime 진행 상황이 UI에 따라잡혀 표시된다.
- [ ] 새 runnable issue가 생기면 runtime이 idle backoff를 기다리지 않고 wake/dispatch한다.
- [ ] 실패한 run이 생기면 회사가 retry/remediation/review lane으로 스스로 이동시키고, 사용자가 수동으로 다음 단계를 누르지 않는다.
- [ ] QA/CEO 결과가 도착하면 state transition이 자동 반영되고 stale result가 이전 상태를 되살리지 않는다.
- [ ] 외부 side-effect approval이 필요한 지점에서는 회사가 멈춘 이유와 필요한 승인만 표시하고, runtime/app 전체가 죽지 않는다.
- [ ] budget cap에 걸리면 dispatch를 멈추고 UI/activity에 이유를 표시한다.
- [ ] app-server 또는 desktop 앱 재시작 후 queued delegated work가 자동 복구되거나, 명확한 recoverable 상태로 남는다.
- [ ] 24시간 동안 duplicate goal/duplicate issue/duplicate run이 같은 event 재처리 때문에 폭증하지 않는다.
- [ ] 24시간 동안 secret/token/credential이 stdout, activity, evidence, screenshot에 노출되지 않는다.

### 6.3.2 회사 자율 운영 UI/UX 관찰 기준

- [ ] 사용자가 현재 회사가 `일하는 중`, `대기 중`, `승인 대기`, `차단됨`, `비용 상한`, `수동 중지` 중 어디에 있는지 3초 안에 알 수 있다.
- [ ] summary banner가 runtime status, latest action, blocked/review attention, budget 상태를 한눈에 보여준다.
- [ ] Board lane의 상태 이름과 issue card status가 같은 의미를 가진다.
- [ ] agent seat/session 표시가 실제 running issue/assignee와 일치한다.
- [ ] Activity feed는 runtime이 방금 자동으로 한 일을 사람이 읽을 수 있는 문장으로 보여준다.
- [ ] Chat Control은 사용자가 다음 단계를 누르도록 유도하지 않고, 회사가 세운 계획과 실행 상태를 관찰하게 만든다.
- [ ] Review queue는 사람이 직접 QA/CEO를 대신 누르는 화면처럼 보이지 않고, 에이전트 결과와 외부 부작용 gate를 구분해서 보여준다.
- [ ] Approval-needed 상태는 `회사가 멈춘 것`이 아니라 `외부 부작용 전 승인 대기`임을 명확히 표시한다.
- [ ] Runtime stop/start는 “회사 일시정지/재개”로 보이고, 이슈 분해/위임/실행을 수동 진행하는 컨트롤처럼 보이지 않는다.
- [ ] Meeting Room floor/brain은 장식이 아니라 현재 company, agent roster, runtime/review/activity 상태를 반영한다.
- [ ] 빈 activity/review/issue 상태에서도 다음 expected autonomous step이 무엇인지 설명한다.
- [ ] 사용자가 목표 입력 후 아무것도 누르지 않아도 화면 변화가 생기는지, 변화가 늦으면 대기/진행 안내가 있는지 확인한다.
- [ ] 장시간 실행 중 memory/CPU spike, fan noise, UI freeze가 있으면 시간과 화면 상태를 기록한다.

### 6.4 Multi-company isolation

- [ ] company A/B를 서로 다른 root로 생성한다.
- [ ] UI selector로 A -> B -> A를 전환한다.
- [ ] company A goal/issue/activity가 company B dashboard에 나타나지 않는다.
- [ ] A에서 만든 goal title을 B 검색/board/activity에서 찾을 수 없다.
- [ ] company A runtime control이 company B runtime에 영향을 주지 않는다.
- [ ] A runtime start 상태에서 B로 전환했을 때 B runtime이 독립 상태를 보여준다.
- [ ] company A agent model/capability 설정이 company B agent에 섞이지 않는다.
- [ ] A agent capability 변경 후 B agent capability API/UI가 그대로인지 확인한다.
- [ ] B에서 만든 issue detail을 열었다가 A로 돌아와도 selected issue/detail drawer가 A의 issue로 복원된다.

### 6.5 Company UI negative/edge flows

- [ ] company 생성 modal에서 취소하면 새 company가 생기지 않는다.
- [ ] agent 생성 modal에서 취소하면 roster가 바뀌지 않는다.
- [ ] goal 생성 modal에서 취소하면 goal count가 바뀌지 않는다.
- [ ] happy path에 issue/delegation/execution 수동 proposal이 필요하면 FAIL로 기록한다. 목표 입력 후 runtime이 자동으로 진행해야 한다.
- [ ] 외부 부작용이 있는 merge/backend proposal에서 취소하면 상태 변화가 없다.
- [ ] network 지연 중 같은 버튼을 여러 번 눌러도 중복 goal/issue/run이 생기지 않는다.
- [ ] 긴 company name, 긴 goal title, 긴 issue title이 sidebar/board/detail layout을 깨지 않는다.
- [ ] agent가 disabled인 경우 delegation 대상에서 제외되거나 disabled 상태가 명확히 표시된다.
- [ ] GitHub readiness failure가 회사 생성/goal/issue 조회를 막지 않고 publish 관련 action만 막는다.
- [ ] budget exceeded 상태가 runtime dispatch를 멈추고 UI에 이유를 표시한다.
- [ ] stale event stream reconnect 후 이미 소비된 QA/CEO 결과가 다시 열리지 않는다.

## 7. Git/GitHub E2E

### 7.1 Readiness/status

- [ ] GitHub PR mode에서 `gh` 미설치 상태를 readiness failure로 표시한다.
- [ ] `gh` 미인증 상태를 readiness failure로 표시한다.
- [ ] origin 없음 상태를 readiness/bootstrap 가능 상태로 표시한다.
- [ ] credential-bearing origin URL이 API/UI/log에 redacted된다.
- [ ] readiness failure는 infinite execution retry로 바뀌지 않는다.

### 7.2 Worktree/publish

- [ ] delegated run이 isolated branch를 만든다.
- [ ] delegated run이 `.cotor/worktrees/<task-id>/<agent>` 아래 isolated worktree를 만든다.
- [ ] 동일 task 재실행 시 기존 worktree reuse 정책이 지켜진다.
- [ ] local base branch와 origin base history mismatch를 readiness failure로 표시한다.
- [ ] origin base fetch failure를 명확히 표시한다.
- [ ] PR create/update는 `GITHUB_PR_CREATE`/`GITHUB_PR_UPDATE` capability gate를 통과해야 한다.

### 7.3 Review/merge side effects

- [ ] PR comment action이 `ActionSubject(companyId, issueId, taskId, agentName)`를 가진다.
- [ ] PR review action이 scoped subject와 approval metadata를 가진다.
- [ ] PR close action이 scoped subject와 approval metadata를 가진다.
- [ ] PR merge action이 scoped subject와 approval metadata를 가진다.
- [ ] subject 없는 GitHub mutating action은 guard가 deny한다.
- [ ] `GITHUB_MERGE_EXECUTE` default disabled에서 merge가 실행되지 않는다.
- [ ] recorded CEO approval이 있는 sandbox merge만 실제 merge까지 진행한다.
- [ ] merge 후 GitHub refresh가 `MERGED`를 확인하기 전에는 local workflow를 merged로 표시하지 않는다.
- [ ] merge conflict/dirty PR은 remediation issue로 되돌아간다.
- [ ] stale merge-conflict block은 PR이 clean해지면 reopen된다.
- [ ] obsolete Cotor-managed retry PR들이 batch close되고 최신 PR은 보존된다.
- [ ] merge 후 local base branch sync가 user work를 clobber하지 않는다.

## 8. Capability/security E2E

### 8.1 Default policy

- [ ] `GITHUB_MERGE_EXECUTE` default `DISABLED`.
- [ ] `MCP_CONTROL` default `DISABLED`.
- [ ] browser interact/screenshot/trace/record/external-domain/login-flow default `DISABLED`.
- [ ] video render/generate/transcode/upload default `DISABLED`.
- [ ] file write, shell exec, package install, git write, PR create/update, external API, memory write, graph write, security scan default `APPROVAL_REQUIRED`.
- [ ] test/lint/build/git read default allow path가 정상이다.

### 8.2 Action classification

- [ ] `git status`, `git diff`, `git log`는 `GIT_READ`.
- [ ] `git push`, `git commit`, `git rebase`, `git checkout -B`, `git branch -D`는 `GIT_WRITE`.
- [ ] `npm install`, `pnpm install`, `pip install`, `brew install`은 `PACKAGE_INSTALL`.
- [ ] `./gradlew test`, `swift test`, `pytest`는 `TEST_RUN`.
- [ ] `./gradlew build`, `swift build`는 `BUILD_RUN`.
- [ ] `skill.run`은 `SKILL_RUN`과 skill allowlist를 검사한다.
- [ ] `browser.*`와 `video.*` action은 matching capability로 매핑된다.

### 8.3 Allowlists and approvals

- [ ] path allowlist는 normalized containment로만 허용한다.
- [ ] sibling prefix path escape가 denied된다.
- [ ] domain allowlist는 exact host 또는 subdomain만 허용한다.
- [ ] `example.com.evil.tld` 같은 substring spoof가 denied된다.
- [ ] skill allowlist 밖 skill은 denied된다.
- [ ] `approvedBy` 또는 `capabilityApproval` 없는 `APPROVAL_REQUIRED` action은 approval required 상태다.
- [ ] recorded approval이 있으면 configured approval path만 통과한다.
- [ ] secretRefs에는 secret 이름만 저장되고 값은 저장되지 않는다.

## 9. Browser/video E2E

### 9.1 Browser smoke planning

- [ ] malformed URL은 `DENIED`.
- [ ] `file://`, `data:`, hostless URL은 `DENIED`.
- [ ] localhost URL은 external-domain capability 없이도 local browser read plan이 가능하다.
- [ ] external URL은 `BROWSER_EXTERNAL_DOMAIN` 없으면 denied.
- [ ] screenshot 요청은 `BROWSER_SCREENSHOT` capability를 요구한다.
- [ ] trace 요청은 `BROWSER_TRACE` capability를 요구한다.
- [ ] record 요청은 `BROWSER_RECORD` capability를 요구한다.
- [ ] interact 요청은 `BROWSER_INTERACT` capability를 요구한다.
- [ ] login/authenticated flow는 `BROWSER_LOGIN_FLOW` capability 없으면 denied.
- [ ] planner는 browser를 직접 실행하지 않고 command plan만 반환한다.

### 9.2 Video planning

- [ ] `video plan`이 script/write capability 상태를 반환한다.
- [ ] `video render-local`은 default denied.
- [ ] `video transcode`는 input path와 output path를 모두 검사한다.
- [ ] output path만 outside allowlist여도 denied된다.
- [ ] `video generate-remote`는 default denied.
- [ ] remote provider id가 command injection으로 해석되지 않고 plan payload에만 남는다.
- [ ] planner는 renderer/ffmpeg/remote API를 직접 실행하지 않는다.

## 10. Provider/local model E2E

- [ ] `provider list` catalog가 known provider를 모두 포함한다.
- [ ] `provider scan`은 PATH availability만 확인한다.
- [ ] `provider test <id>`는 해당 command availability message를 반환한다.
- [ ] scan/test가 login, install, pull, download, render, sync, remote refresh를 실행하지 않는다.
- [ ] `GET /api/app/agents/models?agent=opencode`가 model list를 반환한다.
- [ ] OpenCode model discovery가 `--refresh`를 자동 실행하지 않는다.
- [ ] company agent model override가 Codex/OpenCode/Ollama/LM Studio/Gemma4에서 저장/표시된다.
- [ ] Ollama local model은 loopback base URL을 사용한다.
- [ ] LM Studio local model은 loopback-compatible base URL을 사용한다.
- [ ] 실제 local model call은 local server가 준비된 경우에만 수행하고, prompt가 외부로 나가지 않는지 확인한다.

## 11. Evidence/knowledge/graphify E2E

- [ ] `graphify update .`가 성공하고 `graphify-out/graph.json`, `graph.html`, `GRAPH_REPORT.md`가 갱신된다.
- [ ] `graphify-out/GRAPH_REPORT.md`의 node/edge/community 수를 기록한다.
- [ ] `cotor agent add graphify` preset이 `graphify explain {input}` 형태로 생성된다.
- [ ] 모든 company agent execution memory에 graphify guidance가 포함된다.
- [ ] Meeting Room Map이 저장소 지도 데이터를 읽고, 기술적인 파일 경로는 기본 UI에 노출하지 않는다.
- [ ] `cotor knowledge inspect`가 local knowledge state를 출력한다.
- [ ] action success hook이 반환한 file/branch/PR evidence가 `.cotor/provenance/` graph에 기록된다.
- [ ] `evidence run`, `evidence file`, `evidence pr`가 기대 node/edge를 보여준다.
- [ ] evidence output에 token, OAuth credential, secret value가 없다.

## 12. Web editor E2E

- [ ] `./shell/cotor web --help`가 출력된다.
- [ ] `./shell/cotor web`으로 local web editor가 열린다.
- [ ] `./shell/cotor web --read-only`에서 저장/실행 mutation이 막힌다.
- [ ] `./shell/cotor web --open`이 browser를 열거나 URL을 명확히 출력한다.
- [ ] `GET /`, `GET /editor`, `GET /company`, `GET /help`가 정상 HTML을 반환한다.
- [ ] `GET /api/help-guide`가 help guide JSON/HTML payload를 반환한다.
- [ ] `GET /api/editor/config`
- [ ] `GET /api/editor/templates`
- [ ] `GET /api/editor/pipelines`
- [ ] `GET /api/editor/pipelines/{name}`
- [ ] `POST /api/editor/save`
- [ ] `POST /api/editor/run`
- [ ] `/api/runtime/*` inspection route가 정상 응답한다.
- [ ] `/api/company/*` compatibility/mirror route가 정상 응답한다.
- [ ] starter YAML을 로드한다.
- [ ] validation 결과가 UI에 표시된다.
- [ ] YAML export가 기존 config 구조를 유지한다.
- [ ] run support가 safe sample config에서 동작한다.
- [ ] invalid YAML은 명확한 validation error를 보여준다.
- [ ] web editor 종료 후 backend/process가 남지 않는다.

## 13. Packaging/install E2E

### 13.1 Source checkout

- [ ] `COTOR_DESKTOP_INSTALL_ROOT=<temp-dir> ./shell/cotor install`
- [ ] temp install root에 `Cotor Desktop.app`이 생성된다.
- [ ] `COTOR_DESKTOP_INSTALL_ROOT=<temp-dir> ./shell/cotor update`
- [ ] update가 rebuild/reinstall한다.
- [ ] `COTOR_DESKTOP_INSTALL_ROOT=<temp-dir> ./shell/cotor delete`
- [ ] app bundle과 download artifacts가 제거된다.

### 13.2 Homebrew/package assumptions

- [ ] `Formula/cotor.rb`의 packaged desktop asset 경로와 실제 release artifact 이름이 맞다.
- [ ] `shell/build-desktop-app-bundle.sh`가 backend jar와 Swift app bundle을 함께 묶는다.
- [ ] `shell/install-desktop-app.sh`가 source checkout과 packaged install layout을 구분한다.
- [ ] Homebrew install path에서는 runtime에 `gradlew`, `build.gradle.kts`, `macos/Package.swift` 존재를 가정하지 않는다.
- [ ] packaged `cotor install`은 packaged app asset을 copy한다.
- [ ] packaged first-run interactive가 local config 없을 때 `~/.cotor/interactive/default/cotor.yaml`을 생성한다.
- [ ] authenticated AI starter가 없으면 safe `example-agent` echo starter로 fallback한다.
- [ ] `/Applications` write 불가 시 `~/Applications` fallback이 동작한다.

## 14. Negative/security regression matrix

- [ ] app-server protected route without token -> unauthorized.
- [ ] app-server wrong token -> unauthorized.
- [ ] MCP control without control token -> unauthorized/forbidden.
- [ ] malformed browser URL -> denied.
- [ ] external browser domain without capability -> denied.
- [ ] path allowlist sibling escape -> denied.
- [ ] domain substring spoof -> denied.
- [ ] GitHub mutation without subject -> denied.
- [ ] GitHub merge default -> denied.
- [ ] provider scan does not call network/install/login.
- [ ] skill validation of missing file -> controlled error.
- [ ] remote URL with embedded credential -> redacted in API/UI/log.
- [ ] stale QA/CEO lineage -> ignored, no state flap.
- [ ] stale task sync does not reopen consumed outcomes.
- [ ] GitHub readiness permanent failure becomes readiness/blocker, not infinite retry.

## 15. Final release gate

Release/merge 전에 아래가 모두 참이어야 합니다.

- [ ] 자동화: `./gradlew formatCheck test shadowJar` PASS.
- [ ] 자동화: `swift test` PASS.
- [ ] 자동화: `git diff --check` PASS.
- [ ] 변경 파일 LSP diagnostics PASS 또는 LSP 환경 blocker와 Gradle 대체 증거 기록.
- [ ] CLI smoke PASS.
- [ ] app-server API smoke PASS.
- [ ] desktop manual smoke PASS: 실제 macOS 앱을 열고 클릭/입력/스크롤/전환을 수행한 증거가 있다.
- [ ] desktop UI/UX improvement loop PASS: 실제 앱 screenshot 기반 결함 분류, 수정, before/after 재검증 기록이 있다.
- [ ] company user flow PASS: 사용자가 앱에서 폴더 선택/회사 생성/목표 입력만 직접 수행했고, 이후 회사형 agent runtime이 이슈 생성/분해/위임/실행/리뷰/머지 게이트를 자동 진행했다.
- [ ] company goal -> issue -> run -> review path PASS: 수동 issue run/delegation 버튼 없이 runtime evidence로 확인했다.
- [ ] 24시간 무인 자율 운영 soak PASS 또는 실행 불가 사유가 명확히 기록됐다.
- [ ] company autonomy UI/UX PASS: 사용자가 회사가 왜 일하고/대기하고/차단됐는지 앱 화면만 보고 이해할 수 있다.
- [ ] company safety gate PASS: 외부 부작용이 있는 merge/backend/provider action만 approval/confirmation gate를 요구하고, cancel은 상태를 바꾸지 않는다.
- [ ] desktop screenshot 또는 recording evidence가 최종 리포트에 링크되어 있다.
- [ ] capability/security negative matrix PASS.
- [ ] GitHub destructive side-effect 항목은 sandbox에서 PASS 또는 명시적으로 `NOT RUN: requires external side-effect approval` 기록.
- [ ] browser/video destructive side-effect 항목은 plan-mode PASS 또는 명시적으로 `NOT RUN: capability disabled by default` 기록.
- [ ] docs English/Korean drift 없음.
- [ ] graphify graph 최신화 완료.
- [ ] known failures와 deferred risks가 최종 리포트에 명확히 적혔다.

## 16. 실패 기록 템플릿

```md
### QA Failure

- Area:
- Scenario:
- Command / Screen / Endpoint:
- Preconditions:
- Expected:
- Actual:
- Evidence:
- Logs:
- Secret/token exposure checked: yes/no
- Severity: P0/P1/P2/P3
- Decision: fix now / document limitation / blocked by environment / not applicable
```

## 17. QA 결과 요약 템플릿

```md
### Full E2E QA Summary

- Build/Test:
- CLI:
- App-server:
- Desktop:
- Desktop click evidence:
- Desktop UI/UX improvement loop:
- Company workflow:
- Company autonomous user flow:
- 24h unattended soak:
- Company autonomy UI/UX:
- Git/GitHub:
- Capability/security:
- Browser/video:
- Provider/local model:
- Evidence/graphify:
- Packaging:
- Not run with reason:
- Blockers:
- Residual risks:
- Final decision: PASS / FAIL / BLOCKED
```
