# Providers

Cotor는 로그인, package install, remote catalog refresh, 유료 model call 없이 알려진 로컬 provider command 존재 여부를 확인할 수 있습니다.

## 명령

```bash
cotor provider list
cotor provider scan
cotor provider test opencode
cotor provider test codex-oauth
```

scan은 각 provider command가 `PATH`에 있는지만 확인합니다. `login`, `install`, `pull`, `download`, `render`, `sync`, network refresh 같은 명령은 의도적으로 호출하지 않습니다.
`provider test`는 canonical provider ID와 `codex`, `codex-exec`, `codex-oauth`, `claude`, `gemma4`, `lmstudio` 같은 agent-facing alias를 함께 받습니다.

## App-Server API

- `GET /api/app/providers`
- `POST /api/app/providers/scan`
- `POST /api/app/providers/{providerId}/test`

## 기본 Provider

기본 catalog에는 AI CLI, local model server, Git/GitHub 도구, browser/video 도구, security scanner, language/package runtime이 포함됩니다: Codex, Claude Code, Gemini, GitHub Copilot, Cursor, Goose, OpenCode, Graphify, Qwen, Ollama, LM Studio, `gh`, `git`, Playwright, FFmpeg, Remotion, Manim, OSV Scanner, Node.js, npm, pnpm, Bun, Python, uv, pip.

OpenCode model discovery는 기존 agent model route와 desktop model picker에서 계속 사용합니다. provider scan은 로컬 provider availability만 보고합니다.
