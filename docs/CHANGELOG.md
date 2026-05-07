# Changelog

## Unreleased

- Refreshed README, architecture, module-boundary, assistant-instruction, and Graphify workflow docs so they describe the current company-first runtime, app-server, macOS shell, policy/evidence, and provider boundaries.
- Added module boundary docs under `docs/modules/` with public entrypoints, allowed dependency directions, test locations, and common change checklists.
- Added root `CLAUDE.md` as a short assistant-routing guide that points Claude Code sessions to `AGENTS.md`, architecture docs, module docs, and Graphify query workflows.
- Documented that this docs refresh does not move public import paths, route paths, config paths, or generated artifact locations; no compatibility shim or user migration is required.
- Added internal A2A v1 routes under `/api/a2a/v1/*` with session open, message post, FIFO pull, snapshot, and artifact metadata registration.
- Added in-memory dedupe handling via `dedupeKey` and lightweight A2A envelope/session models.
- Added company dashboard exposure of `AgentContextEntry` and `AgentMessage` so desktop issue detail can render recent A2A handoffs and thread activity.
- Added CI job and step timeouts plus `--stacktrace` on Gradle test execution.
- Added shared test shutdown registry support for `DesktopAppService`.
- Hardened `DesktopStateStore` lock acquisition with bounded retries and lock-holder diagnostics.
