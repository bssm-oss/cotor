# 데스크톱 앱

원문: [DESKTOP_APP.md](DESKTOP_APP.md)

데스크톱 앱은 기존 Kotlin 런타임과 로컬호스트 `cotor app-server` 위에 올라가는 macOS 네이티브 셸입니다.

## Homebrew 설치 (권장)

```bash
brew tap bssm-oss/cotor https://github.com/bssm-oss/cotor.git
brew install cotor
cotor install
```

정리:

- Homebrew 패키지에는 `Cotor Desktop.app` 번들이 함께 들어 있습니다.
- `cotor install`, `cotor update`는 Homebrew prefix 안에서 재빌드하지 않고, 패키지된 번들을 그대로 재사용합니다.
- packaged install에서 로컬 config가 없을 때 `cotor` 인터랙티브 starter config는 `~/.cotor/interactive/default/cotor.yaml` 아래에 생성됩니다.
- packaged 설치와 첫 실행 규칙은 [HOMEBREW_INSTALL.md](HOMEBREW_INSTALL.md)를 보면 됩니다.

원라이너 설치도 지원합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/bssm-oss/cotor/master/shell/brew-install.sh | bash
```

## 소스에서 설치

```bash
cotor install
cotor update
cotor delete
```

소스 체크아웃에서는 로컬에서 번들을 빌드한 뒤 설치합니다.

## 구성 요소

- `cotor app-server`
  - 저장소, 워크스페이스, 태스크, 목표, 이슈, 리뷰 큐, 런타임 상태를 제공하는 localhost API
- `macos/`
  - SwiftUI 셸
- `src/main/kotlin/com/cotor/app/`
  - 저장소/워크스페이스/태스크/목표/이슈/리뷰 큐/런타임 서비스

## 백엔드 실행

```bash
cotor app-server --port 8787
```

로컬 인증 토큰을 붙이려면:

```bash
export COTOR_APP_TOKEN='your-local-token'
cotor app-server --port 8787 --token your-local-token
```

MCP 제어 도구를 별도 토큰으로 열려면:

```bash
export COTOR_APP_CONTROL_TOKEN='your-local-control-token'
cotor app-server --port 8787 --token your-local-token --control-token your-local-control-token
```

`/api/app/mcp`는 읽기 전용입니다. 상태를 바꾸는 MCP 도구는 `/api/app/mcp/control`에 있으며 control token이 필요합니다.

## macOS 앱 실행

```bash
swift run --package-path macos CotorDesktopApp
```

백엔드 URL을 직접 지정하려면:

```bash
export COTOR_APP_SERVER_URL='http://127.0.0.1:8787'
export COTOR_APP_TOKEN='your-local-token'
swift run --package-path macos CotorDesktopApp
```

번들 backend를 launcher가 관리할 때 launcher와 `DesktopAPI`는 같은 `COTOR_APP_TOKEN` 값을 읽습니다. 환경 변수가 없으면 양쪽 모두 embedded session용 desktop-local token으로 폴백합니다. 패키지 launcher는 이 token을 backend process argument에 넣지 않고 backend 환경 변수와 `0600` runtime token file로 전달합니다.
embedded backend에는 부모 shell 환경 전체가 아니라 최소한으로 정리된 환경만 전달됩니다. 따라서 우연히 설정된 API key, GitHub/Linear token, password 계열 변수는 로컬 app-server로 상속되지 않습니다. 특정 workflow가 환경 변수 기반 credential을 꼭 필요로 한다면 외부 `cotor app-server`를 명시적으로 실행해서 연결하세요.

## 로컬 앱 번들 설치

```bash
cotor install
open "/Applications/Cotor Desktop.app" || open "$HOME/Applications/Cotor Desktop.app"
```

설치된 번들은 필요할 때 로컬 백엔드를 지연 시작합니다.
마지막 데스크톱 창을 닫으면 앱도 종료되고 번들 백엔드도 같이 내려갑니다.

```bash
cotor update
cotor delete
```

`cotor delete`는 표준 `/Applications`, `~/Applications`, 다운로드 산출물을 지웁니다. `COTOR_DESKTOP_INSTALL_ROOT`가 설정되어 있으면 그 override 설치 루트의 `Cotor Desktop.app`도 함께 제거합니다.

### 설치 레이아웃별 차이

- **Homebrew / packaged install**
  - 패키지 안에 들어 있는 데스크톱 번들을 복사합니다.
  - 런타임 시점에 Gradle/Swift 재빌드는 하지 않습니다.
- **소스 체크아웃**
  - 로컬에서 번들을 다시 빌드한 뒤 설치합니다.

## 현재 셸 모델

현재 macOS 셸에는 두 가지 최상위 모드가 있습니다.

### `Company`

- 회사 선택기
- 하나의 루트 폴더에 묶이는 회사 생성
- 기본으로 `라이브 오피스` 픽셀 오피스 런타임 projection을 열고, 이벤트 기반 에이전트 sprite, 이슈 카드, A2A/message 이동, 리뷰 흐름, 활동/리뷰 drawer detail을 제공하는 `상황실` 직접 탐색
- 에이전트 정의 작성
- 에이전트 편집기와 팀 카드에서 압축형 사수 배정 표시. 새 회사에는 HR Manager가 기본 생성되어 필요한 specialist 고용과 사수 지정을 맡음
- Marketing Operator skill을 선택하면 channel, domain, 일일 게시 한도, 브랜드 규칙, session/secret reference, 최근 marketing run log를 설정하는 위임 정책 패널 표시
- 목표 목록과 목표 생성
- 앱 내부의 Linear 스타일 이슈 보드/캔버스
- 자연어 회사 명령을 메시지 스레드처럼 처리하는 전용 `운영 채팅` 탐색 surface. 자동화 모드, 승인, 런타임 동작은 지속 노출되는 상태/제어 패널이 아니라 채팅 명령으로 노출
- 회사와 이슈 surface는 점진적 공개 구조를 사용해서 첫 화면에는 현재 회사 신호와 핵심 이슈 큐만 보이고, 백엔드 health, 경로, 비용 상한, 메타데이터, 실행 로그, Linear 링크, 에이전트 대화는 펼치는 상세 화면 안에 둠
- 완료한 일, PR/리뷰 결과, 차단 항목, 복구 이벤트, 추정 비용을 전날 기준으로 집계한 아침 보고서 전용 `보고서` surface
- 별도 평가 이력을 저장하지 않고 기존 이슈, 실행, 리뷰, 조직 프로필, 회사 에이전트 정의에서 에이전트별 점수, 성공률, QA 통과율, 재시도, 평균 시간, 확인된 추정 비용을 계산하는 전용 `인사평가` surface
- 회사 메모리 스냅샷 카드는 company/project/team/agent 4계층을 보여주며, backend contract의 `workflowMemory`는 예전 client를 위한 호환 필드로 유지
- 자율 discovery scan은 CEO triage goal을 만들기 전에 내부 품질 신호를 먼저 수집하고, 저장된 problem signal은 app-server와 CLI에서 확인 가능
- CEO 채팅 인테이크: 대충 쓴 채팅 요청도 확인 후 CEO 소유 목표, 정리된 브리프, 담당 하위 이슈로 만들며 GitHub 저장소를 자동 생성하지 않음
- 이벤트 기반으로 바로 갱신되는 회사 활동 피드
- 회사 live update는 무거운 전체 refresh 대신 company event stream + 회사 전용 dashboard snapshot으로 상태를 반영
- 이슈 실행 상세 카드는 이제 각 issue-linked run마다 에이전트 CLI, 선택 모델, 백엔드 종류, 프로세스 ID, 할당 프롬프트, stdout/stderr, 브랜치, PR 링크, 퍼블리시 요약을 함께 보여줌
- 비동기 상세 정보와 메모리 스냅샷 요청은 완료 전에 선택된 issue/task가 바뀌면 오래된 응답을 적용하지 않음
- 회사 실시간 stream이 끊기면 마지막 snapshot은 유지한 채 `회사 실시간 업데이트 연결이 끊어졌습니다. 다시 동기화하는 중...` 메시지를 보여주며 복구
- 런타임 건강도, CEO가 처리하는 PR 승인, 차단 워크플로우 수, 리뷰 주의 수, 최근 오류/동작을 한곳에 모아 둔 압축형 회사 요약 배너
- 압축형 회사 요약과 회사 설정에서 선택한 런타임의 추정 비용과 일/월 비용 상한도 함께 표시
- 고정된 보드 surface 안에서도 lane 내부 스크롤로 차단/리뷰 카드가 길게 쌓여도 읽을 수 있는 이슈 보드
- stale한 Cotor retry PR은 배치 정리로 닫아서 리뷰 루프가 오래된 open PR을 계속 쌓아 두지 않게 함
- 연결된 GitHub PR이 다시 clean 상태가 되면 stale CEO merge-conflict 차단도 자동으로 다시 열림
- 예전 CEO merge-conflict 때문에 execution 이슈가 `BLOCKED`에 남아 있던 경우도 다시 `PLANNED`로 되돌려 rebase와 republish를 이어서 할 수 있게 함
- PR이 이미 머지됐는데 stale execution sync 때문에 막혀 남은 execution 이슈도 다음 runtime tick에서 자동으로 닫힘
- 런타임 시작/중지/상태
- 회사 런타임을 명시적으로 중지하면 앱 재실행이나 회사 refresh 뒤에도 사용자가 다시 시작할 때까지 그대로 유지
- 회사 모드 이벤트마다 전체 데스크톱 새로고침을 돌리지 않고, 회사 전용 dashboard snapshot으로 상태를 바로 패치
- 한 wave의 goal work가 끝나면 CEO planning lane을 다시 열어서 첫 decomposition 이후 goal이 얼어붙지 않게 함
- continuous improvement goal은 팀 구성이 허용하면 여러 branchable issue와 병렬 slice를 만들도록 유도
- 짧은 고수준 goal 설명도 더 넓은 execution portfolio로 보강해서, 큰 팀이 한두 개 이슈로만 줄어들지 않게 함
- 새 runnable work가 생기면 stale polling tick을 기다리지 않고 런타임이 즉시 깨어나며, 여러 회사 역할이 같은 execution CLI를 써도 runnable issue를 병렬로 시작할 수 있음
- 로컬 merge 완료 표시는 GitHub 새로고침 결과가 실제 `MERGED`일 때만 기록됨

### `TUI`

- 회사 워크플로 상태와 독립적
- 폴더/저장소를 골라 standalone `cotor` 세션 실행
- 여러 개의 live TUI 세션 병렬 유지
- 선택한 세션 중심의 터미널 작업 영역

## 저장소와 실행 격리

- 각 agent run은 `codex/cotor/<task-slug>/<agent-name>` 브랜치를 사용합니다.
- 각 agent run은 `.cotor/worktrees/<task-id>/<agent-name>` 아래 독립 worktree를 가집니다.
- 같은 task를 다시 실행하면 기존 격리 worktree를 재사용합니다.

## 현재 Company API 표면

현재 company-first 라우트:

- `GET /api/app/companies`
- `POST /api/app/companies`
- `GET /api/app/companies/{companyId}`
- `PATCH /api/app/companies/{companyId}`
- `GET /api/app/companies/{companyId}/agents`
- `POST /api/app/companies/{companyId}/agents`
- `PATCH /api/app/companies/{companyId}/agents/{agentId}`
- `GET /api/app/companies/{companyId}/agents/performance`
- `GET /api/app/companies/{companyId}/projects`
- `GET /api/app/companies/{companyId}/goals`
- `POST /api/app/companies/{companyId}/goals`
- `POST /api/app/companies/{companyId}/chat-intake`
- `POST /api/app/companies/{companyId}/operator/commands`
- `GET /api/app/companies/{companyId}/issues`
- `GET /api/app/companies/{companyId}/review-queue`
- `GET /api/app/companies/{companyId}/activity`
- `GET /api/app/companies/{companyId}/dashboard`
- `GET /api/app/companies/{companyId}/reports`
- `GET /api/app/companies/{companyId}/reports/{date}`
- `POST /api/app/companies/{companyId}/reports/generate`
- `GET /api/app/companies/{companyId}/memory-snapshot`
- `GET /api/app/companies/{companyId}/problem-signals`
- `POST /api/app/companies/{companyId}/autonomy/discovery-scan`
- `GET /api/app/companies/{companyId}/contexts`
- `GET /api/app/companies/{companyId}/runtime`
- `POST /api/app/companies/{companyId}/runtime/start`
- `POST /api/app/companies/{companyId}/runtime/stop`
- `GET /api/app/marketing/policies`
- `POST /api/app/marketing/policies`
- `PATCH /api/app/marketing/policies/{policyId}`
- `GET /api/app/marketing/runs`
- `POST /api/app/marketing/runs`
- `GET /api/app/marketing/runs/{runId}`
- `PATCH /api/app/companies/{companyId}/linear`
- `POST /api/app/companies/{companyId}/linear/resync`
- `PATCH /api/app/workspaces/{workspaceId}/base-branch`

오래된 클라이언트를 위한 `/api/app/company/*` 호환 라우트도 여전히 남아 있습니다.

## 현재 실제로 되는 것

- 여러 회사 생성
- 회사당 하나의 작업 폴더 바인딩
- 최소 입력 기반 회사 에이전트 정의
- 회사 에이전트별 모델 선택 저장. Codex/OpenCode뿐 아니라 Ollama/LM Studio에서 발견된 앱 관리형 로컬 모델도 같은 방식으로 선택 가능. 데스크톱 백엔드는 필요하면 로컬 Ollama를 직접 켜고, 설치된 Gemma 4 모델을 우선 사용하며, 기본 `gemma4:e2b` alias가 없으면 설치된 Gemma 계열 모델로 자동 대체
- 회사 에이전트별 선택 사수(`mentorAgentId`) 저장. 사수는 같은 회사의 활성 에이전트만 선택할 수 있고, 고급 배정 영역에서 비울 수 있음
- 새 회사에는 HR Manager와 CEO/Product/Engineering/Builder/QA/Release 기본 사수 관계를 함께 생성
- 회사 에이전트 편집기에서 내장 스킬 카탈로그를 보여주고, 친근한 스킬 선택값을 각 에이전트의 `SKILL_RUN` capability allowlist로 저장
- 에이전트 편집기에서 Marketing Operator 위임 정책 설정. 이 정책은 허용된 자사/social domain과 channel 안에서만 browser 및 marketing publish capability를 열고, 정책 밖 action은 사용자 승인으로 보내지 않고 deny 처리
- 로컬 지도 도구가 있으면 작업공간 구조 확인용 내장 회사 에이전트 선택 가능, 그리고 모든 회사 에이전트 실행 메모리에 가벼운 작업공간 지도 지침 주입
- 회사 목표 생성
- 목표를 이슈로 자동 분해
- 이슈 위임 및 실행
- issue-linked agent run에 A2A bridge metadata와 `COTOR_A2A_*` 환경 변수를 주입하고, bridge/context artifact를 canonical collaboration evidence로 사용
- 직접 완료되는 실행 이슈는 collaboration evidence 또는 verification evidence가 부족하면 일반 실행 실패가 아니라 issue verification/runtime 필드에 이유를 남기고 차단
- 내부 품질 신호를 `CompanyProblemSignal`로 저장하고, actionable/dedupe/cooldown 조건을 통과한 신호만 CEO triage goal로 전환
- 회사 단위 Linear sync가 켜져 있으면 바깥 Linear로 이슈/진행 상태 미러링
- 연결된 태스크와 실행 이력 조회
- 기존 이슈, 실행, 리뷰, 조직 프로필, 회사 에이전트 정의에서 파생한 에이전트별 성과를 조회하고, 데이터가 부족한 에이전트는 별도로 표시
- 리뷰 큐 아이템 생성 및 머지 처리
- `라이브 오피스` 런타임 projection과 runtime/backend/review/session 요약, 이벤트 기반 움직임, agent/issue/zone 상세 sheet를 함께 제공하는 전용 상황실 보기
- 운영 채팅 surface에서 상태 점검, 선택 회사의 모든 에이전트 OpenCode DeepSeek(`opencode-go/deepseek-v4-flash`) 변경, 런타임 시작/중지, 막힌 이슈 재시도, GitHub/Linear 상태 재동기화를 하나의 메시지형 명령 채팅으로 실행
- 운영 채팅에서 필요한 specialist 고용이나 사수 지정을 HR Manager에게 맡길 수 있음. HR 고용은 `opencode/nemotron-3-super-free`를 사용하고, 중복 역할과 chat/runtime tick별 무제한 고용을 막음
- 느슨한 채팅 요청을 CEO 해석, 성공 기준, 회사 목표, 담당 이슈로 바꾸되 GitHub 연결/PR 발행은 별도 명시 설정으로 유지
- `ASK_ME`, `AGENT_APPROVED`, `FULL_AUTO` 자동화 모드를 채팅 명령으로 바꿀 수 있고 기본값은 `AGENT_APPROVED`. 복구 가능한 민감 작업은 사용자 확인 rail 대신 CEO/QA/Reviewer 승인으로 라우팅
- 저장소 삭제, 대량 파일 삭제, secret 작업, 비용 상한 해제, 배포/머지 정책 해제 같은 hard-gate 작업은 모든 모드에서 차단
- 정상적인 회사 모드에서는 수동 새로고침 없이 회사 활동 조회
- 압축형 회사 요약 배너에서 런타임 건강도, CEO 승인/차단/리뷰 주의, 최근 런타임 신호 조회
- 회사 콘솔 안에서 추정 비용을 확인하고 일/월 비용 상한을 조정
- 전날 로컬 런타임, 활동, 이슈, 실행, 리뷰 데이터를 기반으로 생성된 결정적 아침 보고서 조회. 활동이 없는 날도 빈 보고서로 남김
- GitHub PR 발행이 필요한데 `gh`/`origin` 준비가 안 된 저장소는 회사 생성 시 경고
- PR 모드가 `gh` CLI, `gh` 인증, 또는 `origin` 누락으로 막히면 회사 사이드바에 간단한 GitHub 빠른 연결 패널 표시
- `origin`이 없는 경우 GitHub 저장소를 자동 생성하지 않고, GitHub 설정 패널에서 기존 저장소 URL을 연결
- 로컬 런타임 루프의 시작/중지/상태 확인
- active autonomous goal이 남아 있어도, 수동으로 중지한 회사 런타임은 사용자가 다시 시작할 때까지 유지
- active task/run이 남아 있으면 빠른 monitoring cadence를 유지해서 stale `RUNNING` 상태를 더 빨리 정리
- app-server 종료로 끊긴 회사 작업은 일반 process-exit 실패로 남기지 않고 다시 큐에 올려 재개 가능하게 복구
- PR 생성 정책 승인 대기는 회사에 CEO/최종 승인 에이전트가 있으면 그 에이전트에게 위임하고, 사용자가 직접 게이트를 승인하지 않아도 게시를 다시 시도함
- 그 후 데스크톱 앱과 번들 backend가 다시 올라오면 queued delegated 회사 작업을 다시 시작하고, 회사 활동 로그에도 그 복구 흐름을 남김
- 필요하면 issue pipeline id로 issue-linked durable run을 묶어서 `cotor resume inspect <run-id>`가 올바른 회사 이슈 실행에 계속 연결되도록 함
- 회사 이슈 실행은 기본적으로 durable run snapshot을 만들어서 이슈의 `durableRunId`를 `cotor resume inspect <run-id>`로 확인할 수 있음
- 기본 회사 프로필은 로컬 설치된 agent CLI를 우선 사용하고, 끝까지 없으면 `echo` fallback 사용

## 현재 한계

- macOS 셸만 지원합니다.
- Linear sync는 회사 단위 outward mirror이며, 기존 Linear 이슈를 다시 Cotor로 가져오지는 않습니다.
- 런타임 자동화에는 action 단위 allow/deny/approval를 다루는 정책 엔진 v1이 들어갔지만, 아직 file-backed 실험 기능입니다.
- 리뷰/PR 동기화에는 `gh` 기반 GitHub control-plane v1이 들어가서 PR 상태, mergeability, status-check summary를 읽어옵니다.
- 회사 이슈 실행은 기본 durable snapshot으로 inspect 가능하지만, 일반 pipeline replay용 `resume continue/fork/approve`와 회사 전체 issue/review continuation은 아직 완전하지 않습니다.
