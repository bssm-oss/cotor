# Cotor TestSprite PRD

## 제품 요약

Cotor는 로컬 우선 멀티 에이전트 워크플로 실행기입니다. 하나의 Kotlin 코어가 CLI/TUI 명령, localhost app-server, 브라우저 기반 파이프라인 편집기, 네이티브 macOS 데스크톱 셸을 구동합니다. 현재 데스크톱 제품 모델의 중심은 Company입니다. Company는 goal, issue, review state, runtime state, agent definition, memory, cost guardrail, local evidence를 소유합니다.

## 주요 사용자

- 로컬 operator: 터미널에서 `cotor`를 실행하고 pipeline config를 검증하며 one-off 또는 interactive agent workflow를 시작합니다.
- 데스크톱 operator: macOS 앱에서 company, goal, issue, review queue, report, runtime control, TUI session을 관리합니다.
- maintainer: 릴리스 전에 CLI, app-server, desktop packaging, provider default, policy/evidence 동작을 검증합니다.

## 제품 표면

1. CLI와 interactive TUI
   - 인자 없는 `cotor`는 interactive mode를 엽니다.
   - `cotor tui`는 interactive mode alias입니다.
   - 명령에는 `init`, `run`, `validate`, `lint`, `test`, `web`, `app-server`, `company`, `auth`, `policy`, `provider`, `skill`, `mcp`, `version`이 포함됩니다.

2. 로컬 app-server
   - Base URL: `http://127.0.0.1:8787`.
   - `/health`와 `/ready`는 인증 없는 reachability probe입니다.
   - `/api/app/**` route는 `Authorization: Bearer <COTOR_APP_TOKEN>`이 필요합니다.
   - `/api/app/mcp`는 read-only입니다.
   - `/api/app/mcp/control`은 `COTOR_APP_CONTROL_TOKEN`이 필요하며 기본 TestSprite 실행 범위에서 제외합니다.

3. Company workflow
   - Company 하나는 하나의 root folder에 바인딩됩니다.
   - Company는 goal, issue, agent, runtime state, activity, review queue, report, memory snapshot, problem signal을 소유합니다.
   - Company runtime control은 해당 company에만 영향을 줘야 하며 전역 app-server reachability와 분리되어야 합니다.
   - 기본 automation mode는 `AGENT_APPROVED`입니다. `FULL_AUTO`에서도 hard-gated destructive action은 차단됩니다.

4. 브라우저 웹 편집기
   - `cotor web --port 8080 --read-only`는 제한적인 frontend testing에 적합한 브라우저 기반 pipeline editor를 시작합니다.
   - 네이티브 macOS 데스크톱 앱은 브라우저 테스트 대상이 아닙니다.

5. 네이티브 macOS 데스크톱
   - 데스크톱 앱은 로컬 app-server 위의 셸입니다.
   - 최상위 mode는 `Company`와 `TUI`입니다.
   - 데스크톱 검증은 Swift build/test와 수동 smoke check로 유지합니다.

## 핵심 기능 요구사항

### CLI와 설정

- `cotor version`은 현재 버전을 출력합니다.
- `cotor help`와 `cotor help --lang ko`는 명령 도움말을 출력합니다.
- `cotor init --starter-template`은 안전한 echo-agent starter config를 만듭니다.
- `cotor validate <file>`과 `cotor lint <file>`은 pipeline/config 파일을 검증합니다.
- `cotor web --read-only`는 쓰기를 허용하지 않는 브라우저 편집기를 시작합니다.
- `cotor app-server --port 8787 --token <token>`은 로컬 HTTP API를 시작합니다.

### App-server 인증과 health

- `/health`와 `/ready`는 bearer auth 없이 응답합니다.
- `/api/app/health`는 bearer token이 없거나 잘못되면 거부합니다.
- 인증된 `/api/app/health`는 healthy app-server 응답을 반환합니다.
- non-loopback app-server host에는 명시적인 token이 필요합니다.

### Company lifecycle

- Company는 name, root path, optional default branch, automation mode, optional daily/monthly budget cents로 생성할 수 있습니다.
- Company list는 저장된 company를 반환하되 관련 없는 local secret을 노출하지 않아야 합니다.
- Company dashboard는 current state, issue, review queue, runtime, report, projection을 compact하게 반환합니다.
- Company update는 name, base branch, autonomy, backend kind, budget guardrail을 바꿀 수 있습니다.
- Company delete는 destructive action이므로 기본 TestSprite 실행에 포함하지 않습니다.

### Agent, goal, issue workflow

- Company agent는 list, create, update, enable/disable, optional model override 설정이 가능합니다.
- Goal은 title, description, success metrics, autonomy flag와 함께 company 아래에 생성됩니다.
- Issue는 title, description, priority, kind와 함께 goal 아래에 생성됩니다.
- Issue는 company별, 필요하면 goal별로 조회할 수 있습니다.
- Issue execution detail은 가능한 경우 agent CLI, selected model, backend kind, process id, prompt, stdout/stderr, branch, PR link, publish summary를 노출합니다.
- Review queue는 company별로 조회할 수 있습니다.
- Review verdict, merge, issue run, runtime start/stop은 mutable flow이므로 sandbox 실행에만 사용합니다.

### TUI session

- TUI session은 workspace와 optional preferred agent에 대해 열립니다.
- Session list, detail, delta, input, terminate endpoint는 분리되어 있습니다.
- Session terminate는 destructive action이므로 기본 TestSprite 실행 범위에서 제외합니다.

### Evidence, policy, MCP

- Evidence는 run, file, pull request 기준으로 조회할 수 있습니다.
- Policy decision은 run과 issue 기준으로 조회할 수 있습니다.
- Read-only MCP tool은 company summary, issue list, durable run inspection, approval queue, evidence summary, verification bundle, memory snapshot, GitHub company events, runtime projection을 제공합니다.
- MCP control tool은 read-only surface에서 비활성화되어야 합니다.

## 기본 TestSprite 실행의 비목표

- 실제 GitHub repository를 만들거나 삭제하지 않습니다.
- 실제 pull request를 publish, merge, close하지 않습니다.
- Company, goal, issue, context entry, local worktree, user file을 삭제하지 않습니다.
- 외부 marketing/browser publish action을 실행하지 않습니다.
- local runtime state, log, `.cotor/`, `.env`, token file, `local.properties`, credential을 업로드하지 않습니다.

## 테스트 데이터 전략

- Mutable company workflow 테스트에는 `/Users/Projects/bssm-oss/cotor-organization/cotor-test`를 사용합니다.
- Disposable company name은 `TestSprite Sandbox <timestamp>`처럼 명확히 만듭니다.
- 테스트가 sandbox runtime start/stop 자체를 다루지 않는 한 runtime은 멈춘 상태로 둡니다.
- 기본 baseline은 read-only dashboard/list/health route를 우선합니다.

## 인수 기준

- TestSprite가 Kotlin/Gradle backend, SwiftPM macOS package, browser web editor를 감지할 수 있습니다.
- TestSprite backend test가 unauthenticated health probe와 token-protected `/api/app` route를 구분합니다.
- 생성된 API test는 `/api/app/**`에 bearer auth를 사용합니다.
- 생성된 test는 sandbox 지시가 명시적으로 허용하지 않는 한 destructive route를 피합니다.
- 생성된 plan은 현재 company-first 제품 모델과 최상위 `Company` / `TUI` desktop shell split을 반영합니다.
- Report는 실패가 제품 결함인지, 누락된 local precondition인지, auth setup 문제인지, 의도적으로 차단된 destructive action인지 구분합니다.
