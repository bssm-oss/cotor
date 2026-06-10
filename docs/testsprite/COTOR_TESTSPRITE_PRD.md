# Cotor TestSprite PRD

## Product Summary

Cotor is a local-first multi-agent workflow runner. A shared Kotlin core powers CLI/TUI commands, a localhost app-server, a browser-based pipeline editor, and a native macOS desktop shell. The current product model is company-first in the desktop layer: a Company owns goals, issues, review state, runtime state, agent definitions, memory, cost guardrails, and local evidence.

## Primary Users

- Local operator: runs `cotor` from a terminal, validates pipeline configs, and starts one-off or interactive agent workflows.
- Desktop operator: manages companies, goals, issues, review queues, reports, runtime controls, and TUI sessions through the native macOS shell.
- Maintainer: verifies CLI, app-server, desktop packaging, provider defaults, and policy/evidence behavior before release.

## Product Surfaces

1. CLI and interactive TUI
   - `cotor` with no args opens interactive mode.
   - `cotor tui` aliases interactive mode.
   - Commands include `init`, `run`, `validate`, `lint`, `test`, `web`, `app-server`, `company`, `auth`, `policy`, `provider`, `skill`, `mcp`, and `version`.

2. Local app-server
   - Base URL: `http://127.0.0.1:8787`.
   - `/health` and `/ready` are unauthenticated reachability probes.
   - `/api/app/**` routes require `Authorization: Bearer <COTOR_APP_TOKEN>`.
   - `/api/app/mcp` is read-only.
   - `/api/app/mcp/control` requires `COTOR_APP_CONTROL_TOKEN` and should not be part of the default TestSprite run.

3. Company workflow
   - A company is bound to one root folder.
   - A company owns goals, issues, agents, runtime state, activity, review queue, reports, memory snapshots, and problem signals.
   - Company runtime controls should affect that company only, not global app-server reachability.
   - Default automation mode is `AGENT_APPROVED`; `FULL_AUTO` still blocks hard-gated destructive actions.

4. Browser web editor
   - `cotor web --port 8080 --read-only` starts a browser-based pipeline editor suitable for limited frontend testing.
   - The native macOS desktop app is not a browser target.

5. Native macOS desktop
   - The desktop app is a shell over the local app-server.
   - Top-level modes are `Company` and `TUI`.
   - Desktop validation remains Swift build/tests plus manual smoke checks.

## Core Functional Requirements

### CLI and configuration

- `cotor version` prints the current version.
- `cotor help` and `cotor help --lang ko` render command help.
- `cotor init --starter-template` creates a safe echo-agent starter config.
- `cotor validate <file>` and `cotor lint <file>` validate pipeline/config files.
- `cotor web --read-only` starts the browser editor without allowing writes.
- `cotor app-server --port 8787 --token <token>` starts a local HTTP API.

### App-server auth and health

- `/health` and `/ready` respond without bearer auth.
- `/api/app/health` rejects missing/invalid bearer tokens.
- Authenticated `/api/app/health` returns a healthy app-server response.
- A non-loopback app-server host requires an explicit token.

### Company lifecycle

- A company can be created with a name, root path, optional default branch, automation mode, and optional daily/monthly budget cents.
- Company listing returns all stored companies without leaking unrelated local secrets.
- A company dashboard returns compact current state, issues, review queue, runtime, reports, and related projections.
- Company update can change name, base branch, autonomy, backend kind, and budget guardrails.
- Deleting a company is destructive and should not be included in default TestSprite runs.

### Agent, goal, and issue workflow

- Company agents can be listed, created, updated, enabled/disabled, and assigned optional model overrides.
- Goals can be created under a company with title, description, success metrics, and autonomy flag.
- Issues can be created under a goal with title, description, priority, and kind.
- Issues can be listed by company and optionally by goal.
- Issue execution details expose agent CLI, selected model, backend kind, process id, prompt, stdout/stderr, branch, PR link, and publish summary when available.
- Review queues can be listed by company.
- Review verdicts, merge, issue run, and runtime start/stop are mutable flows and should be reserved for sandbox runs only.

### TUI sessions

- A TUI session opens against a workspace and optional preferred agent.
- Session list, detail, delta, input, and terminate endpoints are separated.
- Terminating sessions is destructive and should not be part of default TestSprite runs.

### Evidence, policy, and MCP

- Evidence can be fetched for runs, files, and pull requests.
- Policy decisions can be queried for runs and issues.
- Read-only MCP tools expose company summary, issue list, durable run inspection, approval queue, evidence summary, verification bundle, memory snapshot, GitHub company events, and runtime projection.
- MCP control tools are disabled on the read-only surface.

## Non-Goals For Default TestSprite Runs

- Do not create or delete real GitHub repositories.
- Do not publish, merge, or close real pull requests.
- Do not delete companies, goals, issues, context entries, local worktrees, or user files.
- Do not run external marketing/browser publish actions.
- Do not upload local runtime state, logs, `.cotor/`, `.env`, token files, `local.properties`, or credentials.

## Test Data Strategy

- Use `/Users/Projects/bssm-oss/cotor-organization/cotor-test` for mutable company workflow tests.
- Use explicit disposable company names such as `TestSprite Sandbox <timestamp>`.
- Keep runtime stopped unless the test case is explicitly about runtime start/stop in the sandbox.
- Prefer read-only dashboard/list/health routes for the default baseline.

## Acceptance Criteria

- TestSprite can detect the Kotlin/Gradle backend, SwiftPM macOS package, and browser web editor.
- TestSprite backend tests distinguish unauthenticated health probes from token-protected `/api/app` routes.
- Generated API tests use bearer auth for `/api/app/**`.
- Generated tests avoid destructive routes unless sandbox instructions explicitly allow them.
- Generated plans reflect the current company-first product model and top-level `Company` / `TUI` desktop shell split.
- Reports identify whether failures are product defects, missing local preconditions, auth setup issues, or intentionally blocked destructive actions.
