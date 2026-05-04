# Agent Capabilities

Cotor stores an explicit capability profile for each company agent and checks that profile in the backend action layer. The desktop UI and CLI can expose toggles, but the source of enforcement is `ActionExecutionService` through `AgentCapabilityGuard`.

## Modes

- `DISABLED`: the action is denied.
- `READ_ONLY`: only read-style actions are allowed.
- `PROPOSE_ONLY`: the action can be proposed, but execution pauses for approval.
- `APPROVAL_REQUIRED`: execution pauses for approval before the action runs.
- `AUTO`: the action can run automatically.

## Safe Defaults

Dangerous actions are not automatic by default:

- `GITHUB_MERGE_EXECUTE`, `MCP_CONTROL`, browser interaction, remote video/image generation, upload, and deploy execution default to `DISABLED`.
- file writes, shell execution, package install, git writes, PR creation/update, external API calls, memory writes, graph writes, and security scans default to `APPROVAL_REQUIRED`.
- local tests, lint, builds, and git reads default to `AUTO` where appropriate.
- memory reads, graph reads, file reads, shell reads, and GitHub reads default to read-only modes.

New company rosters also receive a repository-scoped execution profile. That profile lets built-in company agents run the local agent CLI and create isolated git worktrees automatically only under the company's repository root. Publishing, PR updates, merges, browser control, package installs, external API calls, and other higher-risk actions keep the stricter catalog defaults unless an operator changes the profile.

## Backend Enforcement

The guard maps runtime action kinds to capability keys before the action block runs:

- `agent.exec` and unsafe shell commands -> `SHELL_EXEC`
- `skill.run` -> `SKILL_RUN`; if `skillAllowlist` is set, the action must carry a matching `skill` metadata value
- `browser.read`, `browser.interact`, `browser.screenshot`, `browser.trace`, `browser.record`, `browser.external-domain`, and `browser.login-flow` -> matching `BROWSER_*` keys
- `video.script-write`, `video.render-local`, `video.generate-remote`, `video.transcode`, and `video.upload` -> matching `VIDEO_*` keys
- package manager installs -> `PACKAGE_INSTALL`
- test/lint/build commands -> `TEST_RUN`, `LINT_RUN`, `BUILD_RUN`
- `git.worktree` -> `GIT_WRITE`
- `git.publish` -> `GITHUB_PR_CREATE`
- GitHub review/comment -> `GITHUB_PR_UPDATE`
- GitHub merge -> `GITHUB_MERGE_EXECUTE`
- HTTP calls -> `EXTERNAL_API_CALL`
- file writes -> `FILE_WRITE`

If a company/agent context is missing, the capability guard does not claim authority over the action and existing policy/risk interceptors still apply.

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

Capability settings can include provider/model hints, path/domain/skill allowlists, secret reference names, evidence/review requirements, and notes. Store secret reference names only; do not store secret values.

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

All routes require the normal app bearer token.

`POST /api/app/browser/smoke` plans a browser smoke run rather than launching a browser directly. It checks `BROWSER_READ` and any requested evidence capabilities such as `BROWSER_SCREENSHOT`, `BROWSER_TRACE`, `BROWSER_RECORD`, or `BROWSER_INTERACT`; non-local hosts also require `BROWSER_EXTERNAL_DOMAIN`.

The video routes also return plans instead of running renderers or remote generation calls. They check the matching `VIDEO_*` capability first and return `DENIED`, `APPROVAL_REQUIRED`, or `READY` with the command that a separate approved runtime step can execute.
