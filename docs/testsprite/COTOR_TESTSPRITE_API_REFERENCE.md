# Cotor TestSprite API Reference

## Base URL And Auth

- Base URL: `http://127.0.0.1:8787`
- Unauthenticated probes: `GET /health`, `GET /ready`
- Authenticated routes: `GET|POST|PATCH|DELETE /api/app/**`
- Header for authenticated routes: `Authorization: Bearer <COTOR_APP_TOKEN>`
- Read-only MCP route: `POST /api/app/mcp`
- Control MCP route: `POST /api/app/mcp/control` with `COTOR_APP_CONTROL_TOKEN`

Start command:

```bash
export COTOR_APP_TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
./gradlew run --args="app-server --port 8787 --token $COTOR_APP_TOKEN"
```

If the app-server generated a token itself, it is stored at:

```text
$HOME/Library/Application Support/CotorDesktop/runtime/backend/app-server.token
```

Do not upload the token file to TestSprite.

## Safe Baseline Endpoints

These endpoints are safe for default TestSprite probing.

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| GET | `/health` | none | app-server liveness |
| GET | `/ready` | none | app-server readiness |
| GET | `/api/app/health` | bearer | authenticated health |
| GET | `/api/app/metrics` | bearer | lightweight ops metrics |
| GET | `/api/app/settings` | bearer | redacted desktop settings |
| GET | `/api/app/settings/backends` | bearer | backend status |
| GET | `/api/app/help-guide?lang=en` | bearer | embedded command guide |
| GET | `/api/app/capabilities/catalog` | bearer | capability catalog |
| GET | `/api/app/providers` | bearer | provider catalog |
| GET | `/api/app/skills` | bearer | skill catalog |
| GET | `/api/app/direct-chat/providers` | bearer | direct chat provider catalog |
| GET | `/api/app/companies` | bearer | company list |
| GET | `/api/app/runtime/cleanup/preview` | bearer | dry-run cleanup preview |

## Company Endpoints

Create a sandbox company only under `/Users/Projects/bssm-oss/cotor-organization/cotor-test`.

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

Common read endpoints:

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

Mutable sandbox-only endpoints:

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

Do not include these in default TestSprite runs:

| Method | Path | Reason |
| --- | --- | --- |
| DELETE | `/api/app/companies/{companyId}` | deletes company state |
| DELETE | `/api/app/companies/{companyId}/goals/{goalId}` | deletes goal |
| DELETE | `/api/app/companies/{companyId}/issues/{issueId}` | deletes issue |
| POST | `/api/app/companies/{companyId}/runtime/start` | starts autonomous work |
| POST | `/api/app/companies/{companyId}/runtime/stop` | changes runtime state |
| POST | `/api/app/review-queue/{itemId}/merge` | may merge code |
| POST | `/api/app/review-queue/{itemId}/qa` | changes review state |
| POST | `/api/app/review-queue/{itemId}/ceo` | changes review state |
| POST | `/api/app/runtime/cleanup` with `apply=true` | deletes worktrees/processes |
| POST | `/api/app/shutdown` | stops app-server |

## Example Mutable Flow For A Sandbox

1. Create company.
2. Create a goal:

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

3. Create an issue:

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

4. Verify:
   - `GET /api/app/companies/{companyId}/dashboard`
   - `GET /api/app/companies/{companyId}/goals`
   - `GET /api/app/companies/{companyId}/issues`

Do not start runtime or delete the records in the default automated suite.

## Repository, Workspace, Task, And TUI Routes

Read/list routes:

- `GET /api/app/repositories`
- `GET /api/app/repositories/{repositoryId}/branches`
- `GET /api/app/workspaces?repositoryId={repositoryId}`
- `GET /api/app/tasks?workspaceId={workspaceId}`
- `GET /api/app/runs?taskId={taskId}`
- `GET /api/app/tui/sessions`

Mutable routes require explicit sandbox instruction:

- `POST /api/app/repositories/open`
- `POST /api/app/workspaces`
- `POST /api/app/tasks`
- `POST /api/app/tasks/{taskId}/run`
- `POST /api/app/tui/sessions`
- `POST /api/app/tui/sessions/{sessionId}/input`
- `POST /api/app/tui/sessions/{sessionId}/terminate`

## Evidence, Verification, GitHub, Knowledge

Read routes:

- `GET /api/app/evidence/runs/{runId}`
- `GET /api/app/evidence/files?path={absolutePath}`
- `GET /api/app/evidence/pull-requests/{pullRequestNumber}`
- `GET /api/app/verification/issues/{issueId}`
- `GET /api/app/github/pull-requests?companyId={companyId}`
- `GET /api/app/github/events?companyId={companyId}`
- `GET /api/app/knowledge/issues/{issueId}`
- `GET /api/app/runtime/issues/{issueId}/projection`

GitHub sync and PR mutation flows should be excluded from default TestSprite runs unless the repository and PR are disposable.

## Browser Web Editor

Frontend target:

```bash
./gradlew run --args="web --port 8080 --read-only"
```

Base URL:

```text
http://127.0.0.1:8080
```

Recommended scope:

- Home page renders.
- Template list can be browsed.
- YAML preview works.
- Read-only mode blocks writes.

## Expected Error Cases

- Missing bearer token on `/api/app/**` should return an auth error.
- Invalid company, goal, issue, repository, workspace, run, or session ids should return 400 or 404.
- Remote/non-loopback app-server URLs should be blocked unless explicitly configured with token.
- Control MCP calls should fail through `/api/app/mcp`.
- Destructive actions may be blocked by policy, missing sandbox preconditions, or missing control token.
