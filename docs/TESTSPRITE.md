# TestSprite Setup

This guide prepares Cotor for TestSprite without committing API keys or local IDE state.

TestSprite is useful for Cotor primarily as an API and browser-flow tester. The native macOS desktop shell is not a browser UI, so validate it with the existing Swift build/tests and hands-on smoke checks after TestSprite finishes.

Cotor also includes a native desktop `Tests` surface. That Test Center is separate from external TestSprite: it runs local, predefined validation commands for the selected company root and shows plan, progress, step status, and bounded logs inside the macOS shell.

## Shared Inputs

Use these files when bootstrapping TestSprite:

- [Cotor TestSprite PRD](testsprite/COTOR_TESTSPRITE_PRD.md)
- [Cotor TestSprite API Reference](testsprite/COTOR_TESTSPRITE_API_REFERENCE.md)

Upload both files in the TestSprite configuration portal when testing the backend API. Keep API keys, app-server bearer tokens, GitHub tokens, Linear tokens, and local token files out of TestSprite uploads.

## Install The MCP Server

TestSprite's current MCP setup uses the npm package `@testsprite/testsprite-mcp`. Configure it in your IDE-level or project-level MCP settings, but keep the real API key in your private config.

Generic MCP configuration:

```json
{
  "mcpServers": {
    "TestSprite": {
      "command": "npx",
      "args": ["@testsprite/testsprite-mcp@latest"],
      "env": {
        "API_KEY": "replace-with-your-testsprite-api-key"
      }
    }
  }
}
```

Local package smoke:

```bash
npx -y @testsprite/testsprite-mcp@latest --help
```

Official references:

- <https://docs.testsprite.com/mcp/getting-started/installation>
- <https://docs.testsprite.com/mcp/core/tools>
- <https://docs.testsprite.com/mcp/maintenance/test-maintenance>

## Backend API Target

Start the localhost app-server with an explicit test token:

```bash
export COTOR_APP_TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
./gradlew run --args="app-server --port 8787 --token $COTOR_APP_TOKEN"
```

Smoke it from another terminal:

```bash
curl -fsS http://127.0.0.1:8787/health
curl -fsS -H "Authorization: Bearer $COTOR_APP_TOKEN" http://127.0.0.1:8787/api/app/health
```

Recommended TestSprite MCP calls:

```js
testsprite_bootstrap_tests({
  localPort: 8787,
  type: "backend",
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor",
  testScope: "codebase"
})

testsprite_generate_code_summary({
  projectRootPath: "/Users/Projects/bssm-oss/cotor-organization/cotor"
})

testsprite_generate_standardized_prd({
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor"
})

testsprite_generate_backend_test_plan({
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor"
})

testsprite_generate_code_and_execute({
  projectName: "cotor",
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor",
  testIds: [],
  additionalInstruction: "Use docs/testsprite/COTOR_TESTSPRITE_PRD.md and docs/testsprite/COTOR_TESTSPRITE_API_REFERENCE.md as the product and API source of truth. Base URL is http://127.0.0.1:8787. Add Authorization: Bearer <COTOR_APP_TOKEN> for /api/app routes. Do not call delete, merge, review approval, runtime cleanup apply=true, external publish, or company runtime start/stop endpoints unless a sandbox company under /Users/Projects/bssm-oss/cotor-organization/cotor-test was created for this run."
})
```

## Optional Browser Target

For the browser-based pipeline editor, start the local web surface in read-only mode:

```bash
./gradlew run --args="web --port 8080 --read-only"
```

Then bootstrap TestSprite as frontend:

```js
testsprite_bootstrap_tests({
  localPort: 8080,
  type: "frontend",
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor",
  testScope: "codebase"
})
```

Keep this scope to navigation, rendering, template browsing, YAML preview, and read-only editor behavior unless you intentionally start a writable web session.

## Safety Rules For TestSprite

- Prefer read-only API checks first: `/health`, `/ready`, `/api/app/health`, `/api/app/metrics`, `/api/app/settings`, `/api/app/providers`, `/api/app/capabilities/catalog`.
- For mutable company tests, use the sandbox root `/Users/Projects/bssm-oss/cotor-organization/cotor-test`.
- Do not test destructive routes by default: company delete, goal delete, issue delete, context delete, TUI terminate, shutdown, runtime cleanup with `apply=true`.
- Do not run merge/review verdict flows against real GitHub state unless the branch and PR are disposable.
- Do not upload `.env`, `.cotor/`, logs, token files, `local.properties`, or generated credentials.
- Treat `testsprite_tests/tmp/` and TestSprite HTML/Markdown reports as generated run artifacts. The generated test plans or stable test code can be reviewed before committing.

## Local Validation Outside TestSprite

Run the normal repository checks after adding or regenerating TestSprite assets:

```bash
./gradlew test -x jacocoTestReport -x jacocoTestCoverageVerification
swift build --package-path macos
graphify update .
```
