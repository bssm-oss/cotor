# TestSprite 설정

이 문서는 API 키나 개인 IDE 상태를 커밋하지 않고 Cotor를 TestSprite에 연결하는 절차입니다.

Cotor에서 TestSprite의 1차 대상은 app-server API와 브라우저 기반 웹 편집기입니다. macOS 데스크톱 앱은 네이티브 SwiftUI 앱이므로 TestSprite 브라우저 UI 테스트 대상이 아닙니다. TestSprite 이후에도 기존 Swift 빌드/테스트와 수동 데스크톱 스모크를 따로 확인해야 합니다.

Cotor에는 데스크톱 내장 `테스트` surface도 있습니다. 이 Test Center는 외부 TestSprite와 별개이며, 선택된 회사 루트에서 로컬 고정 검증 명령을 실행하고 계획, 진행률, 단계별 상태, 제한된 로그를 macOS 셸 안에 표시합니다.

## 공유 입력 파일

TestSprite 설정 포털에서 아래 파일을 사용하십시오.

- [Cotor TestSprite PRD](testsprite/COTOR_TESTSPRITE_PRD.md)
- [Cotor TestSprite API Reference](testsprite/COTOR_TESTSPRITE_API_REFERENCE.md)

backend API 테스트를 구성할 때 두 파일을 함께 업로드합니다. API 키, app-server bearer token, GitHub token, Linear token, 로컬 token 파일은 TestSprite 업로드에 포함하지 않습니다.

## MCP 서버 설치

현재 TestSprite MCP 설정은 npm 패키지 `@testsprite/testsprite-mcp`를 사용합니다. 실제 API 키는 개인 IDE 설정에만 저장하십시오.

일반 MCP 설정 예시:

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

로컬 패키지 스모크:

```bash
npx -y @testsprite/testsprite-mcp@latest --help
```

공식 문서:

- <https://docs.testsprite.com/mcp/getting-started/installation>
- <https://docs.testsprite.com/mcp/core/tools>
- <https://docs.testsprite.com/mcp/maintenance/test-maintenance>

## 백엔드 API 대상

명시적인 테스트 토큰으로 localhost app-server를 시작합니다.

```bash
export COTOR_APP_TOKEN="$(uuidgen | tr '[:upper:]' '[:lower:]')"
./gradlew run --args="app-server --port 8787 --token $COTOR_APP_TOKEN"
```

다른 터미널에서 확인합니다.

```bash
curl -fsS http://127.0.0.1:8787/health
curl -fsS -H "Authorization: Bearer $COTOR_APP_TOKEN" http://127.0.0.1:8787/api/app/health
```

권장 TestSprite MCP 호출:

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

## 선택적 브라우저 대상

브라우저 기반 파이프라인 편집기를 테스트하려면 read-only 모드로 로컬 웹 표면을 시작합니다.

```bash
./gradlew run --args="web --port 8080 --read-only"
```

그 다음 TestSprite를 frontend로 bootstrap합니다.

```js
testsprite_bootstrap_tests({
  localPort: 8080,
  type: "frontend",
  projectPath: "/Users/Projects/bssm-oss/cotor-organization/cotor",
  testScope: "codebase"
})
```

기본 범위는 navigation, rendering, template browsing, YAML preview, read-only editor 동작으로 제한합니다. 쓰기 가능한 웹 세션은 의도적으로 시작했을 때만 테스트하십시오.

## TestSprite 안전 규칙

- 먼저 읽기 전용 API를 테스트합니다: `/health`, `/ready`, `/api/app/health`, `/api/app/metrics`, `/api/app/settings`, `/api/app/providers`, `/api/app/capabilities/catalog`.
- 변경이 필요한 company 테스트는 `/Users/Projects/bssm-oss/cotor-organization/cotor-test` 샌드박스 root를 사용합니다.
- 기본적으로 destructive route를 호출하지 않습니다: company delete, goal delete, issue delete, context delete, TUI terminate, shutdown, `apply=true` runtime cleanup.
- 실제 GitHub 상태에 대해 merge/review verdict 흐름을 테스트하지 않습니다. 테스트하려면 disposable branch와 PR을 사용합니다.
- `.env`, `.cotor/`, 로그, token 파일, `local.properties`, 생성된 credential은 업로드하지 않습니다.
- `testsprite_tests/tmp/`와 TestSprite HTML/Markdown report는 생성 실행물로 봅니다. 생성된 test plan이나 안정화된 test code는 검토 후 커밋할 수 있습니다.

## TestSprite 외 로컬 검증

TestSprite 산출물을 추가하거나 재생성한 뒤에는 기존 저장소 검증을 실행합니다.

```bash
./gradlew test -x jacocoTestReport -x jacocoTestCoverageVerification
swift build --package-path macos
graphify update .
```
