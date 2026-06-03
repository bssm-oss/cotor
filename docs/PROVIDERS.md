# Providers

Cotor can scan known local provider commands without logging in, installing packages, refreshing remote catalogs, or triggering paid model calls.

## Commands

```bash
cotor provider list
cotor provider scan
cotor provider test opencode
cotor provider test codex-oauth
```

The scan checks whether each provider command is available on `PATH`. It intentionally avoids commands such as `login`, `install`, `pull`, `download`, `render`, `sync`, and network refresh operations.
`provider test` accepts canonical provider IDs and common agent-facing aliases such as `codex`, `codex-exec`, `codex-oauth`, `claude`, `gemma4`, and `lmstudio`.

## App-Server API

- `GET /api/app/providers`
- `POST /api/app/providers/scan`
- `POST /api/app/providers/{providerId}/test`

## Known Providers

The default catalog includes AI CLIs, local model servers, Git/GitHub tooling, browser/video tools, security scanners, and language/package runtimes: Codex, Claude Code, Gemini, GitHub Copilot, Cursor, Goose, OpenCode, Graphify, Qwen, Ollama, LM Studio, `gh`, `git`, Playwright, FFmpeg, Remotion, Manim, OSV Scanner, Node.js, npm, pnpm, Bun, Python, uv, and pip.

OpenCode model discovery remains available through the existing agent model route and desktop model picker; provider scan only reports local provider availability.
