# 에이전트 Capability

Cotor는 회사 에이전트마다 명시적인 capability profile을 저장하고, 이 profile을 backend action layer에서 검사합니다. 데스크톱 UI나 CLI는 토글을 보여줄 수 있지만 실제 강제 지점은 `ActionExecutionService`의 `AgentCapabilityGuard`입니다.

## 모드

- `DISABLED`: action을 거부합니다.
- `READ_ONLY`: 읽기 성격의 action만 허용합니다.
- `PROPOSE_ONLY`: 제안은 가능하지만 실행 전 승인이 필요합니다.
- `APPROVAL_REQUIRED`: 실행 전 승인이 필요합니다.
- `AUTO`: 자동 실행을 허용합니다.

## 안전 기본값

위험한 action은 기본값으로 자동 실행되지 않습니다.

- `GITHUB_MERGE_EXECUTE`, `MCP_CONTROL`, browser interaction, remote video/image generation, upload, deploy execution은 기본 `DISABLED`입니다.
- file write, shell execution, package install, git write, PR 생성/수정, external API call, memory write, graph write, security scan은 기본 `APPROVAL_REQUIRED`입니다.
- local test, lint, build, git read는 상황에 맞게 `AUTO`입니다.
- memory read, graph read, file read, shell read, GitHub read는 읽기 중심 모드입니다.

새 회사의 기본 로스터에는 저장소 범위 실행 profile도 함께 저장됩니다. 이 profile은 기본 회사 에이전트가 회사 저장소 루트 안에서만 로컬 agent CLI 실행과 격리 git worktree 생성을 자동으로 할 수 있게 합니다. publish, PR 수정, merge, browser 제어, package install, external API call 같은 더 위험한 action은 운영자가 profile을 바꾸지 않는 한 더 엄격한 catalog 기본값을 유지합니다.

## Backend 강제

guard는 action block이 실행되기 전에 runtime action kind를 capability key로 매핑합니다.

- `agent.exec` 및 위험 shell command -> `SHELL_EXEC`
- `skill.run` -> `SKILL_RUN`; `skillAllowlist`가 있으면 action metadata의 `skill` 값이 일치해야 합니다.
- `browser.read`, `browser.interact`, `browser.screenshot`, `browser.trace`, `browser.record`, `browser.external-domain`, `browser.login-flow` -> 대응하는 `BROWSER_*` key
- `video.script-write`, `video.render-local`, `video.generate-remote`, `video.transcode`, `video.upload` -> 대응하는 `VIDEO_*` key
- package manager install -> `PACKAGE_INSTALL`
- test/lint/build command -> `TEST_RUN`, `LINT_RUN`, `BUILD_RUN`
- `git.worktree` -> `GIT_WRITE`
- `git.publish` -> `GITHUB_PR_CREATE`
- GitHub review/comment -> `GITHUB_PR_UPDATE`
- GitHub merge -> `GITHUB_MERGE_EXECUTE`
- HTTP call -> `EXTERNAL_API_CALL`
- file write -> `FILE_WRITE`

company/agent context가 없는 action에는 capability guard가 권한을 주장하지 않으며, 기존 policy/risk interceptor가 계속 적용됩니다.

## CLI

```bash
cotor capability list
cotor capability inspect GITHUB_MERGE_EXECUTE
cotor capability simulate --company <companyId> --agent <agentId> --action github.merge
cotor capability simulate --company <companyId> --agent <agentId> --action skill.run --skill graphify
cotor capability simulate --company <companyId> --agent <agentId> --action browser.screenshot
cotor capability simulate --company <companyId> --agent <agentId> --action video.render-local
cotor company agent capabilities <agentId> --company-id <companyId>
cotor company agent capability <agentId> SHELL_EXEC --company-id <companyId> --mode AUTO
cotor skill list
cotor skill validate ./skill.yaml
cotor skill run graphify --company <companyId> --agent <agentId> --input "map repository"
cotor browser smoke --company <companyId> --agent <agentId> --url http://127.0.0.1:3000 --screenshot
cotor video plan --company <companyId> --agent <agentId> --issue <issueId> --project ./video
cotor video render --company <companyId> --agent <agentId> --project ./video --provider remotion
cotor video transcode --company <companyId> --agent <agentId> --input ./input.mov --output ./output.mp4
```

CLI/API에서는 내부 skill id를 안정적으로 유지합니다. 데스크톱 앱에서는 회사 에이전트를 설정할 때 `Repository Mapper`, `Browser Tester`, `Video Builder` 같은 더 친근한 배정 이름으로 표시합니다.

Capability setting에는 provider/model 힌트, path/domain/skill allowlist, secret reference 이름, evidence/review 요구사항, notes를 넣을 수 있습니다. secret 값은 저장하지 말고 reference 이름만 저장하세요.

## App-Server API

- `GET /api/app/capabilities/catalog`
- `GET /api/app/companies/{companyId}/agents/{agentId}/capabilities`
- `PATCH /api/app/companies/{companyId}/agents/{agentId}/capabilities`
- `POST /api/app/companies/{companyId}/agents/{agentId}/capabilities/simulate`
- `POST /api/app/browser/smoke`
- `POST /api/app/video/plan`
- `POST /api/app/video/render-local`
- `POST /api/app/video/transcode`
- `POST /api/app/video/generate-remote`

모든 route는 기존 app bearer token을 요구합니다.

`POST /api/app/browser/smoke`는 browser를 즉시 실행하지 않고 browser smoke 실행 계획을 만듭니다. `BROWSER_READ`와 요청된 evidence capability(`BROWSER_SCREENSHOT`, `BROWSER_TRACE`, `BROWSER_RECORD`, `BROWSER_INTERACT`)를 검사하며, local host가 아닌 대상은 `BROWSER_EXTERNAL_DOMAIN`도 필요합니다.

video route도 renderer나 remote generation call을 즉시 실행하지 않고 계획만 반환합니다. 먼저 대응하는 `VIDEO_*` capability를 검사하고, 별도 승인된 runtime step이 실행할 수 있는 command와 함께 `DENIED`, `APPROVAL_REQUIRED`, `READY`를 반환합니다.
