# Cotor TestSprite API Reference

## Base URL과 인증

- Base URL: `http://127.0.0.1:8787`
- 인증 없는 probe: `GET /health`, `GET /ready`
- 인증 route: `GET|POST|PATCH|DELETE /api/app/**`
- 인증 header: `Authorization: Bearer <COTOR_APP_TOKEN>`
- Read-only MCP route: `POST /api/app/mcp`
- Control MCP route: `POST /api/app/mcp/control` with `COTOR_APP_CONTROL_TOKEN`

시작 명령:

```bash
export COTOR_APP_TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
./gradlew run --args="app-server --port 8787 --token $COTOR_APP_TOKEN"
```

app-server가 token을 직접 생성했다면 아래에 저장됩니다.

```text
$HOME/Library/Application Support/CotorDesktop/runtime/backend/app-server.token
```

이 token 파일은 TestSprite에 업로드하지 않습니다.

## 안전한 기본 Endpoint

아래 endpoint는 기본 TestSprite probing에 안전합니다.

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | none | app-server liveness |
| GET | `/ready` | none | app-server readiness |
| GET | `/api/app/health` | bearer | authenticated health |
| GET | `/api/app/metrics` | bearer | lightweight ops metrics |
| GET | `/api/app/settings` | bearer | redacted desktop settings |
| GET | `/api/app/settings/backends` | bearer | backend status |
| GET | `/api/app/help-guide?lang=ko` | bearer | embedded command guide |
| GET | `/api/app/capabilities/catalog` | bearer | capability catalog |
| GET | `/api/app/providers` | bearer | provider catalog |
| GET | `/api/app/skills` | bearer | skill catalog |
| GET | `/api/app/direct-chat/providers` | bearer | direct chat provider catalog |
| GET | `/api/app/companies` | bearer | company list |
| GET | `/api/app/runtime/cleanup/preview` | bearer | dry-run cleanup preview |

## Company Endpoint

Sandbox company는 `/Users/Projects/bssm-oss/cotor-organization/cotor-test` 아래에서만 생성합니다.

```http
POST /api/app/companies
Authorization: Bearer <COTOR_APP_TOKEN>
Content-Type: application/json

{
  "name": "TestSprite Sandbox",
  "rootPath": "/Users/Projects/bssm-oss/cotor-organization/cotor-test",
  "defaultBaseBranch": "main",
  "autonomyEnabled": false,
  "operatorAutomationMode": "AGENT_APPROVED",
  "dailyBudgetCents": 0,
  "monthlyBudgetCents": 0
}
```

주요 읽기 endpoint:

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/api/app/companies/{companyId}` | company detail |
| GET | `/api/app/companies/{companyId}/dashboard` | focused company dashboard |
| GET | `/api/app/companies/{companyId}/agents` | agent definitions |
| GET | `/api/app/companies/{companyId}/agents/performance` | derived agent performance |
| GET | `/api/app/companies/{companyId}/projects` | project contexts |
| GET | `/api/app/companies/{companyId}/goals` | company goals |
| GET | `/api/app/companies/{companyId}/issues` | company issues |
| GET | `/api/app/companies/{companyId}/review-queue` | review queue |
| GET | `/api/app/companies/{companyId}/activity` | activity feed |
| GET | `/api/app/companies/{companyId}/reports` | report summaries |
| GET | `/api/app/companies/{companyId}/memory-snapshot` | memory layers |
| GET | `/api/app/companies/{companyId}/problem-signals` | autonomous discovery signals |
| GET | `/api/app/companies/{companyId}/runtime` | company runtime status |
| GET | `/api/app/companies/{companyId}/backend` | backend status |
| GET | `/api/app/companies/{companyId}/github/status` | GitHub readiness |
| GET | `/api/app/companies/{companyId}/execution-log` | execution log |
| GET | `/api/app/companies/{companyId}/issue-graph` | issue graph projection |
| GET | `/api/app/companies/{companyId}/budget` | budget usage |

Sandbox 전용 mutable endpoint:

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/api/app/companies/{companyId}/agents` | create agent definition |
| PATCH | `/api/app/companies/{companyId}/agents/{agentId}` | update agent definition |
| POST | `/api/app/companies/{companyId}/goals` | create goal |
| PATCH | `/api/app/companies/{companyId}/goals/{goalId}` | update goal |
| POST | `/api/app/companies/{companyId}/issues` | create issue |
| PATCH | `/api/app/issues/{issueId}/assignee` | update assignee |
| POST | `/api/app/companies/{companyId}/chat-intake` | create goal/issues from chat |
| POST | `/api/app/companies/{companyId}/operator/chat` | operator chat |
| POST | `/api/app/companies/{companyId}/autonomy/discovery-scan` | run discovery scan |

기본 TestSprite 실행에서 제외할 endpoint:

| Method | Path | Reason |
| --- | --- | --- |
| DELETE | `/api/app/companies/{companyId}` | company state 삭제 |
| DELETE | `/api/app/companies/{companyId}/goals/{goalId}` | goal 삭제 |
| DELETE | `/api/app/companies/{companyId}/issues/{issueId}` | issue 삭제 |
| POST | `/api/app/companies/{companyId}/runtime/start` | autonomous work 시작 |
| POST | `/api/app/companies/{companyId}/runtime/stop` | runtime state 변경 |
| POST | `/api/app/review-queue/{itemId}/merge` | code merge 가능 |
| POST | `/api/app/review-queue/{itemId}/qa` | review state 변경 |
| POST | `/api/app/review-queue/{itemId}/ceo` | review state 변경 |
| POST | `/api/app/runtime/cleanup` with `apply=true` | worktree/process 삭제 |
| POST | `/api/app/shutdown` | app-server 중지 |

## Sandbox Mutable Flow 예시

1. Company를 생성합니다.
2. Goal을 생성합니다.

```http
POST /api/app/companies/{companyId}/goals
Authorization: Bearer <COTOR_APP_TOKEN>
Content-Type: application/json

{
  "title": "Verify TestSprite sandbox",
  "description": "Exercise safe company CRUD without starting runtime.",
  "successMetrics": ["Company dashboard reflects created goal"],
  "autonomyEnabled": false
}
```

3. Issue를 생성합니다.

```http
POST /api/app/companies/{companyId}/issues
Authorization: Bearer <COTOR_APP_TOKEN>
Content-Type: application/json

{
  "goalId": "<goalId>",
  "title": "Read-only dashboard validation",
  "description": "Confirm issue appears in the company issue list.",
  "priority": 3,
  "kind": "testsprite"
}
```

4. 아래 endpoint로 확인합니다.
   - `GET /api/app/companies/{companyId}/dashboard`
   - `GET /api/app/companies/{companyId}/goals`
   - `GET /api/app/companies/{companyId}/issues`

기본 automated suite에서는 runtime을 시작하거나 record를 삭제하지 않습니다.

## Repository, Workspace, Task, TUI Route

읽기/list route:

- `GET /api/app/repositories`
- `GET /api/app/repositories/{repositoryId}/branches`
- `GET /api/app/workspaces?repositoryId={repositoryId}`
- `GET /api/app/tasks?workspaceId={workspaceId}`
- `GET /api/app/runs?taskId={taskId}`
- `GET /api/app/tui/sessions`

Mutable route는 명시적인 sandbox 지시가 있을 때만 사용합니다.

- `POST /api/app/repositories/open`
- `POST /api/app/workspaces`
- `POST /api/app/tasks`
- `POST /api/app/tasks/{taskId}/run`
- `POST /api/app/tui/sessions`
- `POST /api/app/tui/sessions/{sessionId}/input`
- `POST /api/app/tui/sessions/{sessionId}/terminate`

## Evidence, Verification, GitHub, Knowledge

읽기 route:

- `GET /api/app/evidence/runs/{runId}`
- `GET /api/app/evidence/files?path={absolutePath}`
- `GET /api/app/evidence/pull-requests/{pullRequestNumber}`
- `GET /api/app/verification/issues/{issueId}`
- `GET /api/app/github/pull-requests?companyId={companyId}`
- `GET /api/app/github/events?companyId={companyId}`
- `GET /api/app/knowledge/issues/{issueId}`
- `GET /api/app/runtime/issues/{issueId}/projection`

GitHub sync와 PR mutation flow는 repository와 PR이 disposable일 때만 TestSprite 범위에 포함합니다.

## 브라우저 웹 편집기

Frontend 대상:

```bash
./gradlew run --args="web --port 8080 --read-only"
```

Base URL:

```text
http://127.0.0.1:8080
```

권장 범위:

- Home page 렌더링.
- Template list browsing.
- YAML preview.
- Read-only mode write blocking.

## 예상 오류 케이스

- `/api/app/**`에 bearer token이 없으면 auth error가 나야 합니다.
- 존재하지 않는 company, goal, issue, repository, workspace, run, session id는 400 또는 404를 반환해야 합니다.
- Remote/non-loopback app-server URL은 token으로 명시 설정하지 않는 한 차단되어야 합니다.
- Control MCP 호출은 `/api/app/mcp`에서 실패해야 합니다.
- Destructive action은 policy, sandbox precondition 누락, control token 누락으로 차단될 수 있습니다.
