# Desktop App

The desktop app is a native macOS shell on top of the existing Kotlin runtime and localhost `cotor app-server`.

## Install via Homebrew (Recommended)

```bash
brew tap bssm-oss/cotor https://github.com/bssm-oss/cotor.git
brew install cotor    # Installs CLI + bundled desktop asset + JDK 17
cotor install         # Copies Cotor Desktop.app into Applications
```

The Homebrew package carries a bundled `Cotor Desktop.app` asset. `cotor install`
and `cotor update` reuse that packaged bundle instead of rebuilding from the Homebrew prefix.
When `cotor` launches interactive mode with no local config in packaged installs, it writes the
starter config under `~/.cotor/interactive/default/cotor.yaml`.
See `docs/HOMEBREW_INSTALL.md` for the full packaged-install and first-run behavior.

Or one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/bssm-oss/cotor/master/shell/brew-install.sh | bash
```

## Install from Source

```bash
cotor install    # Build + install to /Applications
cotor update     # Rebuild + reinstall
cotor delete     # Remove app
```

## Components

- `cotor app-server`
  - localhost API for repositories, workspaces, tasks, goals, issues, review queue, and runtime state
- `macos/`
  - SwiftUI shell
- `src/main/kotlin/com/cotor/app/`
  - repository, workspace, task, goal, issue, review-queue, and runtime services

## Run The Backend

```bash
cotor app-server --port 8787
```

Optional local auth:

```bash
export COTOR_APP_TOKEN='your-local-token'
cotor app-server --port 8787 --token your-local-token
```

Optional MCP control auth:

```bash
export COTOR_APP_CONTROL_TOKEN='your-local-control-token'
cotor app-server --port 8787 --token your-local-token --control-token your-local-control-token
```

`/api/app/mcp` is read-only. Mutating MCP tools live under `/api/app/mcp/control` and require the control token.

## Run The macOS App

```bash
swift run --package-path macos CotorDesktopApp
```

Optional backend override:

```bash
export COTOR_APP_SERVER_URL='http://127.0.0.1:8787'
export COTOR_APP_TOKEN='your-local-token'
swift run --package-path macos CotorDesktopApp
```

When the bundled backend is launcher-managed, the launcher and `DesktopAPI` both read the same `COTOR_APP_TOKEN` value. If the variable is unset, both sides fall back to the desktop-local token used for embedded sessions. The packaged launcher passes this token through the backend environment and a `0600` runtime token file rather than placing it in the backend process arguments.
The embedded backend receives a minimal sanitized environment instead of the full parent shell environment, so incidental API keys, GitHub/Linear tokens, and password-like variables are not inherited by the local app-server. Run an external `cotor app-server` explicitly if a workflow must provide additional environment-scoped credentials.

## Install A Local App Bundle

```bash
cotor install
open "/Applications/Cotor Desktop.app" || open "$HOME/Applications/Cotor Desktop.app"
```

The bundle starts the local backend lazily when needed.
Closing the last desktop window quits the app and shuts down the bundled backend.

You can update or remove the installed bundle from the CLI:

```bash
cotor update
cotor delete
```

`cotor delete` removes the standard `/Applications`, `~/Applications`, and download artifacts. When `COTOR_DESKTOP_INSTALL_ROOT` is set, it also removes `Cotor Desktop.app` from that override install root.

Behavior depends on the install layout:

- Homebrew / packaged install
  - `cotor install` and `cotor update` copy the packaged desktop bundle from the install root
  - no Gradle or Swift rebuild happens at runtime
- Source checkout
  - `cotor install` and `cotor update` rebuild the desktop bundle locally, then install it

## Current Shell Model

The current macOS shell has two top-level modes.

- `Company`
  - company selector
  - company creation bound to one root folder
  - direct `Meeting Room` navigation that opens to a `Live Office` pixel-office runtime projection, with event-driven agent sprites, issue cards, A2A/message movement, review flow, and compact activity/review drawer details
  - agent-definition composer
  - compact mentor assignment in the agent editor and team cards, with new companies seeded with an HR Manager who can assign mentors and hire missing specialists
  - Marketing Operator skill selection that reveals a delegation-policy panel for allowed channels, domains, daily publish limits, brand rules, session/secret references, and recent marketing run logs
  - goal list and goal creation
  - Linear-style issue board/canvas inside the app
  - dedicated `Operator Chat` navigation surface with a message-thread interface for natural-language company commands; automation modes, approvals, and runtime actions are exposed through chat commands rather than persistent status/control panels
  - progressive disclosure across the company and issue surfaces: the first view shows only the current company signal and focused issue queue, while backend health, paths, cost guardrails, metadata, execution logs, Linear links, and agent conversation details stay behind expandable detail views
  - dedicated `Reports` surface for previous-day morning reports covering completed work, PR/review outcomes, blockers, recovery events, and estimated cost snapshots
  - dedicated `Performance` surface for derived per-agent execution scores, success rates, QA pass rates, retries, duration, and known estimated cost without storing separate evaluation history
  - company memory snapshot cards show company, project, team, and agent memory; `workflowMemory` remains in the backend contract for older clients
  - autonomous discovery scans internal quality signals before synthesizing CEO triage goals, and persisted problem signals are available through the app-server and CLI
  - CEO chat intake: a vague chat request can be confirmed into one CEO-owned goal, a clarified brief, and assigned downstream issues without creating a GitHub repository
- company activity feed with live event-driven updates
- live company updates use the company event stream plus a focused company dashboard snapshot, not a heavyweight full refresh on every event
- issue execution detail cards now show agent CLI, selected model, backend kind, process id, assigned prompt, stdout/stderr, branch, PR link, and publish summary for each issue-linked run
- async detail and memory snapshot refreshes ignore stale responses if the selected issue/task changes before the request completes
- if the live company stream disconnects, the UI keeps the last company snapshot and shows `Live company updates disconnected. Re-syncing...` while it recovers
  - compact company summary banner that keeps runtime health, CEO-handled PR approvals, blocked workflows, review attention, and the latest error/action in one place
  - compact company summary and company settings now surface estimated spend plus daily/monthly cost guardrails for the selected runtime
  - scrollable issue-board lanes so tall blocked/review queues stay readable inside the fixed board surface
  - stale Cotor-managed retry PRs are reconciled and closed in batches so the review loop does not keep piling up obsolete open PRs
  - stale CEO merge-conflict blocks are reopened automatically once the linked GitHub PR reports a clean merge state again
  - legacy CEO merge-conflict blockers that left execution stuck in `BLOCKED` are pushed back to `PLANNED` so the company can rebase and republish on the next wave
  - stale execution issues that were accidentally left blocked after a PR already merged are closed automatically on the next runtime tick
  - runtime start/stop/status
  - an explicit runtime stop remains sticky across app restarts and company refreshes until the user starts that company again
  - company mode uses a focused company dashboard snapshot instead of forcing a full desktop refresh on every event
- when one wave of goal work finishes, the CEO planning lane can reopen for the next wave instead of freezing the goal after the first decomposition
- continuous improvement goals now ask for multi-issue portfolios and parallel branchable work when the team can support it
- short high-level goal descriptions are enriched into a broader execution portfolio so larger teams do not collapse into only one or two issues
- runtime dispatch is no longer forced to wait for a stale polling tick before reacting to new runnable work, and multiple runnable issues can start in parallel even when several company roles share the same execution CLI
- local merge completion is only recorded after GitHub confirms the refreshed pull request state is actually `MERGED`
- `TUI`
  - independent from company workflow state
  - folder or repository selection for launching standalone `cotor` sessions
  - multiple live TUI sessions can stay open in parallel
  - dominant center terminal surface focused on the currently selected session

## Repository And Run Isolation

- each agent run gets its own branch named `codex/cotor/<task-slug>/<agent-name>`
- each agent run gets its own worktree under `.cotor/worktrees/<task-id>/<agent-name>`
- re-running the same task reuses the existing isolated worktree

## Current Company API Surface

Current company-first routes:

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

Compatibility routes under `/api/app/company/*` still exist for older clients.

## What Works Today

- create multiple companies
- bind each company to one working folder
- define company agents with minimal user input
- store an optional per-agent model override alongside the provider CLI so company roles can pin Codex/OpenCode models or app-managed local models discovered from Ollama/LM Studio explicitly. The desktop backend can start local Ollama on demand, prefers installed Gemma 4 models, and falls back to installed Gemma-family models when the default `gemma4:e2b` alias is unavailable.
- store an optional `mentorAgentId` per company agent; mentor choices are limited to active agents in the same company and clearable from the advanced assignment controls.
- seed every new company with an HR Manager role plus default mentor relationships across CEO, product, engineering, builder, QA, and release roles.
- show the built-in skill catalog in the company agent editor and save each agent's friendly skill selections into the `SKILL_RUN` capability allowlist.
- configure a Marketing Operator delegation policy from the agent editor; the policy opens browser and marketing publish capabilities only for allowed owned/social domains and channels, while out-of-policy actions are denied instead of routed to user approval.
- expose the repository map as a built-in company-agent choice when the local map tool is available, and inject lightweight workspace-map guidance into every company agent execution memory bundle
- create a company goal
- auto-decompose that goal into issues
- delegate and run issues
- inject A2A run bridge metadata and `COTOR_A2A_*` environment variables into issue-linked agent runs, then use bridge/context artifacts as canonical collaboration evidence
- block direct execution completion when collaboration evidence or verification evidence is missing, recording the reason in issue verification/runtime fields instead of treating it as a generic run failure
- scan internal quality signals into `CompanyProblemSignal` records and convert only actionable, deduped, cooldown-safe signals into CEO triage goals
- mirror company issues and progress to Linear when company-scoped Linear sync is enabled
- inspect linked tasks and runs
- inspect derived per-agent performance from existing issues, runs, reviews, org profiles, and company agent definitions, with insufficient-data agents called out separately
- populate and merge review queue items
- inspect a dedicated Meeting Room view that defaults to the `Live Office` runtime projection, with synthesized runtime/backend/review/session summaries, event-driven movement, and agent/issue/zone detail sheets
- use the Operator Chat surface to ask for status, bulk switch selected-company agents to OpenCode DeepSeek (`opencode-go/deepseek-v4-flash`), start/stop runtime, retry blocked issues, and re-sync GitHub/Linear state from one message-style command chat
- use Operator Chat for HR staffing requests such as hiring missing specialists or assigning mentors. HR hires use `opencode/nemotron-3-super-free`, avoid duplicate role coverage, and stay capped per chat command and runtime tick.
- turn a loose chat request into a CEO interpretation, success criteria, a company goal, and assigned issues while keeping GitHub connection/publishing as a separate explicit setup step
- choose `ASK_ME`, `AGENT_APPROVED`, or `FULL_AUTO` automation; `AGENT_APPROVED` is the default and routes recoverable sensitive actions to CEO/QA/Reviewer approval instead of a user confirmation rail
- keep hard-gated actions blocked in every mode, including repository deletion, bulk file deletion, secret operations, budget-cap removal, and deployment/merge policy unlocks
- inspect company activity without manual refresh in normal company mode
- inspect compact runtime status and focused recent issues first, then open advanced company or issue details for approval, blocked/review attention, runtime signals, and execution evidence
- inspect estimated spend and adjust daily/monthly cost guardrails without leaving the company console
- inspect deterministic morning reports generated from previous-day local runtime, activity, issue, run, and review data, including empty-day reports when there was no activity
- warn during company creation when GitHub PR publishing is required but the repository is not ready for `gh`/`origin` publishing
- surface a compact GitHub quick-connect panel in the company sidebar when PR mode is blocked by a missing `gh` CLI, `gh` auth, or `origin`
- connect an existing GitHub repository from the GitHub settings panel without auto-creating a remote repository when `origin` is missing
- start, stop, and inspect the local runtime loop
- keep an explicit company stop sticky until the user presses Start again, even if active autonomous goals still exist
- keep active company work on a fast monitoring cadence so stale `RUNNING` tasks/runs are reconciled sooner
- re-queue company issues that were interrupted by an app-server shutdown instead of leaving them blocked by a generic process-exit failure
- delegate PR creation policy approval pauses to the company's CEO/chief approval agent when one exists, then requeue publishing without requiring the user to approve the gate manually
- resume queued delegated company work after the desktop app and bundled backend come back, and record that recovery in the live company activity feed
- bind issue-linked durable runs through the issue pipeline id when needed, so `cotor resume inspect <run-id>` remains attached to the correct company issue run
- create durable run snapshots for company issue execution by default so the issue `durableRunId` can be inspected with `cotor resume inspect <run-id>`
- prefer locally installed agent CLIs for default company profiles, with `echo` as a final fallback

## Current Limits

- macOS shell only
- Linear sync is company-scoped and mirrors Cotor-managed issues outward; it does not yet import existing Linear issues back into Cotor
- runtime automation now includes a policy engine v1 for action allow/deny/approval decisions, but it is still file-backed and experimental
- review and PR sync now include a GitHub control-plane v1 with PR state, mergeability, and status-check summary syncing through `gh`
- company issue execution is inspectable through durable run snapshots by default; generic pipeline replay with `resume continue/fork/approve` and full company issue/review continuation are still incomplete
