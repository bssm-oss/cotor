# Cotor

Cotor is a local-first AI workflow runner that grew into a company-style AI operating system: a CEO AI delegates work to subordinate AIs, CLI agents keep costs down, workflows stay visible in macOS, and a goal can drive an always-on issue loop. The same Kotlin core powers pipeline execution, the localhost `app-server`, and the native desktop shell.
Smoke test: `cotor version`

## What Is Current In This Build

- CLI/TUI orchestration with `SEQUENTIAL`, `PARALLEL`, and `DAG` pipelines
- Validation, linting, status, statistics, checkpoints, and template generation
- Local web editor with YAML export and run support
- macOS desktop shell backed by `cotor app-server`
- Native desktop Test Center for local validation plans, run status, and step logs inside the selected company
- Multi-company operations layer with companies, agent definitions, goals, issues, review queue, activity feed, and runtime start/stop/status
- Built-in HR Manager role that can conservatively add missing specialists and assign a mentor for each company agent
- Estimated AI spend tracking per company with configurable daily and monthly cost guardrails
- Per-agent git branch and worktree isolation for delegated execution
- Runtime hardening for command validation, durable replay side-effect approval, and desktop/backend token consistency

## Current Command Surface

Top-level commands registered in `Main.kt`:

`init`, `run`, `dash`, `interactive`, `validate`, `test`, `template`, `resume`, `checkpoint`, `stats`, `doctor`, `status`, `list`, `web`, `app-server`, `lint`, `explain`, `plugin`, `agent`, `company`, `auth`, `policy`, `evidence`, `github`, `knowledge`, `mcp`, `version`, `completion`

Important entry behavior:

- `cotor` with no args launches `interactive`
- `cotor tui` is an alias to `interactive`
- `interactive` defaults to a single preferred agent chat; use `--mode auto|compare` or `:mode ...` to fan out to multiple agents
- `cotor help ai` prints a prose usage guide for operators
- `cotor help web` launches a web help page with the command collection and quick-start guidance
- interactive transcripts live under `.cotor/interactive/...`, and each session now writes `interactive.log` beside the transcript files
- `cotor init --starter-template` generates a safe local `example-agent` Echo scaffold so validate/run succeeds before any AI CLI is authenticated
- packaged first-run interactive writes its auto-generated starter config under `~/.cotor/interactive/default/cotor.yaml` when no local config exists
- packaged first-run interactive only auto-selects AI starters that are actually ready to answer immediately; otherwise it falls back to the safe `example-agent` echo starter instead of failing on an unauthenticated CLI
- unknown first args fall back to direct pipeline execution

Current subcommand support:

- `agent add`, `agent list`
- `auth codex-oauth login|status|logout`
- `company ...` for company/agent/goal/issue/review/runtime/backend/linear/context/message/autonomy operations, including `company autonomy scan <company-id>` and `company problem-signals <company-id>`
- `plugin init`
- `checkpoint gc`
- `policy validate`, `policy simulate`
- `capability list`, `capability inspect`, `capability simulate`
- `provider list`, `provider scan`, `provider test`
- `skill list`, `skill inspect`, `skill validate`, `skill run`
- `browser smoke` for backend-gated browser smoke planning
- `video plan`, `video render`, `video transcode`, `video generate-remote` for backend-gated video work planning
- `evidence run`, `evidence file`, `evidence pr`
- `github sync`, `github inspect-pr`, `github list`, `github events`
- `knowledge inspect`
- `verification inspect`
- `runtime inspect`
- `mcp serve --readonly`
- app-server MCP read/control split: `/api/app/mcp` is read-only, `/api/app/mcp/control` requires `COTOR_APP_CONTROL_TOKEN`

Current template types:

- `compare`
- `chain`
- `review`
- `consensus`
- `fanout`
- `selfheal`
- `verified`
- `blocked-escalation`
- `custom`

## Codebase Entrypoints

Start from these files when reading or changing the project:

- CLI bootstrap: `src/main/kotlin/com/cotor/Main.kt`
- CLI commands: `src/main/kotlin/com/cotor/presentation/cli/`
- generic pipeline runtime: `src/main/kotlin/com/cotor/domain/orchestrator/`, `src/main/kotlin/com/cotor/domain/executor/`, `src/main/kotlin/com/cotor/domain/planning/`
- local app-server routes: `src/main/kotlin/com/cotor/app/AppServer.kt`
- local Test Center runner: `src/main/kotlin/com/cotor/app/CotorTestCenterService.kt`
- company workflow service: `src/main/kotlin/com/cotor/app/DesktopAppService.kt`
- desktop API DTOs and state models: `src/main/kotlin/com/cotor/app/DesktopModels.kt`, `macos/Sources/CotorDesktopApp/Models.swift`
- macOS desktop shell: `macos/Sources/CotorDesktopApp/DesktopStore.swift`, `macos/Sources/CotorDesktopApp/ContentView.swift`, `macos/Sources/CotorDesktopApp/DesktopAPI.swift`
- runtime control/evidence: `src/main/kotlin/com/cotor/runtime/`, `src/main/kotlin/com/cotor/policy/`, `src/main/kotlin/com/cotor/provenance/`, `src/main/kotlin/com/cotor/knowledge/`
- provider and tool adapters: `src/main/kotlin/com/cotor/data/plugin/`, `src/main/kotlin/com/cotor/data/process/`, `src/main/kotlin/com/cotor/providers/`

For module boundaries, public entrypoints, and allowed dependency directions, see [docs/modules/README.md](docs/modules/README.md).

## Install

### Homebrew (Recommended)

```bash
brew tap bssm-oss/cotor https://github.com/bssm-oss/cotor.git
brew install bssm-oss/cotor/cotor
```

This installs JDK 17 + the CLI and packages a bundled desktop app asset.
Run `cotor install` after `brew install` to copy `Cotor Desktop.app` into Applications.
`cotor install` / `cotor update` reuse the packaged app instead of rebuilding from the Homebrew prefix.
`cotor install` prints the exact installed app path and falls back to `~/Applications` when `/Applications` is not writable.

Update:

```bash
cotor update --verify
# or: cotor upgrade --verify
```

For packaged installs, `cotor update --verify` upgrades the Homebrew formula,
copies the bundled desktop app into Applications, verifies codesign, launches
the installed app, and checks `/health`.

### Direct DMG Download

Download the latest DMG from [GitHub Releases](https://github.com/bssm-oss/cotor/releases/latest):

1. Download `Cotor-<version>.dmg`
2. Open the DMG file
3. Drag `Cotor Desktop.app` to `/Applications`

### From Source

```bash
git clone https://github.com/bssm-oss/cotor.git
cd cotor
./shell/cotor version   # JDK 17 auto-detected, shadowJar auto-built
```

## Quick Start

```bash
cotor version
cotor help
cotor help --lang ko
cotor init --starter-template
cotor install
cotor app-server --port 8787
open "/Applications/Cotor Desktop.app"
```

Experimental durable runtime:

```bash
export COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1
cotor run <pipeline> -c cotor.yaml
cotor resume inspect <run-id>
cotor resume continue <run-id> --config cotor.yaml
cotor resume fork <run-id> --from <checkpoint-id> --config cotor.yaml
cotor resume approve <run-id> --checkpoint <checkpoint-id>
```

Durable replay records side-effect kinds such as file writes and secret reads precisely. Any replay-unsafe side effect now pauses `continue` / `fork` until the run is explicitly approved.

## macOS Desktop

After `brew install cotor`, install the packaged desktop app with:

```bash
cotor install    # Install bundled app from Homebrew package
cotor update --verify
cotor upgrade --verify
cotor delete     # Remove app
```

If no local `cotor.yaml` exists, the first packaged `cotor` run writes a starter config under
`~/.cotor/interactive/default/cotor.yaml`. If no authenticated AI CLI or API key is ready yet,
that starter intentionally falls back to `example-agent` echo mode instead of failing immediately.
If you run `cotor` inside a repo that already contains `./cotor.yaml`, that local config still wins.

From a source checkout, the same commands still rebuild the desktop app locally before installing it.
The Settings screen shows the current backend owner, build, source commit when
available, health, installed app path, and whether Homebrew reports an update.

Current desktop model:

- top-level `Company` and `TUI` shell modes
- `Company` mode for multi-company operations, agent team, goals, issue board/canvas, activity feed, runtime controls, and a dedicated `Meeting Room` surface
- dedicated `Operator Chat` navigation surface that sends selected-company messages through an LLM-first operator planner; the planner prefers local Ollama Gemma when available, interprets loose natural language, chooses validated company tools, and then answers from the actual tool results instead of keyword-matching canned status text
- `Company` summary keeps only the immediate company signal and recent issues visible by default; team work, live runs, CEO decisions, Linear state, and activity history sit behind an expandable detail section
- `Company` and issue surfaces use progressive disclosure so paths, backend health, cost guardrails, metadata, execution logs, and agent conversation details appear only after opening deeper detail views
- dedicated `Reports` navigation surface shows deterministic previous-day morning reports with completed work, PR/review outcomes, blockers, recovery events, and estimated cost snapshots
- dedicated `Performance` navigation surface shows derived per-agent scores, success rates, QA pass rates, retries, duration, and known estimated cost from existing company execution data
- company memory snapshots now separate company, project, team, and agent memory; the older workflow memory field remains as a compatibility alias for project + team context
- autonomous runtime discovery scans internal quality signals before creating new work, so idle loops produce observable `idle-no-discovered-problems` or `discovery-triage-created` states instead of random continuous prompts
- `Company` mode now uses event-driven live updates as the primary path, so activity, issues, review state, and runtime status update without a manual refresh in normal operation; malformed NDJSON event lines are logged and skipped without killing the stream
- desktop backend launch, health checks, shutdown, and client requests use the same `COTOR_APP_TOKEN` source so token-protected local sessions stay aligned
- embedded desktop backends start with a sanitized environment so incidental API keys, provider tokens, and password-like parent-shell variables are not passed into the local app-server
- `Meeting Room` opens to a `Live Office` pixel-office projection by default, using runtime data for agent state, issue cards, A2A messages, review flow, and activity; the activity/review detail surfaces stay behind a compact drawer
- company issue execution details now surface agent CLI, selected model, backend kind, process id, assigned prompt, stdout/stderr, branch, PR link, and publish summary instead of only change metadata
- `cotor company issue run <issue-id>` waits for a settled issue state by default so local CLI-launched agent work is not orphaned; use `--async` only when an already-running app-server should own the background work
- company runtime now wakes immediately on issue/task/review transitions and can dispatch multiple runnable issues in parallel even when different roles share the same execution CLI
- CEO merge only marks local workflow state as merged after GitHub refresh confirms the PR is actually `MERGED`
- company CEO/chief approval agents can satisfy PR creation policy gates internally, so publish retries do not stop on a user-facing approval prompt when the company has an approval authority
- Company Operator supports `ASK_ME`, `AGENT_APPROVED`, and `FULL_AUTO`; `AGENT_APPROVED` is the default, while `FULL_AUTO` still blocks hard-gated actions such as repository deletion, bulk file deletion, secret operations, budget-cap removal, and deployment/merge policy unlocks
- company agent definitions now support an optional per-agent model override for providers like Codex, OpenCode, Ollama, LM Studio, and app-managed local Gemma models; Cotor prefers installed Gemma 4 models and falls back to installed Gemma-family models instead of failing on a missing default alias
- company agent definitions also store an optional mentor, shown as one compact team-card line and editable from the advanced assignment controls
- selecting the Marketing Operator skill on a company agent exposes a delegation-policy panel for owned/social channels, allowed domains, publish limits, brand rules, and session/secret references
- stale Cotor-managed retry PRs are reconciled and closed in batches so repeated review loops do not keep hundreds of obsolete open PRs around
- legacy CEO merge-conflict blockers are pushed back into execution so the company can rebase, republish, and continue instead of staying stuck in a blocked approval lane
- if the live company stream drops, the desktop shell keeps the current company snapshot on screen and shows a company-specific re-sync message instead of a generic decode error
- the issue board keeps each lane scrollable inside a fixed board surface so long blocked/review lanes stay readable instead of clipping at the top
- stale merge-conflict blocks are re-opened automatically when the linked GitHub PR becomes clean again, so resolved rebases flow back into the CEO lane without a manual reset
- stale execution issues that were accidentally left `BLOCKED` after the linked PR already merged are normalized back to `DONE` on the next runtime tick
- `TUI` mode for standalone folder-backed `cotor` terminals, with multiple live sessions in parallel
- top session strip for active execution contexts
- collapsible detail drawer for changes, files, ports, browser, and review metadata
- a built-in desktop help sheet that surfaces the command collection and quick usage guidance inside the app

## Autonomous Company Status

The current build includes a working local operations layer:

- create multiple companies, each bound to one working folder
- surface a GitHub readiness warning during company creation when GitHub PR mode is enabled but `gh` auth/origin setup is missing; Cotor does not create GitHub repositories automatically when no origin exists
- connect an existing GitHub repository from the desktop app by signing in with `gh` and saving the repository URL as `origin`
- define company agents with only title, CLI, and role summary
- optionally pin a provider model per company agent definition, including local `gemma4`, `ollama`, and `lmstudio` agents. The desktop backend can start local Ollama on demand, prefers installed Gemma 4 models, and falls back to installed Gemma-family models when the default `gemma4:12b` alias is not present.
- seed new companies with an HR Manager plus mentor relationships, and let Operator Chat handle requests such as team staffing or mentor assignment without adding another always-visible control panel
- use the built-in repository map agent from the same team, while every company agent receives lightweight workspace-map guidance in its execution memory
- delegate Marketing Operator browser publishing only through a prior policy; out-of-policy owned/social actions are denied rather than sent to a user approval queue
- create company goals
- decompose goals into issues
- delegate and run issues
- open A2A bridge metadata for issue-linked agent runs, inject `COTOR_A2A_*` environment variables, and require bridge/context evidence before direct execution completion can become `DONE`
- run internal discovery scans that persist `CompanyProblemSignal` records for repeated failures, stale blocked work, review failures, verification gaps, runtime errors, stale follow-ups, and repository-graph warnings
- inspect completed company issue runs through `cotor resume inspect <run-id>` without enabling the experimental pipeline replay flag
- inspect per-agent performance derived from existing company issues, runs, reviews, org profiles, and agent definitions, with insufficient-data agents shown separately
- populate and merge ready review queue items
- inspect the dedicated Meeting Room page as a `Live Office` runtime projection with event-driven agent sprites, issue movement, review flow, runtime/backend/review/session summaries, and click-through agent/issue/zone detail sheets
- use the Operator Chat surface to ask for status, change selected-company agents to the local Ollama Gemma 4 12B default (`gemma4:12b` or OpenCode's `ollama/gemma4:12b` bridge), explicitly choose DeepSeek only when requested, start/stop runtime, retry blocked issues, and re-sync GitHub/Linear state from one command chat
- ask the HR Manager through Operator Chat to hire missing specialists or assign mentors; HR hires inherit the company execution model policy, avoid duplicate roles, and cap automatic hiring so teams do not grow without bounds
- let the CEO clarify a loose chat request into a goal, success criteria, and assigned downstream issues without auto-creating GitHub repositories
- route sensitive recoverable actions to senior company agents in `AGENT_APPROVED` mode instead of requiring a user-facing confirmation panel
- inspect compact runtime status and recent issues from the company summary page, then open advanced details only when needed
- inspect estimated company spend and adjust daily/monthly runtime guardrails from deeper company settings instead of the default summary
- inspect stored morning reports for the previous local day; reports are generated from local runtime, activity, issue, run, and review data rather than LLM-generated prose
- start and stop a local autonomous runtime loop per company
- preview runtime artifact cleanup with `cotor company runtime cleanup --company-id <id> --dry-run` or `--all-companies --dry-run`; actual pruning requires `--apply` and protects active/open/review/PR-linked worktrees
- let the CEO reopen planning after one wave finishes so active goals can generate the next wave instead of freezing after the first batch of issues
- bias autonomous continuous-improvement goals toward multi-issue portfolios and parallel branchable slices instead of a single narrow follow-up
- enrich short high-level goal descriptions into a broader execution portfolio so larger teams do not collapse into only one or two issues
- keep concrete user-entered file/PR goals as one execution issue, so direct installed-app requests do not wait for CEO provider planning or split into unrelated issue fragments
- keep an explicit company stop sticky across app restarts, dashboard reads, and live reconnects until the user presses Start again
- keep the company runtime in a fast monitoring cadence while active tasks/runs still exist, so dead or stale `RUNNING` runs reconcile sooner instead of looking idle for a long backoff window
- when the app-server shuts down during active company work, current builds re-queue interrupted issues instead of leaving them permanently blocked by a generic process-exit failure
- when the desktop app comes back after that shutdown, a running company runtime resumes queued delegated work and the company activity feed reflects the recovery without a full manual refresh

Current limits in this build:

- the app uses a Linear-style board inside Cotor; it is not a live external Linear sync
- runtime automation is intentionally minimal
- policy engine is v1 and currently focuses on readably simulating and enforcing action-level allow/deny/approval decisions rather than a full external policy language
- risk approval is v1 and currently uses action-kind/path/network heuristics rather than a full repository diff risk model
- GitHub control plane is v1 and currently syncs PR state, mergeability, and status-check summaries through `gh`, not a webhook-driven GitHub App
- verification bundles persist contract/outcome state locally, and company issue completion now records `verificationStatus` / `verificationSummary`; deeper verifier-agent continuation is still prompt-driven rather than a separate verifier runtime
- runtime projection surfaces expose issue-level `runtimeDisposition`, but the runtime scheduler is still heuristic rather than fully market/simulation driven
- company context persistence now includes structured evidence and knowledge stores under `.cotor/provenance/` and `.cotor/knowledge/`, but retrieval is still read-oriented
- company issue execution creates inspectable durable run snapshots by default; `resume continue/fork/approve` for generic pipeline replay remains experimental behind `COTOR_EXPERIMENTAL_DURABLE_RUNTIME_V2=1`

Inspect `.cotor/companies/` in the working folder to review the persisted company state.

## Documentation

Start here:

- [Documentation Index](docs/INDEX.md)
- [Architecture Overview](docs/ARCHITECTURE.md)
- [Module Boundaries](docs/modules/README.md)
- [English Guide](docs/README.md)
- [Korean Guide](docs/README.ko.md)
- [Quick Start](docs/QUICK_START.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Desktop App](docs/DESKTOP_APP.md)
- [Features](docs/FEATURES.md)
- [Validation Plan](docs/TEST_PLAN.md)
- [Contributing Guide](CONTRIBUTING.md)
- [Team Ops](docs/team-ops/README.md)
- [AI Agent Rules](AGENTS.md)

Historical reports, release notes, and architecture drafts are linked from [docs/INDEX.md](docs/INDEX.md) under `Historical / design records`.

## Graphify Workflow

Graphify is part of the source-of-truth workflow for this repo. Use it to narrow architecture and refactor questions before reading broad file sets.

- Report: `graphify-out/GRAPH_REPORT.md`
- Graph data: `graphify-out/graph.json`
- Human navigation UI: `graphify-out/graph.html`

Read `graphify-out/GRAPH_REPORT.md` first when investigating architecture, module ownership, surprising dependencies, or god nodes. Do not paste `graphify-out/graph.json` into prompts or docs; use targeted graph commands instead.

Common commands from the repository root:

```bash
graphify .                  # initial graph build when no graph exists
graphify update .           # refresh code/document corpus after changes
graphify cluster-only .     # recompute communities after large structure changes
graphify query "How does DesktopAppService relate to AppServer?"
graphify path "DesktopAppService" "AgentRun"
graphify explain "CompanyProblemSignal"
graphify hook status
graphify hook install
graphify claude install
graphify codex install
graphify opencode install
```

Assistant slash-command environments may expose the same workflow as `/graphify .`, `/graphify . --update`, and `/graphify . --cluster-only`. The installed CLI in this checkout uses the subcommands shown above.

After a refactor, compare the before/after `GRAPH_REPORT.md` summary and inspect changed communities before trusting the docs.

## Validation

```bash
cotor version
./gradlew formatCheck
./gradlew test -x jacocoTestReport -x jacocoTestCoverageVerification
swift build --package-path macos
swift test --package-path macos
graphify update .
```
