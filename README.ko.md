# Cotor

Cotor는 로컬 우선 AI 워크플로우 실행기에서 출발해, CEO AI가 하위 AI에게 일을 분배하고 CLI 기반 실행으로 비용을 낮추며 macOS에서 운영 상태를 보는 “회사형 AI 운영체제”로 확장된 도구입니다. 파이프라인 실행, localhost `app-server`, 네이티브 데스크톱 셸이 같은 Kotlin 기반을 공유합니다.

## 현재 빌드에서 실제로 되는 것

- `SEQUENTIAL`, `PARALLEL`, `DAG` 파이프라인 실행
- 검증, 린트, 상태 조회, 통계, 체크포인트, 템플릿 생성
- 로컬 웹 에디터와 YAML 저장/실행
- `cotor app-server` 기반 macOS 데스크톱 셸
- 회사, 에이전트 정의, 목표, 이슈, 리뷰 큐, 활동 피드, 런타임 상태를 포함한 다중 컴퍼니 운영 레이어
- 회사별 추정 AI 비용 집계와 일/월 비용 상한 설정
- 명령 검증, durable replay side-effect 승인, 데스크톱/백엔드 토큰 일관성에 대한 런타임 hardening

## 현재 CLI 명령 체계

`Main.kt` 기준 최상위 명령:

`init`, `run`, `dash`, `interactive`, `validate`, `test`, `template`, `resume`, `checkpoint`, `stats`, `doctor`, `status`, `list`, `web`, `app-server`, `lint`, `explain`, `plugin`, `agent`, `company`, `auth`, `policy`, `evidence`, `github`, `knowledge`, `mcp`, `version`, `completion`

중요한 진입 규칙:

- 인자 없이 `cotor`를 실행하면 `interactive`가 시작됩니다.
- `cotor tui`는 `interactive` 별칭입니다.
- `interactive`는 기본적으로 선호 단일 에이전트 채팅으로 시작하고, `--mode auto|compare` 또는 `:mode ...`로 멀티 에이전트에 전환할 수 있습니다.
- `cotor help ai`는 줄글 형태의 사용 가이드를 출력합니다.
- `cotor help web`은 명령어 모음집과 빠른 시작 안내를 웹 도움말 표면으로 엽니다.
- interactive transcript는 `.cotor/interactive/...` 아래에 저장되며, 각 세션은 transcript 옆에 `interactive.log`도 기록합니다.
- packaged install에서 로컬 config가 없으면 interactive starter config는 현재 디렉터리 대신 `~/.cotor/interactive/default/cotor.yaml` 아래에 생성됩니다.
- packaged first-run interactive는 즉시 응답 가능한 AI starter만 자동 선택하고, 인증되지 않은 CLI 때문에 깨지는 대신 안전한 `example-agent` Echo starter로 내려갑니다.
- 첫 인자가 알 수 없는 명령이면 직접 파이프라인 실행으로 폴백합니다.

현재 서브커맨드:

- `agent add`, `agent list`
- `auth codex-oauth login|status|logout`
- `company ...` 로 회사/에이전트/목표/이슈/리뷰/런타임/백엔드/Linear/context/message/autonomy 조작. `company autonomy scan <company-id>`, `company problem-signals <company-id>` 포함
- `plugin init`
- `checkpoint gc`
- `policy validate`, `policy simulate`
- `capability list`, `capability inspect`, `capability simulate`
- `provider list`, `provider scan`, `provider test`
- `skill list`, `skill inspect`, `skill validate`, `skill run`
- backend capability gate를 통과한 browser smoke 계획을 만드는 `browser smoke`
- backend capability gate를 통과한 video 작업 계획을 만드는 `video plan`, `video render`, `video transcode`, `video generate-remote`
- `evidence run`, `evidence file`, `evidence pr`
- `github sync`, `github inspect-pr`, `github list`, `github events`
- `knowledge inspect`
- `verification inspect`
- `runtime inspect`
- `mcp serve --readonly`
- app-server MCP는 `/api/app/mcp` 읽기 전용과 `COTOR_APP_CONTROL_TOKEN`이 필요한 `/api/app/mcp/control` 제어 표면으로 분리됩니다.

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

## 설치

### Homebrew (권장)

```bash
brew tap bssm-oss/cotor https://github.com/bssm-oss/cotor.git
brew install bssm-oss/cotor/cotor
```

JDK 17과 CLI가 함께 설치되며, 번들된 데스크톱 앱도 포함됩니다.
`brew install` 후 `cotor install`을 실행하여 `Cotor Desktop.app`을 Applications에 복사하세요.
`cotor install` / `cotor update`는 패키지된 앱을 재사용하여 다시 빌드하지 않습니다.
`cotor install`은 정확한 설치 경로를 출력하며, `/Applications`에 쓸 수 없으면 `~/Applications`로 대체합니다.

업데이트:

```bash
brew upgrade bssm-oss/cotor/cotor
```

### DMG 직접 다운로드

[GitHub Releases](https://github.com/bssm-oss/cotor/releases/latest)에서 최신 DMG를 다운로드:

1. `Cotor-<version>.dmg` 다운로드
2. DMG 파일 열기
3. `Cotor Desktop.app`을 `/Applications`로 드래그

### 소스에서 빌드

```bash
git clone https://github.com/bssm-oss/cotor.git
cd cotor
./shell/cotor version   # JDK 17 자동 감지, shadowJar 자동 빌드
```

## 빠른 시작

```bash
cotor version
cotor help
cotor help --lang en
cotor init --starter-template
cotor install
cotor app-server --port 8787
open "/Applications/Cotor Desktop.app"
```

실험적 durable runtime 사용 예:

```bash
export COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1
cotor run <pipeline> -c cotor.yaml
cotor resume inspect <run-id>
cotor resume continue <run-id> --config cotor.yaml
cotor resume fork <run-id> --from <checkpoint-id> --config cotor.yaml
cotor resume approve <run-id> --checkpoint <checkpoint-id>
```

Durable replay는 file write, secret read 같은 side-effect 종류를 정확히 기록합니다. replay-safe가 아닌 side-effect는 `continue` / `fork` 중 명시적 승인이 있기 전까지 실행을 멈춥니다.

## macOS 데스크톱

`brew install cotor` 후 데스크톱 앱 설치:

```bash
cotor install
open "/Applications/Cotor Desktop.app"
```

앱 관리 명령:

```bash
cotor install   # 처음 설치
cotor update    # 업데이트
cotor delete    # 삭제
```

- Homebrew 설치: `cotor install`이 패키지된 번들을 복사 (빌드 불필요)
- 소스 설치: `cotor install`이 로컬에서 빌드 후 설치
- `cotor install`은 정확한 설치 경로를 출력
- `/Applications`에 쓸 수 없으면 `~/Applications` 사용

현재 데스크톱 셸 구조:

- 최상위 `Company` / `TUI` 모드 분리
- `Company` 모드에서 회사 목록, 에이전트 정의, 목표, 이슈 보드/캔버스, 활동 피드, 런타임 제어, 전용 `미팅룸` surface 제공
- 자연어 회사 명령을 메시지처럼 주고받는 전용 `운영 채팅` 탐색 surface 제공. 자동화 모드, 승인, 런타임 동작은 항상 보이는 제어 레일이 아니라 채팅 명령으로 처리
- `Company` 요약은 기본 화면에서 즉시 필요한 회사 상태와 최근 이슈만 보여주고, 팀 작업, 실행 현황, CEO 결정, Linear 상태, 활동 기록은 펼치는 세부정보 안에 둠
- `Company`와 이슈 surface는 점진적 공개 구조를 사용해서 경로, 백엔드 health, 비용 상한, 메타데이터, 실행 로그, 에이전트 대화 같은 고급 정보는 더 깊은 상세 화면에서만 표시
- 전용 `보고서` 탐색 surface에서 완료한 일, PR/리뷰 결과, 차단 항목, 복구 이벤트, 추정 비용을 전날 기준으로 모은 결정적 아침 보고서를 보여줌
- 전용 `인사평가` 탐색 surface에서 기존 회사 실행 데이터로 파생한 에이전트별 점수, 성공률, QA 통과율, 재시도, 평균 시간, 확인된 추정 비용을 보여줌
- 회사 메모리 스냅샷은 company/project/team/agent 4계층으로 나뉘며, 기존 workflow memory 필드는 project + team의 호환 alias로 유지
- 자율 런타임은 새 일을 만들기 전에 내부 품질 신호를 먼저 스캔해서, idle 루프가 무작위 continuous prompt 대신 `idle-no-discovered-problems` 또는 `discovery-triage-created` 같은 관측 가능한 상태를 남김
- `Company` 모드는 기본적으로 이벤트 기반 live update를 사용해서, 정상 동작 중에는 수동 새로고침 없이 활동 로그, 이슈, 리뷰 상태, 런타임 상태가 바로 반영됨
- 데스크톱 backend launch, health check, shutdown, client request가 같은 `COTOR_APP_TOKEN` source를 사용해서 token-protected local session이 어긋나지 않음
- embedded 데스크톱 backend는 정리된 최소 환경으로 시작해서, 우연히 부모 shell에 있던 API key, provider token, password 계열 변수를 로컬 app-server로 넘기지 않음
- `미팅룸`은 기본으로 쉬운 `지도`를 열고, 준비된 그래프가 없어도 폴더 기반 기본 지도를 보여주며, `에이전트 회의`와 라이브 플로어 보기를 바로 전환할 수 있음
- 회사 이슈 실행 상세는 이제 단순 변경점이 아니라 에이전트 CLI, 선택 모델, 백엔드 종류, 프로세스 ID, 할당 프롬프트, stdout/stderr, 브랜치, PR 링크, 퍼블리시 요약까지 함께 보여줌
- `cotor company issue run <issue-id>`는 기본적으로 이슈가 정착 상태가 될 때까지 기다려서, CLI에서 시작한 로컬 에이전트 작업이 중간에 고아 작업으로 끊기지 않게 함. 이미 실행 중인 app-server가 백그라운드 작업을 맡아야 할 때만 `--async` 사용
- 회사 런타임은 이제 이슈/태스크/리뷰 상태 변화가 생기면 바로 깨어나며, 서로 다른 역할이 같은 execution CLI를 쓰더라도 runnable issue를 병렬로 시작할 수 있음
- CEO 머지는 GitHub 새로고침 결과가 실제 `MERGED`로 확인된 뒤에만 로컬 workflow 상태를 merged로 기록함
- 회사 CEO/최종 승인 에이전트가 있으면 PR 생성 정책 게이트도 내부 승인으로 처리해서, 사용자가 직접 승인 프롬프트를 누르지 않아도 게시 재시도가 이어짐
- 운영 채팅은 `ASK_ME`, `AGENT_APPROVED`, `FULL_AUTO`를 지원하며 기본값은 `AGENT_APPROVED`. `FULL_AUTO`에서도 저장소 삭제, 대량 파일 삭제, secret 작업, 비용 상한 해제, 배포/머지 정책 해제 같은 hard-gate 작업은 차단
- 회사 에이전트 정의는 이제 Codex, OpenCode, Ollama, LM Studio, 앱 관리형 로컬 Gemma 모델 같은 provider별로 선택 모델을 개별 지정할 수 있음. Cotor는 설치된 Gemma 4 모델을 우선 사용하고, 기본 `gemma4:e2b` alias가 없으면 설치된 Gemma 계열 모델로 실패 없이 이어감
- 회사 에이전트에서 Marketing Operator skill을 선택하면 owned/social channel, 허용 domain, 게시 한도, 브랜드 규칙, session/secret reference를 설정하는 위임 정책 패널 표시
- 회사 실시간 stream이 잠깐 끊겨도 현재 company snapshot은 유지하고, generic decode 오류 대신 회사 전용 재동기화 메시지를 보여줌
- 이슈 보드는 lane 내부 스크롤을 써서 차단/리뷰 카드가 많아져도 상단만 잘린 채 보이지 않게 함
- stale한 Cotor retry PR은 배치 정리로 닫아서 같은 리뷰 루프가 수백 개의 오래된 open PR을 계속 남기지 않게 함
- GitHub PR이 다시 clean 상태가 되면 stale merge-conflict 차단도 자동으로 CEO lane으로 되돌려서, rebase 후 수동 리셋 없이 흐름을 이어감
- 오래된 CEO merge-conflict 차단 상태는 다시 execution으로 되돌려 rebase, republish, 후속 진행이 가능하게 함
- 연결된 PR이 이미 머지됐는데 stale execution sync 때문에 `BLOCKED`로 남은 이슈는 다음 runtime tick에서 자동으로 `DONE`으로 정규화됨
- `TUI` 모드에서 폴더 기반 단독 `cotor` 터미널을 여러 개 병렬로 유지
- 활성 실행 컨텍스트를 옮기는 상단 세션 스트립
- 변경점, 파일, 포트, 브라우저, 리뷰 메타데이터를 담는 접이식 상세 드로어
- 앱 안에서 명령어 모음집과 빠른 사용 흐름을 볼 수 있는 내장 Help sheet

## 자율 운영 회사 상태

현재 빌드에서 실제로 가능한 흐름:

- 작업 폴더별로 여러 회사 생성
- GitHub PR 모드인데 `gh` 인증이나 `origin` 연결이 없으면 회사 생성 직후 바로 경고 표시. `origin`이 없다고 Cotor가 GitHub 저장소를 자동 생성하지는 않음
- 데스크톱 앱에서 `gh` 로그인과 기존 GitHub 저장소 URL 저장으로 `origin` 연결
- 직함/CLI/역할 설명만으로 회사 에이전트 정의
- `gemma4`, `ollama`, `lmstudio` 에이전트로 회사 에이전트별 provider 모델 선택 저장. 데스크톱 백엔드는 필요하면 로컬 Ollama를 직접 켜고, 설치된 Gemma 4 모델을 우선 사용하며, 기본 `gemma4:e2b` alias가 없으면 설치된 Gemma 계열 모델로 자동 대체
- 같은 에이전트 팀에서 내장 저장소 지도 에이전트로 작업공간 구조를 확인하며, 모든 회사 에이전트의 실행 메모리에도 가벼운 작업공간 지도 지침 주입
- Marketing Operator browser 게시 작업은 사전 위임 정책으로만 열고, 정책 밖 owned/social action은 사용자 승인 queue로 보내지 않고 deny 처리
- 회사 목표 생성
- 목표를 이슈로 분해
- 이슈 위임 및 실행
- issue-linked agent run마다 A2A bridge metadata를 열고 `COTOR_A2A_*` 환경 변수를 주입하며, 직접 완료되는 실행 이슈는 bridge/context evidence가 있어야 `DONE`으로 넘어감
- 반복 실패, 오래 막힌 이슈, 리뷰 실패, 검증 공백, 런타임 오류, 오래된 follow-up, repository graph 경고를 `CompanyProblemSignal`로 저장하는 내부 discovery scan 실행
- 완료된 회사 이슈 실행은 실험적 pipeline replay flag 없이도 `cotor resume inspect <run-id>`로 durable run을 확인 가능
- 기존 회사 이슈, 실행, 리뷰, 조직 프로필, 에이전트 정의에서 파생한 에이전트별 성과를 조회하고, 데이터가 부족한 에이전트는 별도로 표시
- 리뷰 큐 생성
- 기본 `지도`, 실시간 협업을 보는 `에이전트 회의` 테이블, runtime/backend/review/session 상태를 합성한 이벤트 월, 움직이는 에이전트 플로어를 함께 제공하는 전용 미팅룸 보기
- 운영 채팅 surface에서 상태 점검, 선택 회사의 모든 에이전트 OpenCode DeepSeek(`opencode-go/deepseek-v4-flash`) 변경, 런타임 시작/중지, 막힌 이슈 재시도, GitHub/Linear 상태 재동기화를 하나의 메시지형 명령 채팅으로 실행
- 느슨하게 쓴 채팅 요청도 CEO가 목표, 성공 기준, 담당 하위 이슈로 정리하게 하되 GitHub 저장소는 자동 생성하지 않음
- `AGENT_APPROVED` 모드에서는 복구 가능한 민감 작업을 사용자 확인 패널 대신 상위 회사 에이전트 승인으로 라우팅
- 한 wave가 끝나면 CEO planning lane을 다시 열어서 active goal이 첫 batch 이후에도 다음 이슈 wave를 이어서 만들 수 있음
- continuous improvement goal은 한 개의 좁은 후속 이슈보다 여러 branchable issue와 병렬 slice를 우선 만들도록 유도
- 짧은 고수준 goal 설명도 더 넓은 execution portfolio로 보강해서, 큰 팀이 한두 개 이슈로만 수렴하지 않게 함
- 회사 런타임을 수동으로 중지하면 앱 재실행, dashboard 조회, 실시간 재연결 뒤에도 시작을 다시 누르기 전까지 그대로 중지 상태 유지
- 회사 요약 페이지에서는 압축된 런타임 상태와 최근 이슈만 먼저 보고, 필요할 때 고급 세부정보를 열어 차단/리뷰/활동 기록 확인
- 전날 로컬 날짜 기준 아침 보고서 조회. 보고서는 LLM 생성 문장이 아니라 로컬 런타임, 활동, 이슈, 실행, 리뷰 데이터 집계로 생성
- 회사별 로컬 자율 런타임 시작/중지
- active task/run이 남아 있으면 회사 런타임이 느린 idle backoff로 내려가지 않고 빠른 monitoring cadence를 유지해서 죽은 `RUNNING` 상태를 더 빨리 정리
- app-server가 active company work 도중 종료되면, 현재 빌드는 일반 process-exit 실패로 굳히지 않고 해당 이슈를 다시 큐에 올려 재개 가능하게 유지
- 그 뒤 데스크톱 앱을 다시 열면 실행 중이던 회사 런타임이 queued delegated work를 다시 태우고, 회사 활동 로그에도 복구 흐름이 바로 반영됨

현재 한계:

- 앱 안의 보드는 `Linear 같은` 운영 UI일 뿐, 외부 Linear 실동기화는 이번 빌드 범위가 아닙니다.
- 런타임 자동화는 최소 루프 수준입니다.
- 정책 엔진은 v1이며, 현재는 외부 정책 언어 대신 action 단위 allow/deny/approval 제어와 simulate/inspect 흐름에 집중합니다.
- risk approval은 v1이며, 현재는 action 종류/경로/네트워크 대상 기반 휴리스틱 점수로만 동작합니다.
- GitHub control plane은 v1이며, 현재는 webhook 기반 GitHub App이 아니라 `gh` 기반 PR 상태/mergeability/status-check summary 동기화 방식입니다.
- verification bundle은 로컬에 contract/outcome 상태를 저장하고, 회사 이슈 완료 시 `verificationStatus` / `verificationSummary`를 남깁니다. 더 깊은 verifier-agent continuation은 아직 별도 runtime이 아니라 prompt-driven 흐름입니다.
- runtime projection surface는 issue 단위 `runtimeDisposition`을 보여주지만, 스케줄러는 아직 heuristic 수준입니다.
- 회사 컨텍스트는 `.cotor/companies/...` 스냅샷에 더해 `.cotor/provenance/`, `.cotor/knowledge/` 기반의 구조화된 증거/지식 저장소를 사용합니다.
- 회사 이슈 실행은 기본적으로 inspect 가능한 durable run snapshot을 생성합니다. 일반 pipeline replay용 `resume continue/fork/approve`는 여전히 `COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1` 뒤의 실험 기능입니다.

## 문서

시작점:

- [문서 인덱스](docs/INDEX.md)
- [영문 가이드](docs/README.md)
- [한글 가이드](docs/README.ko.md)
- [빠른 시작](docs/QUICK_START.md)
- [문제 해결](docs/TROUBLESHOOTING.ko.md)
- [데스크톱 앱](docs/DESKTOP_APP.md)
- [기능 목록](docs/FEATURES.md)
- [검증 계획](docs/TEST_PLAN.md)
- [팀 운영](docs/team-ops/README.ko.md)
- [AI 에이전트 규칙](AGENTS.md)

과거 리포트, 릴리스 기록, 설계 초안은 [docs/INDEX.md](docs/INDEX.md)의 `Historical / design records` 섹션에서 찾을 수 있습니다.

## 검증 기준선

```bash
./gradlew --no-build-cache test -x jacocoTestCoverageVerification
cd macos && swift build
```
